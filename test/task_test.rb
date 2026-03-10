require_relative "test_helper"

class DischargerTaskTest < Minitest::Test
  def setup
    @task = Discharger::Task.new
  end

  def test_initialize
    assert_equal :release, @task.name
    assert_equal "develop", @task.working_branch
    assert_equal "stage", @task.staging_branch
    assert_equal "main", @task.production_branch
    assert_equal "Release the current version to stage", @task.description
    assert_equal false, @task.auto_deploy_staging
  end

  def test_create
    task = Discharger::Task.create(:test_task) do
      self.version_file = "VERSION"
      self.version_limit = "1.0.0"
      self.version_redo_proc = -> { "1.0.1" }
      self.changelog_file = "CHANGELOG.md"
      self.fragment = "changelog.d"
      self.updated_paths = ["lib/"]
      self.commit = "Initial commit"
      self.commit_finalize = "Finalize commit"
    end

    assert_equal :test_task, task.name
    assert_equal "VERSION", task.version_file
    assert_equal "1.0.0", task.version_limit
    assert_equal "1.0.1", task.version_redo_proc.call
    assert_equal "CHANGELOG.md", task.changelog_file
    assert_equal "changelog.d", task.fragment
    assert_equal ["lib/"], task.updated_paths
    assert_equal "Initial commit", task.commit
    assert_equal "Finalize commit", task.commit_finalize
  end

  def test_create_forwards_tag_pattern_to_reissue
    pattern = /^v(\d+\.\d+\..+)$/
    captured_tag_pattern = nil

    original_create = Reissue::Task.method(:create)
    Reissue::Task.define_singleton_method(:create) do |name = :reissue, &block|
      reissue_task = Reissue::Task.new(name)
      block&.call(reissue_task)
      captured_tag_pattern = reissue_task.tag_pattern
      reissue_task
    end

    Discharger::Task.create(:test_tag_pattern) do
      self.version_file = "VERSION"
      self.tag_pattern = pattern
    end

    assert_equal pattern, captured_tag_pattern
  ensure
    Reissue::Task.define_singleton_method(:create, original_create)
  end

  def test_syscall_success
    output = StringIO.new
    assert_output(/Hello, World!/) do
      result = @task.syscall(["echo", "Hello, World!"], output:)
      assert result
    end
  end

  def test_syscall_failure
    assert_raises(SystemExit) do
      capture_io do
        @task.syscall(["false"])
      end
    end
  end

  def test_sysecho
    assert_output("Hello, World!\n") do
      assert @task.sysecho("Hello, World!")
    end
  end

  def test_define
    @task.chat_token = "fake_token"
    @task.release_message_channel = "#general"
    @task.version_constant = "VERSION"
    @task.pull_request_url = "http://example.com"

    @task.define

    assert_equal [
      "release",
      "release:build",
      "release:config",
      "release:prepare",
      "release:slack",
      "release:stage"
    ], Rake::Task.tasks.map(&:name).grep(/^release/).sort
  end

  def test_validate_version_match_success
    @task.version_file = "VERSION"

    # Stub git_show_version to return matching versions
    @task.define_singleton_method(:git_show_version) { |_branch| "2026.1.A" }

    output = StringIO.new
    result = @task.validate_version_match!("stage", "develop", output:)

    assert result
    assert_match(/Versions match/, output.string)
  end

  def test_validate_version_match_failure
    @task.version_file = "VERSION"

    # Stub git_show_version to return different versions
    @task.define_singleton_method(:git_show_version) do |branch|
      (branch == "stage") ? "2026.1.A" : "2026.1.B"
    end

    assert_raises(SystemExit) do
      capture_io { @task.validate_version_match!("stage", "develop") }
    end
  end

  def test_validate_release_commit_success
    sha = "abc123def456"

    # Stub both methods to return same SHA
    @task.define_singleton_method(:git_local_sha) { |_branch| sha }
    @task.define_singleton_method(:git_version_file_commit) { |_branch| sha }

    output = StringIO.new
    result = @task.validate_release_commit!("develop", output:)

    assert result
    assert_match(/HEAD is the release commit/, output.string)
  end

  def test_validate_release_commit_failure
    head_sha = "abc123def456"
    release_sha = "xyz789ghi012"

    # Stub to return different SHAs
    @task.define_singleton_method(:git_local_sha) { |_branch| head_sha }
    @task.define_singleton_method(:git_version_file_commit) { |_branch| release_sha }
    @task.version_file = "VERSION"

    assert_raises(SystemExit) do
      capture_io { @task.validate_release_commit!("develop") }
    end
  end

  def test_auto_deploy_staging_can_be_enabled
    @task.auto_deploy_staging = true
    assert_equal true, @task.auto_deploy_staging
  end
end

class DischargerReleaseCommandSequenceTest < Minitest::Test
  FAKE_VERSION = "1.2.3"

  def setup
    @commands = []
    @original_stdin = $stdin
    Rake::Task.define_task(:environment) {} unless Rake::Task.task_defined?(:environment)
  end

  def teardown
    $stdin = @original_stdin
  end

  def build_task(name, auto_deploy:)
    noop_task = Object.new
    noop_task.define_singleton_method(:invoke) { |*_args| }
    noop_task.define_singleton_method(:reenable) {}
    mock_tasker = Object.new
    mock_tasker.define_singleton_method(:[]) { |_name| noop_task }

    task = Discharger::Task.new(name, tasker: mock_tasker)
    task.version_constant = "DischargerReleaseCommandSequenceTest::FAKE_VERSION"
    task.version_file = "VERSION"
    task.changelog_file = "CHANGELOG.md"
    task.release_message_channel = "#releases"
    task.chat_token = "fake_token"
    task.pull_request_url = "http://example.com"
    task.app_name = "TestApp"
    task.commit_identifier = -> { "abc123" }
    task.auto_deploy_staging = auto_deploy

    commands = @commands
    task.define_singleton_method(:syscall) do |*steps, **_kwargs, &_block|
      steps.each { |cmd| commands << cmd }
      true
    end
    task.define_singleton_method(:sysecho) { |*_args, **_kwargs| true }
    task.define_singleton_method(:validate_version_match!) { |*_args, **_kwargs| true }
    task.define_singleton_method(:validate_release_commit!) { |*_args, **_kwargs| true }
    task.define_singleton_method(:existing_pr_number) { |*_args| nil }

    task
  end

  def command_issued?(pattern)
    @commands.any? { |cmd|
      joined = cmd.join(" ")
      pattern.is_a?(Regexp) ? joined.match?(pattern) : joined == pattern
    }
  end

  def test_standard_mode_merges_staging_without_pr_create
    task = build_task(:rel_std_seq, auto_deploy: false)
    task.define
    $stdin = StringIO.new("\n")

    capture_io { Rake::Task["rel_std_seq"].invoke }

    refute command_issued?(/gh pr create/),
      "Standard mode should not create a PR"
    assert command_issued?("gh pr merge stage --merge"),
      "Should merge staging branch"
    assert command_issued?(/git tag -a v1\.2\.3 .+ main/),
      "Should tag production branch"
    assert command_issued?("git push origin v1.2.3"),
      "Should push the tag"
    assert command_issued?(/git fetch origin stage:stage main:main/),
      "Should fetch staging and production branches"
  end

  def test_auto_deploy_mode_creates_pr_then_merges_working_branch
    task = build_task(:rel_auto_seq, auto_deploy: true)
    task.define
    $stdin = StringIO.new("\n")

    capture_io { Rake::Task["rel_auto_seq"].invoke }

    assert command_issued?(/gh pr create --base main --head develop/),
      "Auto-deploy should create PR from working branch to production"
    assert command_issued?("gh pr merge develop --merge"),
      "Auto-deploy should merge working branch (not staging)"
    assert command_issued?(/git tag -a v1\.2\.3 .+ main/),
      "Should tag production branch"
    assert command_issued?("git push origin v1.2.3"),
      "Should push the tag"
    assert command_issued?("git fetch origin main:main develop"),
      "Should fetch production branch and working branch tracking ref"
    assert command_issued?("git reset --hard origin/develop"),
      "Should reset working branch to match remote"
  end

  def test_auto_deploy_mode_pr_create_precedes_merge
    task = build_task(:rel_order_seq, auto_deploy: true)
    task.define
    $stdin = StringIO.new("\n")

    capture_io { Rake::Task["rel_order_seq"].invoke }

    create_idx = @commands.index { |c| c.join(" ").match?(/gh pr create/) }
    merge_idx = @commands.index { |c| c.join(" ").match?(/gh pr merge/) }

    assert create_idx, "Expected gh pr create command"
    assert merge_idx, "Expected gh pr merge command"
    assert_operator create_idx, :<, merge_idx,
      "PR create must precede PR merge"
  end

  def test_auto_deploy_mode_reuses_existing_pr
    task = build_task(:rel_reuse_seq, auto_deploy: true)
    task.define_singleton_method(:existing_pr_number) { |*_args| "42" }
    task.define
    $stdin = StringIO.new("\n")

    capture_io { Rake::Task["rel_reuse_seq"].invoke }

    refute command_issued?(/gh pr create/),
      "Should not create a PR when one already exists"
    assert command_issued?("gh pr merge 42 --merge"),
      "Should merge by PR number when reusing an existing PR"
  end
end

class DischargerExistingPrNumberTest < Minitest::Test
  FakeStatus = Struct.new(:ok) do
    def success? = ok
  end

  def setup
    @task = Discharger::Task.new
    @original_capture3 = Open3.method(:capture3)
  end

  def teardown
    Open3.define_singleton_method(:capture3, @original_capture3)
  end

  def stub_capture3(stdout, stderr, success)
    status = FakeStatus.new(success)
    Open3.define_singleton_method(:capture3) { |*_args| [stdout, stderr, status] }
  end

  def test_returns_pr_number_when_pr_exists
    stub_capture3("42\n", "", true)
    assert_equal "42", @task.existing_pr_number("main", "develop")
  end

  def test_returns_nil_when_no_pr_exists
    stub_capture3("", "", true)
    assert_nil @task.existing_pr_number("main", "develop")
  end

  def test_returns_nil_on_command_failure
    stub_capture3("", "error", false)
    assert_nil @task.existing_pr_number("main", "develop")
  end
end

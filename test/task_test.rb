require_relative "test_helper"

class DischargerTaskTest < Minitest::Test
  TEST_VERSION = "1.2.3"

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

  def test_create_forwards_retain_changelogs_to_reissue
    retainer = ->(version_hash, content) { [version_hash, content] }
    captured_retain_changelogs = nil

    original_create = Reissue::Task.method(:create)
    Reissue::Task.define_singleton_method(:create) do |name = :reissue, &block|
      reissue_task = Reissue::Task.new(name)
      block&.call(reissue_task)
      captured_retain_changelogs = reissue_task.retain_changelogs
      reissue_task
    end

    Discharger::Task.create(:test_retain_changelogs) do
      self.version_file = "VERSION"
      self.retain_changelogs = retainer
    end

    assert_equal retainer, captured_retain_changelogs
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

  def test_find_release_commit_returns_sha_that_introduced_version_header
    later_sha = "later123def456"
    finalize_sha = "final123def456"
    @task.changelog_file = "CHANGELOG.md"
    @task.version_constant = "DischargerTaskTest::TEST_VERSION"
    @task.define_singleton_method(:git_file_commits) { |_branch, _path| [later_sha, finalize_sha] }
    @task.define_singleton_method(:git_merge_commit?) { |_sha| false }
    @task.define_singleton_method(:git_show_at_commit) do |ref, _path|
      case ref
      when later_sha
        "## [1.2.3] - 2026-04-20\n\n### Changed\n- Later edit\n"
      when "#{later_sha}^"
        "## [1.2.3] - 2026-04-20\n\n### Changed\n- Thing\n"
      when finalize_sha
        "## [1.2.3] - 2026-04-20\n\n### Changed\n- Thing\n"
      when "#{finalize_sha}^"
        "## [1.2.3] - Unreleased\n\n### Changed\n- Thing\n"
      end
    end

    output = StringIO.new
    result = @task.find_release_commit!("develop", output:)

    assert_equal finalize_sha, result
    assert_match(/Release commit/, output.string)
  end

  def test_find_release_commit_skips_merge_commit_that_looks_like_finalize
    merge_sha = "merge123def456"
    finalize_sha = "final123def456"
    @task.changelog_file = "CHANGELOG.md"
    @task.version_constant = "DischargerTaskTest::TEST_VERSION"
    @task.define_singleton_method(:git_file_commits) { |_branch, _path| [merge_sha, finalize_sha] }
    @task.define_singleton_method(:git_merge_commit?) { |sha| sha == merge_sha }
    @task.define_singleton_method(:git_show_at_commit) do |ref, _path|
      case ref
      when merge_sha
        "## [1.2.3] - 2026-04-20\n\n### Changed\n- Thing\n"
      when "#{merge_sha}^"
        "## [1.2.3] - Unreleased\n\n### Changed\n- Thing\n"
      when finalize_sha
        "## [1.2.3] - 2026-04-20\n\n### Changed\n- Thing\n"
      when "#{finalize_sha}^"
        "## [1.2.3] - Unreleased\n\n### Changed\n- Thing\n"
      end
    end

    output = StringIO.new
    result = @task.find_release_commit!("develop", output:)

    assert_equal finalize_sha, result
  end

  def test_find_release_commit_aborts_when_no_commit_touches_changelog
    @task.changelog_file = "CHANGELOG.md"
    @task.version_constant = "DischargerTaskTest::TEST_VERSION"
    @task.define_singleton_method(:git_file_commits) { |_branch, _path| [] }

    assert_raises(SystemExit) do
      capture_io { @task.find_release_commit!("develop") }
    end
  end

  def test_find_release_commit_aborts_when_version_header_missing
    @task.changelog_file = "CHANGELOG.md"
    @task.version_constant = "DischargerTaskTest::TEST_VERSION"
    @task.define_singleton_method(:git_file_commits) { |_branch, _path| ["abc123def456"] }
    @task.define_singleton_method(:git_merge_commit?) { |_sha| false }
    @task.define_singleton_method(:git_show_at_commit) do |_ref, _path|
      "## [9.9.9] - 2020-01-01\n\n### Changed\n- Old thing\n"
    end

    assert_raises(SystemExit) do
      capture_io { @task.find_release_commit!("develop") }
    end
  end

  def test_auto_deploy_staging_can_be_enabled
    @task.auto_deploy_staging = true
    assert_equal true, @task.auto_deploy_staging
  end

  def test_validate_pr_branch_accepts_bump_branch
    assert @task.validate_pr_branch!("bump/next-1-2-4")
  end

  def test_validate_pr_branch_rejects_detached_head
    assert_raises(SystemExit) do
      capture_io { @task.validate_pr_branch!("HEAD") }
    end
  end

  def test_validate_pr_branch_rejects_working_branch
    assert_raises(SystemExit) do
      capture_io { @task.validate_pr_branch!("develop") }
    end
  end
end

class DischargerReleaseCommandSequenceTest < Minitest::Test
  FAKE_VERSION = "1.2.3"
  FakeStatus = Struct.new(:ok) do
    def success? = ok
  end

  def setup
    @commands = []
    @slack_invocations = []
    @original_stdin = $stdin
    Rake::Task.define_task(:environment) {} unless Rake::Task.task_defined?(:environment)
  end

  def teardown
    $stdin = @original_stdin
  end

  FAKE_RELEASE_SHA = "fakeReleaseSha0"

  def build_task(name, auto_deploy:, pr_label: nil)
    slack_invocations = @slack_invocations
    noop_task = Object.new
    noop_task.define_singleton_method(:invoke) { |*args| slack_invocations << args }
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
    task.pr_label = pr_label

    commands = @commands
    task.define_singleton_method(:syscall) do |*steps, **_kwargs, &block|
      steps.each { |cmd| commands << cmd }
      block&.call("", "", FakeStatus.new(true))
      true
    end
    task.define_singleton_method(:system) { |*_args| true }
    task.define_singleton_method(:sysecho) { |*_args, **_kwargs| true }
    task.define_singleton_method(:delete_local_branch) { |branch| commands << ["git", "branch", "-D", branch] }
    task.define_singleton_method(:validate_version_match!) { |*_args, **_kwargs| true }
    task.define_singleton_method(:validate_pr_label!) { true }
    task.define_singleton_method(:ensure_clean_worktree!) { true }
    task.define_singleton_method(:ensure_branch_not_ahead!) { |_branch| true }
    task.define_singleton_method(:current_branch!) { "bump/next-1-2-4" }
    task.define_singleton_method(:existing_pr_number) { |_base, _head, state: "open"| (state == "open") ? "42" : nil }
    task.define_singleton_method(:git_ancestor?) { |_ancestor, _descendant| false }
    task.define_singleton_method(:find_release_commit!) { |_branch, **_kwargs| FAKE_RELEASE_SHA }

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
    assert command_issued?("gh pr merge 42 --merge"),
      "Should merge the open staging PR by number"
    assert command_issued?(/git tag -a v1\.2\.3 .+ main/),
      "Should tag production branch"
    assert command_issued?("git push origin v1.2.3"),
      "Should push the tag"
    assert command_issued?(/git fetch origin stage:stage main:main/),
      "Should fetch staging and production branches"
  end

  def test_auto_deploy_mode_tags_release_commit_directly
    task = build_task(:rel_auto_seq, auto_deploy: true)
    task.define
    $stdin = StringIO.new("\n")

    capture_io { Rake::Task["rel_auto_seq"].invoke }

    refute command_issued?(/gh pr create/),
      "Auto-deploy should not create a production PR"
    refute command_issued?(/gh pr merge/),
      "Auto-deploy should not merge a production PR"
    assert command_issued?("git fetch origin develop"),
      "Auto-deploy should fetch working branch only"
    refute command_issued?(/main:main/),
      "Auto-deploy should not fetch the production branch"
    assert command_issued?("git reset --hard origin/develop"),
      "Should reset working branch to match remote"
    assert command_issued?(/git tag -a v1\.2\.3 .+ #{FAKE_RELEASE_SHA}/o),
      "Should tag the computed release commit SHA (not production branch)"
    assert command_issued?("git push origin v1.2.3"),
      "Should push the tag"
    refute command_issued?(/git branch -D (stage|main)/),
      "Auto-deploy should not clean up production/staging local branches"
  end

  def test_auto_deploy_mode_slack_message_reports_tagged_sha
    task = build_task(:rel_slack_sha, auto_deploy: true)
    task.define
    $stdin = StringIO.new("\n")

    capture_io { Rake::Task["rel_slack_sha"].invoke }

    released = @slack_invocations.find { |args| args.first.to_s.start_with?("Released") }
    assert released, "Expected a 'Released ...' Slack invocation"
    message = released.first
    assert_includes message, FAKE_RELEASE_SHA[0, 8],
      "Slack message must report the tagged commit SHA (tag_ref[0, 8])"
    refute_includes message, "abc123",
      "Slack message must not report commit_identifier SHA (HEAD-based) in auto_deploy mode"
  end

  def test_standard_mode_skips_merge_when_source_already_in_production
    task = build_task(:rel_merged_seq, auto_deploy: false)
    task.define_singleton_method(:existing_pr_number) { |_base, _head, state: "open"| nil }
    task.define_singleton_method(:git_ancestor?) { |_ancestor, _descendant| true }
    task.define
    $stdin = StringIO.new("\n")

    capture_io { Rake::Task["rel_merged_seq"].invoke }

    refute command_issued?(/gh pr merge/),
      "Should not attempt merge when PR is already merged"
    assert command_issued?(/git tag -a v1\.2\.3 .+ main/),
      "Should still tag production branch"
    assert command_issued?("git push origin v1.2.3"),
      "Should still push the tag"
  end

  def test_prepare_resets_working_branch_to_origin_before_branching
    task = build_task(:rel_prepare_sync, auto_deploy: true)
    task.define
    $stdin = StringIO.new("\n")

    capture_io { Rake::Task["rel_prepare_sync:prepare"].invoke }

    fetch_idx = @commands.index { |c| c.join(" ") == "git fetch origin develop" }
    reset_idx = @commands.index { |c| c.join(" ") == "git reset --hard origin/develop" }
    branch_idx = @commands.index { |c| c.join(" ").match?(/^git checkout -b bump\/finish-/) }

    assert fetch_idx, "Expected fetch of origin working_branch"
    assert reset_idx, "Expected reset --hard origin/working_branch before branching"
    assert branch_idx, "Expected creation of bump/finish branch"
    assert_operator fetch_idx, :<, reset_idx, "Fetch must precede reset"
    assert_operator reset_idx, :<, branch_idx,
      "Reset must precede new branch creation so bump branch starts from latest origin state"
  end

  def test_prepare_checks_ahead_state_after_fetch_before_reset
    task = build_task(:rel_prepare_ahead, auto_deploy: true)
    ahead_checks = []
    task.define_singleton_method(:ensure_branch_not_ahead!) do |branch|
      ahead_checks << @commands.size
      true
    end
    task.instance_variable_set(:@commands, @commands)
    task.define
    $stdin = StringIO.new("\n")

    capture_io { Rake::Task["rel_prepare_ahead:prepare"].invoke }

    fetch_idx = @commands.index { |c| c.join(" ") == "git fetch origin develop" }
    reset_idx = @commands.index { |c| c.join(" ") == "git reset --hard origin/develop" }

    assert_equal 1, ahead_checks.size, "Should invoke ensure_branch_not_ahead! once"
    assert_operator fetch_idx, :<, ahead_checks.first, "Fetch must precede ahead-check"
    assert_operator ahead_checks.first, :<=, reset_idx, "Ahead-check must precede reset"
  end

  def test_release_auto_deploy_checks_ahead_state_before_reset
    task = build_task(:rel_auto_ahead, auto_deploy: true)
    ahead_checks = []
    task.define_singleton_method(:ensure_branch_not_ahead!) do |branch|
      ahead_checks << @commands.size
      true
    end
    task.instance_variable_set(:@commands, @commands)
    task.define
    $stdin = StringIO.new("\n")

    capture_io { Rake::Task["rel_auto_ahead"].invoke }

    fetch_idx = @commands.index { |c| c.join(" ") == "git fetch origin develop" }
    reset_idx = @commands.index { |c| c.join(" ") == "git reset --hard origin/develop" }

    assert ahead_checks.any?, "Should invoke ensure_branch_not_ahead! in auto-deploy release"
    assert_operator fetch_idx, :<, ahead_checks.first, "Fetch must precede ahead-check"
    assert_operator ahead_checks.first, :<=, reset_idx, "Ahead-check must precede reset"
  end

  def test_release_auto_deploy_checks_clean_worktree_before_reset
    task = build_task(:rel_auto_clean, auto_deploy: true)
    clean_calls = []
    task.define_singleton_method(:ensure_clean_worktree!) do
      clean_calls << @commands.size
      true
    end
    task.instance_variable_set(:@commands, @commands)
    task.define
    $stdin = StringIO.new("\n")

    capture_io { Rake::Task["rel_auto_clean"].invoke }

    reset_idx = @commands.index { |c| c.join(" ") == "git reset --hard origin/develop" }

    assert clean_calls.any?, "Should invoke ensure_clean_worktree! in auto-deploy release"
    assert_operator clean_calls.first, :<=, reset_idx, "Clean-worktree check must precede reset"
  end

  def test_release_build_checks_out_build_branch_before_deleting_staging
    task = build_task(:rel_build_order, auto_deploy: false)
    task.define
    $stdin = StringIO.new("\n")

    capture_io { Rake::Task["rel_build_order:build"].invoke }

    checkout_build_idx = @commands.index { |c| c.join(" ") == "git checkout develop" }
    delete_stage_idx = @commands.index { |c| c.join(" ") == "git branch -D stage" }
    create_stage_idx = @commands.index { |c| c.join(" ") == "git checkout -b stage" }

    assert checkout_build_idx, "Expected checkout of build_branch"
    assert delete_stage_idx, "Expected delete of staging local branch"
    assert create_stage_idx, "Expected creation of staging branch"
    assert_operator checkout_build_idx, :<, delete_stage_idx,
      "Must checkout build_branch before deleting staging — else delete fails when on staging"
    assert_operator delete_stage_idx, :<, create_stage_idx,
      "Must delete staging before recreating it"
  end

  def test_prepare_uses_gh_pr_create_with_label_when_pr_label_set
    task = build_task(:rel_prep_label, auto_deploy: true, pr_label: "no-changelog-needed")
    task.define
    $stdin = StringIO.new("\n")

    capture_io { Rake::Task["rel_prep_label:prepare"].invoke }

    gh_create = @commands.find { |c| c.first == "gh" && c[1] == "pr" && c[2] == "create" }
    assert gh_create, "Expected gh pr create invocation when pr_label is set"
    assert_includes gh_create, "--label"
    assert_includes gh_create, "no-changelog-needed"
    assert_includes gh_create, "--base"
    assert_includes gh_create, "develop"
    assert_includes gh_create, "--head"
    assert(gh_create.any? { |arg| arg.match?(/^bump\/finish-/) }, "Head should be the finish branch")

    refute(@commands.any? { |c| c.first == "open" },
      "Should not open browser URL when pr_label triggers gh-based PR creation")
  end

  def test_prepare_keeps_open_flow_when_pr_label_unset
    task = build_task(:rel_prep_open, auto_deploy: true)
    task.define
    $stdin = StringIO.new("\n")

    capture_io { Rake::Task["rel_prep_open:prepare"].invoke }

    refute(@commands.any? { |c| c.first == "gh" && c[1] == "pr" && c[2] == "create" },
      "Should not invoke gh pr create when pr_label is nil")
    assert(@commands.any? { |c| c.first == "open" },
      "Should fall back to opening compare URL when pr_label is nil")
  end

  def test_release_uses_gh_pr_create_with_label_for_bump_pr_when_pr_label_set
    task = build_task(:rel_label, auto_deploy: true, pr_label: "no-changelog-needed")
    task.define
    $stdin = StringIO.new("\n")

    capture_io { Rake::Task["rel_label"].invoke }

    bump_pr_create = @commands.find { |c|
      c.first == "gh" && c[1] == "pr" && c[2] == "create" &&
        c.include?("--title") && c[c.index("--title") + 1].to_s.start_with?("Bump version")
    }
    assert bump_pr_create, "Expected gh pr create for bump version PR when pr_label is set"
    assert_includes bump_pr_create, "--label"
    assert_includes bump_pr_create, "no-changelog-needed"
  end
end

class DischargerReleasePreconditionTest < Minitest::Test
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

  def test_validate_pr_label_returns_true_without_label
    assert @task.validate_pr_label!
  end

  def test_validate_pr_label_checks_configured_label
    @task.pr_label = "no-changelog-needed"
    stub_capture3("", "", true)

    assert @task.validate_pr_label!
  end

  def test_validate_pr_label_aborts_when_label_is_missing
    @task.pr_label = "no-changelog-needed"
    stub_capture3("", "not found", false)

    assert_raises(SystemExit) do
      capture_io { @task.validate_pr_label! }
    end
  end

  def test_ensure_clean_worktree_allows_clean_checkout
    stub_capture3("", "", true)

    assert @task.ensure_clean_worktree!
  end

  def test_ensure_clean_worktree_aborts_on_dirty_checkout
    stub_capture3(" M CHANGELOG.md\n", "", true)

    assert_raises(SystemExit) do
      capture_io { @task.ensure_clean_worktree! }
    end
  end

  def test_ensure_branch_not_ahead_passes_when_count_is_zero
    stub_capture3("0\n", "", true)
    assert @task.ensure_branch_not_ahead!("develop")
  end

  def test_ensure_branch_not_ahead_aborts_when_local_has_unpushed_commits
    stub_capture3("3\n", "", true)

    assert_raises(SystemExit) do
      capture_io { @task.ensure_branch_not_ahead!("develop") }
    end
  end

  def test_existing_pr_number_returns_pr_number_when_pr_exists
    stub_capture3("42\n", "", true)
    assert_equal "42", @task.existing_pr_number("main", "stage")
  end

  def test_existing_pr_number_returns_nil_when_no_pr_exists
    stub_capture3("", "", true)
    assert_nil @task.existing_pr_number("main", "stage")
  end

  def test_existing_pr_number_returns_nil_on_command_failure
    stub_capture3("", "error", false)
    assert_nil @task.existing_pr_number("main", "stage")
  end
end

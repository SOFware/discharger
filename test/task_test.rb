require_relative "test_helper"

class DischargerConfirmationTest < Minitest::Test
  def setup
    @task = Discharger::Task.new
    @original_stdin = $stdin
    @original_confirmation = ENV.delete("DISCHARGER_RELEASE_CONFIRM")
  end

  def teardown
    $stdin = @original_stdin
    ENV["DISCHARGER_RELEASE_CONFIRM"] = @original_confirmation
  end

  def test_enter_continues
    $stdin = StringIO.new("\n")

    output, = capture_io { @task.send(:confirm_or_exit!) }

    assert_includes output, "Are you ready to continue?"
  end

  def test_x_exits
    ["x\n", "Xstop\n"].each do |input|
      $stdin = StringIO.new(input)

      capture_io { assert_raises(SystemExit) { @task.send(:confirm_or_exit!) } }
    end
  end

  def test_eof_exits_with_failure_and_instructions
    $stdin = StringIO.new("")

    _, error_output = capture_io do
      error = assert_raises(SystemExit) { @task.send(:confirm_or_exit!) }
      refute_equal 0, error.status
    end

    assert_includes error_output, "interactively"
    assert_includes error_output, "DISCHARGER_RELEASE_CONFIRM=1"
  end

  def test_eof_runs_the_cleanup_before_exiting
    $stdin = StringIO.new("")
    cleaned = false

    capture_io do
      assert_raises(SystemExit) { @task.send(:confirm_or_exit!) { cleaned = true } }
    end

    assert cleaned
  end

  def test_x_runs_the_cleanup_before_exiting
    $stdin = StringIO.new("x\n")
    cleaned = false

    capture_io do
      assert_raises(SystemExit) { @task.send(:confirm_or_exit!) { cleaned = true } }
    end

    assert cleaned
  end

  def test_enter_skips_the_cleanup
    $stdin = StringIO.new("\n")
    cleaned = false

    capture_io { @task.send(:confirm_or_exit!) { cleaned = true } }

    refute cleaned
  end

  def test_env_confirmation_skips_prompt_and_stdin
    ENV["DISCHARGER_RELEASE_CONFIRM"] = "1"
    $stdin = Object.new
    $stdin.define_singleton_method(:gets) { raise "stdin must not be read" }

    output, = capture_io { @task.send(:confirm_or_exit!) }

    assert_includes output, "Confirmation taken from DISCHARGER_RELEASE_CONFIRM"
    refute_includes output, "Are you ready to continue?"
  end
end

class DischargerTaskTest < Minitest::Test
  def setup
    @task = Discharger::Task.new
  end

  def test_initialize
    assert_equal :release, @task.name
    assert_equal "main", @task.working_branch
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

  def test_removed_settings_warn_and_do_nothing
    Discharger::Task::REMOVED_SETTINGS.each do |setting|
      _, err = capture_io { @task.public_send(:"#{setting}=", "stage") }

      assert_match(/#{setting} was removed in discharger 0.5.0/, err)
    end
    assert_equal "main", @task.working_branch
  end

  def test_create_tolerates_a_rakefile_that_sets_removed_settings
    task = nil
    capture_io do
      task = Discharger::Task.create(:test_removed) do
        self.version_file = "VERSION"
        self.staging_branch = "stage"
        self.production_branch = "main"
      end
    end

    assert_equal :test_removed, task.name
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
      "release:config",
      "release:prepare",
      "release:slack"
    ], Rake::Task.tasks.map(&:name).grep(/^release/).sort
  end

  TEST_VERSION = "1.2.3"

  def test_find_release_commit_returns_newest_change_to_the_dated_section
    bump_sha = "bump123def456"
    refinalize_sha = "refin123def456"
    finalize_sha = "final123def456"
    @task.changelog_file = "CHANGELOG.md"
    @task.version_constant = "DischargerTaskTest::TEST_VERSION"
    @task.define_singleton_method(:git_file_commits) { |_branch, _path| [bump_sha, refinalize_sha, finalize_sha] }
    @task.define_singleton_method(:git_show_at_commit) do |ref, _path|
      case ref
      when bump_sha
        "## [1.2.4] - Unreleased\n\n## [1.2.3] - 2026-04-20\n\n- Thing\n- Hotfix\n"
      when "#{bump_sha}^", refinalize_sha
        "## [1.2.3] - 2026-04-20\n\n- Thing\n- Hotfix\n"
      when "#{refinalize_sha}^", finalize_sha
        "## [1.2.3] - 2026-04-20\n\n- Thing\n"
      when "#{finalize_sha}^"
        "## [1.2.3] - Unreleased\n\n- Thing\n"
      end
    end

    output = StringIO.new
    result = @task.find_release_commit!("main", output:)

    assert_equal refinalize_sha, result
    assert_match(/Release commit/, output.string)
  end

  def test_find_release_commit_finds_finalize_commit_merged_through_a_pr
    @task.changelog_file = "CHANGELOG.md"
    @task.version_constant = "DischargerTaskTest::TEST_VERSION"

    in_throwaway_repo do |git, commit|
      commit.call("CHANGELOG.md", "## [1.2.3] - Unreleased\n", "Start 1.2.3")
      git.call("checkout", "-b", "bump/finish-1-2-3")
      finalize_sha = commit.call("CHANGELOG.md", "## [1.2.3] - 2026-04-20\n", "Finalize 1.2.3")
      git.call("checkout", "main")
      commit.call("feature.rb", "", "Unrelated work")
      git.call("merge", "--no-ff", "bump/finish-1-2-3", "-m", "Merge finish PR")
      commit.call("CHANGELOG.md", "## [1.2.4] - Unreleased\n\n## [1.2.3] - 2026-04-20\n", "Start 1.2.4")

      assert_equal finalize_sha, @task.find_release_commit!("main", output: StringIO.new)
    end
  end

  def test_find_release_commit_tags_a_hotfix_refinalize
    @task.changelog_file = "CHANGELOG.md"
    @task.version_constant = "DischargerTaskTest::TEST_VERSION"

    in_throwaway_repo do |_git, commit|
      commit.call("CHANGELOG.md", "## [1.2.3] - Unreleased\n", "Start 1.2.3")
      commit.call("CHANGELOG.md", "## [1.2.3] - 2026-04-20\n\n- Feature\n", "Finalize 1.2.3")
      commit.call("fix.rb", "", "Hotfix")
      refinalize_sha = commit.call("CHANGELOG.md", "## [1.2.3] - 2026-04-20\n\n- Feature\n- Hotfix\n", "Finalize 1.2.3 again")
      commit.call("later.rb", "", "Merged after the re-finalize")

      assert_equal refinalize_sha, @task.find_release_commit!("main", output: StringIO.new)
    end
  end

  def in_throwaway_repo
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        git = ->(*args) { system("git", "-c", "user.name=Test", "-c", "user.email=test@example.com", *args, exception: true, out: File::NULL, err: File::NULL) }
        commit = ->(file, text, message) {
          File.write(file, text)
          git.call("add", file)
          git.call("commit", "-m", message)
          `git rev-parse HEAD`.strip
        }
        git.call("init", "-q", "-b", "main")
        yield git, commit
      end
    end
  end

  def test_find_release_commit_aborts_when_no_commit_touches_changelog
    @task.changelog_file = "CHANGELOG.md"
    @task.version_constant = "DischargerTaskTest::TEST_VERSION"
    @task.define_singleton_method(:git_file_commits) { |_branch, _path| [] }

    assert_raises(SystemExit) do
      capture_io { @task.find_release_commit!("main") }
    end
  end

  def test_find_release_commit_aborts_when_version_header_missing
    @task.changelog_file = "CHANGELOG.md"
    @task.version_constant = "DischargerTaskTest::TEST_VERSION"
    @task.define_singleton_method(:git_file_commits) { |_branch, _path| ["abc123def456"] }
    @task.define_singleton_method(:git_show_at_commit) do |_ref, _path|
      "## [9.9.9] - 2020-01-01\n\n### Changed\n- Old thing\n"
    end

    assert_raises(SystemExit) do
      capture_io { @task.find_release_commit!("main") }
    end
  end
end

class DischargerReleaseCommandSequenceTest < Minitest::Test
  FAKE_VERSION = "1.2.3"
  FAKE_RELEASE_SHA = "f4c0ffee1234567890abcdef"

  def setup
    @commands = []
    @original_stdin = $stdin
    Rake::Task.define_task(:environment) {} unless Rake::Task.task_defined?(:environment)
  end

  def teardown
    $stdin = @original_stdin
  end

  def build_task(name, pr_label: nil)
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
    task.pr_label = pr_label

    commands = @commands
    task.define_singleton_method(:syscall) do |*steps, **_kwargs, &_block|
      steps.each { |cmd| commands << cmd }
      true
    end
    task.define_singleton_method(:sysecho) { |*_args, **_kwargs| true }
    task.define_singleton_method(:find_release_commit!) { |*_args, **_kwargs| FAKE_RELEASE_SHA }
    task.define_singleton_method(:ensure_branch_not_ahead!) { |_branch| true }
    task.define_singleton_method(:ensure_clean_worktree!) { true }
    task.define_singleton_method(:ensure_tag_absent!) { |_tag| true }

    task
  end

  def stop(task, method)
    task.define_singleton_method(method) { |*_args| raise SystemExit }
  end

  def command_issued?(pattern)
    @commands.any? { |cmd|
      joined = cmd.join(" ")
      pattern.is_a?(Regexp) ? joined.match?(pattern) : joined == pattern
    }
  end

  def test_release_tags_the_release_commit_on_the_working_branch
    task = build_task(:rel_seq)
    task.define
    $stdin = StringIO.new("\n")

    capture_io { Rake::Task["rel_seq"].invoke }

    refute command_issued?(/gh pr/),
      "Release should neither create nor merge a production PR"
    assert command_issued?("git tag -a v1.2.3 -m 'Release 1.2.3' #{FAKE_RELEASE_SHA}"),
      "Should tag the changelog finalize commit"
    assert command_issued?("git push origin v1.2.3"),
      "Should push the tag"
    assert command_issued?("git fetch origin main"),
      "Should fetch the working branch"
    assert command_issued?("git reset --hard origin/main"),
      "Should reset working branch to match remote"
    refute command_issued?(/stage|production/),
      "Release should not touch any other branch"
  end

  def test_release_refuses_to_reset_over_unpushed_commits
    task = build_task(:rel_guard_seq)
    ahead_checked_at = nil
    commands = @commands
    task.define_singleton_method(:ensure_branch_not_ahead!) { |_branch|
      ahead_checked_at = commands.length
      true
    }
    task.define
    $stdin = StringIO.new("\n")

    capture_io { Rake::Task["rel_guard_seq"].invoke }

    reset_idx = @commands.index { |c| c.join(" ") == "git reset --hard origin/main" }
    assert reset_idx, "Expected a reset from origin"
    assert ahead_checked_at, "Expected the unpushed-commit check to run"
    assert_operator ahead_checked_at, :<=, reset_idx,
      "Unpushed-commit check must run before the reset"
  end

  def test_release_checks_the_tree_branch_and_tag_before_asking_to_confirm
    task = build_task(:rel_order)
    events = []
    commands = @commands
    task.define_singleton_method(:ensure_clean_worktree!) { events << :clean }
    task.define_singleton_method(:ensure_branch_not_ahead!) { |_branch| events << :not_ahead }
    task.define_singleton_method(:ensure_tag_absent!) { |tag| events << [:tag_absent, tag] }
    task.define_singleton_method(:find_release_commit!) do |branch, **_kwargs|
      events << [:release_commit, branch]
      FAKE_RELEASE_SHA
    end
    task.define_singleton_method(:confirm_or_exit!) { events << [:confirm, commands.length] }
    task.define
    $stdin = StringIO.new("\n")

    capture_io { Rake::Task["rel_order"].invoke }

    confirm = events.index { |event| event.is_a?(Array) && event.first == :confirm }
    assert_equal [:clean, :not_ahead, [:tag_absent, "v1.2.3"], [:release_commit, "origin/main"]], events.first(confirm),
      "Every check must run before the confirmation prompt"
    checkout_idx = @commands.index { |c| c.join(" ") == "git checkout main" }
    assert_operator events[confirm].last, :<=, checkout_idx,
      "The checkout and reset must wait for the confirmation"
  end

  def test_release_stops_before_tagging_when_the_tag_already_exists
    task = build_task(:rel_tag_exists)
    stop(task, :ensure_tag_absent!)
    task.define
    $stdin = StringIO.new("\n")

    assert_raises(SystemExit) { capture_io { Rake::Task["rel_tag_exists"].invoke } }

    refute command_issued?(/git tag/), "Should not tag over an existing tag"
    refute command_issued?(/git reset/), "Should stop before touching the checkout"
  end

  def test_release_stops_on_a_dirty_tree_before_fetching
    task = build_task(:rel_dirty)
    stop(task, :ensure_clean_worktree!)
    task.define

    assert_raises(SystemExit) { capture_io { Rake::Task["rel_dirty"].invoke } }

    assert_empty @commands
  end

  def test_prepare_stops_on_unpushed_commits_before_resetting
    task = build_task(:rel_prep_ahead)
    stop(task, :ensure_branch_not_ahead!)
    task.define

    assert_raises(SystemExit) { capture_io { Rake::Task["rel_prep_ahead:prepare"].invoke } }

    assert command_issued?("git fetch origin main"), "Should fetch before comparing with origin"
    refute command_issued?(/git reset|git checkout -b/), "Should stop before resetting or branching"
  end

  def test_prepare_resets_working_branch_from_origin_before_branching
    task = build_task(:rel_prep_seq)
    ahead_checked_at = nil
    commands = @commands
    task.define_singleton_method(:ensure_clean_worktree!) { true }
    task.define_singleton_method(:ensure_branch_not_ahead!) { |_branch|
      ahead_checked_at = commands.length
      true
    }
    task.define
    $stdin = StringIO.new("\n")

    capture_io { Rake::Task["rel_prep_seq:prepare"].invoke }

    reset_idx = @commands.index { |c| c.join(" ") == "git reset --hard origin/main" }
    branch_idx = @commands.index { |c| c.join(" ") == "git checkout -b bump/finish-1-2-3" }

    assert reset_idx, "Expected a reset from origin"
    assert branch_idx, "Expected the finish branch to be created"
    assert_operator reset_idx, :<, branch_idx,
      "Finish branch must be cut after resetting to origin"
    assert ahead_checked_at, "Expected the unpushed-commit check to run"
    assert_operator ahead_checked_at, :<=, reset_idx,
      "Unpushed-commit check must run before the reset"
  end

  def test_prepare_creates_labeled_pr_when_pr_label_is_set
    task = build_task(:rel_prep_label, pr_label: "no-changelog-needed")
    task.define_singleton_method(:ensure_clean_worktree!) { true }
    task.define_singleton_method(:ensure_branch_not_ahead!) { |_branch| true }
    task.define_singleton_method(:validate_pr_label!) { true }
    task.define_singleton_method(:existing_pr_number) { |*_args| nil }
    task.define
    $stdin = StringIO.new("\n")

    capture_io { Rake::Task["rel_prep_label:prepare"].invoke }

    assert command_issued?("gh pr create --base main --head bump/finish-1-2-3 --title Finish version 1.2.3 --body Completing development for 1.2.3. --label no-changelog-needed"),
      "Should create the finish PR with the configured label"
    refute command_issued?(/^open /),
      "Should not open a browser compare page when the PR is created directly"
  end

  def test_prepare_keeps_compare_url_flow_without_pr_label
    task = build_task(:rel_prep_nolabel)
    task.define_singleton_method(:ensure_clean_worktree!) { true }
    task.define_singleton_method(:ensure_branch_not_ahead!) { |_branch| true }
    task.define
    $stdin = StringIO.new("\n")

    capture_io { Rake::Task["rel_prep_nolabel:prepare"].invoke }

    refute command_issued?(/gh pr create/),
      "Should not create a PR without a configured label"
    assert command_issued?(/^open http/),
      "Should open the compare URL"
  end

  def test_release_creates_labeled_bump_pr_when_pr_label_is_set
    task = build_task(:rel_bump_label, pr_label: "no-changelog-needed")
    task.define_singleton_method(:validate_pr_label!) { true }
    task.define_singleton_method(:existing_pr_number) { |*_args| nil }
    task.define
    $stdin = StringIO.new("\n")

    capture_io { Rake::Task["rel_bump_label"].invoke }

    assert command_issued?(/gh pr create --base main --head \S+ --title Bump version to \S+ --body  --label no-changelog-needed/),
      "Should create the bump PR with the configured label"
    refute command_issued?(/^open /),
      "Should not open a browser compare page for the bump PR"
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

  def test_ensure_clean_worktree_allows_clean_checkout
    stub_capture3("", "", true)

    assert @task.ensure_clean_worktree!
  end

  def test_ensure_clean_worktree_aborts_on_dirty_checkout
    stub_capture3(" M CHANGELOG.md\n", "", true)

    error = assert_raises(SystemExit) do
      capture_io { @task.ensure_clean_worktree! }
    end
    assert_includes error.message, "before releasing"
  end

  def test_ensure_branch_not_ahead_passes_when_count_is_zero
    stub_capture3("0\n", "", true)
    assert @task.ensure_branch_not_ahead!("main")
  end

  def test_ensure_branch_not_ahead_aborts_when_local_has_unpushed_commits
    stub_capture3("3\n", "", true)

    assert_raises(SystemExit) do
      capture_io { @task.ensure_branch_not_ahead!("main") }
    end
  end

  def test_ensure_branch_not_ahead_passes_when_the_branch_is_not_checked_out_locally
    stub_capture3("", "", false)

    assert @task.ensure_branch_not_ahead!("main")
  end

  def test_ensure_branch_not_ahead_counts_commits_missing_from_origin
    captured = nil
    status = FakeStatus.new(true)
    Open3.define_singleton_method(:capture3) { |*args|
      captured = args
      ["0\n", "", status]
    }

    @task.ensure_branch_not_ahead!("main")

    assert_includes captured, "origin/main..main"
  end

  def test_ensure_tag_absent_passes_when_origin_has_no_such_tag
    stub_capture3("", "", true)

    assert @task.ensure_tag_absent!("v1.2.3")
  end

  def test_ensure_tag_absent_aborts_when_the_tag_exists_on_origin
    stub_capture3("f4c0ffee\trefs/tags/v1.2.3\n", "", true)

    error = assert_raises(SystemExit) do
      capture_io { @task.ensure_tag_absent!("v1.2.3") }
    end
    assert_match(/v1\.2\.3 already exists on origin/, error.message)
  end

  def test_ensure_tag_absent_aborts_when_origin_cannot_be_reached
    stub_capture3("", "fatal: could not read from remote", false)

    error = assert_raises(SystemExit) do
      capture_io { @task.ensure_tag_absent!("v1.2.3") }
    end
    assert_match(/Could not list tags on origin/, error.message)
  end

  def test_validate_pr_label_returns_true_without_label
    assert @task.validate_pr_label!
  end

  def test_validate_pr_label_queries_the_configured_label
    @task.pr_label = "no-changelog-needed"
    captured = nil
    status = FakeStatus.new(true)
    Open3.define_singleton_method(:capture3) { |*args|
      captured = args
      ["no-changelog-needed\n", "", status]
    }

    assert @task.validate_pr_label!
    assert_equal ["gh", "label", "list", "--search", "no-changelog-needed", "--json", "name", "--jq", ".[].name"], captured
  end

  def test_validate_pr_label_aborts_when_label_is_missing
    @task.pr_label = "no-changelog-needed"
    stub_capture3("", "not found", false)

    assert_raises(SystemExit) do
      capture_io { @task.validate_pr_label! }
    end
  end

  def test_validate_pr_label_aborts_when_search_only_finds_other_labels
    @task.pr_label = "no-changelog-needed"
    stub_capture3("Refactor\n", "", true)

    assert_raises(SystemExit) do
      capture_io { @task.validate_pr_label! }
    end
  end

  def test_create_labeled_pr_creates_pr_with_label
    @task.pr_label = "no-changelog-needed"
    @task.define_singleton_method(:existing_pr_number) { |*_args| nil }
    created = nil
    @task.define_singleton_method(:syscall) { |*steps|
      created = steps
      true
    }

    @task.create_labeled_pr!(head: "bump/finish-1-2-3", title: "Finish version 1.2.3", body: "Completing development for 1.2.3.")

    assert_equal [["gh", "pr", "create", "--base", "main", "--head", "bump/finish-1-2-3", "--title", "Finish version 1.2.3", "--body", "Completing development for 1.2.3.", "--label", "no-changelog-needed"]], created
  end

  def test_create_labeled_pr_reuses_existing_pr
    @task.pr_label = "no-changelog-needed"
    @task.define_singleton_method(:existing_pr_number) { |*_args| "17" }
    created = false
    @task.define_singleton_method(:syscall) { |*_steps|
      created = true
    }
    echoed = nil
    @task.define_singleton_method(:sysecho) { |message, **_kwargs|
      echoed = message
      true
    }

    @task.create_labeled_pr!(head: "bump/finish-1-2-3", title: "Finish version 1.2.3", body: "")

    refute created, "Should not run gh pr create when a PR already exists"
    assert_match(/Reusing existing PR #17/, echoed)
  end
end

class DischargerExistingPrNumberTest < Minitest::Test
  include Capture3Stubbing

  def setup
    @task = Discharger::Task.new
  end

  def test_returns_pr_number_when_pr_exists
    stub_capture3(stdout: "42\n") do
      assert_equal "42", @task.existing_pr_number("main", "bump/finish-1-2-3")
    end
  end

  def test_returns_nil_when_no_pr_exists
    stub_capture3 do
      assert_nil @task.existing_pr_number("main", "bump/finish-1-2-3")
    end
  end

  def test_returns_nil_on_command_failure
    stub_capture3(stderr: "error", success: false) do
      assert_nil @task.existing_pr_number("main", "bump/finish-1-2-3")
    end
  end
end

class DischargerRunbookAnnouncementTest < Minitest::Test
  def setup
    @task = Discharger::Task.new
  end

  def test_returns_nil_when_runbook_is_not_configured
    assert_nil @task.runbook_announcement("1.2.3", ["Run `rake data:cleanup`"])
  end

  def test_reports_no_tasks_when_runbook_is_empty
    @task.runbook_file = "RUNBOOK.md"

    assert_equal <<~MSG.chomp, @task.runbook_announcement("1.2.3", [])
      *Post-release runbook for 1.2.3*
      No runbook tasks for this release.
    MSG
  end

  def test_uses_singular_step_for_a_single_item
    @task.runbook_file = "RUNBOOK.md"

    assert_equal <<~MSG.chomp, @task.runbook_announcement("1.2.3", ["Run `rake data:cleanup`"])
      *Post-release runbook for 1.2.3* — 1 step

      • Run `rake data:cleanup`
    MSG
  end

  def test_lists_every_item_as_a_bullet
    @task.runbook_file = "RUNBOOK.md"
    items = ["Run `rake data:cleanup` (abc1234)", "Re-index search documents (def5678)"]

    assert_equal <<~MSG.chomp, @task.runbook_announcement("1.2.3", items)
      *Post-release runbook for 1.2.3* — 2 steps

      • Run `rake data:cleanup` (abc1234)
      • Re-index search documents (def5678)
    MSG
  end

  def test_runbook_items_are_empty_when_runbook_is_not_configured
    assert_empty @task.runbook_items
  end

  def test_runbook_items_reads_checklist_text_from_the_runbook_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, "RUNBOOK.md")
      File.write(path, <<~MARKDOWN)
        # Runbook

        Steps to perform after releasing the version below.

        ## [1.2.3] - 2026-07-21

        - [ ] Run `rake data:cleanup` (abc1234)
        - [x] Re-index search documents (def5678)
      MARKDOWN

      @task.runbook_file = path

      assert_equal [
        "Run `rake data:cleanup` (abc1234)",
        "Re-index search documents (def5678)"
      ], @task.runbook_items
    end
  end
end

class DischargerRunbookForwardingTest < Minitest::Test
  def test_create_forwards_runbook_file_to_reissue
    captured_runbook_file = nil

    original_create = Reissue::Task.method(:create)
    Reissue::Task.define_singleton_method(:create) do |name = :reissue, &block|
      reissue_task = Reissue::Task.new(name)
      block&.call(reissue_task)
      captured_runbook_file = reissue_task.runbook_file
      reissue_task
    end

    Discharger::Task.create(:test_runbook_file) do
      self.version_file = "VERSION"
      self.runbook_file = "RUNBOOK.md"
    end

    assert_equal "RUNBOOK.md", captured_runbook_file
  ensure
    Reissue::Task.define_singleton_method(:create, original_create)
  end
end

class DischargerReleaseThreadTest < Minitest::Test
  FAKE_VERSION = "1.2.3"

  def setup
    @slack_calls = []
    @original_stdin = $stdin
    Rake::Task.define_task(:environment) {} unless Rake::Task.task_defined?(:environment)

    # The release task reads the changelog straight off disk to post it to Slack.
    @changelog_path = Rails.root.join("CHANGELOG.md")
    File.write(@changelog_path, "## [1.2.3]\n\n### Fixed\n\n- A bug\n")
  end

  def teardown
    $stdin = @original_stdin
    FileUtils.rm_f(@changelog_path)
  end

  # Builds a task whose :slack subtask records its arguments and assigns a new
  # message timestamp on each post, the way the real Slack task does.
  def build_task(name, runbook_items: nil)
    holder = []
    slack_calls = @slack_calls
    timestamps = ["ROOT.1", "REPLY.1", "REPLY.2"]

    noop = Object.new
    noop.define_singleton_method(:invoke) { |*_args| }
    noop.define_singleton_method(:reenable) {}

    slack = Object.new
    slack.define_singleton_method(:reenable) {}
    slack.define_singleton_method(:invoke) do |*args|
      slack_calls << args
      holder.first.instance_variable_set(:@last_message_ts, timestamps.shift)
    end

    tasker = Object.new
    tasker.define_singleton_method(:[]) do |task_name|
      task_name.to_s.end_with?(":slack") ? slack : noop
    end

    task = Discharger::Task.new(name, tasker:)
    holder << task

    task.version_constant = "DischargerReleaseThreadTest::FAKE_VERSION"
    task.version_file = "VERSION"
    task.changelog_file = "CHANGELOG.md"
    task.release_message_channel = "#releases"
    task.chat_token = "fake_token"
    task.pull_request_url = "http://example.com"
    task.app_name = "TestApp"
    task.commit_identifier = -> { "abc123" }
    task.runbook_file = runbook_items && "RUNBOOK.md"

    task.define_singleton_method(:syscall) do |*_steps, **_kwargs, &block|
      block&.call("", "", nil)
      true
    end
    task.define_singleton_method(:sysecho) { |*_args, **_kwargs| true }
    task.define_singleton_method(:ensure_branch_not_ahead!) { |_branch| true }
    task.define_singleton_method(:ensure_clean_worktree!) { true }
    task.define_singleton_method(:ensure_tag_absent!) { |_tag| true }
    task.define_singleton_method(:find_release_commit!) { |*_args, **_kwargs| "f4c0ffee1234567890abcdef" }
    changelog_text = File.read(@changelog_path)
    task.define_singleton_method(:git_show_at_commit) { |_sha, _path| changelog_text }
    task.define_singleton_method(:runbook_items) { runbook_items || [] }

    task
  end

  def run_release(name, runbook_items: nil)
    task = build_task(name, runbook_items:)
    task.define
    $stdin = StringIO.new("\n")
    capture_io { Rake::Task[name.to_s].invoke }
    task
  end

  def test_posts_runbook_as_a_reply_in_the_release_thread
    run_release(:rel_runbook, runbook_items: ["Run `rake data:cleanup`"])

    assert_equal 3, @slack_calls.size, "Expected announcement, changelog, and runbook"

    runbook_text, channel, emoji, ts = @slack_calls.last
    assert_match(/Post-release runbook for 1\.2\.3/, runbook_text)
    assert_match(/• Run `rake data:cleanup`/, runbook_text)
    assert_equal "#releases", channel
    assert_equal ":clipboard:", emoji
    assert_equal "ROOT.1", ts, "Runbook must thread off the release announcement"
  end

  def test_threads_changelog_and_runbook_off_the_release_announcement
    run_release(:rel_thread_root, runbook_items: ["Rotate the signing key"])

    changelog_ts = @slack_calls[1][3]
    runbook_ts = @slack_calls[2][3]

    assert_equal "ROOT.1", changelog_ts
    assert_equal "ROOT.1", runbook_ts,
      "Runbook must thread off the root, not off the changelog reply"
  end

  def test_reports_no_tasks_when_runbook_is_configured_but_empty
    run_release(:rel_runbook_empty, runbook_items: [])

    assert_equal 3, @slack_calls.size
    assert_match(/No runbook tasks for this release\./, @slack_calls.last.first)
  end

  def test_posts_nothing_extra_when_runbook_is_not_configured
    run_release(:rel_no_runbook, runbook_items: nil)

    assert_equal 2, @slack_calls.size,
      "Projects without a runbook should only get the announcement and changelog"
  end
end

class DischargerSlackTaskTest < Minitest::Test
  # A fake Slack::Web::Client whose chat_postMessage records its options and
  # either returns the response or raises the error it was built with.
  FakeClient = Struct.new(:response, :error, :calls) do
    def chat_postMessage(**options)
      calls << options
      raise error if error
      response
    end
  end

  def setup
    Rake::Task.define_task(:environment) {} unless Rake::Task.task_defined?(:environment)
    @task = Discharger::Task.new(:"slack_#{name}")
    @task.release_message_channel = "#releases"
    @task.chat_token = "fake_token"
    @task.instance_variable_set(:@last_message_ts, "STALE")
  end

  def slack_task
    @task.define
    Rake::Task["#{@task.name}:slack"]
  end

  # Swaps Slack::Web::Client.new for the duration of the block. Takes a client
  # to hand back, or a block-less lambda to run in its place.
  def stub_slack_client(client)
    original = Slack::Web::Client.method(:new)
    Slack::Web::Client.define_singleton_method(:new) do |*_args, **_opts|
      client.respond_to?(:call) ? client.call : client
    end
    yield
  ensure
    Slack::Web::Client.define_singleton_method(:new, original)
  end

  def test_skips_posting_when_chat_token_is_blank
    @task.chat_token = nil
    task = slack_task

    stub_slack_client(-> { flunk "Built a Slack client without a token" }) do
      output, _ = capture_io { task.invoke("Released 1.2.3") }
      assert_match(/Slack message not sent: chat_token is not set\./, output)
      assert_match(/Slack release token from your team.s password manager/, output)
      assert_match(/Post this to #releases yourself:\n\nReleased 1\.2\.3\n/, output)
    end
    assert_nil @task.last_message_ts
  end

  def test_continues_when_slack_rejects_the_message
    task = slack_task
    client = FakeClient.new(nil, Slack::Web::Api::Errors::InvalidAuth.new("invalid_auth"), [])

    stub_slack_client(client) do
      output, _ = capture_io { task.invoke("Released 1.2.3") }
      assert_match(/Slack message not sent: invalid_auth\./, output)
      assert_match(/Post this to #releases yourself:\n\nReleased 1\.2\.3\n/, output)
    end
    assert_nil @task.last_message_ts
  end

  def test_posts_the_message_and_records_its_timestamp
    task = slack_task
    client = FakeClient.new({"ts" => "123.456"}, nil, [])

    stub_slack_client(client) do
      assert_output(/Message sent: 123\.456/) do
        task.invoke("Released 1.2.3", nil, ":chipmunk:", "111.222")
      end
    end

    assert_equal "123.456", @task.last_message_ts
    assert_equal(
      [{text: "Released 1.2.3", channel: "#releases", icon_emoji: ":chipmunk:", thread_ts: "111.222"}],
      client.calls
    )
  end
end

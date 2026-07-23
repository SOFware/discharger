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

  TEST_VERSION = "1.2.3"

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

  def build_task(name, auto_deploy:, pr_label: nil)
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
    task.pr_label = pr_label

    commands = @commands
    task.define_singleton_method(:syscall) do |*steps, **_kwargs, &_block|
      steps.each { |cmd| commands << cmd }
      true
    end
    task.define_singleton_method(:sysecho) { |*_args, **_kwargs| true }
    task.define_singleton_method(:validate_version_match!) { |*_args, **_kwargs| true }
    task.define_singleton_method(:find_release_commit!) { |*_args, **_kwargs| FAKE_RELEASE_SHA }
    task.define_singleton_method(:pr_already_merged?) { |_ref| false }

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

  def test_auto_deploy_mode_tags_release_commit_directly
    task = build_task(:rel_auto_seq, auto_deploy: true)
    task.define
    $stdin = StringIO.new("\n")

    capture_io { Rake::Task["rel_auto_seq"].invoke }

    refute command_issued?(/gh pr create/),
      "Auto-deploy should not create a production PR"
    refute command_issued?(/gh pr merge/),
      "Auto-deploy should not merge a PR"
    assert command_issued?("git tag -a v1.2.3 -m 'Release 1.2.3' #{FAKE_RELEASE_SHA}"),
      "Should tag the changelog finalize commit"
    assert command_issued?("git push origin v1.2.3"),
      "Should push the tag"
    assert command_issued?("git fetch origin develop"),
      "Should fetch the working branch"
    assert command_issued?("git reset --hard origin/develop"),
      "Should reset working branch to match remote"
  end

  def test_prepare_resets_working_branch_from_origin_before_branching
    task = build_task(:rel_prep_seq, auto_deploy: true)
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

    reset_idx = @commands.index { |c| c.join(" ") == "git reset --hard origin/develop" }
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
    task = build_task(:rel_prep_label, auto_deploy: true, pr_label: "no-changelog-needed")
    task.define_singleton_method(:ensure_clean_worktree!) { true }
    task.define_singleton_method(:ensure_branch_not_ahead!) { |_branch| true }
    task.define_singleton_method(:validate_pr_label!) { true }
    task.define_singleton_method(:existing_pr_number) { |*_args| nil }
    task.define
    $stdin = StringIO.new("\n")

    capture_io { Rake::Task["rel_prep_label:prepare"].invoke }

    assert command_issued?("gh pr create --base develop --head bump/finish-1-2-3 --title 'Finish version 1.2.3' --body 'Completing development for 1.2.3.' --label 'no-changelog-needed'"),
      "Should create the finish PR with the configured label"
    refute command_issued?(/^open /),
      "Should not open a browser compare page when the PR is created directly"
  end

  def test_prepare_keeps_compare_url_flow_without_pr_label
    task = build_task(:rel_prep_nolabel, auto_deploy: true)
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
    task = build_task(:rel_bump_label, auto_deploy: true, pr_label: "no-changelog-needed")
    task.define_singleton_method(:validate_pr_label!) { true }
    task.define_singleton_method(:existing_pr_number) { |*_args| nil }
    task.define
    $stdin = StringIO.new("\n")

    capture_io { Rake::Task["rel_bump_label"].invoke }

    assert command_issued?(/gh pr create --base develop --head \S+ --title 'Bump version to \S+' --body '' --label 'no-changelog-needed'/),
      "Should create the bump PR with the configured label"
    refute command_issued?(/^open /),
      "Should not open a browser compare page for the bump PR"
  end

  def test_standard_mode_skips_merge_when_pr_already_merged
    task = build_task(:rel_merged_seq, auto_deploy: false)
    task.define_singleton_method(:pr_already_merged?) { |_ref| true }
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

  def test_ensure_branch_not_ahead_counts_commits_missing_from_origin
    captured = nil
    status = FakeStatus.new(true)
    Open3.define_singleton_method(:capture3) { |*args|
      captured = args
      ["0\n", "", status]
    }

    @task.ensure_branch_not_ahead!("develop")

    assert_includes captured, "origin/develop..develop"
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
      ["", "", status]
    }

    assert @task.validate_pr_label!
    assert_equal ["gh", "label", "view", "no-changelog-needed"], captured
  end

  def test_validate_pr_label_aborts_when_label_is_missing
    @task.pr_label = "no-changelog-needed"
    stub_capture3("", "not found", false)

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

    assert_equal [["gh pr create --base develop --head bump/finish-1-2-3 --title 'Finish version 1.2.3' --body 'Completing development for 1.2.3.' --label 'no-changelog-needed'"]], created
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

class DischargerPrAlreadyMergedTest < Minitest::Test
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

  def test_returns_true_when_pr_is_merged
    stub_capture3("MERGED\n", "", true)
    assert @task.pr_already_merged?("stage")
  end

  def test_returns_false_when_pr_is_open
    stub_capture3("OPEN\n", "", true)
    refute @task.pr_already_merged?("stage")
  end

  def test_returns_false_on_command_failure
    stub_capture3("", "error", false)
    refute @task.pr_already_merged?("stage")
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
    task.define_singleton_method(:validate_version_match!) { |*_args, **_kwargs| true }
    task.define_singleton_method(:pr_already_merged?) { |_ref| false }
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

class DischargerStageAnnouncementTest < Minitest::Test
  FAKE_VERSION = "1.2.3"

  def setup
    @slack_calls = []
    Rake::Task.define_task(:environment) {} unless Rake::Task.task_defined?(:environment)
  end

  # Builds a task whose :slack subtask records its arguments and assigns a new
  # message timestamp on each post, the way the real Slack task does.
  def build_task(name, runbook_items: nil)
    holder = []
    slack_calls = @slack_calls
    timestamps = ["ROOT.1", "REPLY.1"]

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

    task.version_constant = "DischargerStageAnnouncementTest::FAKE_VERSION"
    task.version_file = "VERSION"
    task.release_message_channel = "#releases"
    task.chat_token = "fake_token"
    task.app_name = "TestApp"
    task.commit_identifier = -> { "abc123" }
    task.runbook_file = runbook_items && "RUNBOOK.md"

    task.define_singleton_method(:syscall) do |*_steps, **_kwargs, &block|
      block&.call("", "", nil)
      true
    end
    task.define_singleton_method(:sysecho) { |*_args, **_kwargs| true }
    task.define_singleton_method(:runbook_items) { runbook_items || [] }

    task
  end

  def run_build(name, runbook_items: nil)
    task = build_task(name, runbook_items:)
    task.define
    capture_io { Rake::Task["#{name}:build"].invoke }
    task
  end

  def test_build_posts_runbook_as_a_reply_in_the_stage_thread
    run_build(:stage_runbook, runbook_items: ["Run `rake data:cleanup`"])

    assert_equal 2, @slack_calls.size, "Expected the build announcement and the runbook"

    runbook_text, channel, emoji, ts = @slack_calls.last
    assert_match(/Post-release runbook for 1\.2\.3/, runbook_text)
    assert_match(/• Run `rake data:cleanup`/, runbook_text)
    assert_equal "#releases", channel
    assert_equal ":clipboard:", emoji
    assert_equal "ROOT.1", ts, "Runbook must thread off the build announcement"
  end

  def test_build_reports_no_tasks_when_runbook_is_configured_but_empty
    run_build(:stage_runbook_empty, runbook_items: [])

    assert_equal 2, @slack_calls.size
    assert_match(/No runbook tasks for this release\./, @slack_calls.last.first)
  end

  def test_build_posts_nothing_extra_when_runbook_is_not_configured
    run_build(:stage_no_runbook, runbook_items: nil)

    assert_equal 1, @slack_calls.size,
      "Projects without a runbook should only get the build announcement"
  end
end

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
  end

  def test_create
    task = Discharger::Task.create(:test_task) do
      self.version_file = "VERSION"
      self.version_limit = "1.0.0"
      self.version_redo_proc = -> { "1.0.1" }
      self.changelog_file = "CHANGELOG.md"
      self.updated_paths = ["lib/"]
      self.commit = "Initial commit"
      self.commit_finalize = "Finalize commit"
    end

    assert_equal :test_task, task.name
    assert_equal "VERSION", task.version_file
    assert_equal "1.0.0", task.version_limit
    assert_equal "1.0.1", task.version_redo_proc.call
    assert_equal "CHANGELOG.md", task.changelog_file
    assert_equal ["lib/"], task.updated_paths
    assert_equal "Initial commit", task.commit
    assert_equal "Finalize commit", task.commit_finalize
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
end

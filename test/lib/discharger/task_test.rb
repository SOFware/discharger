require_relative "../../test_helper"
require "fileutils"
require "open3"
require "minitest/mock"

class DischargerTaskTest < Minitest::Test
  def setup
    @task = Discharger::Task.new
    @task.version_constant = "VERSION"
    @task.app_name = "TestApp"
    @task.release_message_channel = "#test-channel"
    @task.chat_token = "test-token"
    @task.pull_request_url = "https://github.com/test/test"
  end

  def test_initialize_with_default_values
    task = Discharger::Task.new
    assert_equal :release, task.name
    assert_equal "develop", task.working_branch
    assert_equal "stage", task.staging_branch
    assert_equal "main", task.production_branch
    assert_equal "Release the current version to stage", task.description
  end

  def test_create_configures_reissue_task
    mock_reissue = Minitest::Mock.new
    # Mock all methods that Reissue::Task calls
    mock_reissue.expect(:version_file=, nil, [String])
    mock_reissue.expect(:version_limit=, nil, [Object])
    mock_reissue.expect(:version_redo_proc=, nil, [Object])
    mock_reissue.expect(:changelog_file=, nil, [String])
    mock_reissue.expect(:updated_paths=, nil, [Object])
    mock_reissue.expect(:commit=, nil, [Object])
    mock_reissue.expect(:commit_finalize=, nil, [Object])

    Reissue::Task.stub :create, ->(&block) { block.call(mock_reissue) } do
      Discharger::Task.create do |t|
        t.version_file = "VERSION"
        t.version_limit = 5
        t.version_redo_proc = -> {}
        t.changelog_file = "CHANGELOG.md"
        t.updated_paths = []
        t.commit = -> {}
        t.commit_finalize = -> {}
      end
    end

    mock_reissue.verify
  end

  def test_syscall_success
    output = StringIO.new
    error = StringIO.new

    # Silence the command output
    silence_output do
      result = @task.syscall(["echo", "test"], output: output, error: error)
      assert result
      assert_includes output.string, "test"
    end
  end

  def test_syscall_failure
    output = StringIO.new
    error = StringIO.new

    # Silence the command output
    silence_output do
      assert_raises(SystemExit) do
        @task.syscall(["false"], output: output, error: error)
      end
    end
  end

  def test_sysecho_outputs_message
    output = StringIO.new
    result = @task.sysecho("test message", output: output)
    assert result
    assert_equal "test message\n", output.string
  end

  def test_define
    @task.chat_token = "fake_token"
    @task.release_message_channel = "#general"
    @task.version_constant = "VERSION"
    @task.pull_request_url = "http://example.com"

    @task.define

    expected_tasks = [
      "prepare",
      "release",
      "release:build",
      "release:config",
      "release:slack",
      "stage"
    ]

    actual_tasks = Rake::Task.tasks.map(&:name).sort
    expected_tasks.each do |task_name|
      assert_includes actual_tasks, task_name, "Expected task '#{task_name}' to exist"
    end
  end

  private

  def silence_output
    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    yield
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
  end
end

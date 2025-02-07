require "test_helper"
require "discharger/task"
require "rake"

# Mock Rails.root for changelog path
unless defined?(Rails)
  module Rails
    def self.root
      Pathname.new(Dir.pwd)
    end
  end
end

class PrepareTest < Minitest::Test
  include Rake::DSL

  def setup
    # Initialize Rake
    @rake = Rake::Application.new
    Rake.application = @rake

    # Create a new Task instance
    @task = Discharger::Task.new

    # Required instance variables from Task class
    @task.name = "test_#{name}"
    @task.version_constant = "VERSION"
    @task.working_branch = "main"
    @task.staging_branch = "staging"
    @task.production_branch = "production"
    @task.release_message_channel = "#releases"
    @task.changelog_file = "CHANGELOG.md"
    @task.app_name = "TestApp"
    @task.pull_request_url = "https://github.com/org/repo/pulls"
    @task.description = "Build and release the application"

    # Mock environment task since it's a prerequisite
    task :environment do
      # No-op for testing
    end

    # Mock VERSION constant
    Object.const_set(:VERSION, "1.0.0") unless Object.const_defined?(:VERSION)

    # Mock reissue:finalize task since it's called by prepare
    task "reissue:finalize"

    # Define helper methods on the task instance
    def @task.commit_identifier
      -> { "abc123" }
    end

    # Stub syscall and sysecho before defining tasks
    @called_commands = []
    def @task.syscall(*commands)
      @called_commands ||= []
      @called_commands.concat(commands.flatten)
      yield if block_given?
      true
    end

    @echoed_messages = []
    def @task.sysecho(message)
      @echoed_messages ||= []
      @echoed_messages << message
    end

    # Call define to set up the tasks
    @task.define
  end

  def teardown
    # Clear Rake tasks between tests
    Rake.application.clear
    Rake::Task.clear
  end

  def test_prepare_for_release_defines_task
    task_names = Rake.application.tasks.map(&:name)
    assert_includes task_names, "prepare"
  end

  def test_prepare_task_executes_expected_git_commands
    # Mock stdin to simulate user pressing enter
    stdin_mock = StringIO.new("\n")
    $stdin = stdin_mock

    Rake::Task["prepare"].invoke
    expected_commands = [
      "git fetch origin main",
      "git checkout main",
      "git checkout -b bump/finish-1-0-0",
      "git push origin bump/finish-1-0-0 --force",
      "git push origin bump/finish-1-0-0 --force",
      "git checkout main",
      "open"  # The PR URL command will be partially matched
    ]

    actual_commands = @task.instance_variable_get(:@called_commands)
    expected_commands.each do |expected_cmd|
      assert_includes actual_commands.join(" "), expected_cmd
    end
  ensure
    $stdin = STDIN
  end

  def test_prepare_task_handles_user_exit
    # Mock stdin to simulate user typing 'x'
    stdin_mock = StringIO.new("x\n")
    $stdin = stdin_mock

    assert_raises(SystemExit) do
      Rake::Task["prepare"].invoke
    end

    expected_commands = [
      "git fetch origin main",
      "git checkout main",
      "git checkout -b bump/finish-1-0-0",
      "git push origin bump/finish-1-0-0 --force"
    ]

    actual_commands = @task.instance_variable_get(:@called_commands)
    assert_equal expected_commands, actual_commands
  ensure
    $stdin = STDIN
  end

  def test_prepare_task_outputs_expected_messages
    # Mock stdin to simulate user pressing enter
    stdin_mock = StringIO.new("\n")
    $stdin = stdin_mock

    Rake::Task["prepare"].invoke

    messages = @task.instance_variable_get(:@echoed_messages)
    assert_includes messages.join, "Branch bump/finish-1-0-0 created"
    assert_includes messages.join, "Check the contents of the CHANGELOG"
    assert_includes messages.join, "Are you ready to continue?"
  ensure
    $stdin = STDIN
  end
end

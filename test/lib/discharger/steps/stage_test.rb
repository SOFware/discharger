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

class Discharger::Steps::StageTest < Minitest::Test
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
    task :environment
    task :build

    # Mock VERSION constant
    Object.const_set(:VERSION, "1.0.0") unless Object.const_defined?(:VERSION)

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

  def test_stage_release_branch_defines_task
    task_names = Rake.application.tasks.map(&:name)
    assert_includes task_names, "stage"
  end

  def test_stage_task_executes_expected_commands
    Rake::Task["stage"].invoke

    expected_url = "open https://github.com/org/repo/pulls/compare/production...staging"
    actual_commands = @task.instance_variable_get(:@called_commands)
    assert_includes actual_commands.join(" "), expected_url
  end

  def test_stage_task_outputs_expected_messages
    Rake::Task["stage"].invoke

    messages = @task.instance_variable_get(:@echoed_messages)
    expected_messages = [
      "Branch staging updated",
      "Open a PR to production to release the version",
      "Once the PR is **approved**, run 'rake release' to release the version"
    ]

    expected_messages.each do |expected_msg|
      assert_includes messages.join, expected_msg
    end
  end

  def test_stage_task_includes_version_in_pr_url
    Rake::Task["stage"].invoke

    actual_commands = @task.instance_variable_get(:@called_commands)
    url = actual_commands.join(" ")
    assert_includes url, "title=Release+1.0.0+to+production"
    assert_includes url, "body=Deploy+1.0.0+to+production"
  end

  def test_stage_task_invokes_build_task
    build_invoked = false
    Rake::Task[:build].enhance { build_invoked = true }

    Rake::Task["stage"].invoke
    assert build_invoked, "Build task should be invoked"
  end
end

require "test_helper"
require "discharger/task"
require "rake"
require "tempfile"

# Mock Rails.root for changelog path
unless defined?(Rails)
  module Rails
    def self.root
      Pathname.new(Dir.pwd)
    end
  end
end

# Mock Slack client with silent operation
unless defined?(Slack)
  module Slack
    def self.configure
      yield(nil)
    end

    module Web
      class Client
        def initialize
        end

        def chat_postMessage(**options)
          # Return silently without printing
          {"ts" => "123.456"}
        end
      end
    end
  end
end

class Discharger::Steps::ReleaseTest < Minitest::Test
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

    # Mock VERSION constant
    Object.const_set(:VERSION, "1.0.0") unless Object.const_defined?(:VERSION)

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

  def test_release_to_production_defines_task
    task_names = Rake.application.tasks.map(&:name)
    assert_includes task_names, @task.name.to_s
  end

  def test_release_to_production_defines_config_task
    task_names = Rake.application.tasks.map(&:name)
    assert_includes task_names, "#{@task.name}:config"
  end

  def test_release_to_production_defines_build_task
    task_names = Rake.application.tasks.map(&:name)
    assert_includes task_names, "#{@task.name}:build"
  end

  def test_release_to_production_defines_slack_task
    task_names = Rake.application.tasks.map(&:name)
    assert_includes task_names, "#{@task.name}:slack"
  end

  def test_build_task_executes_expected_git_commands
    Rake::Task["#{@task.name}:build"].invoke
    expected_commands = [
      "git fetch origin main",
      "git checkout main",
      "git branch -D staging 2>/dev/null || true",
      "git checkout -b staging",
      "git push origin staging --force",
      "git checkout main"
    ]
    actual_commands = @task.instance_variable_get(:@called_commands)
    assert_equal expected_commands, actual_commands
  end

  def test_slack_task_with_default_parameters
    Rake::Task["#{@task.name}:slack"].invoke("Test message")
    messages = @task.instance_variable_get(:@echoed_messages)
    assert_includes messages.join, "Test message"
  end

  def test_slack_task_with_custom_parameters
    Rake::Task["#{@task.name}:slack"].invoke("Test message", "#custom", ":smile:")
    messages = @task.instance_variable_get(:@echoed_messages)
    assert_includes messages.join, "Test message"
  end

  def test_tagging_a_gem
    original_changelog = @task.changelog_file

    @task.mono_repo = true
    @task.gem_tag = "gem-v1.0.0"

    # Mock gets method to return 'y'
    def $stdin.gets
      "y\n"
    end

    begin
      # Clear and redefine tasks while preserving setup state
      Rake.application.clear
      Rake::Task.clear

      # Re-mock prerequisite tasks
      task :environment
      task :reissue
      task :build
      task :slack
      task :config

      # Mock VERSION constant again
      Object.const_set(:VERSION, "1.0.0") unless Object.const_defined?(:VERSION)

      @task.define
      Rake::Task["#{@task.name}"].invoke

      # Use instance variables set in setup
      assert_includes @echoed_messages.join, "Would you like to tag and release"
      assert_includes @called_commands, "git tag gem-v1.0.0"
      assert_includes @called_commands, "git push --tags"
      assert_includes @echoed_messages.join, "Successfully tagged and pushed gem-v1.0.0"
    ensure
      # Remove the mock method
      class << $stdin
        remove_method :gets
      end
      # Restore original values
      @task.changelog_file = original_changelog
    end
  end
end

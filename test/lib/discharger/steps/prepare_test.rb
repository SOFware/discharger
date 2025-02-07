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

class Discharger::Steps::PrepareTest < Minitest::Test
  include Rake::DSL

  def setup
    # Initialize Rake
    @rake = Rake::Application.new
    Rake.application = @rake

    # Create a temporary changelog file
    @changelog = Tempfile.new(["CHANGELOG", ".md"])
    @changelog.write("## Version 1.0.0\n\n* Initial release\n")
    @changelog.close

    # Create a new Task instance
    @task = Discharger::Task.new

    # Required instance variables from Task class
    @task.name = "test_#{name}"
    @task.version_constant = "VERSION"
    @task.working_branch = "main"
    @task.staging_branch = "staging"
    @task.production_branch = "production"
    @task.changelog_file = @changelog.path
    @task.description = "Build and release the application"

    # Mock environment task since it's a prerequisite
    task :environment

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
    # Clean up temporary changelog file
    @changelog.unlink
  end

  def test_prepare_for_release_defines_task
    task_names = Rake.application.tasks.map(&:name)
    assert_includes task_names, "prepare"
  end

  def test_prepare_task_executes_expected_git_commands
    Rake::Task["prepare"].invoke

    expected_commands = [
      "git fetch origin main",
      "git checkout main",
      "git pull origin main"
    ]
    actual_commands = @task.instance_variable_get(:@called_commands)
    assert_equal expected_commands, actual_commands
  end

  def test_prepare_task_outputs_expected_messages
    Rake::Task["prepare"].invoke

    messages = @task.instance_variable_get(:@echoed_messages)
    expected_messages = [
      "Preparing version 1.0.0 for release",
      "Checking changelog for version 1.0.0",
      "Version 1.0.0 is ready for release"
    ]

    expected_messages.each do |expected_msg|
      assert_includes messages, expected_msg
    end
  end

  def test_prepare_task_checks_changelog
    @changelog = Tempfile.new(["CHANGELOG", ".md"])
    @changelog.write("No version information")
    @changelog.close
    @task.changelog_file = @changelog.path

    error = assert_raises(RuntimeError) do
      Rake::Task["prepare"].invoke
    end

    assert_equal "Version 1.0.0 not found in #{@changelog.path}", error.message
  end

  def test_prepare_task_with_gem_tag
    @task.mono_repo = true
    @task.gem_tag = "gem-v1.0.0"

    Rake::Task["prepare"].invoke

    expected_commands = [
      "git fetch origin gem-v1.0.0",
      "git tag -l gem-v1.0.0",
      "git fetch origin main",
      "git checkout main",
      "git pull origin main"
    ]
    actual_commands = @task.instance_variable_get(:@called_commands)
    assert_equal expected_commands, actual_commands
  end
end

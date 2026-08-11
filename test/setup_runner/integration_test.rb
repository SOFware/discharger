require "test_helper"
require "setup_runner_test_helper"
require "discharger/setup_runner"

class SetupRunnerIntegrationTest < ActiveSupport::TestCase
  include SetupRunnerTestHelper

  test "runs setup with configuration file" do
    # Create a simple configuration
    config_content = <<~YAML
      app_name: TestApp
      steps:
        - env
      custom_steps:
        - description: "Create test file"
          command: "touch test_output.txt"
    YAML

    create_file("setup.yml", config_content)
    create_file(".env.example", "TEST_VAR=example")

    # Run the setup with silent logger
    logger = Logger.new(StringIO.new)
    capture_output do
      Discharger::SetupRunner.run("setup.yml", logger)
    end

    # Verify env command created .env file
    assert_file_exists(".env")
    assert_file_contains(".env", "TEST_VAR=example")

    # Verify custom command ran
    assert_file_exists("test_output.txt")
  end

  test "warns when github_packages is configured but missing from steps" do
    create_file("setup.yml", <<~YAML)
      app_name: TestApp
      github_packages:
        source: "https://rubygems.pkg.github.com/example"
      steps:
        - env
    YAML

    io = StringIO.new
    capture_output do
      Discharger::SetupRunner.run("setup.yml", Logger.new(io))
    end

    assert_match(/github_packages is configured but missing from steps/, io.string)
    assert_match(%r{https://rubygems\.pkg\.github\.com/example}, io.string)
  end

  test "warns about unscheduled github_packages without an explicit logger" do
    create_file("setup.yml", <<~YAML)
      app_name: TestApp
      github_packages:
        source: "https://rubygems.pkg.github.com/example"
      steps:
        - env
    YAML

    out, _ = capture_output do
      Discharger::SetupRunner.run("setup.yml")
    end

    assert_match(/github_packages is configured but missing from steps/, out,
      "the warning must reach the default stdout logger, as bin/setup passes none")
  end

  test "stays quiet when github_packages is configured and scheduled" do
    create_file("setup.yml", <<~YAML)
      app_name: TestApp
      github_packages:
        source: "https://rubygems.pkg.github.com/example"
      steps:
        - github_packages
        - env
    YAML

    # Swap in a no-op subclass so the test never shells out to gh or the
    # network; the real command would probe the source with live credentials.
    registry = Discharger::SetupRunner::CommandRegistry
    original = registry.get("github_packages")
    noop = Class.new(original) do
      def execute
      end
    end
    registry.register("github_packages", noop)

    io = StringIO.new
    capture_output do
      Discharger::SetupRunner.run("setup.yml", Logger.new(io))
    end

    refute_match(/missing from steps/, io.string)
  ensure
    registry.register("github_packages", original) if original
  end

  test "stays quiet when github_packages is scheduled programmatically" do
    create_file("setup.yml", <<~YAML)
      app_name: TestApp
      github_packages:
        source: "https://rubygems.pkg.github.com/example"
      steps:
        - env
    YAML

    noop = Class.new(Discharger::SetupRunner::Commands::GithubPackagesCommand) do
      def execute
      end
    end

    io = StringIO.new
    capture_output do
      Discharger::SetupRunner.run("setup.yml", Logger.new(io)) do |runner|
        runner.add_command(noop.new(runner.config, Dir.pwd, runner.logger))
      end
    end

    refute_match(/missing from steps/, io.string)
  end

  test "stays quiet when a custom step references the source" do
    create_file("setup.yml", <<~YAML)
      app_name: TestApp
      github_packages:
        source: "https://rubygems.pkg.github.com/example"
      steps:
        - env
      custom_steps:
        - description: "Store credentials"
          command: "echo https://rubygems.pkg.github.com/example >/dev/null"
    YAML

    io = StringIO.new
    capture_output do
      Discharger::SetupRunner.run("setup.yml", Logger.new(io))
    end

    refute_match(/missing from steps/, io.string)
  end

  test "stays quiet when github_packages is not configured at all" do
    create_file("setup.yml", <<~YAML)
      app_name: TestApp
      steps:
        - env
    YAML

    io = StringIO.new
    capture_output do
      Discharger::SetupRunner.run("setup.yml", Logger.new(io))
    end

    refute_match(/missing from steps/, io.string)
  end

  test "runs a named custom step at its scheduled position" do
    create_file("setup.yml", <<~YAML)
      app_name: TestApp
      steps:
        - prepare
        - env
      custom_steps:
        - name: prepare
          description: "Prepare marker"
          command: "touch marker.txt"
    YAML
    create_file(".env.example", "TEST_VAR=example")

    out = nil
    with_output_enabled do
      out, _ = capture_output do
        Discharger::SetupRunner.run("setup.yml", Logger.new(StringIO.new))
      end
    end

    assert_file_exists("marker.txt")
    assert_operator out.index("Prepare marker"), :<, out.index("Setup environment file"),
      "the named custom step must run at its scheduled position, not last"
  end

  test "allows programmatic configuration" do
    Discharger::SetupRunner.configure do |config|
      config.app_name = "ProgrammaticApp"
    end

    assert_equal "ProgrammaticApp", Discharger::SetupRunner.configuration.app_name
  end

  test "registers and uses custom commands" do
    # Define a custom command class
    custom_command_class = Class.new(Discharger::SetupRunner::Commands::BaseCommand) do
      def execute
        File.write("custom_command_output.txt", "Custom command executed")
      end

      def description
        "Custom test command"
      end
    end

    # Register the command
    Discharger::SetupRunner.register_command("test_custom", custom_command_class)

    # Verify registration
    assert_includes Discharger::SetupRunner.list_commands, "test_custom"
    assert_equal custom_command_class, Discharger::SetupRunner.get_command("test_custom")

    # Create config that uses the custom command
    config_content = <<~YAML
      app_name: TestApp
      steps:
        - test_custom
    YAML

    create_file("setup.yml", config_content)

    # Run setup with silent logger
    logger = Logger.new(StringIO.new)
    Discharger::SetupRunner.run("setup.yml", logger)

    # Verify custom command executed
    assert_file_exists("custom_command_output.txt")
    assert_file_contains("custom_command_output.txt", "Custom command executed")
  ensure
    # Clean up registration
    Discharger::SetupRunner.unregister_command("test_custom")
  end

  test "yields runner for customization" do
    config_content = <<~YAML
      app_name: TestApp
      steps:
        - bundler
    YAML

    create_file("setup.yml", config_content)
    create_file("Gemfile", "source 'https://rubygems.org'")

    commands_executed = []

    # Create logger for the tracking command
    logger = Logger.new(StringIO.new)

    Discharger::SetupRunner.run("setup.yml", logger) do |runner|
      # Add a custom command to track execution
      tracking_command = Class.new(Discharger::SetupRunner::Commands::BaseCommand) do
        define_method :execute do
          commands_executed << "tracking_command"
        end
      end.new({}, Dir.pwd, logger)

      runner.add_command(tracking_command)
    end

    assert_includes commands_executed, "tracking_command"
  end

  test "handles missing configuration gracefully" do
    assert_raises(Errno::ENOENT) do
      Discharger::SetupRunner.run("non_existent.yml")
    end
  end
end

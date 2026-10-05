require "test_helper"
require "setup_runner_test_helper"
require "discharger/setup_runner/prerequisites_loader"

class PrerequisitesLoaderTest < ActiveSupport::TestCase
  include SetupRunnerTestHelper

  test "run returns false when config file does not exist" do
    loader = Discharger::SetupRunner::PrerequisitesLoader.new("non_existent.yml")

    result = loader.run
    refute result
  end

  test "run returns true when config file exists" do
    create_file("setup.yml", "app_name: TestApp")
    loader = Discharger::SetupRunner::PrerequisitesLoader.new("setup.yml")

    capture_io { loader.run }  # suppress output
    assert loader.run
  end

  test "sets DB_PORT from config when not set in environment" do
    yaml_content = <<~YAML
      database:
        port: 5433
      steps:
        - pg_tools
    YAML
    create_file("setup.yml", yaml_content)

    original_db_port = ENV["DB_PORT"]
    original_pgport = ENV["PGPORT"]
    ENV.delete("DB_PORT")
    ENV.delete("PGPORT")

    begin
      loader = Discharger::SetupRunner::PrerequisitesLoader.new("setup.yml")
      capture_io { loader.run }

      assert_equal "5433", ENV["DB_PORT"]
      assert_equal "5433", ENV["PGPORT"]
    ensure
      if original_db_port
        ENV["DB_PORT"] = original_db_port
      else
        ENV.delete("DB_PORT")
      end
      if original_pgport
        ENV["PGPORT"] = original_pgport
      else
        ENV.delete("PGPORT")
      end
    end
  end

  test "does not set PGPORT when PostgreSQL CLI setup is not enabled" do
    yaml_content = <<~YAML
      database:
        port: 5433
      steps:
        - docker
        - database
    YAML
    create_file("setup.yml", yaml_content)

    original_db_port = ENV["DB_PORT"]
    original_pgport = ENV["PGPORT"]
    ENV.delete("DB_PORT")
    ENV.delete("PGPORT")

    begin
      loader = Discharger::SetupRunner::PrerequisitesLoader.new("setup.yml")
      capture_io { loader.run }

      assert_equal "5433", ENV["DB_PORT"]
      assert_nil ENV["PGPORT"]
    ensure
      if original_db_port
        ENV["DB_PORT"] = original_db_port
      else
        ENV.delete("DB_PORT")
      end
      if original_pgport
        ENV["PGPORT"] = original_pgport
      else
        ENV.delete("PGPORT")
      end
    end
  end

  test "sets PGPORT when pg_tools step is enabled" do
    yaml_content = <<~YAML
      database:
        port: 5433
      steps:
        - docker
        - pg_tools
        - database
    YAML
    create_file("setup.yml", yaml_content)

    original_db_port = ENV["DB_PORT"]
    original_pgport = ENV["PGPORT"]
    ENV.delete("DB_PORT")
    ENV.delete("PGPORT")

    begin
      loader = Discharger::SetupRunner::PrerequisitesLoader.new("setup.yml")
      capture_io { loader.run }

      assert_equal "5433", ENV["DB_PORT"]
      assert_equal "5433", ENV["PGPORT"]
    ensure
      if original_db_port
        ENV["DB_PORT"] = original_db_port
      else
        ENV.delete("DB_PORT")
      end
      if original_pgport
        ENV["PGPORT"] = original_pgport
      else
        ENV.delete("PGPORT")
      end
    end
  end

  test "does not override DB_PORT when already set in environment" do
    yaml_content = <<~YAML
      database:
        port: 5433
    YAML
    create_file("setup.yml", yaml_content)

    original_db_port = ENV["DB_PORT"]
    ENV["DB_PORT"] = "5555"

    begin
      loader = Discharger::SetupRunner::PrerequisitesLoader.new("setup.yml")
      capture_io { loader.run }

      assert_equal "5555", ENV["DB_PORT"]
    ensure
      if original_db_port
        ENV["DB_PORT"] = original_db_port
      else
        ENV.delete("DB_PORT")
      end
    end
  end

  test "sets DB_NAME from config when not set in environment" do
    yaml_content = <<~YAML
      database:
        name: db-myapp
    YAML
    create_file("setup.yml", yaml_content)

    original_db_name = ENV["DB_NAME"]
    ENV.delete("DB_NAME")

    begin
      loader = Discharger::SetupRunner::PrerequisitesLoader.new("setup.yml")
      capture_io { loader.run }

      assert_equal "myapp", ENV["DB_NAME"]  # db- prefix is stripped
    ensure
      if original_db_name
        ENV["DB_NAME"] = original_db_name
      else
        ENV.delete("DB_NAME")
      end
    end
  end

  test "db_name in config overrides the name derived from the container" do
    create_file("setup.yml", <<~YAML)
      database:
        name: db-skedify
        db_name: coordinator
    YAML
    with_env("DB_NAME" => nil) do
      capture_io { Discharger::SetupRunner::PrerequisitesLoader.run("setup.yml") }
      assert_equal "coordinator", ENV["DB_NAME"]
    end
  end

  test "db_name: false leaves DB_NAME to the app" do
    create_file("setup.yml", <<~YAML)
      database:
        name: db-skedify
        db_name: false
    YAML
    with_env("DB_NAME" => nil) do
      capture_io { Discharger::SetupRunner::PrerequisitesLoader.run("setup.yml") }
      assert_nil ENV["DB_NAME"]
    end
  end

  test "runs pre_steps from config" do
    # Use a custom step name to avoid conflicting with built-in commands
    yaml_content = <<~YAML
      pre_steps:
        - test_mock_step
    YAML
    create_file("setup.yml", yaml_content)

    # Create and register a mock command using the registry's own register method
    executed = false
    mock_command = Class.new(Discharger::SetupRunner::PreCommands::BasePreCommand) do
      define_method(:description) { "Mock Test Step" }
      define_method(:execute) { executed = true }
    end

    Discharger::SetupRunner::PreCommands::PreCommandRegistry.register("test_mock_step", mock_command)

    loader = Discharger::SetupRunner::PrerequisitesLoader.new("setup.yml")
    capture_io { loader.run }

    assert executed, "Pre-step should have been executed"
  end

  test "prints each pre_step's elapsed time" do
    create_file("setup.yml", <<~YAML)
      pre_steps:
        - test_timed_step
        - description: "Say hello"
          command: "echo hello"
    YAML
    mock_command = Class.new(Discharger::SetupRunner::PreCommands::BasePreCommand) do
      define_method(:description) { "Timed Step" }
      define_method(:execute) {}
    end
    Discharger::SetupRunner::PreCommands::PreCommandRegistry.register("test_timed_step", mock_command)

    output, _ = capture_io { Discharger::SetupRunner::PrerequisitesLoader.new("setup.yml").run }

    assert_match(/^  Timed Step: \d+\.\d\ds$/, output)
    assert_match(/^  Say hello: \d+\.\d\ds$/, output)
  end

  test "warns about unknown pre_steps" do
    yaml_content = <<~YAML
      pre_steps:
        - unknown_step
    YAML
    create_file("setup.yml", yaml_content)

    loader = Discharger::SetupRunner::PrerequisitesLoader.new("setup.yml")

    output, _ = capture_io { loader.run }
    assert_match(/Unknown pre-step 'unknown_step'/, output)
  end

  test "runs custom pre_steps with command" do
    yaml_content = <<~YAML
      pre_steps:
        - command: "true"
          description: Say hello
    YAML
    create_file("setup.yml", yaml_content)

    loader = Discharger::SetupRunner::PrerequisitesLoader.new("setup.yml")

    output, _ = capture_io { loader.run }
    assert_match(/Say hello: \d+\.\d\ds/, output)
  end

  test "skips custom pre_step when condition is not met" do
    yaml_content = <<~YAML
      pre_steps:
        - command: "true"
          description: Say hello
          condition: ENV['NONEXISTENT_VAR']
    YAML
    create_file("setup.yml", yaml_content)

    loader = Discharger::SetupRunner::PrerequisitesLoader.new("setup.yml")

    output, _ = capture_io { loader.run }
    assert_match(/Skipping: Say hello/, output)
  end

  test "runs custom pre_step when condition is met" do
    yaml_content = <<~YAML
      pre_steps:
        - command: "true"
          description: Say hello
          condition: ENV['HOME']
    YAML
    create_file("setup.yml", yaml_content)

    loader = Discharger::SetupRunner::PrerequisitesLoader.new("setup.yml")

    output, _ = capture_io { loader.run }
    assert_match(/Say hello: \d+\.\d\ds/, output)
  end

  test "evaluate_condition handles negated ENV checks" do
    yaml_content = <<~YAML
      pre_steps:
        - command: "true"
          description: Say hello
          condition: "!ENV['DEFINITELY_NOT_SET_VAR']"
    YAML
    create_file("setup.yml", yaml_content)

    loader = Discharger::SetupRunner::PrerequisitesLoader.new("setup.yml")

    output, _ = capture_io { loader.run }
    assert_match(/Say hello: \d+\.\d\ds/, output)
  end

  test "evaluate_condition handles File.exist? checks" do
    create_file("test_file.txt", "content")
    yaml_content = <<~YAML
      pre_steps:
        - command: "true"
          description: Check file
          condition: File.exist?('test_file.txt')
    YAML
    create_file("setup.yml", yaml_content)

    loader = Discharger::SetupRunner::PrerequisitesLoader.new("setup.yml")

    output, _ = capture_io { loader.run }
    assert_match(/Check file: \d+\.\d\ds/, output)
  end

  test "evaluate_condition handles negated File.exist? checks" do
    yaml_content = <<~YAML
      pre_steps:
        - command: "true"
          description: Create env file
          condition: "!File.exist?('missing_file.txt')"
    YAML
    create_file("setup.yml", yaml_content)

    loader = Discharger::SetupRunner::PrerequisitesLoader.new("setup.yml")

    output, _ = capture_io { loader.run }
    assert_match(/Create env file: \d+\.\d\ds/, output)

    create_file("present.txt", "x")
    yaml_content = <<~YAML
      pre_steps:
        - command: "true"
          description: Should skip
          condition: "!File.exist?('present.txt')"
    YAML
    create_file("setup.yml", yaml_content)

    loader = Discharger::SetupRunner::PrerequisitesLoader.new("setup.yml")
    output, _ = capture_io { loader.run }
    assert_match(/Skipping: Should skip/, output)
  end
end

require "test_helper"
require "setup_runner_test_helper"
require "discharger/setup_runner/commands/custom_command"
require "logger"

class CustomCommandTest < ActiveSupport::TestCase
  include SetupRunnerTestHelper

  def setup
    super
    @config = {}
    @logger = Logger.new(StringIO.new)
  end

  test "initializes with step configuration" do
    step_config = {
      "command" => "echo 'Hello'",
      "description" => "Test command"
    }

    command = Discharger::SetupRunner::Commands::CustomCommand.new(
      @config, @test_dir, @logger, step_config
    )

    assert_equal step_config, command.step_config
  end

  test "description returns custom description when provided" do
    step_config = {
      "command" => "echo 'Hello'",
      "description" => "Say hello"
    }

    command = Discharger::SetupRunner::Commands::CustomCommand.new(
      @config, @test_dir, @logger, step_config
    )

    assert_equal "Say hello", command.description
  end

  test "description returns command when description not provided" do
    step_config = {
      "command" => "echo 'Hello'"
    }

    command = Discharger::SetupRunner::Commands::CustomCommand.new(
      @config, @test_dir, @logger, step_config
    )

    assert_equal "Custom command: echo 'Hello'", command.description
  end

  test "can_execute? returns true when command is present" do
    step_config = {
      "command" => "echo 'Hello'"
    }

    command = Discharger::SetupRunner::Commands::CustomCommand.new(
      @config, @test_dir, @logger, step_config
    )

    assert command.can_execute?
  end

  test "can_execute? returns false when command is missing" do
    step_config = {}

    command = Discharger::SetupRunner::Commands::CustomCommand.new(
      @config, @test_dir, @logger, step_config
    )

    refute command.can_execute?
  end

  test "execute runs command without condition" do
    step_config = {
      "command" => "echo 'Hello'",
      "description" => "Say hello"
    }

    command = Discharger::SetupRunner::Commands::CustomCommand.new(
      @config, @test_dir, @logger, step_config
    )

    system_called = false
    command.define_singleton_method(:system!) do |*args|
      system_called = true if args.join(" ") == "echo 'Hello'"
    end

    command.execute

    assert system_called
  end

  test "execute runs command when condition is true" do
    step_config = {
      "command" => "echo 'Hello'",
      "description" => "Say hello",
      "condition" => "true"
    }

    command = Discharger::SetupRunner::Commands::CustomCommand.new(
      @config, @test_dir, @logger, step_config
    )

    system_called = false
    command.define_singleton_method(:system!) do |*args|
      system_called = true if args.join(" ") == "echo 'Hello'"
    end

    command.execute

    assert system_called
  end

  test "execute skips command when condition is false" do
    step_config = {
      "command" => "echo 'Hello'",
      "description" => "Say hello",
      "condition" => "false"
    }

    io = StringIO.new
    logger = Logger.new(io)

    command = Discharger::SetupRunner::Commands::CustomCommand.new(
      @config, @test_dir, logger, step_config
    )

    system_called = false
    command.define_singleton_method(:system!) do |*args|
      system_called = true
    end

    command.execute

    refute system_called
    assert_match(/Skipping Say hello \(condition not met\)/, io.string)
  end

  test "execute evaluates ENV conditions" do
    ENV["TEST_MODE"] = "enabled"

    step_config = {
      "command" => "echo 'Test mode'",
      "description" => "Test mode command",
      "condition" => "ENV['TEST_MODE'] == 'enabled'"
    }

    command = Discharger::SetupRunner::Commands::CustomCommand.new(
      @config, @test_dir, @logger, step_config
    )

    system_called = false
    command.define_singleton_method(:system!) do |*args|
      system_called = true
    end

    command.execute

    assert system_called
  ensure
    ENV.delete("TEST_MODE")
  end

  test "execute evaluates File existence conditions" do
    test_file = File.join(@test_dir, "test.rb")
    File.write(test_file, "# test")

    step_config = {
      "command" => "echo 'File exists'",
      "description" => "File check command",
      "condition" => "File.exist?('#{test_file}')"
    }

    command = Discharger::SetupRunner::Commands::CustomCommand.new(
      @config, @test_dir, @logger, step_config
    )

    system_called = false
    command.define_singleton_method(:system!) do |*args|
      system_called = true
    end

    command.execute

    assert system_called
  end

  test "execute logs activity" do
    step_config = {
      "command" => "echo 'Hello'",
      "description" => "Say hello"
    }

    io = StringIO.new
    logger = Logger.new(io)

    command = Discharger::SetupRunner::Commands::CustomCommand.new(
      @config, @test_dir, logger, step_config
    )

    command.define_singleton_method(:system!) { |*args| }

    command.execute

    log_output = io.string
    assert_match(/\[CustomCommand\] Running: Say hello/, log_output)
  end
end

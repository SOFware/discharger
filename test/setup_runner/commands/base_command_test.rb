require "test_helper"
require "setup_runner_test_helper"
require "discharger/setup_runner/commands/base_command"
require "logger"

class BaseCommandTest < ActiveSupport::TestCase
  include SetupRunnerTestHelper

  class TestCommand < Discharger::SetupRunner::Commands::BaseCommand
    def execute
      log "Executing test command"
      "test result"
    end
  end

  class FailingTestCommand < Discharger::SetupRunner::Commands::BaseCommand
    def execute
      system!("false")
    end
  end

  class ConditionalTestCommand < Discharger::SetupRunner::Commands::BaseCommand
    def can_execute?
      false
    end
  end

  def setup
    super
    @config = { "test" => "config" }
    @logger = Logger.new(StringIO.new)
    @command = TestCommand.new(@config, @test_dir, @logger)
  end

  test "initializes with config, app_root, and logger" do
    assert_equal @config, @command.config
    assert_equal @test_dir, @command.app_root
    assert_equal @logger, @command.logger
  end

  test "execute raises NotImplementedError for base class" do
    base_command = Discharger::SetupRunner::Commands::BaseCommand.new(@config, @test_dir, @logger)
    assert_raises(NotImplementedError) do
      base_command.execute
    end
  end

  test "can_execute? returns true by default" do
    assert @command.can_execute?
  end

  test "description returns humanized class name" do
    assert_equal "Test command", @command.description
  end

  test "log writes to logger with class name prefix" do
    io = StringIO.new
    logger = Logger.new(io)
    command = TestCommand.new(@config, @test_dir, logger)
    
    command.send(:log, "Test message")
    
    assert_match(/\[TestCommand\] Test message/, io.string)
  end

  test "system! executes command successfully" do
    command = TestCommand.new(@config, @test_dir, @logger)
    
    # Since NO_SPINNER is set, system! should work without spinner
    _stdout, _stderr = capture_output do
      command.send(:system!, "echo", "hello")
    end
    
    # The command should execute without raising
    assert true, "Command executed successfully"
  end

  test "system! raises error on command failure" do
    command = FailingTestCommand.new(@config, @test_dir, @logger)
    
    error = assert_raises(RuntimeError) do
      command.execute
    end
    assert_match(/false failed/, error.message)
  end

  test "system! doesn't raise for docker command failures" do
    command = TestCommand.new(@config, @test_dir, @logger)
    
    # Docker commands that fail should not raise
    # Using a docker command that will fail
    _stdout, _stderr = capture_output do
      command.send(:system!, "docker", "run", "--fake-flag-that-doesnt-exist")
    end
    
    # Should not raise an error for docker commands
    assert true, "Docker command failure handled gracefully"
  end

  test "ask_to_install prompts user and yields on Y" do
    command = TestCommand.new(@config, @test_dir, @logger)
    
    # Simulate user input
    input = StringIO.new("Y\n")
    command.define_singleton_method(:gets) { input.gets }
    
    yielded = false
    output, _ = capture_output do
      command.send(:ask_to_install, "test tool") { yielded = true }
    end
    
    assert yielded
    assert_match(/You do not currently use test tool/, output)
  end

  test "ask_to_install doesn't yield on non-Y input" do
    command = TestCommand.new(@config, @test_dir, @logger)
    
    # Simulate user input
    input = StringIO.new("n\n")
    command.define_singleton_method(:gets) { input.gets }
    
    yielded = false
    capture_output do
      command.send(:ask_to_install, "test tool") { yielded = true }
    end
    
    refute yielded
  end

  test "proceed_with prompts user and yields on Y" do
    command = TestCommand.new(@config, @test_dir, @logger)
    
    # Simulate user input
    input = StringIO.new("Y\n")
    command.define_singleton_method(:gets) { input.gets }
    
    yielded = false
    output, _ = capture_output do
      command.send(:proceed_with, "test task") { yielded = true }
    end
    
    assert yielded
    assert_match(/Proceed with test task\?/, output)
  end

  test "subclass can override can_execute?" do
    command = ConditionalTestCommand.new(@config, @test_dir, @logger)
    refute command.can_execute?
  end

  test "subclass implements execute method" do
    result = @command.execute
    assert_equal "test result", result
  end
end
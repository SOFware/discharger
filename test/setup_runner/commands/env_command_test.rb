require "test_helper"
require "setup_runner_test_helper"
require "discharger/setup_runner/commands/env_command"
require "logger"

class EnvCommandTest < ActiveSupport::TestCase
  include SetupRunnerTestHelper

  def setup
    super
    @config = {}
    @logger = Logger.new(StringIO.new)
    @command = Discharger::SetupRunner::Commands::EnvCommand.new(@config, @test_dir, @logger)
  end

  test "description returns correct text" do
    assert_equal "Setup environment file", @command.description
  end

  test "can_execute? returns true when .env.example exists" do
    create_file(".env.example", "TEST_VAR=example")
    assert @command.can_execute?
  end

  test "can_execute? returns false when .env.example does not exist" do
    refute @command.can_execute?
  end

  test "execute creates .env from .env.example when .env does not exist" do
    create_file(".env.example", "TEST_VAR=example\nANOTHER_VAR=value")
    
    @command.execute
    
    assert_file_exists(".env")
    assert_file_contains(".env", "TEST_VAR=example")
    assert_file_contains(".env", "ANOTHER_VAR=value")
  end

  test "execute does not overwrite existing .env file" do
    create_file(".env.example", "TEST_VAR=example")
    create_file(".env", "TEST_VAR=production\nCUSTOM_VAR=custom")
    
    @command.execute
    
    # .env should remain unchanged
    assert_file_contains(".env", "TEST_VAR=production")
    assert_file_contains(".env", "CUSTOM_VAR=custom")
    refute File.read(".env").include?("example")
  end

  test "execute logs activity" do
    create_file(".env.example", "TEST_VAR=example")
    
    io = StringIO.new
    logger = Logger.new(io)
    command = Discharger::SetupRunner::Commands::EnvCommand.new(@config, @test_dir, logger)
    
    command.execute
    
    log_output = io.string
    assert_match(/\[EnvCommand\] Setting up .env file/, log_output)
    assert_match(/\[EnvCommand\] .env file created from .env.example/, log_output)
  end

  test "execute logs when .env already exists" do
    create_file(".env.example", "TEST_VAR=example")
    create_file(".env", "TEST_VAR=production")
    
    io = StringIO.new
    logger = Logger.new(io)
    command = Discharger::SetupRunner::Commands::EnvCommand.new(@config, @test_dir, logger)
    
    command.execute
    
    log_output = io.string
    assert_match(/\[EnvCommand\] Setting up .env file/, log_output)
    assert_match(/\[EnvCommand\] .env file already exists. Doing nothing./, log_output)
  end
end
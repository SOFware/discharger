require "test_helper"
require "discharger/setup_runner/command_registry"
require "discharger/setup_runner/commands/base_command"

class CommandRegistryTest < ActiveSupport::TestCase
  class TestCommand < Discharger::SetupRunner::Commands::BaseCommand
    def execute
      "test executed"
    end
  end

  class AnotherTestCommand < Discharger::SetupRunner::Commands::BaseCommand
    def execute
      "another test executed"
    end
  end

  setup do
    # Save current commands
    @original_commands = {}
    Discharger::SetupRunner::CommandRegistry.names.each do |name|
      @original_commands[name] = Discharger::SetupRunner::CommandRegistry.get(name)
    end
    # Clear registry before each test
    Discharger::SetupRunner::CommandRegistry.clear
  end

  teardown do
    # Clear registry after each test
    Discharger::SetupRunner::CommandRegistry.clear
    # Restore original commands
    @original_commands.each do |name, command_class|
      Discharger::SetupRunner::CommandRegistry.register(name, command_class)
    end
  end

  test "registers a new command" do
    registry = Discharger::SetupRunner::CommandRegistry
    
    registry.register("test_command", TestCommand)
    
    assert_equal TestCommand, registry.get("test_command")
  end

  test "registers command with symbol name" do
    registry = Discharger::SetupRunner::CommandRegistry
    
    registry.register(:test_command, TestCommand)
    
    assert_equal TestCommand, registry.get("test_command")
  end

  test "overwrites existing command" do
    registry = Discharger::SetupRunner::CommandRegistry
    
    registry.register("test_command", TestCommand)
    registry.register("test_command", AnotherTestCommand)
    
    assert_equal AnotherTestCommand, registry.get("test_command")
  end

  test "returns nil for unregistered command" do
    registry = Discharger::SetupRunner::CommandRegistry
    
    assert_nil registry.get("non_existent")
  end

  test "returns all registered commands" do
    registry = Discharger::SetupRunner::CommandRegistry
    
    registry.register("test1", TestCommand)
    registry.register("test2", AnotherTestCommand)
    
    all_commands = registry.all
    
    assert_includes all_commands, TestCommand
    assert_includes all_commands, AnotherTestCommand
    assert_equal 2, all_commands.size
  end

  test "returns all command names" do
    registry = Discharger::SetupRunner::CommandRegistry
    
    registry.register("test1", TestCommand)
    registry.register("test2", AnotherTestCommand)
    
    names = registry.names
    
    assert_includes names, "test1"
    assert_includes names, "test2"
    assert_equal 2, names.size
  end

  test "clears all commands" do
    registry = Discharger::SetupRunner::CommandRegistry
    
    registry.register("test_command", TestCommand)
    assert_not_empty registry.all
    
    registry.clear
    
    assert_empty registry.all
    assert_empty registry.names
  end

  test "starts with empty registry" do
    registry = Discharger::SetupRunner::CommandRegistry
    
    assert_empty registry.all
    assert_empty registry.names
  end
end
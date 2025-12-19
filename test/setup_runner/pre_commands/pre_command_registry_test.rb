require "test_helper"
require "discharger/setup_runner/pre_commands/pre_command_registry"

class PreCommandRegistryTest < ActiveSupport::TestCase
  test "get returns built-in homebrew command" do
    command_class = Discharger::SetupRunner::PreCommands::PreCommandRegistry.get("homebrew")
    assert_equal Discharger::SetupRunner::PreCommands::HomebrewPreCommand, command_class
  end

  test "get returns built-in postgresql_tools command" do
    command_class = Discharger::SetupRunner::PreCommands::PreCommandRegistry.get("postgresql_tools")
    assert_equal Discharger::SetupRunner::PreCommands::PostgresqlToolsPreCommand, command_class
  end

  test "get returns nil for unknown command" do
    command_class = Discharger::SetupRunner::PreCommands::PreCommandRegistry.get("unknown")
    assert_nil command_class
  end

  test "register adds custom command" do
    custom_class = Class.new(Discharger::SetupRunner::PreCommands::BasePreCommand)
    Discharger::SetupRunner::PreCommands::PreCommandRegistry.register("custom_test", custom_class)

    command_class = Discharger::SetupRunner::PreCommands::PreCommandRegistry.get("custom_test")
    assert_equal custom_class, command_class
  end

  test "names includes built-in commands" do
    names = Discharger::SetupRunner::PreCommands::PreCommandRegistry.names
    assert_includes names, "homebrew"
    assert_includes names, "postgresql_tools"
  end

  test "get accepts symbols" do
    command_class = Discharger::SetupRunner::PreCommands::PreCommandRegistry.get(:homebrew)
    assert_equal Discharger::SetupRunner::PreCommands::HomebrewPreCommand, command_class
  end
end

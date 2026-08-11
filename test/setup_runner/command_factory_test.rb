require "test_helper"
require "discharger/setup_runner/configuration"
require "discharger/setup_runner/command_factory"
require "logger"
require "stringio"

class CommandFactoryTest < ActiveSupport::TestCase
  test "constructs every registered command without warnings when no steps are configured" do
    config = Discharger::SetupRunner::Configuration.new
    io = StringIO.new
    factory = Discharger::SetupRunner::CommandFactory.new(config, Dir.pwd, Logger.new(io))

    commands = factory.create_all_commands

    assert_equal Discharger::SetupRunner::CommandRegistry.ordered_names.size, commands.size
    refute_match(/Failed to create command/, io.string)
  end
end

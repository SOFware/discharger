require "test_helper"
require "discharger/setup_runner/pre_commands/base_pre_command"

class BasePreCommandTest < ActiveSupport::TestCase
  class TestPreCommand < Discharger::SetupRunner::PreCommands::BasePreCommand
    def execute
      "executed"
    end
  end

  test "initializes with config" do
    config = {"database" => {"port" => 5432}}
    command = TestPreCommand.new(config)

    assert_equal config, command.config
  end

  test "initializes with empty config by default" do
    command = TestPreCommand.new

    assert_equal({}, command.config)
  end

  test "description returns humanized class name" do
    command = TestPreCommand.new
    assert_equal "Test", command.description
  end

  test "execute raises NotImplementedError in base class" do
    command = Discharger::SetupRunner::PreCommands::BasePreCommand.new

    assert_raises(NotImplementedError) do
      command.execute
    end
  end

  test "platform_darwin? returns correct value" do
    command = TestPreCommand.new

    # This will be true on macOS, false on other platforms
    if /darwin/.match?(RbConfig::CONFIG["host_os"])
      assert command.send(:platform_darwin?)
    else
      refute command.send(:platform_darwin?)
    end
  end

  test "platform_linux? returns correct value" do
    command = TestPreCommand.new

    # This will be true on Linux, false on other platforms
    if /linux/.match?(RbConfig::CONFIG["host_os"])
      assert command.send(:platform_linux?)
    else
      refute command.send(:platform_linux?)
    end
  end

  test "command_exists? returns true for existing command" do
    command = TestPreCommand.new

    # 'echo' should exist on all Unix-like systems
    assert command.send(:command_exists?, "echo")
  end

  test "command_exists? returns false for non-existing command" do
    command = TestPreCommand.new

    refute command.send(:command_exists?, "definitely_not_a_real_command_12345")
  end

  test "log outputs message with indentation" do
    command = TestPreCommand.new

    output = capture_io { command.send(:log, "test message") }[0]
    assert_equal "  test message\n", output
  end
end

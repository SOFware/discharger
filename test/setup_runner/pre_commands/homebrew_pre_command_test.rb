require "test_helper"
require "discharger/setup_runner/pre_commands/homebrew_pre_command"

class HomebrewPreCommandTest < ActiveSupport::TestCase
  def setup
    @command = Discharger::SetupRunner::PreCommands::HomebrewPreCommand.new
  end

  test "description returns correct text" do
    assert_equal "Ensure Homebrew is installed", @command.description
  end

  test "execute returns true when brew is already installed" do
    @command.define_singleton_method(:command_exists?) { |cmd| cmd == "brew" }

    output = capture_io { @command.execute }
    assert_match(/Homebrew found at/, output[0])
  end

  test "execute logs homebrew not found when brew is missing on unsupported platform" do
    @command.define_singleton_method(:command_exists?) { |_cmd| false }
    @command.define_singleton_method(:platform_darwin?) { false }
    @command.define_singleton_method(:platform_linux?) { false }

    output, _ = capture_io { @command.execute }

    assert_match(/Homebrew not found/, output)
    assert_match(/Unsupported platform/, output)
  end

  test "execute attempts to install on darwin when brew is missing" do
    installed = false
    verified = false

    @command.define_singleton_method(:command_exists?) { |_cmd| verified }
    @command.define_singleton_method(:platform_darwin?) { true }
    @command.define_singleton_method(:platform_linux?) { false }
    @command.define_singleton_method(:system) do |*_args|
      installed = true
      true
    end

    # After install, pretend it worked
    @command.define_singleton_method(:verify_installation) do
      verified = true
      true
    end

    capture_io { @command.execute }

    assert installed, "Should have attempted to install Homebrew"
  end

  test "HOMEBREW_INSTALL_URL is the correct URL" do
    expected_url = "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
    assert_equal expected_url, Discharger::SetupRunner::PreCommands::HomebrewPreCommand::HOMEBREW_INSTALL_URL
  end
end

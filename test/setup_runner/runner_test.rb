require "test_helper"
require "discharger/setup_runner"

class SetupRunnerRunnerTest < ActiveSupport::TestCase
  test "passes its defaulted logger and app_root to the command factory" do
    config = Discharger::SetupRunner::Configuration.new
    runner = Discharger::SetupRunner::Runner.new(config)

    assert_same runner.logger, runner.command_factory.logger,
      "warnings from the factory are lost when it gets the raw nil logger"
    assert_same runner.app_root, runner.command_factory.app_root
  end
end

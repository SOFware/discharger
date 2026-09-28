require "test_helper"
require "discharger/setup_runner"
require "setup_runner_test_helper"

class SetupRunnerRunnerTest < ActiveSupport::TestCase
  test "passes its defaulted logger and app_root to the command factory" do
    config = Discharger::SetupRunner::Configuration.new
    runner = Discharger::SetupRunner::Runner.new(config)

    assert_same runner.logger, runner.command_factory.logger,
      "warnings from the factory are lost when it gets the raw nil logger"
    assert_same runner.app_root, runner.command_factory.app_root
  end
end

class SetupRunnerRunnerTimingTest < ActiveSupport::TestCase
  include SetupRunnerTestHelper

  test "reports each step's elapsed time and the total" do
    create_file("setup.yml", <<~YAML)
      app_name: TestApp
      steps:
        - env
      custom_steps:
        - description: "Touch a file"
          command: "touch timed.txt"
    YAML

    output, _ = with_output_enabled do
      capture_output do
        Discharger::SetupRunner.run("setup.yml", Logger.new(StringIO.new))
      end
    end

    assert_match(/Touch a file: \d+\.\d\ds/, output)
    assert_match(/Setup completed successfully! \(\d+\.\d\ds\)/, output)
  end
end

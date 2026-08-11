require "test_helper"
require "discharger/setup_runner/configuration"
require "discharger/setup_runner/command_factory"
require "logger"
require "stringio"

class CommandFactoryTest < ActiveSupport::TestCase
  test "schedules a named custom step at its position in steps" do
    config = config_with(
      steps: %w[git seed bundler],
      custom_steps: [
        {"name" => "seed", "description" => "Seed data", "command" => "true"}
      ]
    )

    commands = factory(config).create_all_commands

    assert_equal [
      Discharger::SetupRunner::Commands::GitCommand,
      Discharger::SetupRunner::Commands::CustomCommand,
      Discharger::SetupRunner::Commands::BundlerCommand
    ], commands.map(&:class)
    assert_equal 1, commands.count { |c| c.is_a?(Discharger::SetupRunner::Commands::CustomCommand) },
      "a scheduled custom step must not also be appended at the end"
  end

  test "appends unnamed and unscheduled named custom steps last" do
    config = config_with(
      steps: %w[git],
      custom_steps: [
        {"name" => "docs", "description" => "Build docs", "command" => "true"},
        {"description" => "Anonymous", "command" => "true"}
      ]
    )

    commands = factory(config).create_all_commands

    assert_equal Discharger::SetupRunner::Commands::GitCommand, commands[0].class
    assert_equal ["Build docs", "Anonymous"], commands[1..].map(&:description)
  end

  test "warns on unknown step names" do
    config = config_with(steps: %w[git sed], custom_steps: [
      {"name" => "seed", "description" => "Seed data", "command" => "true"}
    ])
    io = StringIO.new

    factory(config, io).create_all_commands

    assert_match(/unknown step "sed"/, io.string)
  end

  test "warns and keeps the first custom step when names collide" do
    config = config_with(
      steps: %w[seed],
      custom_steps: [
        {"name" => "seed", "description" => "First", "command" => "true"},
        {"name" => "seed", "description" => "Second", "command" => "true"}
      ]
    )
    io = StringIO.new

    commands = factory(config, io).create_all_commands

    assert_match(/duplicate custom step name "seed"/, io.string)
    assert_equal ["First", "Second"], commands.map(&:description),
      "the first entry takes the scheduled slot; the duplicate still runs last"
  end

  test "warns when a custom step name is shadowed by a built-in" do
    config = config_with(
      steps: %w[bundler],
      custom_steps: [
        {"name" => "bundler", "description" => "Fake bundler", "command" => "true"}
      ]
    )
    io = StringIO.new

    commands = factory(config, io).create_all_commands

    assert_match(/custom step name "bundler" is shadowed by a built-in/, io.string)
    assert_equal Discharger::SetupRunner::Commands::BundlerCommand, commands.first.class
  end

  test "does not warn about duplicate names when no steps are configured" do
    config = config_with(steps: [], custom_steps: [
      {"name" => "seed", "description" => "First", "command" => "true"},
      {"name" => "seed", "description" => "Second", "command" => "true"}
    ])
    io = StringIO.new

    factory(config, io).create_all_commands

    refute_match(/duplicate custom step name/, io.string,
      "nothing resolves by name without steps, so the warning is noise")
  end

  test "does not mislabel a failing registered command as unknown" do
    require "discharger/setup_runner"
    broken = Class.new(Discharger::SetupRunner::Commands::BaseCommand) do
      def initialize(*)
        raise "boom"
      end
    end
    Discharger::SetupRunner.register_command("broken", broken)
    config = config_with(steps: %w[broken])
    io = StringIO.new

    factory(config, io).create_all_commands

    assert_match(/Failed to create command broken/, io.string)
    refute_match(/unknown step/, io.string)
  ensure
    Discharger::SetupRunner.unregister_command("broken")
  end

  test "empty steps still runs every built-in then custom steps last" do
    config = config_with(steps: [], custom_steps: [
      {"name" => "seed", "description" => "Seed data", "command" => "true"}
    ])

    commands = factory(config).create_all_commands

    assert_equal Discharger::SetupRunner::CommandRegistry.ordered_names.size + 1, commands.size
    assert_equal "Seed data", commands.last.description
  end

  test "constructs every registered command without warnings when no steps are configured" do
    config = Discharger::SetupRunner::Configuration.new
    io = StringIO.new
    factory = Discharger::SetupRunner::CommandFactory.new(config, Dir.pwd, Logger.new(io))

    commands = factory.create_all_commands

    assert_equal Discharger::SetupRunner::CommandRegistry.ordered_names.size, commands.size
    refute_match(/Failed to create command/, io.string)
  end

  private

  def config_with(steps:, custom_steps: [])
    config = Discharger::SetupRunner::Configuration.new
    config.steps = steps
    config.custom_steps = custom_steps
    config
  end

  def factory(config, io = StringIO.new)
    Discharger::SetupRunner::CommandFactory.new(config, Dir.pwd, Logger.new(io))
  end
end

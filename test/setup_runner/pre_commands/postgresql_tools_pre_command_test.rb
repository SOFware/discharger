require "test_helper"
require "discharger/setup_runner/pre_commands/postgresql_tools_pre_command"

class PostgresqlToolsPreCommandTest < ActiveSupport::TestCase
  def setup
    @config = {"database" => {"version" => "15"}}
    @command = Discharger::SetupRunner::PreCommands::PostgresqlToolsPreCommand.new(@config)
  end

  test "description returns correct text" do
    assert_equal "Ensure PostgreSQL client tools are installed", @command.description
  end

  test "execute returns true when pg_dump is already installed" do
    @command.define_singleton_method(:command_exists?) { |cmd| cmd == "pg_dump" }

    result = nil
    output = capture_io { result = @command.execute }

    assert result
    assert_match(/PostgreSQL client tools found/, output[0])
  end

  test "execute logs tools not found when pg_dump is missing on unsupported platform" do
    @command.define_singleton_method(:command_exists?) { |_cmd| false }
    @command.define_singleton_method(:platform_darwin?) { false }
    @command.define_singleton_method(:platform_linux?) { false }

    result = nil
    output, _ = capture_io { result = @command.execute }

    refute result
    assert_match(/PostgreSQL client tools .* not found/, output)
    assert_match(/Unsupported platform/, output)
  end

  test "execute attempts brew install on darwin when pg_dump is missing" do
    brew_called = false
    brew_args = nil

    @command.define_singleton_method(:command_exists?) { |_cmd| false }
    @command.define_singleton_method(:platform_darwin?) { true }
    @command.define_singleton_method(:platform_linux?) { false }
    @command.define_singleton_method(:system) do |cmd|
      brew_called = true
      brew_args = cmd
      true
    end

    capture_io { @command.execute }

    assert brew_called, "Should have attempted to install via brew"
    assert_match(/brew install postgresql@15/, brew_args)
  end

  test "uses default version 14 when not specified in config" do
    command = Discharger::SetupRunner::PreCommands::PostgresqlToolsPreCommand.new({})
    brew_args = nil

    command.define_singleton_method(:command_exists?) { |_cmd| false }
    command.define_singleton_method(:platform_darwin?) { true }
    command.define_singleton_method(:platform_linux?) { false }
    command.define_singleton_method(:system) do |cmd|
      brew_args = cmd
      true
    end

    capture_io { command.execute }

    assert_match(/postgresql@14/, brew_args)
  end

  test "execute attempts apt install on linux when pg_dump is missing" do
    apt_called = false
    apt_args = nil

    @command.define_singleton_method(:command_exists?) do |cmd|
      cmd == "apt-get"  # apt-get exists, but pg_dump doesn't
    end
    @command.define_singleton_method(:platform_darwin?) { false }
    @command.define_singleton_method(:platform_linux?) { true }
    @command.define_singleton_method(:system) do |cmd|
      apt_called = true
      apt_args ||= cmd
      true
    end

    capture_io { @command.execute }

    assert apt_called, "Should have attempted to install via apt"
    assert_match(/apt-get install.*postgresql-client-15/, apt_args)
  end
end

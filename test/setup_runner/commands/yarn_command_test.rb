require "test_helper"
require "setup_runner_test_helper"
require "discharger/setup_runner/commands/yarn_command"
require "logger"

class YarnCommandTest < ActiveSupport::TestCase
  include SetupRunnerTestHelper

  def setup
    super
    @config = {}
    @logger = Logger.new(StringIO.new)
    @command = Discharger::SetupRunner::Commands::YarnCommand.new(@config, @test_dir, @logger)
  end

  test "description returns correct text" do
    assert_equal "Install JavaScript dependencies", @command.description
  end

  test "can_execute? returns true when package.json exists" do
    create_file("package.json", '{"name": "test-app"}')
    assert @command.can_execute?
  end

  test "can_execute? returns false when package.json does not exist" do
    refute @command.can_execute?
  end

  test "execute uses yarn with corepack for yarn.lock projects" do
    create_file("package.json", '{"name": "test-app"}')
    create_file("yarn.lock", "# yarn lockfile v1")

    commands_run = []

    @command.define_singleton_method(:system_quiet) do |cmd|
      case cmd
      when "which corepack"
        true
      when "yarn check --check-files > /dev/null 2>&1"
        false # Forces yarn install
      else
        true
      end
    end

    @command.define_singleton_method(:system!) do |*args|
      commands_run << args.join(" ")
    end

    @command.execute

    assert_includes commands_run, "corepack enable"
    assert_includes commands_run, "corepack use yarn@stable"
    assert_includes commands_run, "yarn install"
  end

  test "execute skips yarn install when yarn check succeeds" do
    create_file("package.json", '{"name": "test-app"}')
    create_file("yarn.lock", "# yarn lockfile v1")

    commands_run = []

    @command.define_singleton_method(:system_quiet) do |cmd|
      true
    end

    @command.define_singleton_method(:system!) do |*args|
      commands_run << args.join(" ")
    end

    @command.execute

    assert_includes commands_run, "corepack enable"
    assert_includes commands_run, "corepack use yarn@stable"
    refute_includes commands_run, "yarn install"
  end

  test "execute uses npm ci for npm projects" do
    create_file("package.json", '{"name": "test-app"}')
    create_file("package-lock.json", '{"lockfileVersion": 2}')

    commands_run = []

    @command.define_singleton_method(:system!) do |*args|
      commands_run << args.join(" ")
    end

    @command.execute

    assert_includes commands_run, "npm ci"
    refute commands_run.any? { |cmd| cmd.include?("yarn") }
  end

  test "execute uses yarn install for generic package.json with yarn available" do
    create_file("package.json", '{"name": "test-app"}')
    # No lock file

    commands_run = []

    @command.define_singleton_method(:system_quiet) do |cmd|
      cmd == "which yarn"
    end

    @command.define_singleton_method(:system!) do |*args|
      commands_run << args.join(" ")
    end

    @command.execute

    assert_includes commands_run, "yarn install"
  end

  test "execute falls back to npm install when yarn not available" do
    create_file("package.json", '{"name": "test-app"}')
    # No lock file

    commands_run = []

    @command.define_singleton_method(:system_quiet) do |cmd|
      !(cmd == "which yarn")
    end

    @command.define_singleton_method(:system!) do |*args|
      commands_run << args.join(" ")
    end

    @command.execute

    assert_includes commands_run, "npm install"
    refute commands_run.any? { |cmd| cmd.include?("yarn") }
  end

  test "execute handles yarn projects without corepack" do
    create_file("package.json", '{"name": "test-app"}')
    create_file("yarn.lock", "# yarn lockfile v1")

    commands_run = []

    @command.define_singleton_method(:system_quiet) do |cmd|
      case cmd
      when "which corepack"
        false # No corepack
      when "yarn check --check-files > /dev/null 2>&1"
        false
      else
        true
      end
    end

    @command.define_singleton_method(:system!) do |*args|
      commands_run << args.join(" ")
    end

    @command.execute

    refute_includes commands_run, "corepack enable"
    assert_includes commands_run, "yarn install"
  end

  test "execute logs activity" do
    create_file("package.json", '{"name": "test-app"}')
    create_file("package-lock.json", "{}")

    io = StringIO.new
    logger = Logger.new(io)
    command = Discharger::SetupRunner::Commands::YarnCommand.new(@config, @test_dir, logger)

    command.define_singleton_method(:system!) { |*args| }

    command.execute

    log_output = io.string
    assert_match(/Installing Node modules/, log_output)
    assert_match(/Found package-lock.json, using npm/, log_output)
  end

  test "execute handles command failures" do
    create_file("package.json", '{"name": "test-app"}')
    create_file("yarn.lock", "")

    @command.define_singleton_method(:system_quiet) do |cmd|
      !cmd.include?("yarn check")
    end

    @command.define_singleton_method(:system!) do |*args|
      raise "yarn install failed"
    end

    assert_raises(RuntimeError) do
      @command.execute
    end
  end
end

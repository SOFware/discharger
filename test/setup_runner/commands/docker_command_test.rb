require "test_helper"
require "setup_runner_test_helper"
require "discharger/setup_runner/commands/docker_command"
require "logger"
require "ostruct"

class DockerCommandTest < ActiveSupport::TestCase
  include SetupRunnerTestHelper

  def setup
    super
    @config = OpenStruct.new
    @logger = Logger.new(StringIO.new)
    @command = Discharger::SetupRunner::Commands::DockerCommand.new(@config, @test_dir, @logger)
  end

  test "description returns correct text" do
    assert_equal "Setup Docker containers", @command.description
  end

  test "can_execute? returns false when docker is not installed" do
    @command.define_singleton_method(:docker_available?) { false }

    refute @command.can_execute?
  end

  test "can_execute? returns false when no containers are configured" do
    @command.define_singleton_method(:docker_available?) { true }

    refute @command.can_execute?
  end

  test "can_execute? returns true when docker exists and database is configured" do
    @config.database = OpenStruct.new(name: "db-test")
    @command.define_singleton_method(:docker_available?) { true }

    assert @command.can_execute?
  end

  test "can_execute? returns true when docker exists and redis is configured" do
    @config.redis = OpenStruct.new(name: "redis-test")
    @command.define_singleton_method(:docker_available?) { true }

    assert @command.can_execute?
  end

  test "execute starts Docker if not running and no native PostgreSQL" do
    @config.database = OpenStruct.new(name: "db-test", port: 5432, version: "14")

    docker_started = false
    container_created = false

    @command.define_singleton_method(:native_postgresql_available?) { false }

    @command.define_singleton_method(:docker_running?) do
      docker_started
    end

    @command.define_singleton_method(:start_docker_for_platform) do
      docker_started = true
    end

    @command.define_singleton_method(:system_quiet) do |cmd|
      case cmd
      when /docker ps.*db-test/
        container_created
      when /docker inspect db-test/
        false
      else
        true
      end
    end

    @command.define_singleton_method(:system!) do |*args|
      cmd = args.join(" ")
      container_created = true if cmd.include?("docker run")
    end

    @command.define_singleton_method(:sleep) { |_| }

    @command.execute

    assert docker_started
    assert container_created
  end

  test "execute skips Docker when native PostgreSQL is available" do
    @config.database = OpenStruct.new(name: "db-test", port: 5432, version: "14")

    docker_checked = false
    container_created = false

    @command.define_singleton_method(:native_postgresql_available?) { true }
    @command.define_singleton_method(:native_postgresql_port) { 5432 }

    @command.define_singleton_method(:docker_running?) do
      docker_checked = true
      false
    end

    @command.define_singleton_method(:system!) do |*args|
      cmd = args.join(" ")
      container_created = true if cmd.include?("docker run")
    end

    @command.execute

    refute docker_checked, "Should not check Docker when native PostgreSQL is available"
    refute container_created, "Should not create container when native PostgreSQL is available"
    assert_equal "5432", ENV["DB_PORT"]
  end

  test "execute creates database container with correct parameters" do
    @config.database = OpenStruct.new(
      name: "db-test",
      port: 5433,
      version: "15",
      password: "secret"
    )

    commands_run = []

    @command.define_singleton_method(:native_postgresql_available?) { false }
    @command.define_singleton_method(:docker_running?) { true }

    @command.define_singleton_method(:system_quiet) do |cmd|
      case cmd
      when /docker ps.*db-test/
        commands_run.any? { |c| c.include?("docker run") }
      when /docker inspect db-test/
        false
      else
        true
      end
    end

    @command.define_singleton_method(:system!) do |*args|
      commands_run << args.join(" ")
    end

    @command.define_singleton_method(:sleep) { |_| }

    @command.execute

    docker_run = commands_run.find { |cmd| cmd.include?("docker run") }
    assert docker_run
    assert_match(/--name db-test/, docker_run)
    assert_match(/-p 5433:5432/, docker_run)
    assert_match(/postgres:15/, docker_run)
    assert_match(/-e POSTGRES_PASSWORD=secret/, docker_run)
    assert_match(/-v db-test:\/var\/lib\/postgresql\/data/, docker_run)
  end

  test "execute creates redis container with correct parameters" do
    @config.redis = OpenStruct.new(
      name: "redis-test",
      port: 6380,
      version: "7"
    )

    commands_run = []

    @command.define_singleton_method(:docker_running?) { true }

    @command.define_singleton_method(:system_quiet) do |cmd|
      case cmd
      when /docker ps.*redis-test/
        commands_run.any? { |c| c.include?("docker run") }
      when /docker inspect redis-test/
        false
      else
        true
      end
    end

    @command.define_singleton_method(:system!) do |*args|
      commands_run << args.join(" ")
    end

    @command.define_singleton_method(:sleep) { |_| }

    @command.execute

    docker_run = commands_run.find { |cmd| cmd.include?("docker run") }
    assert docker_run
    assert_match(/--name redis-test/, docker_run)
    assert_match(/-p 6380:6379/, docker_run)
    assert_match(/redis:7/, docker_run)
  end

  test "execute starts existing stopped container" do
    @config.database = OpenStruct.new(name: "db-test", port: 5432)

    commands_run = []

    @command.define_singleton_method(:native_postgresql_available?) { false }
    @command.define_singleton_method(:docker_running?) { true }

    @command.define_singleton_method(:system_quiet) do |cmd|
      case cmd
      when /docker ps.*db-test/
        commands_run.include?("docker start db-test")
      when /docker inspect db-test/
        true
      when /docker start db-test/
        commands_run << cmd
        true
      else
        true
      end
    end

    @command.define_singleton_method(:sleep) { |_| }

    @command.execute

    assert_includes commands_run, "docker start db-test"
  end

  test "execute recreates container if start fails" do
    @config.database = OpenStruct.new(name: "db-test", port: 5432)

    commands_run = []

    @command.define_singleton_method(:native_postgresql_available?) { false }
    @command.define_singleton_method(:docker_running?) { true }

    @command.define_singleton_method(:system_quiet) do |cmd|
      case cmd
      when /docker ps.*db-test/
        commands_run.include?("docker run -d --name db-test -p 5432:5432 -e POSTGRES_PASSWORD=postgres -v db-test:/var/lib/postgresql/data postgres:14")
      when /docker inspect db-test/
        true
      when /docker start db-test/
        false
      when /docker rm -f db-test/
        commands_run << cmd
        true
      else
        true
      end
    end

    @command.define_singleton_method(:system!) do |*args|
      commands_run << args.join(" ")
    end

    @command.define_singleton_method(:sleep) { |_| }

    @command.execute

    assert_includes commands_run, "docker rm -f db-test"
    assert commands_run.any? { |cmd| cmd.include?("docker run") }
  end

  test "execute skips container if already running" do
    @config.database = OpenStruct.new(name: "db-test")

    commands_run = []

    @command.define_singleton_method(:docker_running?) { true }

    @command.define_singleton_method(:system_quiet) do |cmd|
      true
    end

    @command.define_singleton_method(:system!) do |*args|
      commands_run << args.join(" ")
    end

    @command.execute

    assert_empty commands_run
  end

  test "execute raises error if container fails to start" do
    @config.database = OpenStruct.new(name: "db-test", port: 5432)

    @command.define_singleton_method(:native_postgresql_available?) { false }
    @command.define_singleton_method(:docker_running?) { true }

    @command.define_singleton_method(:system_quiet) do |cmd|
      case cmd
      when /docker ps.*db-test/
        false
      when /docker inspect db-test/
        false
      else
        true
      end
    end

    @command.define_singleton_method(:system!) { |*args| }
    @command.define_singleton_method(:sleep) { |_| }

    assert_raises(RuntimeError) do
      @command.execute
    end
  end
end

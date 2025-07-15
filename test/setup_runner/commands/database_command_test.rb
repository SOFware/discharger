require "test_helper"
require "setup_runner_test_helper"
require "discharger/setup_runner/commands/database_command"
require "logger"
require "ostruct"

class DatabaseCommandTest < ActiveSupport::TestCase
  include SetupRunnerTestHelper

  def setup
    super
    @config = OpenStruct.new
    @logger = Logger.new(StringIO.new)
    @command = Discharger::SetupRunner::Commands::DatabaseCommand.new(@config, @test_dir, @logger)
    create_file("bin/rails", "#!/usr/bin/env ruby\n# Rails stub")
    FileUtils.chmod(0755, File.join(@test_dir, "bin/rails"))
  end

  test "description returns correct text" do
    assert_equal "Setup database", @command.description
  end

  test "can_execute? returns true when bin/rails exists" do
    assert @command.can_execute?
  end

  test "can_execute? returns false when bin/rails does not exist" do
    FileUtils.rm_rf(File.join(@test_dir, "bin"))
    refute @command.can_execute?
  end

  test "execute runs all database commands in sequence" do
    commands_run = []
    
    @command.define_singleton_method(:system!) do |*args|
      if args.first.is_a?(Hash)
        env = args.shift
        command = args.join(" ")
        commands_run << { env: env, command: command }
      else
        command = args.join(" ")
        commands_run << { env: {}, command: command }
      end
    end
    
    @command.execute
    
    assert_equal 5, commands_run.size
    
    # Development database commands
    assert_equal "bin/rails db:drop db:create > /dev/null 2>&1", commands_run[0][:command]
    assert_equal "bin/rails db:schema:load db:migrate", commands_run[1][:command]
    assert_equal "bin/rails db:seed", commands_run[2][:command]
    assert_empty commands_run[2][:env]
    
    # Test database commands
    assert_equal "bin/rails db:drop db:create db:schema:load > /dev/null 2>&1", commands_run[3][:command]
    assert_equal({ "RAILS_ENV" => "test" }, commands_run[3][:env])
    
    # Cleanup commands
    assert_equal "bin/rails log:clear tmp:clear > /dev/null 2>&1", commands_run[4][:command]
  end

  test "execute passes SEED_DEV_ENV when config.seed_env is true" do
    @config.seed_env = true
    commands_run = []
    
    @command.define_singleton_method(:system!) do |*args|
      if args.first.is_a?(Hash)
        env = args.shift
        command = args.join(" ")
        commands_run << { env: env, command: command }
      else
        command = args.join(" ")
        commands_run << { env: {}, command: command }
      end
    end
    
    @command.execute
    
    # Find the seed command
    seed_command = commands_run.find { |cmd| cmd[:command] == "bin/rails db:seed" }
    assert_equal({ "SEED_DEV_ENV" => "true" }, seed_command[:env])
  end

  test "execute logs all activities" do
    io = StringIO.new
    logger = Logger.new(io)
    command = Discharger::SetupRunner::Commands::DatabaseCommand.new(@config, @test_dir, logger)
    
    command.define_singleton_method(:system!) { |*args| }
    
    command.execute
    
    log_output = io.string
    assert_match(/Setting up database/, log_output)
    assert_match(/Dropping & recreating the development database/, log_output)
    assert_match(/Loading the database schema/, log_output)
    assert_match(/Seeding the database/, log_output)
    assert_match(/Dropping & recreating the test database/, log_output)
    assert_match(/Removing old logs and tempfiles/, log_output)
  end

  test "execute handles database command failures" do
    @command.define_singleton_method(:system!) do |*args|
      if args.join(" ").include?("db:schema:load")
        raise "Database connection failed"
      end
    end
    
    assert_raises(RuntimeError) do
      @command.execute
    end
  end
end
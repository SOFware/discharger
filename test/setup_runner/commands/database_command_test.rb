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
    
    assert_equal 7, commands_run.size
    
    # Development database connection termination
    assert_equal "bin/rails runner", commands_run[0][:command].split[0..1].join(" ")
    assert_match(/pg_terminate_backend/, commands_run[0][:command])
    assert_empty commands_run[0][:env]
    
    # Development database commands
    assert_equal "bin/rails db:drop db:create > /dev/null 2>&1", commands_run[1][:command]
    assert_equal "bin/rails db:schema:load db:migrate", commands_run[2][:command]
    assert_equal "bin/rails db:seed", commands_run[3][:command]
    assert_empty commands_run[3][:env]
    
    # Test database connection termination
    assert_equal "bin/rails runner", commands_run[4][:command].split[0..1].join(" ")
    assert_match(/pg_terminate_backend/, commands_run[4][:command])
    assert_equal({ "RAILS_ENV" => "test" }, commands_run[4][:env])
    
    # Test database commands
    assert_equal "bin/rails db:drop db:create db:schema:load > /dev/null 2>&1", commands_run[5][:command]
    assert_equal({ "RAILS_ENV" => "test" }, commands_run[5][:env])
    
    # Cleanup commands
    assert_equal "bin/rails log:clear tmp:clear > /dev/null 2>&1", commands_run[6][:command]
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

  test "terminates database connections before dropping database" do
    commands_run = []
    drop_would_fail_without_termination = true
    
    @command.define_singleton_method(:system!) do |*args|
      if args.first.is_a?(Hash)
        env = args.shift
        command = args.join(" ")
        commands_run << { env: env, command: command }
      else
        command = args.join(" ")
        commands_run << { env: {}, command: command }
      end
      
      # Simulate that drop would fail if connections weren't terminated
      if command.include?("db:drop") && drop_would_fail_without_termination
        raise "Database is being accessed by other users" 
      end
      
      # If we see the termination command, mark that connections are terminated
      if command.include?("pg_terminate_backend")
        drop_would_fail_without_termination = false
      end
    end
    
    # This should not raise an error because connections are terminated first
    @command.execute
    
    # Verify termination happened before drops
    termination_indices = commands_run.each_index.select { |i| 
      commands_run[i][:command].include?("pg_terminate_backend") 
    }
    drop_indices = commands_run.each_index.select { |i| 
      commands_run[i][:command].include?("db:drop") 
    }
    
    assert_equal 2, termination_indices.size, "Should terminate connections for both dev and test"
    assert_equal 2, drop_indices.size, "Should drop both dev and test databases"
    
    # Ensure termination happens before drop for development
    assert termination_indices[0] < drop_indices[0], 
           "Development DB connections should be terminated before drop"
    
    # Ensure termination happens before drop for test
    assert termination_indices[1] < drop_indices[1], 
           "Test DB connections should be terminated before drop"
  end

  test "terminate_database_connections uses rails runner with PostgreSQL check" do
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
    
    # Call the private method directly
    @command.send(:terminate_database_connections)
    
    assert_equal 1, commands_run.size
    runner_command = commands_run[0]
    
    assert_equal "bin/rails runner", runner_command[:command].split[0..1].join(" ")
    assert_match(/ActiveRecord::Base\.connection\.adapter_name.*postgresql/i, runner_command[:command])
    assert_match(/pg_terminate_backend/, runner_command[:command])
    assert_match(/pg_stat_activity/, runner_command[:command])
    assert_match(/current_database/, runner_command[:command])
    assert_match(/pg_backend_pid/, runner_command[:command])
  end

  test "terminate_database_connections handles non-PostgreSQL databases gracefully" do
    # This test ensures the command doesn't fail for non-PostgreSQL databases
    # The rails runner script includes a check for PostgreSQL adapter
    commands_run = []
    
    @command.define_singleton_method(:system!) do |*args|
      command = args.join(" ")
      # Simulate successful execution even if not PostgreSQL
      commands_run << command
    end
    
    @command.send(:terminate_database_connections)
    
    assert_equal 1, commands_run.size
    assert_match(/adapter_name.*postgresql/i, commands_run[0])
  end
end
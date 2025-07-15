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
    FileUtils.chmod(0o755, File.join(@test_dir, "bin/rails"))

    # Store original Open3.capture3 method
    @original_capture3 = Open3.method(:capture3)
  end

  def teardown
    super
    # Restore original Open3.capture3 if it was modified
    if @original_capture3 && Open3.singleton_class.method_defined?(:capture3)
      Open3.singleton_class.remove_method(:capture3)
      Open3.define_singleton_method(:capture3, @original_capture3)
    end
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
    spinner_calls = []

    @command.define_singleton_method(:with_spinner) do |message, &block|
      spinner_calls << message
      block.call
    end

    # Mock Open3.capture3 to succeed
    Open3.define_singleton_method(:capture3) do |*args|
      ["", "", OpenStruct.new(success?: true)]
    end

    @command.execute

    # Check spinner messages
    assert spinner_calls.include?("Terminating existing database connections")
    assert spinner_calls.include?("Dropping and recreating development database")
    assert spinner_calls.include?("Loading database schema and running migrations")
    assert spinner_calls.include?("Seeding the database")
    assert spinner_calls.include?("Terminating existing database connections (test)")
    assert spinner_calls.include?("Setting up test database")
    assert spinner_calls.include?("Clearing logs and temp files")
  end

  test "execute passes SEED_DEV_ENV when config.seed_env is true" do
    @config.seed_env = true
    capture3_calls = []

    # Mock spinner
    @command.define_singleton_method(:with_spinner) do |message, &block|
      block.call
    end

    # Mock Open3.capture3 to track calls
    Open3.define_singleton_method(:capture3) do |*args|
      capture3_calls << args
      ["", "", OpenStruct.new(success?: true)]
    end

    @command.execute

    # Find the seed command call
    seed_call = capture3_calls.find { |call| call.any? { |arg| arg.is_a?(String) && arg.include?("db:seed") } }
    assert seed_call.first.is_a?(Hash) && seed_call.first["SEED_DEV_ENV"] == "true"
  end

  test "execute runs all expected commands" do
    capture3_calls = []

    # Mock spinner
    @command.define_singleton_method(:with_spinner) do |message, &block|
      block.call
    end

    # Mock Open3.capture3 to track calls
    Open3.define_singleton_method(:capture3) do |*args|
      capture3_calls << args.join(" ")
      ["", "", OpenStruct.new(success?: true)]
    end

    @command.execute

    # Check that all expected commands were run
    assert capture3_calls.any? { |cmd| cmd.include?("pg_terminate_backend") }
    assert capture3_calls.any? { |cmd| cmd.include?("db:drop db:create") }
    assert capture3_calls.any? { |cmd| cmd.include?("db:schema:load") }
    assert capture3_calls.any? { |cmd| cmd.include?("db:seed") }
    assert capture3_calls.any? { |cmd| cmd.include?("log:clear tmp:clear") }
  end

  test "execute handles database command failures" do
    # Mock spinner to call block but then handle result
    @command.define_singleton_method(:with_spinner) do |message, &block|
      result = block.call
      # Since NO_SPINNER is set in tests, we need to handle errors here
      if result.is_a?(Hash) && !result[:success] && result[:raise_error] != false
        raise result[:error]
      end
      result
    end

    # Mock Open3.capture3 for other calls
    Open3.define_singleton_method(:capture3) do |*args|
      if args.join(" ").include?("db:schema:load")
        ["", "Database connection failed", OpenStruct.new(success?: false)]
      else
        ["", "", OpenStruct.new(success?: true)]
      end
    end

    assert_raises(RuntimeError) do
      @command.execute
    end
  end

  test "terminates database connections before dropping database" do
    spinner_order = []

    @command.define_singleton_method(:with_spinner) do |message, &block|
      spinner_order << message
      block.call
    end

    # Mock Open3.capture3 to succeed
    Open3.define_singleton_method(:capture3) do |*args|
      ["", "", OpenStruct.new(success?: true)]
    end

    @command.execute

    # Verify termination happens before drops
    term_dev_idx = spinner_order.index("Terminating existing database connections")
    drop_dev_idx = spinner_order.index("Dropping and recreating development database")
    term_test_idx = spinner_order.index("Terminating existing database connections (test)")
    drop_test_idx = spinner_order.index("Setting up test database")

    assert term_dev_idx < drop_dev_idx, "Dev connections should be terminated before drop"
    assert term_test_idx < drop_test_idx, "Test connections should be terminated before drop"
  end

  test "terminate_database_connections uses rails runner with PostgreSQL check" do
    capture3_called = false
    capture3_args = nil

    # Mock Open3.capture3 to track the call
    Open3.define_singleton_method(:capture3) do |*args|
      capture3_called = true
      capture3_args = args
      ["", "", OpenStruct.new(success?: true)]
    end

    # Call the private method directly
    @command.send(:terminate_database_connections)

    assert capture3_called, "Should call capture3"
    assert capture3_args.any? { |arg| arg == "bin/rails" }
    assert capture3_args.any? { |arg| arg == "runner" }

    # Find the runner script argument
    runner_script = capture3_args.find { |arg| arg.is_a?(String) && arg.include?("ActiveRecord") }
    assert runner_script, "Should have runner script"
    assert_match(/ActiveRecord::Base\.connection\.adapter_name.*postgresql/i, runner_script)
    assert_match(/pg_terminate_backend/, runner_script)
    assert_match(/pg_stat_activity/, runner_script)
    assert_match(/current_database/, runner_script)
    assert_match(/pg_backend_pid/, runner_script)
  end

  test "terminate_database_connections handles non-PostgreSQL databases gracefully" do
    # This test ensures the command doesn't fail for non-PostgreSQL databases
    # The rails runner script includes a check for PostgreSQL adapter
    capture3_called = false

    # Mock Open3.capture3
    Open3.define_singleton_method(:capture3) do |*args|
      capture3_called = true
      # Simulate successful execution even if not PostgreSQL
      ["", "", OpenStruct.new(success?: true)]
    end

    @command.send(:terminate_database_connections)

    assert capture3_called, "Should attempt to run the command"
  end
end

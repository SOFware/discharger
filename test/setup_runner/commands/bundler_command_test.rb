require "test_helper"
require "setup_runner_test_helper"
require "discharger/setup_runner/commands/bundler_command"
require "logger"

class BundlerCommandTest < ActiveSupport::TestCase
  include SetupRunnerTestHelper

  def setup
    super
    @config = {}
    @logger = Logger.new(StringIO.new)
    @command = Discharger::SetupRunner::Commands::BundlerCommand.new(@config, @test_dir, @logger)
  end

  test "description returns correct text" do
    assert_equal "Install Ruby dependencies", @command.description
  end

  test "can_execute? returns true when Gemfile exists" do
    create_file("Gemfile", "source 'https://rubygems.org'")
    assert @command.can_execute?
  end

  test "can_execute? returns false when Gemfile does not exist" do
    refute @command.can_execute?
  end

  test "execute installs bundler and runs bundle install when bundle check fails" do
    create_file("Gemfile", "source 'https://rubygems.org'")
    
    commands_run = []
    @command.define_singleton_method(:system!) do |*args|
      command = args.join(" ")
      commands_run << command
      # Don't raise for bundle check failure
    end
    @command.define_singleton_method(:system_quiet) do |*args|
      command = args.join(" ")
      commands_run << command
      # bundle check fails
      args.join(" ") == "bundle check" ? false : true
    end
    
    @command.execute
    
    assert_equal 3, commands_run.size
    assert_equal "gem install bundler --conservative", commands_run[0]
    assert_equal "bundle check", commands_run[1]
    assert_equal "bundle install", commands_run[2]
  end

  test "execute installs bundler but skips bundle install when bundle check succeeds" do
    create_file("Gemfile", "source 'https://rubygems.org'")
    
    commands_run = []
    @command.define_singleton_method(:system!) do |*args|
      command = args.join(" ")
      commands_run << command
    end
    @command.define_singleton_method(:system_quiet) do |*args|
      command = args.join(" ")
      commands_run << command
      true # all commands succeed
    end
    
    @command.execute
    
    assert_equal 2, commands_run.size
    assert_equal "gem install bundler --conservative", commands_run[0]
    # bundle check is called via system, not system!, so it's the last one
    assert_equal "bundle check", commands_run[1]
    # bundle install should not be called
  end

  test "execute logs activity" do
    create_file("Gemfile", "source 'https://rubygems.org'")
    
    io = StringIO.new
    logger = Logger.new(io)
    command = Discharger::SetupRunner::Commands::BundlerCommand.new(@config, @test_dir, logger)
    
    command.define_singleton_method(:system!) { |*args| }
    command.define_singleton_method(:system_quiet) { |*args| true }
    
    command.execute
    
    log_output = io.string
    assert_match(/\[BundlerCommand\] Installing dependencies/, log_output)
  end

  test "execute handles gem install failure" do
    create_file("Gemfile", "source 'https://rubygems.org'")
    
    @command.define_singleton_method(:system!) do |*args|
      raise "gem install bundler --conservative failed:"
    end
    
    assert_raises(RuntimeError) do
      @command.execute
    end
  end

  test "execute handles bundle install failure" do
    create_file("Gemfile", "source 'https://rubygems.org'")
    
    @command.define_singleton_method(:system!) do |*args|
      command = args.join(" ")
      if command == "bundle install"
        raise "bundle install failed:"
      end
    end
    @command.define_singleton_method(:system_quiet) do |*args|
      command = args.join(" ")
      command == "bundle check" ? false : true
    end
    
    assert_raises(RuntimeError) do
      @command.execute
    end
  end
end
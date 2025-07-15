require "test_helper"
require "setup_runner_test_helper"
require "discharger/setup_runner/commands/brew_command"
require "logger"

class BrewCommandTest < ActiveSupport::TestCase
  include SetupRunnerTestHelper

  def setup
    super
    @config = {}
    @logger = Logger.new(StringIO.new)
    @command = Discharger::SetupRunner::Commands::BrewCommand.new(@config, @test_dir, @logger)
  end

  test "description returns correct text" do
    assert_equal "Install Homebrew dependencies", @command.description
  end

  test "can_execute? returns true when Brewfile exists" do
    create_file("Brewfile", "brew 'git'")
    assert @command.can_execute?
  end

  test "can_execute? returns false when Brewfile does not exist" do
    refute @command.can_execute?
  end

  test "execute runs brew bundle when user confirms" do
    create_file("Brewfile", "brew 'git'")
    
    # Mock user input and system call
    input = StringIO.new("Y\n")
    @command.define_singleton_method(:gets) { input.gets }
    
    system_called = false
    @command.define_singleton_method(:system!) do |*args|
      system_called = true if args.join(" ") == "brew bundle"
    end
    
    output, _ = capture_output do
      @command.execute
    end
    
    assert system_called
    assert_match /Proceed with brew bundle\?/, output
  end

  test "execute does not run brew bundle when user declines" do
    create_file("Brewfile", "brew 'git'")
    
    # Mock user input
    input = StringIO.new("n\n")
    @command.define_singleton_method(:gets) { input.gets }
    
    system_called = false
    @command.define_singleton_method(:system!) do |*args|
      system_called = true if args.join(" ") == "brew bundle"
    end
    
    capture_output do
      @command.execute
    end
    
    refute system_called
  end

  test "execute logs activity" do
    create_file("Brewfile", "brew 'git'")
    
    io = StringIO.new
    logger = Logger.new(io)
    command = Discharger::SetupRunner::Commands::BrewCommand.new(@config, @test_dir, logger)
    
    # Mock user input and system call
    input = StringIO.new("Y\n")
    command.define_singleton_method(:gets) { input.gets }
    command.define_singleton_method(:system!) { |*args| }
    
    capture_output do
      command.execute
    end
    
    log_output = io.string
    assert_match /\[BrewCommand\] Ensuring brew dependencies/, log_output
    assert_match /\[BrewCommand\] Executing brew bundle/, log_output
    assert_match /\[BrewCommand\] brew bundle succeeded/, log_output
  end

  test "execute handles brew bundle failure" do
    create_file("Brewfile", "brew 'git'")
    
    # Mock user input and failing system call
    input = StringIO.new("Y\n")
    @command.define_singleton_method(:gets) { input.gets }
    @command.define_singleton_method(:system!) do |*args|
      raise "brew bundle failed:"
    end
    
    assert_raises(RuntimeError) do
      capture_output do
        @command.execute
      end
    end
  end
end
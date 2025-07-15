require "test_helper"
require "setup_runner_test_helper"
require "discharger/setup_runner/commands/git_command"
require "logger"
require "ostruct"

class GitCommandTest < ActiveSupport::TestCase
  include SetupRunnerTestHelper

  def setup
    super
    @config = OpenStruct.new
    @logger = Logger.new(StringIO.new)
    @command = Discharger::SetupRunner::Commands::GitCommand.new(@config, @test_dir, @logger)
    FileUtils.mkdir_p(File.join(@test_dir, ".git"))
  end

  test "description returns correct text" do
    assert_equal "Setup git configuration", @command.description
  end

  test "can_execute? returns true when .git directory exists" do
    assert @command.can_execute?
  end

  test "can_execute? returns false when .git directory does not exist" do
    FileUtils.rm_rf(File.join(@test_dir, ".git"))
    refute @command.can_execute?
  end

  test "execute sets up commit template when .commit-template exists" do
    create_file(".commit-template", "[TICKET-ID] Subject\n\nBody")
    
    commands_run = []
    @command.define_singleton_method(:system!) do |*args|
      commands_run << args.join(" ")
    end
    
    @command.execute
    
    assert_includes commands_run, "git config --local commit.template .commit-template"
  end

  test "execute does not set commit template when file does not exist" do
    commands_run = []
    @command.define_singleton_method(:system!) do |*args|
      commands_run << args.join(" ")
    end
    
    @command.execute
    
    refute commands_run.any? { |cmd| cmd.include?("commit.template") }
  end

  test "execute sets up git hooks path when .githooks directory exists" do
    FileUtils.mkdir_p(File.join(@test_dir, ".githooks"))
    
    commands_run = []
    @command.define_singleton_method(:system!) do |*args|
      commands_run << args.join(" ")
    end
    
    @command.execute
    
    assert_includes commands_run, "git config --local core.hooksPath .githooks"
  end

  test "execute does not set hooks path when directory does not exist" do
    commands_run = []
    @command.define_singleton_method(:system!) do |*args|
      commands_run << args.join(" ")
    end
    
    @command.execute
    
    refute commands_run.any? { |cmd| cmd.include?("hooksPath") }
  end

  test "execute applies custom git config from configuration" do
    @config.git_config = {
      "user.name" => "Test User",
      "user.email" => "test@example.com",
      "pull.rebase" => "true"
    }
    
    commands_run = []
    @command.define_singleton_method(:system!) do |*args|
      commands_run << args.join(" ")
    end
    
    @command.execute
    
    assert_includes commands_run, "git config --local user.name 'Test User'"
    assert_includes commands_run, "git config --local user.email 'test@example.com'"
    assert_includes commands_run, "git config --local pull.rebase 'true'"
  end

  test "execute handles all git setup options together" do
    create_file(".commit-template", "Template")
    FileUtils.mkdir_p(File.join(@test_dir, ".githooks"))
    @config.git_config = { "core.autocrlf" => "input" }
    
    commands_run = []
    @command.define_singleton_method(:system!) do |*args|
      commands_run << args.join(" ")
    end
    
    @command.execute
    
    assert_equal 3, commands_run.size
    assert commands_run.any? { |cmd| cmd.include?("commit.template") }
    assert commands_run.any? { |cmd| cmd.include?("hooksPath") }
    assert commands_run.any? { |cmd| cmd.include?("core.autocrlf") }
  end

  test "execute logs all activities" do
    create_file(".commit-template", "Template")
    FileUtils.mkdir_p(File.join(@test_dir, ".githooks"))
    @config.git_config = { "user.name" => "Test" }
    
    io = StringIO.new
    logger = Logger.new(io)
    command = Discharger::SetupRunner::Commands::GitCommand.new(@config, @test_dir, logger)
    
    command.define_singleton_method(:system!) { |*args| }
    
    command.execute
    
    log_output = io.string
    assert_match(/Setting up git configuration/, log_output)
    assert_match(/Git commit template configured/, log_output)
    assert_match(/Git hooks path configured/, log_output)
    assert_match(/Set git config user.name/, log_output)
  end

  test "execute handles git command failures" do
    create_file(".commit-template", "Template")
    
    @command.define_singleton_method(:system!) do |*args|
      raise "Git config failed"
    end
    
    assert_raises(RuntimeError) do
      @command.execute
    end
  end
end
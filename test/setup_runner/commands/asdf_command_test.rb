require "test_helper"
require "setup_runner_test_helper"
require "discharger/setup_runner/commands/asdf_command"
require "logger"

class AsdfCommandTest < ActiveSupport::TestCase
  include SetupRunnerTestHelper

  def setup
    super
    @config = {}
    @logger = Logger.new(StringIO.new)
    @command = Discharger::SetupRunner::Commands::AsdfCommand.new(@config, @test_dir, @logger)
  end

  test "description returns correct text" do
    assert_equal "Install tool versions with asdf", @command.description
  end

  test "can_execute? returns true when .tool-versions exists" do
    create_file(".tool-versions", "ruby 3.0.0\nnode 18.0.0")
    assert @command.can_execute?
  end

  test "can_execute? returns false when .tool-versions does not exist" do
    refute @command.can_execute?
  end

  test "execute returns early when asdf is not installed" do
    create_file(".tool-versions", "ruby 3.0.0")

    @command.define_singleton_method(:system_quiet) do |cmd|
      !(cmd == "which asdf")
    end

    io = StringIO.new
    logger = Logger.new(io)
    command = Discharger::SetupRunner::Commands::AsdfCommand.new(@config, @test_dir, logger)
    command.define_singleton_method(:system_quiet) do |cmd|
      !(cmd == "which asdf")
    end

    command.execute

    log_output = io.string
    assert_match(/asdf not installed/, log_output)
  end

  test "execute installs nodejs plugin when not present" do
    create_file(".tool-versions", "node 18.0.0")

    plugins_added = []
    versions_installed = []
    user_responded = false

    @command.define_singleton_method(:system_quiet) do |cmd|
      case cmd
      when "which asdf"
        true
      when "asdf plugin list | grep nodejs"
        false # Plugin not installed
      when "asdf plugin list | grep ruby"
        true # Ruby plugin already installed
      else
        true
      end
    end

    @command.define_singleton_method(:system!) do |*args|
      cmd = args.join(" ")
      if cmd.include?("asdf plugin add")
        plugins_added << cmd
      elsif cmd.include?("asdf install")
        versions_installed << cmd
      end
    end

    @command.define_singleton_method(:gets) {
      user_responded = true
      StringIO.new("Y\n").gets
    }

    with_tty_stdin do
      capture_output do
        @command.execute
      end
    end

    assert user_responded
    assert_includes plugins_added, "asdf plugin add nodejs https://github.com/asdf-vm/asdf-nodejs.git"
    assert_includes versions_installed, "asdf install node 18.0.0"
  end

  test "execute installs ruby plugin when not present" do
    create_file(".tool-versions", "ruby 3.0.0")

    plugins_added = []
    versions_installed = []

    @command.define_singleton_method(:system_quiet) do |cmd|
      case cmd
      when "which asdf"
        true
      when "asdf plugin list | grep ruby"
        false # Plugin not installed
      when "asdf plugin list | grep nodejs"
        true # Node plugin already installed
      else
        true
      end
    end

    @command.define_singleton_method(:system!) do |*args|
      cmd = args.join(" ")
      if cmd.include?("asdf plugin add")
        plugins_added << cmd
      elsif cmd.include?("asdf install")
        versions_installed << cmd
      end
    end

    @command.define_singleton_method(:gets) { StringIO.new("Y\n").gets }

    with_tty_stdin do
      capture_output do
        @command.execute
      end
    end

    assert_includes plugins_added, "asdf plugin add ruby https://github.com/asdf-vm/asdf-ruby.git"
    assert_includes versions_installed, "asdf install ruby 3.0.0"
  end

  test "execute skips plugin installation when user declines" do
    create_file(".tool-versions", "ruby 3.0.0")

    plugins_added = []

    @command.define_singleton_method(:system_quiet) do |cmd|
      case cmd
      when "which asdf"
        true
      when "asdf plugin list | grep ruby"
        false # Plugin not installed
      else
        true
      end
    end

    @command.define_singleton_method(:system!) do |*args|
      cmd = args.join(" ")
      plugins_added << cmd if cmd.include?("asdf plugin add")
    end

    @command.define_singleton_method(:gets) { StringIO.new("n\n").gets }

    with_tty_stdin do
      capture_output do
        @command.execute
      end
    end

    assert_empty plugins_added
  end

  test "execute handles multiple versions in .tool-versions" do
    create_file(".tool-versions", "ruby 3.0.0\nnode 18.0.0\npython 3.9.0")

    versions_installed = []

    @command.define_singleton_method(:system_quiet) do |cmd|
      true
    end

    @command.define_singleton_method(:system!) do |*args|
      cmd = args.join(" ")
      versions_installed << cmd if cmd.include?("asdf install")
    end

    @command.execute

    # Should not install any versions since no new plugins were added
    assert_empty versions_installed
  end
end

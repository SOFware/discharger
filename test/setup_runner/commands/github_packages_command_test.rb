require "test_helper"
require "setup_runner_test_helper"
require "discharger/setup_runner/configuration"
require "discharger/setup_runner/commands/github_packages_command"
require "logger"
require "open3"
require "socket"

class GithubPackagesCommandTest < ActiveSupport::TestCase
  include SetupRunnerTestHelper

  SOURCE = "https://rubygems.pkg.github.com/example"

  def setup
    super
    @config = Discharger::SetupRunner::Configuration.new
    @config.github_packages = Discharger::SetupRunner::GithubPackagesConfig.new.tap do |g|
      g.source = SOURCE
    end
    @logger = Logger.new(StringIO.new)
    @command = Discharger::SetupRunner::Commands::GithubPackagesCommand.new(@config, @test_dir, @logger)
  end

  test "description returns correct text" do
    assert_equal "Configure GitHub Packages credentials", @command.description
  end

  test "can_execute? returns true when a source is configured" do
    assert @command.can_execute?
  end

  test "can_execute? returns false when no github_packages config is present" do
    @config.github_packages = nil
    refute @command.can_execute?
  end

  test "can_execute? returns false when the source is empty" do
    @config.github_packages.source = ""
    refute @command.can_execute?
  end

  test "execute stores and verifies credentials when gh is installed and authenticated" do
    stored = []
    stub_shell(gh_installed: true, authenticated: true,
      gh_outputs: {["api", "user", "--jq", ".login"] => "octocat", ["auth", "token"] => "gho_secret"})
    @command.define_singleton_method(:store_bundler_credentials) { |user, token| stored << [user, token] }
    @command.define_singleton_method(:credentials_valid?) { |_user, _token| true }

    @command.execute

    assert_equal [["octocat", "gho_secret"]], stored
  end

  test "execute skips without storing credentials when gh is not installed" do
    stored = []
    stub_shell(gh_installed: false, authenticated: false, gh_outputs: {})
    @command.define_singleton_method(:store_bundler_credentials) { |user, token| stored << [user, token] }

    @command.execute

    assert_empty stored
  end

  test "execute skips without storing credentials when not authenticated and login fails" do
    stored = []
    stub_shell(gh_installed: true, authenticated: false, gh_outputs: {})
    @command.define_singleton_method(:login) { false }
    @command.define_singleton_method(:store_bundler_credentials) { |user, token| stored << [user, token] }

    @command.execute

    assert_empty stored
  end

  test "execute skips without storing credentials when gh returns no token" do
    stored = []
    stub_shell(gh_installed: true, authenticated: true,
      gh_outputs: {["api", "user", "--jq", ".login"] => "octocat", ["auth", "token"] => nil})
    @command.define_singleton_method(:store_bundler_credentials) { |user, token| stored << [user, token] }

    @command.execute

    assert_empty stored
  end

  test "execute warns about missing read:packages scope when the source rejects credentials" do
    io = StringIO.new
    logger = Logger.new(io)
    command = Discharger::SetupRunner::Commands::GithubPackagesCommand.new(@config, @test_dir, logger)
    stub_shell(gh_installed: true, authenticated: true,
      gh_outputs: {["api", "user", "--jq", ".login"] => "octocat", ["auth", "token"] => "gho_secret"},
      command: command)
    command.define_singleton_method(:store_bundler_credentials) { |_user, _token| }
    command.define_singleton_method(:credentials_valid?) { |_user, _token| false }

    command.execute

    assert_match(/read:packages/, io.string)
    assert_match(/gh auth refresh/, io.string)
  end

  test "execute never logs the token" do
    io = StringIO.new
    logger = Logger.new(io)
    command = Discharger::SetupRunner::Commands::GithubPackagesCommand.new(@config, @test_dir, logger)
    stub_shell(gh_installed: true, authenticated: true,
      gh_outputs: {["api", "user", "--jq", ".login"] => "octocat", ["auth", "token"] => "gho_secret"},
      command: command)
    command.define_singleton_method(:store_bundler_credentials) { |_user, _token| }
    command.define_singleton_method(:credentials_valid?) { |_user, _token| true }

    command.execute

    refute_match(/gho_secret/, io.string)
  end

  test "store_bundler_credentials writes the credentials to the local bundler config" do
    calls = stub_capture3(success: true) do
      @command.send(:store_bundler_credentials, "octocat", "gho_secret")
    end

    assert_equal [["bundle", "config", "set", "--local", SOURCE, "octocat:gho_secret"]], calls
  end

  test "store_bundler_credentials raises without leaking the token when bundle config fails" do
    error = assert_raises(RuntimeError) do
      stub_capture3(success: false, stderr: "could not write config") do
        @command.send(:store_bundler_credentials, "octocat", "gho_secret")
      end
    end

    assert_match(/could not write config/, error.message)
    refute_match(/gho_secret/, error.message)
  end

  test "execute warns when the source responds 401 to the credential probe" do
    io = StringIO.new
    with_stub_registry("401 Unauthorized") do |source|
      command = probing_command(io, source)
      command.execute
    end

    assert_match(/read:packages/, io.string)
  end

  test "execute reports success when the source accepts the credential probe" do
    io = StringIO.new
    with_stub_registry("200 OK") do |source|
      command = probing_command(io, source)
      command.execute
    end

    assert_match(/Configured bundler credentials/, io.string)
    refute_match(/read:packages/, io.string)
  end

  test "execute treats an unreachable source as unverifiable, not invalid" do
    io = StringIO.new
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    server.close
    command = probing_command(io, "http://127.0.0.1:#{port}/example")

    command.execute

    assert_match(/Configured bundler credentials/, io.string)
    refute_match(/read:packages/, io.string)
  end

  test "command is registered as github_packages" do
    require "discharger/setup_runner/command_registry"
    assert_equal Discharger::SetupRunner::Commands::GithubPackagesCommand,
      Discharger::SetupRunner::CommandRegistry.get("github_packages")
  end

  private

  # Captures the argv Open3.capture3 is called with so the credential write
  # can be asserted without shelling out to a real bundler.
  def stub_capture3(success:, stderr: "")
    calls = []
    original = Open3.method(:capture3)
    status = Object.new
    status.define_singleton_method(:success?) { success }
    Open3.define_singleton_method(:capture3) do |*args|
      calls << args
      ["", stderr, status]
    end
    yield
    calls
  ensure
    Open3.define_singleton_method(:capture3, original)
  end

  # A command with real credential probing against the given source;
  # everything before the probe is stubbed to succeed.
  def probing_command(io, source)
    config = Discharger::SetupRunner::Configuration.new
    config.github_packages = Discharger::SetupRunner::GithubPackagesConfig.new.tap { |g| g.source = source }
    command = Discharger::SetupRunner::Commands::GithubPackagesCommand.new(config, @test_dir, Logger.new(io))
    stub_shell(gh_installed: true, authenticated: true,
      gh_outputs: {["api", "user", "--jq", ".login"] => "octocat", ["auth", "token"] => "gho_secret"},
      command: command)
    command.define_singleton_method(:store_bundler_credentials) { |_user, _token| }
    command
  end

  # Minimal one-request HTTP server so the probe hits a real socket.
  def with_stub_registry(status_line)
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    thread = Thread.new do
      client = server.accept
      while (line = client.gets) && line != "\r\n"; end
      client.write "HTTP/1.1 #{status_line}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
      client.close
    end
    yield "http://127.0.0.1:#{port}/example"
  ensure
    thread&.kill
    server&.close
  end

  def stub_shell(gh_installed:, authenticated:, gh_outputs:, command: @command)
    command.define_singleton_method(:system_quiet) do |*args|
      case args.join(" ")
      when "which gh" then gh_installed
      when "gh auth status" then authenticated
      else false
      end
    end
    command.define_singleton_method(:gh) { |*args| gh_outputs[args] }
  end
end

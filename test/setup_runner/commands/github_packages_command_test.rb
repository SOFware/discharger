require "test_helper"
require "setup_runner_test_helper"
require "discharger/setup_runner/configuration"
require "discharger/setup_runner/commands/github_packages_command"
require "logger"
require "open3"
require "socket"

class GithubPackagesCommandTest < ActiveSupport::TestCase
  include SetupRunnerTestHelper
  include StubRegistry

  SOURCE = "https://rubygems.pkg.github.com/example"

  def setup
    super
    @config = Discharger::SetupRunner::Configuration.new
    @config.github_packages = Discharger::SetupRunner::GithubPackagesConfig.new.tap do |g|
      g.source = SOURCE
    end
    @io = StringIO.new
    @command = Discharger::SetupRunner::Commands::GithubPackagesCommand.new(@config, @test_dir, Logger.new(@io))
  end

  test "description returns correct text" do
    assert_equal "Check GitHub Packages credentials", @command.description
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

  test "execute reports when the source accepts the gh token" do
    stub_shell(gh_installed: true, authenticated: true,
      gh_outputs: {["api", "user", "--jq", ".login"] => "octocat", ["auth", "token"] => "gho_secret"})
    probed = stub_probe(true)

    @command.execute

    assert_equal [["octocat", "gho_secret"]], probed
    assert_match(/accepts the gh token/, @io.string)
  end

  test "execute warns about read:packages when the source rejects the token" do
    stub_shell(gh_installed: true, authenticated: true,
      gh_outputs: {["api", "user", "--jq", ".login"] => "octocat", ["auth", "token"] => "gho_secret"})
    stub_probe(false)

    @command.execute

    assert_match(/did not accept the gh token/, @io.string)
    assert_match(/gh auth refresh -s read:packages/, @io.string)
  end

  test "execute skips the probe when gh is not installed" do
    stub_shell(gh_installed: false, authenticated: false, gh_outputs: {})
    probed = stub_probe(true)

    @command.execute

    assert_empty probed
    assert_match(/gh\) not found/, @io.string)
  end

  test "execute skips the probe when not authenticated and login fails" do
    stub_shell(gh_installed: true, authenticated: false, gh_outputs: {})
    @command.define_singleton_method(:login) { false }
    probed = stub_probe(true)

    @command.execute

    assert_empty probed
    assert_match(/Not logged in/, @io.string)
  end

  test "execute skips the probe when gh returns no token" do
    stub_shell(gh_installed: true, authenticated: true,
      gh_outputs: {["api", "user", "--jq", ".login"] => "octocat", ["auth", "token"] => nil})
    probed = stub_probe(true)

    @command.execute

    assert_empty probed
    assert_match(/Could not read GitHub credentials/, @io.string)
  end

  test "execute never logs the token" do
    stub_shell(gh_installed: true, authenticated: true,
      gh_outputs: {["api", "user", "--jq", ".login"] => "octocat", ["auth", "token"] => "gho_secret"})
    stub_probe(true)

    @command.execute

    refute_match(/gho_secret/, @io.string)
  end

  test "execute warns when the source responds 401 to the credential probe" do
    with_stub_registry("401 Unauthorized") { |source| probing_command(source).execute }

    assert_match(/read:packages/, @io.string)
  end

  test "execute reports acceptance when the source answers 200" do
    with_stub_registry("200 OK") { |source| probing_command(source).execute }

    assert_match(/accepts the gh token/, @io.string)
    refute_match(/read:packages/, @io.string)
  end

  test "execute treats a 404 as rejection" do
    with_stub_registry("404 Not Found") { |source| probing_command(source).execute }

    assert_match(/did not accept the gh token/, @io.string)
  end

  test "execute treats a 500 as rejection" do
    with_stub_registry("500 Internal Server Error") { |source| probing_command(source).execute }

    assert_match(/did not accept the gh token/, @io.string)
  end

  test "execute treats an unreachable source as rejection" do
    probing_command(unreachable_registry).execute

    assert_match(/did not accept the gh token/, @io.string)
    refute_match(/accepts the gh token/, @io.string)
  end

  test "gh returns the command's output when the CLI answers" do
    with_fake_gh("echo octocat") do
      assert_equal "octocat", @command.send(:gh, "api", "user", "--jq", ".login")
    end
  end

  test "gh returns nil when the CLI fails" do
    with_fake_gh("exit 1") do
      assert_nil @command.send(:gh, "auth", "token")
    end
  end

  test "gh gives up with a message when the CLI stalls" do
    ENV["DISCHARGER_GH_TIMEOUT"] = "0.2"

    with_fake_gh("sleep 5; echo late") do
      assert_nil @command.send(:gh, "auth", "token")
    end

    assert_match(/gh auth token did not answer within 0s/, @io.string)
  ensure
    ENV.delete("DISCHARGER_GH_TIMEOUT")
  end

  test "authenticated? treats a stalled gh auth status as not logged in" do
    io = StringIO.new
    command = Discharger::SetupRunner::Commands::GithubPackagesCommand.new(@config, @test_dir, Logger.new(io))
    ENV["DISCHARGER_GH_TIMEOUT"] = "0.2"

    with_fake_gh("sleep 5") do
      refute command.send(:authenticated?)
    end

    assert_match(/gh auth status did not answer within 0s/, io.string)
  ensure
    ENV.delete("DISCHARGER_GH_TIMEOUT")
  end

  test "gh_timeout defaults to 15, takes setup.yml's value, and lets the env var win" do
    assert_equal 15.0, @command.send(:gh_timeout)

    @config.github_packages.gh_timeout = 5
    assert_equal 5.0, @command.send(:gh_timeout)

    ENV["DISCHARGER_GH_TIMEOUT"] = "0.5"
    assert_equal 0.5, @command.send(:gh_timeout)
  ensure
    ENV.delete("DISCHARGER_GH_TIMEOUT")
  end

  test "gh returns nil when the CLI is not installed" do
    with_fake_gh(nil) do
      assert_nil @command.send(:gh, "auth", "token")
    end
  end

  test "command is registered as github_packages" do
    require "discharger/setup_runner/command_registry"
    assert_equal Discharger::SetupRunner::Commands::GithubPackagesCommand,
      Discharger::SetupRunner::CommandRegistry.get("github_packages")
  end

  test "github_packages runs before bundler when no steps are configured" do
    require "discharger/setup_runner/command_registry"
    names = Discharger::SetupRunner::CommandRegistry.ordered_names

    assert_includes names, "github_packages"
    assert_includes names, "bundler"
    assert_operator names.index("github_packages"), :<, names.index("bundler")
  end

  private

  # Records the credentials each probe receives and answers with `accepted`.
  def stub_probe(accepted, command: @command)
    probed = []
    command.define_singleton_method(:source_accepts_token?) do |user, token|
      probed << [user, token]
      accepted
    end
    probed
  end

  # Puts a fake gh (or none, for nil) first on PATH for the block.
  def with_fake_gh(body)
    bin = File.join(@test_dir, "fake-bin")
    FileUtils.mkdir_p(bin)
    if body
      File.write(File.join(bin, "gh"), "#!/bin/sh\n#{body}\n")
      File.chmod(0o755, File.join(bin, "gh"))
    end
    original_path = ENV["PATH"]
    ENV["PATH"] = body ? "#{bin}:#{original_path}" : bin
    yield
  ensure
    ENV["PATH"] = original_path
  end

  # A command that really probes the given source; everything before the
  # probe is stubbed to succeed.
  def probing_command(source)
    config = Discharger::SetupRunner::Configuration.new
    config.github_packages = Discharger::SetupRunner::GithubPackagesConfig.new.tap { |g| g.source = source }
    command = Discharger::SetupRunner::Commands::GithubPackagesCommand.new(config, @test_dir, Logger.new(@io))
    stub_shell(gh_installed: true, authenticated: true,
      gh_outputs: {["api", "user", "--jq", ".login"] => "octocat", ["auth", "token"] => "gho_secret"},
      command: command)
    command
  end

  def stub_shell(gh_installed:, authenticated:, gh_outputs:, command: @command)
    command.define_singleton_method(:system_quiet) { |*args| args.join(" ") == "which gh" && gh_installed }
    status_output = authenticated ? "" : nil
    command.define_singleton_method(:gh) do |*args|
      (args == ["auth", "status"]) ? status_output : gh_outputs[args]
    end
  end
end

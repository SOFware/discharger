require "test_helper"
require "generators/discharger/install/install_generator"
require "rails/generators/test_case"
require "open3"

class InstallGeneratorTest < Rails::Generators::TestCase
  include StubRegistry

  tests Discharger::Generators::InstallGenerator
  destination File.expand_path("../tmp", __dir__)

  setup :prepare_destination

  test "creates initializer file" do
    run_generator

    assert_file "config/initializers/discharger.rb" do |content|
      assert_match(/Discharger\.configure do/, content)
    end
  end

  test "creates setup script with default path" do
    run_generator

    assert_file "bin/setup" do |content|
      assert_match(/Discharger::Setup\.run/, content)
    end

    template = File.read(File.expand_path("../../lib/generators/discharger/install/templates/setup", __dir__))
    assert_equal template, File.read(File.join(destination_root, "bin/setup")),
      "bin/setup must be a verbatim copy of the template so drift is visible as a plain diff"

    # Check file is executable
    assert File.executable?(File.join(destination_root, "bin/setup"))
  end

  test "generated setup stores GitHub Packages credentials before installing a missing bundle" do
    log = with_stub_registry("200 OK") { |source| run_generated_setup(bundle_check_status: 1, source: source) }

    config_set = log.index { |line| line.start_with?("bundle config set --local http://127.0.0.1:") && line.end_with?("/example octocat:gh-test-token") }
    install = log.index("bundle install")
    assert config_set, "expected credentials to be stored, got:\n#{log.join("\n")}"
    assert install, "expected bundle install, got:\n#{log.join("\n")}"
    assert_operator config_set, :<, install, "credentials must be stored before bundle install"
    assert_match(%r{\Abundle exec .*/bin/setup\z}, reexec_line(log), "setup must re-exec under bundle exec")
  end

  test "generated setup skips installing when the bundle is satisfied" do
    log = run_generated_setup(bundle_check_status: 0)

    refute_includes log, "bundle install"
    assert_empty log.grep(/\Agh /)
    assert reexec_line(log), "setup must re-exec under bundle exec"
  end

  test "generated setup still installs when gh is not authenticated" do
    log = run_generated_setup(bundle_check_status: 1, gh_auth_status: 1)

    assert_empty log.grep(/\Abundle config set/)
    assert_includes log, "bundle install"
  end

  test "generated setup leaves bundler credentials alone when the source rejects the gh token" do
    log, stderr, status = with_stub_registry("401 Unauthorized") do |source|
      run_generated_setup_raw(bundle_check_status: 1, source: source)
    end

    assert status.success?, stderr
    assert_empty log.grep(/\Abundle config set/)
    assert_includes log, "bundle install"
    assert_match(/gh auth refresh -s read:packages/, stderr)
  end

  test "generated setup leaves bundler credentials alone when the source answers 404" do
    log, stderr = with_stub_registry("404 Not Found") do |source|
      run_generated_setup_raw(bundle_check_status: 1, source: source)
    end

    assert_empty log.grep(/\Abundle config set/)
    assert_includes log, "bundle install"
    assert_match(/Leaving bundler credentials/, stderr)
  end

  test "generated setup leaves bundler credentials alone when the source answers 500" do
    log, stderr = with_stub_registry("500 Internal Server Error") do |source|
      run_generated_setup_raw(bundle_check_status: 1, source: source)
    end

    assert_empty log.grep(/\Abundle config set/)
    assert_includes log, "bundle install"
    assert_match(/Leaving bundler credentials/, stderr)
  end

  test "generated setup leaves bundler credentials alone when the source is unreachable" do
    log = run_generated_setup(bundle_check_status: 1, source: unreachable_registry)

    assert_empty log.grep(/\Abundle config set/)
    assert_includes log, "bundle install"
  end

  test "generated setup re-execs from the app root when invoked elsewhere" do
    log = run_generated_setup(bundle_check_status: 0, from: Dir.tmpdir)

    assert_includes log, "cwd #{destination_root}"
    assert_match(/\Abundle exec .* #{Regexp.escape(File.join(destination_root, "bin/setup"))}\z/, reexec_line(log))
  end

  test "generated setup leaves a missing setup.yml for the bundled pass to report" do
    log = run_generated_setup(bundle_check_status: 1, setup_yml: false)

    assert_empty log.grep(/\Agh /)
    assert_includes log, "bundle install"
  end

  test "generated setup aborts with a credentials hint when bundle install fails" do
    _log, stderr, status = run_generated_setup_raw(bundle_check_status: 1, bundle_install_status: 1)

    refute status.success?
    assert_match(/bundle install failed/, stderr)
    assert_match(/gh auth login/, stderr)
  end

  test "generated setup opens with a do-not-edit notice that points at setup.yml and the gem" do
    run_generator

    header = File.readlines(File.join(destination_root, "bin/setup")).first(20).join
    assert_match(/GENERATED BY DISCHARGER\. DO NOT EDIT/, header)
    assert_match(/config\/setup\.yml/, header)
    assert_match(/lib\/generators\/discharger\/install\/templates\/setup/, header)
    assert_match(/generate discharger:install --setup-only --force/, header)
  end

  test "setup-only regenerates the script without touching setup.yml or the initializer" do
    run_generator
    File.write(File.join(destination_root, "config/setup.yml"), "app_name: Customized\n")
    File.write(File.join(destination_root, "config/initializers/discharger.rb"), "# customized\n")
    File.write(File.join(destination_root, "bin/setup"), "# hand edited\n")

    run_generator ["--setup-only", "--force"]

    assert_file "bin/setup" do |content|
      assert_match(/Discharger::Setup\.run/, content)
    end
    assert_file "config/setup.yml", "app_name: Customized\n"
    assert_file "config/initializers/discharger.rb", "# customized\n"
  end

  test "setup-only on a fresh app creates only the script" do
    run_generator ["--setup-only"]

    assert_file "bin/setup"
    assert_no_file "config/setup.yml"
    assert_no_file "config/initializers/discharger.rb"
  end

  test "creates setup script with custom path" do
    run_generator ["--setup_path=scripts/setup"]

    assert_file "scripts/setup" do |content|
      assert_match(/Discharger::Setup\.run/, content)
    end

    # Check file is executable
    assert File.executable?(File.join(destination_root, "scripts/setup"))
  end

  test "creates sample setup.yml" do
    run_generator

    assert_file "config/setup.yml" do |content|
      assert_match(/app_name:/, content)
      assert_match(/steps:/, content)
      refute_match(/^\s+- pg_tools$/, content)
      assert_match(/structure\.sql/, content)
    end
  end

  test "all generated files are created" do
    run_generator

    assert_file "config/initializers/discharger.rb"
    assert_file "bin/setup"
    assert_file "config/setup.yml"
  end

  private

  # Returns the commands the stub bundle/gh saw, in order; the stub
  # `bundle exec` exits instead of re-running the script.
  def run_generated_setup(**options)
    log, stderr, status = run_generated_setup_raw(**options)
    assert status.success?, "bin/setup failed: #{stderr}\n#{log.join("\n")}"
    log
  end

  def run_generated_setup_raw(bundle_check_status:, bundle_install_status: 0, gh_auth_status: 0, source: "https://rubygems.pkg.github.com/example", from: destination_root, setup_yml: true)
    run_generator
    File.write(File.join(destination_root, "Gemfile"), "source 'https://rubygems.org'\n")
    if setup_yml
      File.write(File.join(destination_root, "config/setup.yml"), <<~YAML)
        app_name: TestApp
        github_packages:
          source: "#{source}"
      YAML
    else
      FileUtils.rm_f(File.join(destination_root, "config/setup.yml"))
    end

    stubs = File.join(destination_root, "stubs")
    log_path = File.join(destination_root, "stub.log")
    write_stub(stubs, "bundle", <<~SH)
      case "$1" in
        check) exit #{bundle_check_status} ;;
        install) exit #{bundle_install_status} ;;
        exec) echo "cwd $PWD" >> "$STUB_LOG"; exit 0 ;;
        *) exit 0 ;;
      esac
    SH
    write_stub(stubs, "gh", <<~SH)
      case "$*" in
        "api user --jq .login") [ #{gh_auth_status} -eq 0 ] && echo octocat; exit #{gh_auth_status} ;;
        "auth token") echo gh-test-token ;;
      esac
      exit 0
    SH

    env = {"PATH" => "#{stubs}:#{ENV["PATH"]}", "STUB_LOG" => log_path}
    _stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, File.join(destination_root, "bin/setup"), chdir: from)
    log = File.exist?(log_path) ? File.readlines(log_path, chomp: true) : []
    [log, stderr, status]
  end

  def reexec_line(log)
    log.find { |line| line.start_with?("bundle exec ") }
  end

  def write_stub(dir, name, body)
    FileUtils.mkdir_p(dir)
    path = File.join(dir, name)
    File.write(path, "#!/bin/sh\necho \"#{name} $*\" >> \"$STUB_LOG\"\n#{body}")
    File.chmod(0o755, path)
  end
end

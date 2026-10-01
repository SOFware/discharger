require "test_helper"
require "setup_runner_test_helper"
require "discharger/setup_check"
require "rake"

class SetupCheckTest < ActiveSupport::TestCase
  include SetupRunnerTestHelper

  TEMPLATE = Discharger::SetupCheck::TEMPLATE

  test "passes when bin/setup is the template verbatim" do
    create_file("bin/setup", File.read(TEMPLATE))
    out = StringIO.new

    assert Discharger::SetupCheck.run(out: out)
    assert_includes out.string, "bin/setup matches the discharger #{Discharger::VERSION} template"
  end

  test "fails and names the regenerate command when bin/setup drifted" do
    lines = File.readlines(TEMPLATE)
    lines[3] = "# edited\n"
    create_file("bin/setup", lines.join)
    out = StringIO.new

    refute Discharger::SetupCheck.run(out: out)
    assert_match(/bin\/setup differs from the discharger .* template at line 4\./, out.string)
    assert_includes out.string, "bin/rails generate discharger:install --setup-only --force"
  end

  test "reports a truncated bin/setup at the line it stops" do
    create_file("bin/setup", File.readlines(TEMPLATE).first(5).join)
    out = StringIO.new

    refute Discharger::SetupCheck.run(out: out)
    assert_match(/at line 6\./, out.string)
  end

  test "fails and names the generate command when bin/setup is missing" do
    out = StringIO.new

    refute Discharger::SetupCheck.run(out: out)
    assert_match(/bin\/setup not found\. Generate it: bin\/rails generate discharger:install --setup-only --force/, out.string)
  end

  test "includes the setup path when the script lives elsewhere" do
    out = StringIO.new

    refute Discharger::SetupCheck.run("scripts/setup", out: out)
    assert_includes out.string, "--setup-only --force --setup_path=scripts/setup"
  end

  test "rake discharger:setup:check aborts on drift and passes on a match" do
    with_fresh_rake do
      load File.expand_path("../lib/tasks/discharger.rake", __dir__)
      task = Rake::Task["discharger:setup:check"]

      create_file("bin/setup", "#!/usr/bin/env ruby\n")
      assert_raises(SystemExit) { capture_io { task.invoke } }

      task.reenable
      create_file("bin/setup", File.read(TEMPLATE))
      capture_io { task.invoke }
    end
  end

  test "the railtie registers the rake task" do
    with_fresh_rake do
      Rails.application.load_tasks

      assert Rake::Task.task_defined?("discharger:setup:check")
    end
  end

  private

  def with_fresh_rake
    original = Rake.application
    Rake.application = Rake::Application.new
    yield
  ensure
    Rake.application = original
  end
end

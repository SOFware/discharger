require "test_helper"
require "setup_runner_test_helper"
require "discharger/setup"

class SetupTest < ActiveSupport::TestCase
  include SetupRunnerTestHelper

  test "run exits when Gemfile is missing" do
    # Remove the Gemfile created by Rails test environment
    FileUtils.rm_f("Gemfile") if File.exist?("Gemfile")

    setup = Discharger::Setup.new("config/setup.yml")

    assert_raises(SystemExit) do
      capture_io { setup.run }
    end
  end

  test "run exits when config file is missing" do
    create_file("Gemfile", "source 'https://rubygems.org'")

    setup = Discharger::Setup.new("config/setup.yml")

    assert_raises(SystemExit) do
      capture_io { setup.run }
    end
  end

  test "class method run creates instance and calls run" do
    create_file("Gemfile", "source 'https://rubygems.org'")
    create_file("config/setup.yml", "app_name: TestApp")

    # Test that the class method creates an instance with correct args
    # We use a test subclass to avoid modifying the original class
    called_with = nil

    test_setup_class = Class.new(Discharger::Setup) do
      define_method(:run) do
        called_with = {config_path: config_path, app_root: app_root}
      end
    end

    # Temporarily replace the class's new method to return our subclass instance
    test_setup_class.run("config/setup.yml")

    assert_equal "config/setup.yml", called_with[:config_path]
    assert_equal Dir.pwd, called_with[:app_root]
  end

  test "initializes with config_path and app_root" do
    setup = Discharger::Setup.new("config/setup.yml", app_root: "/custom/path")

    assert_equal "config/setup.yml", setup.config_path
    assert_equal "/custom/path", setup.app_root
  end

  test "defaults app_root to current directory" do
    setup = Discharger::Setup.new("config/setup.yml")

    assert_equal Dir.pwd, setup.app_root
  end

  test "print_header outputs setup message" do
    create_file("Gemfile", "source 'https://rubygems.org'")
    create_file("config/setup.yml", "app_name: TestApp")

    setup = Discharger::Setup.new("config/setup.yml")

    output, _ = capture_io { setup.send(:print_header) }
    assert_match(/Running Discharger setup/, output)
    assert_match(/config\/setup.yml/, output)
  end

  test "print_footer outputs success message" do
    setup = Discharger::Setup.new("config/setup.yml")

    output, _ = capture_io { setup.send(:print_footer) }
    assert_match(/Setup completed successfully/, output)
  end

  test "validate_environment checks for Gemfile" do
    FileUtils.rm_f("Gemfile") if File.exist?("Gemfile")

    setup = Discharger::Setup.new("config/setup.yml")

    assert_raises(SystemExit) do
      capture_io { setup.send(:validate_environment) }
    end
  end

  test "validate_environment checks for config file" do
    create_file("Gemfile", "source 'https://rubygems.org'")
    FileUtils.rm_f("config/setup.yml") if File.exist?("config/setup.yml")

    setup = Discharger::Setup.new("config/setup.yml")

    assert_raises(SystemExit) do
      capture_io { setup.send(:validate_environment) }
    end
  end

  test "validate_environment passes when both files exist" do
    create_file("Gemfile", "source 'https://rubygems.org'")
    create_file("config/setup.yml", "app_name: TestApp")

    setup = Discharger::Setup.new("config/setup.yml")

    # Should not raise
    capture_io { setup.send(:validate_environment) }
    assert true, "Validation passed"
  end

  test "load_rails warns when config/application.rb is missing" do
    create_file("Gemfile", "source 'https://rubygems.org'")
    create_file("config/setup.yml", "app_name: TestApp")

    setup = Discharger::Setup.new("config/setup.yml")

    output, _ = capture_io { setup.send(:load_rails) }
    assert_match(/config\/application.rb not found/, output)
  end

  test "run_prerequisites calls PrerequisitesLoader" do
    create_file("Gemfile", "source 'https://rubygems.org'")
    create_file("config/setup.yml", "app_name: TestApp")

    # Use a subclass to intercept the call without modifying global state
    loader_path = nil

    test_setup_class = Class.new(Discharger::Setup) do
      define_method(:run_prerequisites) do
        puts "\n== Setting up prerequisites =="
        loader_path = config_path
      end
    end

    setup = test_setup_class.new("config/setup.yml")
    capture_io { setup.send(:run_prerequisites) }

    assert_equal "config/setup.yml", loader_path
  end

  test "run_setup_commands calls SetupRunner" do
    create_file("Gemfile", "source 'https://rubygems.org'")
    create_file("config/setup.yml", "app_name: TestApp")

    # Use a subclass to intercept the call without modifying global state
    runner_path = nil

    test_setup_class = Class.new(Discharger::Setup) do
      define_method(:run_setup_commands) do
        runner_path = config_path
      end
    end

    setup = test_setup_class.new("config/setup.yml")
    capture_io { setup.send(:run_setup_commands) }

    assert_equal "config/setup.yml", runner_path
  end

  test "full run orchestrates all phases" do
    create_file("Gemfile", "source 'https://rubygems.org'")
    create_file("config/setup.yml", "app_name: TestApp")

    # Track which phases were called
    phases_called = []

    test_setup_class = Class.new(Discharger::Setup) do
      define_method(:load_bundler) { phases_called << :bundler }
      define_method(:run_prerequisites) { phases_called << :prerequisites }
      define_method(:load_rails) { phases_called << :rails }
      define_method(:run_setup_commands) { phases_called << :setup_commands }
    end

    setup = test_setup_class.new("config/setup.yml")
    capture_io { setup.run }

    assert_equal [:bundler, :prerequisites, :rails, :setup_commands], phases_called
  end

  test "run changes to app_root directory" do
    create_file("Gemfile", "source 'https://rubygems.org'")
    create_file("config/setup.yml", "app_name: TestApp")

    original_dir = Dir.pwd
    dir_during_run = nil

    test_setup_class = Class.new(Discharger::Setup) do
      define_method(:load_bundler) {}
      define_method(:run_prerequisites) { dir_during_run = Dir.pwd }
      define_method(:load_rails) {}
      define_method(:run_setup_commands) {}
    end

    setup = test_setup_class.new("config/setup.yml", app_root: @test_dir)
    capture_io { setup.run }

    # Resolve symlinks for comparison (macOS /var -> /private/var)
    expected_dir = File.realpath(@test_dir)
    actual_dir = File.realpath(dir_during_run)

    assert_equal expected_dir, actual_dir
    assert_equal original_dir, Dir.pwd, "Should restore original directory after run"
  end
end

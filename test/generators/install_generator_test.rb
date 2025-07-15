require "test_helper"
require "generators/discharger/install/install_generator"
require "rails/generators/test_case"

class InstallGeneratorTest < Rails::Generators::TestCase
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
      assert_match(/Discharger::SetupRunner/, content)
    end
    
    # Check file is executable
    assert File.executable?(File.join(destination_root, "bin/setup"))
  end

  test "creates setup script with custom path" do
    run_generator ["--setup_path=scripts/setup"]
    
    assert_file "scripts/setup" do |content|
      assert_match(/Discharger::SetupRunner/, content)
    end
    
    # Check file is executable
    assert File.executable?(File.join(destination_root, "scripts/setup"))
  end

  test "creates sample setup.yml" do
    run_generator
    
    assert_file "config/setup.yml" do |content|
      assert_match(/app_name:/, content)
      assert_match(/commands:/, content)
    end
  end

  test "all generated files are created" do
    run_generator
    
    assert_file "config/initializers/discharger.rb"
    assert_file "bin/setup"
    assert_file "config/setup.yml"
  end
end
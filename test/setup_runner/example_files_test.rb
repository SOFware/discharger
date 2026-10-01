require "test_helper"
require "setup_runner_test_helper"
require "discharger/setup_runner/example_files"

class ExampleFilesTest < ActiveSupport::TestCase
  include SetupRunnerTestHelper

  test "create_missing copies config examples and .env.example to their counterparts" do
    create_file("config/database.yml.example", "adapter: postgresql")
    create_file("config/environments/development.rb.example", "configure")
    create_file(".env.example", "SECRET=example")

    created = Discharger::SetupRunner::ExampleFiles.create_missing(@test_dir)

    assert_equal [".env", "config/database.yml", "config/environments/development.rb"], created
    assert_file_contains("config/database.yml", "adapter: postgresql")
    assert_file_contains("config/environments/development.rb", "configure")
    assert_file_contains(".env", "SECRET=example")
  end

  test "create_missing leaves existing counterparts alone" do
    create_file("config/database.yml.example", "adapter: postgresql")
    create_file("config/database.yml", "adapter: sqlite3")
    create_file(".env.example", "SECRET=example")
    create_file(".env", "SECRET=mine")

    created = Discharger::SetupRunner::ExampleFiles.create_missing(@test_dir)

    assert_empty created
    assert_file_contains("config/database.yml", "adapter: sqlite3")
    assert_file_contains(".env", "SECRET=mine")
  end

  test "create_missing returns nothing when there are no examples" do
    assert_empty Discharger::SetupRunner::ExampleFiles.create_missing(@test_dir)
  end

  test "create_missing can be limited to config examples" do
    create_file("config/database.yml.example", "adapter: postgresql")
    create_file(".env.example", "SECRET=example")

    created = Discharger::SetupRunner::ExampleFiles.create_missing(@test_dir, [Discharger::SetupRunner::ExampleFiles::CONFIG])

    assert_equal ["config/database.yml"], created
    refute_file_exists(".env")
  end
end

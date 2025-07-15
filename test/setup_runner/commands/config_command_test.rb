require "test_helper"
require "setup_runner_test_helper"
require "discharger/setup_runner/commands/config_command"
require "logger"

class ConfigCommandTest < ActiveSupport::TestCase
  include SetupRunnerTestHelper

  def setup
    super
    @config = {}
    @logger = Logger.new(StringIO.new)
    @command = Discharger::SetupRunner::Commands::ConfigCommand.new(@config, @test_dir, @logger)
  end

  test "description returns correct text" do
    assert_equal "Setup configuration files", @command.description
  end

  test "can_execute? always returns true" do
    assert @command.can_execute?
  end

  test "execute copies database.yml.example to database.yml" do
    create_file("config/database.yml.example", "production:\n  adapter: postgresql")
    
    @command.execute
    
    assert_file_exists("config/database.yml")
    assert_file_contains("config/database.yml", "adapter: postgresql")
  end

  test "execute does not overwrite existing database.yml" do
    create_file("config/database.yml.example", "production:\n  adapter: postgresql")
    create_file("config/database.yml", "development:\n  adapter: sqlite3")
    
    @command.execute
    
    # Should still contain original content
    assert_file_contains("config/database.yml", "adapter: sqlite3")
    refute_file_contains("config/database.yml", "adapter: postgresql")
  end

  test "execute copies Procfile.dev to Procfile" do
    create_file("Procfile.dev", "web: bundle exec rails server")
    
    @command.execute
    
    assert_file_exists("Procfile")
    assert_file_contains("Procfile", "web: bundle exec rails server")
  end

  test "execute does not overwrite existing Procfile" do
    create_file("Procfile.dev", "web: bundle exec rails server")
    create_file("Procfile", "web: bundle exec puma")
    
    @command.execute
    
    # Should still contain original content
    assert_file_contains("Procfile", "web: bundle exec puma")
    refute_file_contains("Procfile", "web: bundle exec rails server")
  end

  test "execute copies all example config files" do
    create_file("config/application.yml.example", "secret_key: example")
    create_file("config/secrets.yml.example", "production:\n  secret_key_base: example")
    
    @command.execute
    
    assert_file_exists("config/application.yml")
    assert_file_contains("config/application.yml", "secret_key: example")
    
    assert_file_exists("config/secrets.yml")
    assert_file_contains("config/secrets.yml", "secret_key_base: example")
  end

  test "execute logs copied files" do
    create_file("config/database.yml.example", "test: data")
    
    io = StringIO.new
    logger = Logger.new(io)
    command = Discharger::SetupRunner::Commands::ConfigCommand.new(@config, @test_dir, logger)
    
    command.execute
    
    log_output = io.string
    assert_match(/Copied config\/database.yml.example to config\/database.yml/, log_output)
  end

  test "execute handles missing config directory gracefully" do
    # No config directory created
    @command.execute
    
    # Should not raise any errors
    refute_file_exists("config/database.yml")
  end

  test "execute handles deeply nested example files" do
    create_file("config/environments/development.rb.example", "Rails.application.configure do\nend")
    
    @command.execute
    
    assert_file_exists("config/environments/development.rb")
    assert_file_contains("config/environments/development.rb", "Rails.application.configure")
  end
end
require "test_helper"
require "setup_runner_test_helper"
require "discharger/setup_runner/configuration"

class ConfigurationTest < ActiveSupport::TestCase
  include SetupRunnerTestHelper

  test "initializes with default values" do
    config = Discharger::SetupRunner::Configuration.new

    assert_equal "Application", config.app_name
    assert_instance_of Discharger::SetupRunner::DatabaseConfig, config.database
    assert_instance_of Discharger::SetupRunner::RedisConfig, config.redis
    assert_equal [], config.services
    assert_equal [], config.steps
    assert_equal [], config.custom_steps
    assert_equal [], config.pre_steps
  end

  test "loads from YAML file" do
    yaml_content = <<~YAML
      app_name: MyTestApp
      database:
        port: 5433
        name: my-db
        version: "15"
        password: secret
      redis:
        port: 6380
        name: my-redis
        version: "7.0"
      services:
        - elasticsearch
        - rabbitmq
      steps:
        - brew
        - bundler
      custom_steps:
        - name: custom_task
          command: echo "custom"
      pre_steps:
        - homebrew
        - postgresql_tools
    YAML

    create_file("test_config.yml", yaml_content)

    config = Discharger::SetupRunner::Configuration.from_file("test_config.yml")

    assert_equal "MyTestApp", config.app_name
    assert_equal 5433, config.database.port
    assert_equal "my-db", config.database.name
    assert_equal "15", config.database.version
    assert_equal "secret", config.database.password
    assert_equal 6380, config.redis.port
    assert_equal "my-redis", config.redis.name
    assert_equal "7.0", config.redis.version
    assert_equal ["elasticsearch", "rabbitmq"], config.services
    assert_equal ["brew", "bundler"], config.steps
    assert_equal [{"name" => "custom_task", "command" => "echo \"custom\""}], config.custom_steps
    assert_equal ["homebrew", "postgresql_tools"], config.pre_steps
  end

  test "loads partial configuration from file" do
    yaml_content = <<~YAML
      app_name: PartialApp
      database:
        port: 5434
    YAML

    create_file("partial_config.yml", yaml_content)

    config = Discharger::SetupRunner::Configuration.from_file("partial_config.yml")

    assert_equal "PartialApp", config.app_name
    assert_equal 5434, config.database.port
    # Check defaults are preserved
    assert_equal "db-app", config.database.name
    assert_equal "14", config.database.version
    assert_equal 6379, config.redis.port
  end

  test "handles empty YAML file" do
    create_file("empty_config.yml", "")

    config = Discharger::SetupRunner::Configuration.from_file("empty_config.yml")

    # Should use all defaults
    assert_equal "Application", config.app_name
    assert_equal 5432, config.database.port
    assert_equal 6379, config.redis.port
  end

  test "raises error for non-existent file" do
    assert_raises(Errno::ENOENT) do
      Discharger::SetupRunner::Configuration.from_file("non_existent.yml")
    end
  end
end

class DatabaseConfigTest < ActiveSupport::TestCase
  test "initializes with default values" do
    config = Discharger::SetupRunner::DatabaseConfig.new

    assert_equal 5432, config.port
    assert_equal "db-app", config.name
    assert_equal "14", config.version
    assert_equal "postgres", config.password
  end

  test "updates from hash" do
    config = Discharger::SetupRunner::DatabaseConfig.new

    config.from_hash({
      "port" => 5433,
      "name" => "custom-db",
      "version" => "15",
      "password" => "custom-pass"
    })

    assert_equal 5433, config.port
    assert_equal "custom-db", config.name
    assert_equal "15", config.version
    assert_equal "custom-pass", config.password
  end

  test "partial update preserves other values" do
    config = Discharger::SetupRunner::DatabaseConfig.new

    config.from_hash({"port" => 5433})

    assert_equal 5433, config.port
    assert_equal "db-app", config.name  # unchanged
    assert_equal "14", config.version    # unchanged
    assert_equal "postgres", config.password  # unchanged
  end
end

class RedisConfigTest < ActiveSupport::TestCase
  test "initializes with default values" do
    config = Discharger::SetupRunner::RedisConfig.new

    assert_equal 6379, config.port
    assert_equal "redis-app", config.name
    assert_equal "latest", config.version
  end

  test "updates from hash" do
    config = Discharger::SetupRunner::RedisConfig.new

    config.from_hash({
      "port" => 6380,
      "name" => "custom-redis",
      "version" => "7.0"
    })

    assert_equal 6380, config.port
    assert_equal "custom-redis", config.name
    assert_equal "7.0", config.version
  end

  test "partial update preserves other values" do
    config = Discharger::SetupRunner::RedisConfig.new

    config.from_hash({"port" => 6380})

    assert_equal 6380, config.port
    assert_equal "redis-app", config.name  # unchanged
    assert_equal "latest", config.version   # unchanged
  end
end

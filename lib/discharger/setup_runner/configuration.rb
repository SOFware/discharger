# frozen_string_literal: true

require "yaml"

module Discharger
  module SetupRunner
    class Configuration
      attr_accessor :app_name, :database, :redis, :services, :steps, :custom_steps

      def initialize
        @app_name = "Application"
        @database = DatabaseConfig.new
        @redis = RedisConfig.new
        @services = []
        @steps = []
        @custom_steps = []
      end

      def self.from_file(path)
        config = new
        yaml = YAML.load_file(path)

        # Handle empty YAML files
        return config if yaml.nil? || yaml == false

        config.app_name = yaml["app_name"] if yaml["app_name"]
        config.database.from_hash(yaml["database"]) if yaml["database"]
        config.redis.from_hash(yaml["redis"]) if yaml["redis"]
        config.services = yaml["services"] || []
        config.steps = yaml["steps"] || []
        config.custom_steps = yaml["custom_steps"] || []

        config
      end
    end

    class DatabaseConfig
      attr_accessor :port, :name, :version, :password

      def initialize
        @port = 5432
        @name = "db-app"
        @version = "14"
        @password = "postgres"
      end

      def from_hash(hash)
        @port = hash["port"] if hash["port"]
        @name = hash["name"] if hash["name"]
        @version = hash["version"] if hash["version"]
        @password = hash["password"] if hash["password"]
      end
    end

    class RedisConfig
      attr_accessor :port, :name, :version

      def initialize
        @port = 6379
        @name = "redis-app"
        @version = "latest"
      end

      def from_hash(hash)
        @port = hash["port"] if hash["port"]
        @name = hash["name"] if hash["name"]
        @version = hash["version"] if hash["version"]
      end
    end
  end
end

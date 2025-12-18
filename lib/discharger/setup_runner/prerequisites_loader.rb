# frozen_string_literal: true

require "yaml"
require_relative "pre_commands/pre_command_registry"

module Discharger
  module SetupRunner
    # PrerequisitesLoader handles setup tasks that must run BEFORE Rails loads.
    # This includes setting environment variables, checking for system dependencies,
    # and installing tools like Homebrew that are needed before bundler/Rails can run.
    #
    # Usage in bin/setup:
    #   require "discharger/prerequisites"
    #   Discharger::SetupRunner::PrerequisitesLoader.run("config/setup.yml")
    #
    class PrerequisitesLoader
      attr_reader :config_path, :config

      def initialize(config_path)
        @config_path = config_path
        @config = load_config
      end

      def self.run(config_path)
        new(config_path).run
      end

      def run
        return false unless config

        set_database_environment
        run_pre_steps
        true
      end

      private

      def load_config
        return nil unless File.exist?(config_path)

        YAML.load_file(config_path)
      rescue => e
        puts "Warning: Could not load #{config_path}: #{e.message}"
        nil
      end

      def set_database_environment
        return unless config["database"]

        db_config = config["database"]
        set_db_port(db_config)
        set_db_name(db_config)
      end

      def set_db_port(db_config)
        if db_config["port"] && !ENV["DB_PORT"]
          ENV["DB_PORT"] = db_config["port"].to_s
          ENV["PGPORT"] = db_config["port"].to_s
          puts "  Setting DB_PORT=#{db_config["port"]} from config/setup.yml"
        elsif ENV["DB_PORT"]
          warn_if_mismatch("DB_PORT", ENV["DB_PORT"], db_config["port"].to_s)
          ENV["PGPORT"] = ENV["DB_PORT"]
        end
      end

      def set_db_name(db_config)
        if db_config["name"] && !ENV["DB_NAME"]
          container_name = db_config["name"].to_s
          db_name = container_name.sub(/^db-/, "")
          ENV["DB_NAME"] = db_name
          puts "  Setting DB_NAME=#{db_name} from config/setup.yml (container: #{container_name})"
        elsif ENV["DB_NAME"]
          container_name = db_config["name"].to_s
          expected_db_name = container_name.sub(/^db-/, "")
          warn_if_mismatch("DB_NAME", ENV["DB_NAME"], expected_db_name)
        end
      end

      def warn_if_mismatch(var_name, env_value, config_value)
        return unless config_value && env_value != config_value
        puts "\n⚠️  WARNING: #{var_name} environment variable (#{env_value}) differs from config/setup.yml (#{config_value})"
        puts "   Using environment variable value. To use config/setup.yml value, unset #{var_name}."
      end

      def run_pre_steps
        pre_steps = config["pre_steps"] || []
        pre_steps.each do |step|
          run_pre_step(step)
        end
      end

      def run_pre_step(step)
        case step
        when String
          run_built_in_pre_step(step)
        when Hash
          run_custom_pre_step(step)
        end
      end

      def run_built_in_pre_step(name)
        command_class = PreCommands::PreCommandRegistry.get(name)
        unless command_class
          puts "  WARNING: Unknown pre-step '#{name}'"
          return
        end

        command = command_class.new(config)
        puts "  #{command.description}..."
        command.execute
      end

      def run_custom_pre_step(step)
        description = step["description"] || step["command"]
        command = step["command"]
        condition = step["condition"]

        if condition && !evaluate_condition(condition)
          puts "  Skipping: #{description} (condition not met)"
          return
        end

        puts "  Running: #{description}"
        system(command)
      end

      def evaluate_condition(condition)
        case condition
        when /^ENV\['(\w+)'\]$/
          !ENV[$1].nil? && !ENV[$1].empty?
        when /^!ENV\['(\w+)'\]$/
          ENV[$1].nil? || ENV[$1].empty?
        when /^File\.exist\?\(['"](.+)['"]\)$/
          File.exist?($1)
        else
          false
        end
      end
    end
  end
end

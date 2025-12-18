# frozen_string_literal: true

require_relative "base_command"
require "open3"

module Discharger
  module SetupRunner
    module Commands
      class DatabaseCommand < BaseCommand
        def execute
          # Drop and recreate development database
          terminate_database_connections
          with_spinner("Dropping and recreating development database") do
            stdout, stderr, status = Open3.capture3(db_env, "bin/rails", "db:drop", "db:create")
            if status.success?
              {success: true}
            else
              error_msg = stderr.empty? ? stdout : stderr
              {success: false, error: "Failed to drop/create database: #{error_msg}"}
            end
          end

          # Load schema and run migrations
          with_spinner("Loading database schema and running migrations") do
            _stdout, stderr, status = Open3.capture3(db_env, "bin/rails", "db:schema:load", "db:migrate")
            if status.success?
              {success: true}
            else
              {success: false, error: "Failed to load schema: #{stderr}"}
            end
          end

          # Seed the database
          seed_env = db_env.merge((config.respond_to?(:seed_env) && config.seed_env) ? {"SEED_DEV_ENV" => "true"} : {})
          with_spinner("Seeding the database") do
            _stdout, stderr, status = Open3.capture3(seed_env, "bin/rails", "db:seed")
            if status.success?
              {success: true}
            else
              {success: false, error: "Failed to seed database: #{stderr}"}
            end
          end

          # Setup test database
          terminate_database_connections("test")
          with_spinner("Setting up test database") do
            test_env = db_env.merge({"RAILS_ENV" => "test"})
            stdout, stderr, status = Open3.capture3(test_env, "bin/rails", "db:drop", "db:create", "db:schema:load")
            if status.success?
              {success: true}
            else
              error_msg = stderr.empty? ? stdout : stderr
              {success: false, error: "Failed to setup test database: #{error_msg}"}
            end
          end

          # Clear logs and temp files
          with_spinner("Clearing logs and temp files") do
            _stdout, _stderr, status = Open3.capture3("bash", "-c", "bin/rails log:clear tmp:clear > /dev/null 2>&1")
            if status.success?
            else
              # Don't fail for log clearing
            end
            {success: true}
          end
        end

        def can_execute?
          File.exist?(File.join(app_root, "bin/rails"))
        end

        def description
          "Setup database"
        end

        private

        def db_env
          # Use Docker PostgreSQL tools if bin/docker-pg directory exists
          docker_pg_path = File.join(app_root, "bin", "docker-pg")
          if File.directory?(docker_pg_path)
            # Prepend docker-pg directory to PATH to use Docker's pg_dump/psql
            {"PATH" => "#{docker_pg_path}:#{ENV["PATH"]}"}
          else
            {}
          end
        end

        def terminate_database_connections(rails_env = nil)
          # Use a Rails runner to terminate connections within the Rails context
          env_vars = rails_env ? {"RAILS_ENV" => rails_env} : {}

          runner_script = <<~RUBY
            begin
              # Only proceed if using PostgreSQL
              if defined?(ActiveRecord::Base) && ActiveRecord::Base.connection.adapter_name =~ /postgresql/i
                ActiveRecord::Base.connection.execute <<-SQL
                  SELECT pg_terminate_backend(pid)
                  FROM pg_stat_activity
                  WHERE datname = current_database() AND pid <> pg_backend_pid();
                SQL
              end
            rescue => e
              # If we can't connect or terminate, that's okay - the database might not exist yet
              # Log error silently in test environment
              puts "Note: Could not terminate existing connections: \#{e.message}" unless ENV['QUIET_SETUP']
            end
          RUBY

          with_spinner("Terminating existing database connections#{" (#{rails_env})" if rails_env}") do
            stdout, stderr, status = Open3.capture3(env_vars, "bin/rails", "runner", runner_script)

            if status.success?
              logger&.debug("Output: #{stdout}") if stdout && !stdout.empty?
            elsif stderr && !stderr.empty?
              logger&.debug("Error: #{stderr}")
              # Don't fail if we can't terminate connections - the database might not exist
            end
            {success: true}
          end
        end
      end
    end
  end
end

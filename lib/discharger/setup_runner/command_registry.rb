# frozen_string_literal: true

require_relative "commands/base_command"
require_relative "commands/asdf_command"
require_relative "commands/brew_command"
require_relative "commands/bundler_command"
require_relative "commands/config_command"
require_relative "commands/database_command"
require_relative "commands/docker_command"
require_relative "commands/env_command"
require_relative "commands/git_command"

module Discharger
  module SetupRunner
    class CommandRegistry
      class << self
        def register(name, command_class)
          commands[name.to_s] = command_class
        end

        def get(name)
          commands[name.to_s]
        end

        def all
          commands.values
        end

        def names
          commands.keys
        end

        def clear
          commands.clear
        end

        private

        def commands
          @commands ||= {}
        end
      end

      # Register built-in commands
      register "asdf", Commands::AsdfCommand
      register "brew", Commands::BrewCommand
      register "bundler", Commands::BundlerCommand
      register "config", Commands::ConfigCommand
      register "database", Commands::DatabaseCommand
      register "docker", Commands::DockerCommand
      register "env", Commands::EnvCommand
      register "git", Commands::GitCommand
    end
  end
end
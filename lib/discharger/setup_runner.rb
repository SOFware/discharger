# frozen_string_literal: true

require_relative "setup_runner/version"
require_relative "setup_runner/configuration"
require_relative "setup_runner/command_registry"
require_relative "setup_runner/command_factory"
require_relative "setup_runner/runner"

module Discharger
  module SetupRunner
    class << self
      def configure
        yield configuration if block_given?
      end

      def configuration
        @configuration ||= Configuration.new
      end

      def run(config_path = nil, logger = nil)
        config = config_path ? Configuration.from_file(config_path) : configuration
        runner = Runner.new(config, Dir.pwd, logger)
        yield runner if block_given?
        runner.run
      end

      # Extension points for adding custom commands
      def register_command(name, command_class)
        CommandRegistry.register(name, command_class)
      end

      def unregister_command(name)
        # Re-register all commands except the one to remove
        all_commands = {}
        CommandRegistry.names.each do |cmd_name|
          unless cmd_name == name.to_s
            all_commands[cmd_name] = CommandRegistry.get(cmd_name)
          end
        end
        CommandRegistry.clear
        all_commands.each do |cmd_name, cmd_class|
          CommandRegistry.register(cmd_name, cmd_class)
        end
      end

      def list_commands
        CommandRegistry.names
      end

      def get_command(name)
        CommandRegistry.get(name)
      end
    end
  end
end

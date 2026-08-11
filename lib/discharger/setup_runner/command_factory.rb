# frozen_string_literal: true

require_relative "command_registry"

module Discharger
  module SetupRunner
    class CommandFactory
      attr_reader :config, :app_root, :logger

      def initialize(config, app_root, logger)
        @config = config
        @app_root = app_root
        @logger = logger
      end

      def create_command(name)
        command_class = CommandRegistry.get(name)
        return nil unless command_class

        command_class.new(config, app_root, logger)
      rescue => e
        logger&.warn "Failed to create command #{name}: #{e.message}"
        nil
      end

      def create_all_commands
        commands = []

        # Create built-in commands from steps
        if config.steps.any?
          # Only reachable here: the else branch schedules every registered
          # command, so github_packages can never be missing from it.
          warn_unscheduled_github_packages
          config.steps.each do |step|
            command = create_command(step)
            commands << command if command
          end
        else
          # If no steps specified, create all registered commands
          CommandRegistry.ordered_names.each do |name|
            command = create_command(name)
            commands << command if command
          end
        end

        # Create custom commands
        if config.respond_to?(:custom_steps) && config.custom_steps.any?
          require_relative "commands/custom_command"
          config.custom_steps.each do |step_config|
            command = Commands::CustomCommand.new(config, app_root, logger, step_config)
            commands << command
          end
        end

        commands
      end

      private

      # A github_packages block with no matching step is inert, and the only
      # symptom is bundler failing against the private source. Say so instead.
      def warn_unscheduled_github_packages
        source = config.github_packages&.source
        return if source.to_s.empty?
        return if config.steps.map(&:to_s).include?("github_packages")

        logger&.warn "github_packages is configured but missing from steps; " \
          "credentials will not be stored and bundler may fail for #{source}"
      end
    end
  end
end

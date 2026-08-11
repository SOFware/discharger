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
        scheduled = []

        # Create built-in and named custom commands from steps
        if config.steps.any?
          named_custom = named_custom_steps
          config.steps.each do |step|
            name = step.to_s
            if CommandRegistry.get(name)
              if named_custom.key?(name)
                logger&.warn "custom step name #{name.inspect} is shadowed by a built-in command; the built-in will run"
              end
              command = create_command(name)
              commands << command if command
            elsif (step_config = named_custom[name])
              scheduled << step_config
              commands << build_custom_command(step_config)
            else
              logger&.warn "unknown step #{name.inspect}; not a built-in or named custom step"
            end
          end
        else
          # If no steps specified, create all registered commands
          CommandRegistry.ordered_names.each do |name|
            command = create_command(name)
            commands << command if command
          end
        end

        # Create the remaining custom commands
        if config.respond_to?(:custom_steps) && config.custom_steps.any?
          config.custom_steps.each do |step_config|
            next if scheduled.any? { |s| s.equal?(step_config) }
            commands << build_custom_command(step_config)
          end
        end

        commands
      end

      private

      # Custom steps with a "name" key can be scheduled by that name in
      # steps:. First entry wins a contested name; later duplicates keep the
      # default run-last behavior.
      def named_custom_steps
        return {} unless config.respond_to?(:custom_steps)

        config.custom_steps.each_with_object({}) do |step_config, named|
          name = step_config["name"].to_s
          next if name.empty?

          if named.key?(name)
            logger&.warn "duplicate custom step name #{name.inspect}; only the first entry can be scheduled"
            next
          end
          named[name] = step_config
        end
      end

      def build_custom_command(step_config)
        require_relative "commands/custom_command"
        Commands::CustomCommand.new(config, app_root, logger, step_config)
      end
    end
  end
end

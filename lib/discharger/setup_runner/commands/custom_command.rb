# frozen_string_literal: true

require_relative "../condition_evaluator"

module Discharger
  module SetupRunner
    module Commands
      class CustomCommand < BaseCommand
        attr_reader :step_config

        def initialize(config, app_root, logger, step_config)
          super(config, app_root, logger)
          @step_config = step_config
        end

        def execute
          command = step_config["command"]
          description = step_config["description"] || command
          condition = step_config["condition"]

          # Check condition if provided using safe evaluator
          if condition && !ConditionEvaluator.evaluate(condition)
            log "Skipping #{description} (condition not met)"
            return
          end

          log "Running: #{description}"
          system!(command)
        end

        def can_execute?
          step_config["command"].present?
        end

        def description
          step_config["description"] || "Custom command: #{step_config["command"]}"
        end
      end
    end
  end
end

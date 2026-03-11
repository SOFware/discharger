# frozen_string_literal: true

require_relative "homebrew_pre_command"
require_relative "postgresql_tools_pre_command"

module Discharger
  module SetupRunner
    module PreCommands
      # Registry for pre-Rails commands.
      # Maps command names (from setup.yml) to command classes.
      class PreCommandRegistry
        BUILT_IN_COMMANDS = {
          "homebrew" => HomebrewPreCommand,
          "postgresql_tools" => PostgresqlToolsPreCommand
        }.freeze

        class << self
          def get(name)
            custom_commands[name.to_s] || BUILT_IN_COMMANDS[name.to_s]
          end

          def register(name, command_class)
            custom_commands[name.to_s] = command_class
          end

          def names
            (BUILT_IN_COMMANDS.keys + custom_commands.keys).uniq
          end

          private

          def custom_commands
            @custom_commands ||= {}
          end
        end
      end
    end
  end
end

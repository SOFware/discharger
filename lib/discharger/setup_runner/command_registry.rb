# frozen_string_literal: true

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
    end
  end
end
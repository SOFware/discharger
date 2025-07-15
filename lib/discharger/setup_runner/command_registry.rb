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

        def load_commands
          # Load base command first
          require_relative "commands/base_command"
          
          # Load all command files from the commands directory
          commands_dir = File.expand_path("commands", __dir__)
          Dir.glob(File.join(commands_dir, "*_command.rb")).each do |file|
            require file
          end
          
          # Auto-register commands based on naming convention
          Commands.constants.each do |const_name|
            next unless const_name.to_s.end_with?("Command")
            
            command_class = Commands.const_get(const_name)
            next unless command_class < Commands::BaseCommand
            next if command_class == Commands::BaseCommand
            
            # Convert class name to command name (e.g., AsdfCommand -> asdf)
            command_name = const_name.to_s.sub(/Command$/, "").gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, "")
            register(command_name, command_class)
          end
        end

        private

        def commands
          @commands ||= {}
        end
      end

      # Load and register all built-in commands
      load_commands
    end
  end
end
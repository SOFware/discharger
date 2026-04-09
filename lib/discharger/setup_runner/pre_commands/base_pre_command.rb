# frozen_string_literal: true

require "rbconfig"

module Discharger
  module SetupRunner
    module PreCommands
      # Base class for pre-Rails commands.
      # These commands run BEFORE bundler/Rails loads, so they must be
      # pure Ruby with no gem dependencies.
      class BasePreCommand
        attr_reader :config

        def initialize(config = {})
          @config = config
        end

        def execute
          raise NotImplementedError, "#{self.class} must implement #execute"
        end

        def description
          self.class.name.split("::").last.gsub(/PreCommand$/, "").gsub(/([a-z])([A-Z])/, '\1 \2')
        end

        protected

        def log(message)
          puts "  #{message}"
        end

        def platform_darwin?
          RbConfig::CONFIG["host_os"] =~ /darwin/
        end

        def platform_linux?
          RbConfig::CONFIG["host_os"] =~ /linux/
        end

        def command_exists?(command)
          system("which #{command} > /dev/null 2>&1")
        end
      end
    end
  end
end

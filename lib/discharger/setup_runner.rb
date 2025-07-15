# frozen_string_literal: true

require "discharger"
require_relative "setup_runner/version"
require_relative "setup_runner/configuration"

module Discharger
  module SetupRunner
    class << self
      def configure
        yield configuration if block_given?
      end

      def configuration
        @configuration ||= Configuration.new
      end

      def run(config_path = nil)
        config = config_path ? Configuration.from_file(config_path) : configuration
        yield config if block_given?
        # Runner will be added in a later commit
        puts "SetupRunner: Configuration loaded for #{config.app_name}"
      end
    end
  end
end
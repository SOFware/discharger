# frozen_string_literal: true

require_relative "base_command"

module Discharger
  module SetupRunner
    module Commands
      class BundlerCommand < BaseCommand
        def execute
          log "Installing dependencies"
          system! "gem install bundler --conservative"
          system_quiet("bundle check") || system!("bundle install")
        end

        def can_execute?
          File.exist?("Gemfile")
        end

        def description
          "Install Ruby dependencies"
        end
      end
    end
  end
end

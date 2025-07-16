# frozen_string_literal: true

require_relative "base_command"

module Discharger
  module SetupRunner
    module Commands
      class BrewCommand < BaseCommand
        def execute
          proceed_with "brew bundle" do
            log "Ensuring brew dependencies"
            system! "brew bundle"
          end
        end

        def can_execute?
          File.exist?("Brewfile")
        end

        def description
          "Install Homebrew dependencies"
        end
      end
    end
  end
end

# frozen_string_literal: true

require_relative "base_command"

module Discharger
  module SetupRunner
    module Commands
      class BrewCommand < BaseCommand
        RETRY_DELAY_SECONDS = 2

        def execute
          proceed_with "brew bundle" do
            log "Ensuring brew dependencies"
            run_brew_bundle
          end
        end

        def can_execute?
          File.exist?("Brewfile")
        end

        def description
          "Install Homebrew dependencies"
        end

        private

        # brew bundle can fail transiently (e.g. Homebrew lock contention from a
        # concurrent `brew` invocation) unrelated to the app's actual dependencies.
        # Retry once before treating it as a real setup failure.
        def run_brew_bundle
          system! "brew bundle"
        rescue => e
          log "brew bundle failed, retrying once: #{e.message}"
          sleep retry_delay
          system! "brew bundle"
        end

        def retry_delay
          RETRY_DELAY_SECONDS
        end
      end
    end
  end
end

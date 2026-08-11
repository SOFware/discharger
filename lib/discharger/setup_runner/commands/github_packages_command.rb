# frozen_string_literal: true

require_relative "base_command"

module Discharger
  module SetupRunner
    module Commands
      # Stores bundler credentials for a private GitHub Packages gem source
      # using the GitHub CLI, so Gemfiles don't need embedded tokens.
      # Credentials are written to the app's .bundle/config — keep .bundle
      # gitignored. Run this step before "bundler" in setup.yml.
      class GithubPackagesCommand < BaseCommand
        # A configured source with nothing scheduled to store its credentials
        # is inert, and the only symptom is bundler failing against the
        # private source. The Runner surfaces this before executing commands.
        # Guarded for duck-typed configs passed to the public Runner API, and
        # quiet when a custom step's command references the source (assumed
        # to handle credentials itself).
        def self.unscheduled_warning(config)
          return unless config.respond_to?(:github_packages)

          source = config.github_packages&.source
          return if source.to_s.empty?
          if config.respond_to?(:custom_steps) &&
              config.custom_steps.any? { |step| step["command"].to_s.include?(source) }
            return
          end

          "github_packages is configured but missing from steps; " \
            "credentials will not be stored and bundler may fail for #{source}"
        end

        def execute
          unless gh_installed?
            log "GitHub CLI (gh) not found; skipping. Install gh and rerun setup or `bundle install` may fail for #{source}"
            return
          end

          unless authenticated? || login
            log "Not logged in to GitHub; skipping. Run `gh auth login` and rerun setup."
            return
          end

          username = gh("api", "user", "--jq", ".login")
          token = gh("auth", "token")
          if username.to_s.empty? || token.to_s.empty?
            log "Could not read GitHub credentials from gh; skipping."
            return
          end

          store_bundler_credentials(username, token)
          if credentials_valid?(username, token)
            log "Configured bundler credentials for #{source}"
          else
            log "#{source} rejected the stored credentials. Your gh token may lack " \
              "the read:packages scope — run `gh auth refresh -s read:packages` and rerun setup."
          end
        end

        def can_execute?
          !source.to_s.empty?
        end

        def description
          "Configure GitHub Packages credentials"
        end

        protected

        def source
          config.github_packages&.source
        end

        def gh_installed?
          system_quiet("which gh")
        end

        def authenticated?
          system_quiet("gh auth status")
        end

        def login
          return false unless $stdin.tty?
          log "Logging in to GitHub..."
          system("gh", "auth", "login")
          authenticated?
        end

        def gh(*args)
          require "open3"
          stdout, _stderr, status = Open3.capture3("gh", *args)
          status.success? ? stdout.chomp : nil
        end

        # Runs bundle config directly instead of through system! so the
        # token never reaches the spinner display or the debug log.
        def store_bundler_credentials(username, token)
          require "open3"
          _stdout, stderr, status = Open3.capture3(
            "bundle", "config", "set", "--local", source, "#{username}:#{token}"
          )
          raise "bundle config set --local #{source} failed: #{stderr}" unless status.success?
        end

        # Probes the source's compact index with the stored credentials.
        # Only a definite 401/403 counts as invalid — network trouble must
        # not fail setup over an unverifiable token.
        def credentials_valid?(username, token)
          require "net/http"
          require "uri"
          uri = URI.join("#{source.chomp("/")}/", "versions")
          response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
            open_timeout: 5, read_timeout: 10) do |http|
            request = Net::HTTP::Get.new(uri)
            request.basic_auth(username, token)
            http.request(request)
          end
          !%w[401 403].include?(response.code)
        rescue => e
          logger&.debug("Could not verify GitHub Packages credentials: #{e.message}")
          true
        end
      end
    end
  end
end

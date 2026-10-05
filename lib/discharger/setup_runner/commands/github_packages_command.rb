# frozen_string_literal: true

require_relative "base_command"

module Discharger
  module SetupRunner
    module Commands
      # Checks the gh token against the GitHub Packages source; bin/setup
      # stored the credentials. The template's first pass mirrors this.
      class GithubPackagesCommand < BaseCommand
        GH_TIMEOUT_SECONDS = 15

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

          if source_accepts_token?(username, token)
            log "#{source} accepts the gh token"
          else
            log "#{source} did not accept the gh token. It may lack the read:packages scope — " \
              "run `gh auth refresh -s read:packages` and rerun setup."
          end
        end

        def can_execute?
          !source.to_s.empty?
        end

        def description
          "Check GitHub Packages credentials"
        end

        protected

        def source
          config.github_packages&.source
        end

        def gh_installed?
          system_quiet("which gh")
        end

        def authenticated?
          !gh("auth", "status").nil?
        end

        def login
          return false unless $stdin.tty?
          log "Logging in to GitHub..."
          system("gh", "auth", "login")
          authenticated?
        end

        def gh(*args)
          require "open3"
          Open3.popen2("gh", *args, err: File::NULL) do |stdin, stdout, wait|
            stdin.close
            out = Thread.new { stdout.read }
            if wait.join(gh_timeout)
              out.value.chomp if wait.value.success?
            else
              Process.kill("KILL", wait.pid)
              out.kill
              log "gh #{args.join(" ")} did not answer within #{gh_timeout.to_i}s."
              nil
            end
          end
        rescue Errno::ENOENT
          nil
        end

        def gh_timeout
          Float(ENV.fetch("DISCHARGER_GH_TIMEOUT") { config.github_packages&.gh_timeout || GH_TIMEOUT_SECONDS })
        end

        def source_accepts_token?(username, token)
          require "net/http"
          require "uri"
          uri = URI.join("#{source.chomp("/")}/", "versions")
          response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
            open_timeout: 5, read_timeout: 10) do |http|
            request = Net::HTTP::Get.new(uri)
            request.basic_auth(username, token)
            http.request(request)
          end
          response.is_a?(Net::HTTPSuccess)
        rescue => e
          logger&.debug("Could not verify GitHub Packages credentials: #{e.message}")
          false
        end
      end
    end
  end
end

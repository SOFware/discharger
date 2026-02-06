require "rake/tasklib"
require "reissue/rake"
require "rainbow/refinement"
require "open3"
using Rainbow

module Discharger
  class Task < Rake::TaskLib
    def self.create(name = :release, tasker: Rake::Task, &block)
      task = new(name, tasker:)
      task.instance_eval(&block) if block
      Reissue::Task.create do |reissue|
        reissue.version_file = task.version_file
        reissue.version_limit = task.version_limit
        reissue.version_redo_proc = task.version_redo_proc
        reissue.changelog_file = task.changelog_file
        reissue.updated_paths = task.updated_paths
        reissue.commit = task.commit
        reissue.commit_finalize = task.commit_finalize
        if task.fragment_directory
          warn "fragment_directory is deprecated, use fragment instead"
          task.fragment = task.fragment_directory
        end
        reissue.fragment = task.fragment
        reissue.clear_fragments = task.clear_fragments
        reissue.tag_pattern = task.tag_pattern
      end
      task.define
      task
    end

    attr_accessor :name

    attr_accessor :description

    attr_accessor :working_branch
    attr_accessor :staging_branch
    attr_accessor :production_branch
    attr_accessor :auto_deploy_staging

    attr_accessor :release_message_channel
    attr_accessor :version_constant

    attr_accessor :chat_token
    attr_accessor :app_name
    attr_accessor :commit_identifier
    attr_accessor :pull_request_url
    attr_accessor :fragment_directory
    attr_accessor :fragment
    attr_accessor :clear_fragments

    attr_reader :last_message_ts

    # Reissue settings
    attr_accessor(
      *Reissue::Task.instance_methods(false).reject { |method|
        method.to_s.match?(/[?=]\z/) || method_defined?(method)
      }
    )

    def initialize(name = :release, tasker: Rake::Task)
      @name = name
      @tasker = tasker
      @working_branch = "develop"
      @staging_branch = "stage"
      @production_branch = "main"
      @description = "Release the current version to #{staging_branch}"
      @clear_fragments = true
      @auto_deploy_staging = false
    end
    private attr_reader :tasker

    # Run a multiple system commands and return true if all commands succeed
    # If any command fails, the method will return false and stop executing
    # any further commands.
    #
    # Provide a block to evaluate the output of the command and return true
    # if the command was successful. If the block returns false, the method
    # will return false and stop executing any further commands.
    #
    # @param *steps [Array<Array<String>>] an array of commands to run
    # @param block [Proc] a block to evaluate the output of the command
    # @return [Boolean] true if all commands succeed, false otherwise
    #
    # @example
    #   syscall(
    #     ["echo Hello, World!"],
    #     ["ls -l"]
    #   )
    def syscall(*steps, output: $stdout, error: $stderr)
      success = false
      stdout, stderr, status = nil
      steps.each do |cmd|
        puts cmd.join(" ").bg(:green).black
        stdout, stderr, status = Open3.capture3(*cmd)
        if status.success?
          output.puts stdout
          success = true
        else
          error.puts stderr
          success = false
          exit(status.exitstatus)
        end
      end
      if block_given?
        success = !!yield(stdout, stderr, status)
        # If the error reports that a rule was bypassed, consider the command successful
        # because we are bypassing the rule intentionally when merging the release branch
        # to the production branch.
        success = true if stderr.match?(/bypassed rule violations/i)
        abort(stderr) unless success
      end
      success
    end

    def sysecho(message, output: $stdout)
      output.puts message
      true
    end

    # Abort if staging branch has different VERSION than working branch
    def validate_version_match!(staging, working, output: $stdout)
      staging_v = git_show_version(staging)
      working_v = git_show_version(working)

      return sysecho("✓ Versions match (#{working_v})".bg(:green).black, output:) if staging_v == working_v

      abort <<~ERROR.bg(:red).white
        VERSION mismatch: #{staging}=#{staging_v || "not found"}, #{working}=#{working_v || "not found"}

        Run: rake #{name}:stage
        Then retry: rake #{name}
      ERROR
    end

    # Abort if HEAD is not the commit that last touched the version file
    def validate_release_commit!(branch, output: $stdout)
      head_sha = git_local_sha(branch)
      release_sha = git_version_file_commit(branch)

      if head_sha.nil? || release_sha.nil?
        abort <<~ERROR.bg(:red).white
          Could not determine release commit.

          HEAD:           #{head_sha || "not found"}
          Release commit: #{release_sha || "not found"}

          Ensure #{branch} exists and #{version_file} has been modified.
        ERROR
      end

      return sysecho("✓ HEAD is the release commit (#{head_sha[0, 8]})".bg(:green).black, output:) if head_sha == release_sha

      abort <<~ERROR.bg(:red).white
        HEAD is not the release commit!

        HEAD:           #{head_sha[0, 8]}
        Release commit: #{release_sha[0, 8]} (last commit to touch #{version_file})

        Something was merged after the release PR. Verify the branch contents and retry.
      ERROR
    end

    def git_show_version(branch)
      content, _, status = Open3.capture3("git", "show", "origin/#{branch}:#{version_file}")
      return nil unless status.success?
      content[/VERSION\s*=\s*["']([^"']+)["']/, 1]
    end

    def git_local_sha(branch)
      stdout, _, status = Open3.capture3("git", "rev-parse", branch)
      return nil unless status.success?
      stdout.strip
    end

    def git_version_file_commit(branch)
      stdout, _, status = Open3.capture3("git", "log", branch, "-1", "--format=%H", "--", version_file)
      return nil unless status.success?
      stdout.strip
    end

    def define
      require "slack-ruby-client"
      Slack.configure do |config|
        config.token = chat_token
      end

      desc <<~DESC
        ---------- STEP 3 ----------
        Release the current version to production

        This task rebases the production branch on the staging branch and tags the
        current version. The production branch and the tag will be pushed to the
        remote repository.

        After the release is complete, a new branch will be created to bump the
        version for the next release.
      DESC
      task "#{name}": [:environment] do
        current_version = Object.const_get(version_constant)

        # When auto_deploy_staging is enabled, release directly from working_branch
        # instead of staging_branch (for CI/CD pipelines that auto-deploy staging)
        release_source = auto_deploy_staging ? working_branch : staging_branch

        sysecho <<~MSG
          Releasing version #{current_version} to production.

          This will tag the current version and push it to the production branch.
          Release source: #{release_source}
        MSG
        sysecho "Are you ready to continue? (Press Enter to continue, Type 'x' and Enter to exit)".bg(:yellow).black
        input = $stdin.gets
        exit if input.chomp.match?(/^x/i)

        # Fetch first, then validate what we fetched
        syscall(
          ["git checkout #{working_branch}"],
          ["git branch -D #{staging_branch} 2>/dev/null || true"],
          ["git branch -D #{production_branch} 2>/dev/null || true"],
          ["git fetch origin #{release_source}:#{release_source} #{production_branch}:#{production_branch}"]
        )

        if auto_deploy_staging
          # Ensure HEAD is the release commit (the commit that touched the version file)
          validate_release_commit!(release_source)
        else
          # Standard mode: validate staging branch has same VERSION as working branch
          validate_version_match!(staging_branch, working_branch)
        end

        continue = syscall(
          ["git checkout #{production_branch}"],
          ["git reset --hard #{release_source}"],
          ["git tag -a v#{current_version} -m 'Release #{current_version}'"],
          ["git push origin #{production_branch}:#{production_branch} v#{current_version}:v#{current_version}"],
          ["git push origin v#{current_version}"]
        ) do
          tasker["#{name}:slack"].invoke("Released #{app_name} #{current_version} (#{commit_identifier.call}) to production.", release_message_channel, ":chipmunk:")
          if last_message_ts.present?
            text = File.read(Rails.root.join(changelog_file))
            tasker["#{name}:slack"].reenable
            tasker["#{name}:slack"].invoke(text, release_message_channel, ":log:", last_message_ts)
          end
          syscall ["git checkout #{working_branch}"]
        end

        abort "Release failed." unless continue

        sysecho <<~MSG
          Version #{current_version} released to production.

          Preparing to bump the version for the next release.

        MSG
        tasker["reissue"].invoke

        new_version_branch = `git rev-parse --abbrev-ref HEAD`.strip
        new_version = new_version_branch.split("/").last
        params = {expand: 1, title: "Bump version to #{new_version}"}
        pr_url = "#{pull_request_url}/compare/#{working_branch}...#{new_version_branch}?#{params.to_query}"

        syscall(["git push origin #{new_version_branch} --force"]) do
          sysecho <<~MSG
            Branch #{new_version_branch} created.

            Open a PR to #{working_branch} to mark the version and update the chaneglog
            for the next release.

            Opening PR: #{pr_url}
          MSG
        end.then do |success|
          syscall ["open", pr_url] if success
        end
      end

      namespace name do
        desc "Echo the configuration settings."
        task :config do
          sysecho "-- Discharger Configuration --".bg(:green).black
          sysecho "SHA: #{commit_identifier.call}".bg(:red).black
          instance_variables.sort.each do |var|
            value = instance_variable_get(var)
            value = value.call if value.is_a?(Proc) && value.arity.zero?
            sysecho "#{var.to_s.sub("@", "").ljust(24)}: #{value}".bg(:yellow).black
          end
          sysecho "----------------------------------".bg(:green).black
        end

        desc description
        task build: :environment do
          if auto_deploy_staging
            sysecho "Note: auto_deploy_staging is enabled. Staging deploys automatically from #{working_branch}.".bg(:yellow).black
          end

          # Allow overriding the working branch via environment variable
          build_branch = ENV["DISCHARGER_BUILD_BRANCH"] || working_branch

          syscall(
            ["git fetch origin #{build_branch}"],
            ["git checkout #{build_branch}"],
            ["git reset --hard origin/#{build_branch}"],
            ["git branch -D #{staging_branch} 2>/dev/null || true"],
            ["git checkout -b #{staging_branch}"],
            ["git push origin #{staging_branch} --force"]
          ) do
            current_version = Object.const_get(version_constant)
            tasker["#{name}:slack"].invoke("Building #{app_name} #{current_version} (#{commit_identifier.call}) on #{staging_branch}.", release_message_channel)
            syscall ["git checkout #{build_branch}"]
          end
        end

        desc "Send a message to Slack."
        task :slack, [:text, :channel, :emoji, :ts] => :environment do |_, args|
          args.with_defaults(
            channel: release_message_channel,
            emoji: nil
          )
          client = Slack::Web::Client.new
          options = args.to_h
          options[:icon_emoji] = options.delete(:emoji) if options[:emoji]
          options[:thread_ts] = options.delete(:ts) if options[:ts]

          sysecho "Sending message to Slack:".bg(:green).black + " #{args[:text]}"
          result = client.chat_postMessage(**options)
          instance_variable_set(:@last_message_ts, result["ts"])
          sysecho %(Message sent: #{result["ts"]})
        end

        desc <<~DESC
          ---------- STEP 1 ----------
          Prepare the current version for release to production (#{production_branch})

          This task will create a new branch to prepare the release. The CHANGELOG
          will be updated and the version will be bumped. The branch will be pushed
          to the remote repository.

          After the branch is created, open a PR to #{working_branch} to finalize
          the release.
        DESC
        task prepare: [:environment] do
          current_version = Object.const_get(version_constant)
          finish_branch = "bump/finish-#{current_version.tr(".", "-")}"

          syscall(
            ["git fetch origin #{working_branch}"],
            ["git checkout #{working_branch}"],
            ["git checkout -b #{finish_branch}"]
          )
          sysecho <<~MSG
            Branch #{finish_branch} created.

            Check the contents of the CHANGELOG and ensure that the text is correct.

            If you need to make changes, edit the CHANGELOG and save the file.
            Then return here to continue with this commit.
          MSG
          sysecho "Are you ready to continue? (Press Enter to continue, Type 'x' and Enter to exit)".bg(:yellow).black
          input = $stdin.gets
          exit if input.chomp.match?(/^x/i)

          tasker["reissue:finalize"].invoke

          params = {
            expand: 1,
            title: "Finish version #{current_version}",
            body: <<~BODY
              Completing development for #{current_version}.
            BODY
          }

          pr_url = "#{pull_request_url}/compare/#{finish_branch}?#{params.to_query}"

          next_step = auto_deploy_staging ? "rake #{name}" : "rake #{name}:stage"
          next_step_desc = auto_deploy_staging ? "release to production" : "stage the release branch"

          continue = syscall ["git push origin #{finish_branch} --force"] do
            sysecho <<~MSG
              Branch #{finish_branch} created.
              Open a PR to #{working_branch} to finalize the release.

              #{pr_url}

              Once the PR is merged, pull down #{working_branch} and run
                '#{next_step}'
              to #{next_step_desc}.
            MSG
          end
          if continue
            syscall ["git checkout #{working_branch}"],
              ["open", pr_url]
          end
        end

        desc <<~DESC
          ---------- STEP 2 ----------
          Stage the release branch

          This task will update Stage, open a PR, and instruct you on the next steps.

          NOTE: If you just want to update the stage environment but aren't ready to release, run:

              bin/rails #{name}:build
        DESC
        task stage: [:environment] do
          if auto_deploy_staging
            sysecho <<~MSG.bg(:yellow).black
              Note: auto_deploy_staging is enabled.
              Staging is handled automatically when code is pushed to #{working_branch}.
              To release to production, run: 'rake #{name}'
            MSG
            next
          end

          tasker["build"].invoke
          current_version = Object.const_get(version_constant)

          params = {
            expand: 1,
            title: "Stage to Main",
            body: <<~BODY
              Deploy #{current_version} to production.
            BODY
          }

          pr_url = "#{pull_request_url}/compare/#{production_branch}...#{staging_branch}?#{params.to_query}"

          sysecho <<~MSG
            Branch #{staging_branch} updated.
            Open a PR to #{production_branch} to release the version.

            Opening PR: #{pr_url}

            Once the PR is **approved**, run 'rake release' to release the version.
          MSG
          syscall ["open", pr_url]
        end
      end
    end
  end
end

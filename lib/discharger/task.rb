require "rake/tasklib"
require "reissue/rake"
require "rainbow/refinement"
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
      end
      task.define
      task
    end

    attr_accessor :name

    attr_accessor :description

    attr_accessor :working_branch
    attr_accessor :staging_branch
    attr_accessor :production_branch

    attr_accessor :release_message_channel
    attr_accessor :version_constant

    attr_accessor :chat_token
    attr_accessor :app_name
    attr_accessor :commit_identifier
    attr_accessor :pull_request_url

    attr_reader :last_message_ts

    # Reissue settings
    attr_accessor(
      *Reissue::Task.instance_methods(false).reject { |method|
        method.to_s.match?(/[\?=]\z/) || method_defined?(method)
      }
    )

    def initialize(name = :release, tasker: Rake::Task)
      @name = name
      @tasker = tasker
      @working_branch = "develop"
      @staging_branch = "stage"
      @production_branch = "main"
      @description = "Release the current version to #{staging_branch}"
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

    # Echo a message to the console
    #
    # @param message [String] the message to echo
    # return [TrueClass]
    def sysecho(message, output: $stdout)
      output.puts message
      true
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
        sysecho <<~MSG
          Releasing version #{current_version} to production.

          This will tag the current version and push it to the production branch.
        MSG
        sysecho "Are you ready to continue? (Press Enter to continue, Type 'x' and Enter to exit)".bg(:yellow).black
        input = $stdin.gets
        exit if input.chomp.match?(/^x/i)

        continue = syscall(
          ["git checkout #{working_branch}"],
          ["git branch -D #{staging_branch} 2>/dev/null || true"],
          ["git branch -D #{production_branch} 2>/dev/null || true"],
          ["git fetch origin #{staging_branch}:#{staging_branch} #{production_branch}:#{production_branch}"],
          ["git checkout #{production_branch}"],
          ["git reset --hard #{staging_branch}"],
          ["git tag -a v#{current_version} -m 'Release #{current_version}'"],
          ["git push origin #{production_branch}:#{production_branch} v#{current_version}:v#{current_version}"],
          ["git push origin v#{current_version}"]
        ) do
          tasker["#{name}:slack"].invoke("Released #{app_name} #{current_version} to production.", release_message_channel, ":chipmunk:")
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
        new_version = Object.const_get(version_constant)
        new_version_branch = "bump/begin-#{new_version.tr(".", "-")}"
        continue = syscall(["git checkout -b #{new_version_branch}"])

        abort "Bump failed." unless continue

        pr_url = "#{pull_request_url}/compare/#{working_branch}...#{new_version_branch}?expand=1&title=Begin%20#{current_version}"

        syscall(["git push origin #{new_version_branch} --force"]) do
          sysecho <<~MSG
            Branch #{new_version_branch} created.

            Open a PR to #{working_branch} to mark the version and update the chaneglog
            for the next release.

            Opening PR: #{pr_url}
          MSG
        end.then do |success|
          syscall ["open #{pr_url}"] if success
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
          syscall(
            ["git fetch origin #{working_branch}"],
            ["git checkout #{working_branch}"],
            ["git branch -D #{staging_branch} 2>/dev/null || true"],
            ["git checkout -b #{staging_branch}"],
            ["git push origin #{staging_branch} --force"]
          ) do
            tasker["#{name}:slack"].invoke("Building #{app_name} #{commit_identifier.call} on #{staging_branch}.", release_message_channel)
            syscall ["git checkout #{working_branch}"]
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

          continue = syscall ["git push origin #{finish_branch} --force"] do
            sysecho <<~MSG
              Branch #{finish_branch} created.
              Open a PR to #{working_branch} to finalize the release.

              #{pr_url}

              Once the PR is merged, pull down #{working_branch} and run
                'rake #{name}:stage'
              to stage the release branch.
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
          tasker["build"].invoke
          current_version = Object.const_get(version_constant)

          params = {
            expand: 1,
            title: "Release #{current_version} to production",
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
          syscall ["open #{pr_url}"]
        end
      end
    end
  end
end

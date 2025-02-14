require "rainbow/refinement"

using Rainbow

module Discharger
  module Steps
    class Release
      include Rake::DSL

      def initialize(task)
        @task = task
        @tasker = task.tasker
      end

      def release_to_production
        push_to_production
        establish_config
        build_environment
        send_message_to_slack
      end

      private

      def push_to_production
        @task.desc <<~DESC
          ---------- STEP 3 ----------
          Release the current version to production

          This task rebases the production branch on the staging branch and tags the
          current version. The production branch and the tag will be pushed to the
          remote repository.

          After the release is complete, a new branch will be created to bump the
          version for the next release.
        DESC
        @task.task @task.name => [:environment] do
          current_version = Object.const_get(@task.version_constant)
          @task.sysecho <<~MSG
            Releasing version #{current_version} to production.

            This will tag the current version and push it to the production branch.
          MSG
          @task.sysecho "Are you ready to continue? (Press Enter to continue, Type 'x' and Enter to exit)".bg(:yellow).black
          input = $stdin.gets
          exit if input.chomp.match?(/^x/i)

          continue = @task.syscall(
            ["git checkout #{@task.working_branch}"],
            ["git branch -D #{@task.staging_branch} 2>/dev/null || true"],
            ["git branch -D #{@task.production_branch} 2>/dev/null || true"],
            ["git fetch origin #{@task.staging_branch}:#{@task.staging_branch} #{@task.production_branch}:#{@task.production_branch}"],
            ["git checkout #{@task.production_branch}"],
            ["git reset --hard #{@task.staging_branch}"],
            ["git tag -a v#{current_version} -m 'Release #{current_version}'"],
            ["git push origin #{@task.production_branch}:#{@task.production_branch} v#{current_version}:v#{current_version}"],
            ["git push origin v#{current_version}"]
          ) do
            @tasker["#{@task.name}:slack"].invoke(
              "Released #{@task.app_name} #{current_version} to production.",
              @task.release_message_channel,
              ":chipmunk:"
            )
            if @task.last_message_ts.present?
              text = File.read(Rails.root.join(@task.changelog_file))
              @tasker["#{@task.name}:slack"].reenable
              @tasker["#{@task.name}:slack"].invoke(
                text,
                @task.release_message_channel,
                ":log:",
                @task.last_message_ts
              )
            end
            @task.syscall ["git checkout #{@task.working_branch}"]
          end

          abort "Release failed." unless continue

          @task.sysecho <<~MSG
            Version #{current_version} released to production.

            Preparing to bump the version for the next release.

          MSG

          @tasker["reissue"].invoke
          new_version = Object.const_get(@task.version_constant)
          new_version_branch = "bump/begin-#{new_version.tr(".", "-")}"
          continue = @task.syscall(["git checkout -b #{new_version_branch}"])

          abort "Bump failed." unless continue

          pr_url = "#{@task.pull_request_url}/compare/#{@task.working_branch}...#{new_version_branch}?expand=1&title=Begin%20#{current_version}"

          @task.syscall(["git push origin #{new_version_branch} --force"]) do
            @task.sysecho <<~MSG
              Branch #{new_version_branch} created.

              Open a PR to #{@task.working_branch} to mark the version and update the chaneglog
              for the next release.

              Opening PR: #{pr_url}
            MSG
          end.then do |success|
            @task.syscall ["open #{pr_url}"] if success
          end
        end
      end

      def establish_config
        @task.desc "Echo the configuration settings."
        @task.task "#{@task.name}:config" do
          @task.sysecho "-- Discharger Configuration --".bg(:green).black
          @task.sysecho "SHA: #{@task.commit_identifier.call}".bg(:red).black
          @task.instance_variables.sort.each do |var|
            value = @task.instance_variable_get(var)
            value = value.call if value.is_a?(Proc) && value.arity.zero?
            @task.sysecho "#{var.to_s.sub("@", "").ljust(24)}: #{value}".bg(:yellow).black
          end
          @task.sysecho "----------------------------------".bg(:green).black
        end
      end

      def build_environment
        @task.desc @task.description
        @task.task "#{@task.name}:build" => :environment do
          @task.syscall(
            ["git fetch origin #{@task.working_branch}"],
            ["git checkout #{@task.working_branch}"],
            ["git branch -D #{@task.staging_branch} 2>/dev/null || true"],
            ["git checkout -b #{@task.staging_branch}"],
            ["git push origin #{@task.staging_branch} --force"]
          ) do
            @tasker["#{@task.name}:slack"].invoke(
              "Building #{@task.app_name} #{@task.commit_identifier.call} on #{@task.staging_branch}.",
              @task.release_message_channel
            )
            @task.syscall ["git checkout #{@task.working_branch}"]
          end
        end
      end

      def send_message_to_slack
        @task.desc "Send a message to Slack."
        @task.task "#{@task.name}:slack", [:text, :channel, :emoji, :ts] => :environment do |_, args|
          args.with_defaults(
            channel: @task.release_message_channel,
            emoji: nil
          )
          client = Slack::Web::Client.new
          options = args.to_h
          options[:icon_emoji] = options.delete(:emoji) if options[:emoji]
          options[:thread_ts] = options.delete(:ts) if options[:ts]

          @task.sysecho "Sending message to Slack:".bg(:green).black + " #{args[:text]}"
          result = client.chat_postMessage(**options)
          @task.instance_variable_set(:@last_message_ts, result["ts"])
          @task.sysecho %(Message sent: #{result["ts"]})
        end
      end
    end
  end
end

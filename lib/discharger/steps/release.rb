require "rainbow/refinement"

using Rainbow

module Release
  def release_to_production
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
    end
  end
end

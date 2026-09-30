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
        reissue.runbook_file = task.runbook_file
        reissue.retain_changelogs = task.retain_changelogs
      end
      task.define
      task
    end

    attr_accessor :name

    attr_accessor :working_branch

    attr_accessor :release_message_channel
    attr_accessor :version_constant

    attr_accessor :chat_token
    attr_accessor :app_name
    attr_accessor :commit_identifier
    attr_accessor :pull_request_url
    attr_accessor :pr_label
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

    REMOVED_SETTINGS = %i[staging_branch production_branch auto_deploy_staging description].freeze

    REMOVED_SETTINGS.each do |setting|
      define_method(:"#{setting}=") do |_value|
        warn "#{setting} was removed in discharger 0.5.0 and does nothing. Delete it from the Rakefile."
      end
    end

    def initialize(name = :release, tasker: Rake::Task)
      @name = name
      @tasker = tasker
      @working_branch = "main"
      @clear_fragments = true
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
        abort(stderr) unless success
      end
      success
    end

    def sysecho(message, output: $stdout)
      output.puts message
      true
    end

    # The newest commit that changed the current version's dated changelog section
    def find_release_commit!(branch, output: $stdout)
      version = Object.const_get(version_constant)
      section = /^## \[#{Regexp.escape(version)}\] - \d{4}-\d{2}-\d{2}.*?(?=^## \[|\z)/m
      sha = git_file_commits(branch, changelog_file).find do |candidate_sha|
        released = git_show_at_commit(candidate_sha, changelog_file)&.[](section)
        released && released != git_show_at_commit("#{candidate_sha}^", changelog_file)&.[](section)
      end

      if sha.nil?
        abort <<~ERROR.bg(:red).white
          Could not locate a release commit.
          Ensure #{branch} exists and #{changelog_file} has been finalized for #{version}.
        ERROR
      end

      sysecho("✓ Release commit: #{sha[0, 8]}".bg(:green).black, output:)
      sha
    end

    def git_file_commits(branch, path)
      stdout, _, status = Open3.capture3("git", "log", "--no-merges", branch, "--format=%H", "--", path)
      return [] unless status.success?
      stdout.lines.map(&:strip)
    end

    def git_show_at_commit(sha, path)
      stdout, _, status = Open3.capture3("git", "show", "#{sha}:#{path}")
      return nil unless status.success?
      stdout
    end

    def ensure_clean_worktree!
      stdout, _, status = Open3.capture3("git", "status", "--porcelain")
      return true if status.success? && stdout.empty?

      abort "Working tree has uncommitted changes. Commit or stash them before running rake #{name}:prepare."
    end

    def validate_pr_label!
      return true unless pr_label

      stdout, stderr, status = Open3.capture3("gh", "label", "list", "--search", pr_label, "--json", "name", "--jq", ".[].name")
      return true if status.success? && stdout.lines.map(&:chomp).include?(pr_label)

      abort <<~ERROR.bg(:red).white
        Could not find GitHub label '#{pr_label}'.

        #{stderr}
      ERROR
    end

    def create_labeled_pr!(head:, title:, body:)
      if (pr_number = existing_pr_number(working_branch, head))
        return sysecho("Reusing existing PR ##{pr_number} for #{head}.")
      end

      syscall(
        ["gh", "pr", "create", "--base", working_branch, "--head", head, "--title", title, "--body", body, "--label", pr_label]
      )
    end

    def ensure_branch_not_ahead!(branch)
      return true unless local_branch?(branch)

      stdout, _, status = Open3.capture3("git", "rev-list", "--count", "origin/#{branch}..#{branch}")
      return true if status.success? && stdout.strip == "0"

      abort <<~ERROR.bg(:red).white
        Local #{branch} has commits not on origin/#{branch}. Refusing to reset --hard.

        Push or remove them before retrying.
      ERROR
    end

    def ensure_tag_absent!(tag)
      stdout, stderr, status = Open3.capture3("git", "ls-remote", "--tags", "origin", "refs/tags/#{tag}")
      abort "Could not list tags on origin: #{stderr}" unless status.success?
      return true if stdout.strip.empty?

      abort <<~ERROR.bg(:red).white
        Tag #{tag} already exists on origin.

        Bump the version, or delete the tag if it was pushed by mistake, before releasing.
      ERROR
    end

    def local_branch?(branch)
      _, _, status = Open3.capture3("git", "rev-parse", "--verify", "--quiet", "refs/heads/#{branch}")
      status.success?
    end

    def fetch_working_branch!
      syscall(["git fetch origin #{working_branch}"])
    end

    def checkout_working_branch!
      syscall(
        ["git checkout #{working_branch}"],
        ["git reset --hard origin/#{working_branch}"]
      )
    end

    def confirm_or_exit!
      sysecho "Are you ready to continue? (Press Enter to continue, Type 'x' and Enter to exit)".bg(:yellow).black
      exit if $stdin.gets.chomp.match?(/^x/i)
    end

    def post_to_slack(text, emoji = nil, thread_ts = nil)
      tasker["#{name}:slack"].reenable
      tasker["#{name}:slack"].invoke(text, release_message_channel, emoji, thread_ts)
    end

    # The post-release steps collected from "Runbook:" commit trailers.
    # Empty when no runbook is configured or the file has yet to be written.
    def runbook_items
      return [] unless runbook_file

      Reissue::Runbook.new(Rails.root.join(runbook_file).to_s).items
    end

    # Build the Slack message listing the post-release steps for a version.
    # Returns nil when the project does not use a runbook, which is distinct
    # from a configured runbook that happens to have no steps this release.
    def runbook_announcement(version, items = runbook_items)
      return nil unless runbook_file

      header = "*Post-release runbook for #{version}*"
      return "#{header}\nNo runbook tasks for this release." if items.empty?

      "#{header} — #{items.size} step#{"s" unless items.size == 1}\n\n" +
        items.map { |item| "• #{item}" }.join("\n")
    end

    # Post the runbook as a reply in a Slack thread, when a runbook is
    # configured. Returns the message posted, or nil when there is no thread
    # to reply to or no runbook to announce.
    def post_runbook_to_thread(version, thread_ts)
      return unless thread_ts.present?
      return unless (message = runbook_announcement(version))

      post_to_slack(message, ":clipboard:", thread_ts)
      message
    end

    def echo_unsent_slack_message(text, channel)
      sysecho "Post this to #{channel} yourself:\n\n#{text}\n"
    end

    def existing_pr_number(base, head)
      stdout, _, status = Open3.capture3(
        "gh", "pr", "list",
        "--base", base,
        "--head", head,
        "--state", "open",
        "--json", "number",
        "--jq", ".[0].number // empty"
      )
      return nil unless status.success?
      pr = stdout.strip
      pr.empty? ? nil : pr
    end

    def define
      require "slack-ruby-client"
      Slack.configure do |config|
        config.token = chat_token
      end

      desc <<~DESC
        ---------- STEP 2 ----------
        Release the current version to production

        This task tags the release commit on #{working_branch} and pushes the
        tag. Production deploys from the tag.

        After the release is complete, a new branch will be created to bump the
        version for the next release.
      DESC
      task "#{name}": [:environment] do
        unless system("gh --version > /dev/null 2>&1")
          abort "Error: GitHub CLI (gh) is required for the release process but was not found. Install it: https://cli.github.com"
        end
        validate_pr_label!
        ensure_clean_worktree!

        current_version = Object.const_get(version_constant)
        tag = "v#{current_version}"

        fetch_working_branch!
        ensure_branch_not_ahead!(working_branch)
        ensure_tag_absent!(tag)
        tag_ref = find_release_commit!("origin/#{working_branch}")

        sysecho <<~MSG
          Releasing version #{current_version} to production.

          This will tag #{tag_ref[0, 8]} on #{working_branch} as #{tag} and push the tag.
        MSG
        confirm_or_exit!

        checkout_working_branch!

        syscall(
          ["git tag -a #{tag} -m 'Release #{current_version}' #{tag_ref}"],
          ["git push origin #{tag}"]
        )

        post_to_slack("Released #{app_name} #{current_version} (#{tag_ref[0, 8]}) to production.", ":chipmunk:")
        # Capture the root before replying; each post overwrites last_message_ts.
        if (thread_ts = last_message_ts).present?
          changelog = git_show_at_commit(tag_ref, changelog_file) || File.read(Rails.root.join(changelog_file))
          post_to_slack(changelog, ":log:", thread_ts)
          post_runbook_to_thread(current_version, thread_ts)
        end

        sysecho <<~MSG
          Version #{current_version} released to production.

          Preparing to bump the version for the next release.

        MSG
        tasker["reissue"].invoke

        new_version_branch = `git rev-parse --abbrev-ref HEAD`.strip
        new_version = new_version_branch.split("/").last

        if pr_label
          syscall(["git push origin #{new_version_branch} --force"])
          create_labeled_pr!(head: new_version_branch, title: "Bump version to #{new_version}", body: "")
        else
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

        desc "Send a message to Slack."
        task :slack, [:text, :channel, :emoji, :ts] => :environment do |_, args|
          instance_variable_set(:@last_message_ts, nil)
          args.with_defaults(
            channel: release_message_channel,
            emoji: nil
          )
          if chat_token.blank?
            sysecho <<~MSG.bg(:yellow).black
              Slack message not sent: chat_token is not set.
              Set it with the Slack release token from your team's password manager before the next release.
            MSG
            echo_unsent_slack_message(args[:text], args[:channel])
            next
          end

          client = Slack::Web::Client.new
          options = args.to_h
          options[:icon_emoji] = options.delete(:emoji) if options[:emoji]
          options[:thread_ts] = options.delete(:ts) if options[:ts]

          sysecho "Sending message to Slack:".bg(:green).black + " #{args[:text]}"
          begin
            result = client.chat_postMessage(**options)
          rescue Faraday::Error => e
            sysecho "Slack message not sent: #{e.message}.".bg(:yellow).black
            echo_unsent_slack_message(args[:text], args[:channel])
            next
          end
          instance_variable_set(:@last_message_ts, result["ts"])
          sysecho %(Message sent: #{result["ts"]})
        end

        desc <<~DESC
          ---------- STEP 1 ----------
          Prepare the current version for release to production

          This task will create a new branch to prepare the release. The CHANGELOG
          will be updated and the version will be bumped. The branch will be pushed
          to the remote repository.

          After the branch is created, open a PR to #{working_branch} to finalize
          the release.
        DESC
        task prepare: [:environment] do
          ensure_clean_worktree!
          validate_pr_label!

          current_version = Object.const_get(version_constant)
          finish_branch = "bump/finish-#{current_version.tr(".", "-")}"

          fetch_working_branch!
          ensure_branch_not_ahead!(working_branch)
          checkout_working_branch!
          syscall(["git checkout -b #{finish_branch}"])
          sysecho <<~MSG
            Branch #{finish_branch} created.

            Check the contents of the CHANGELOG and ensure that the text is correct.

            If you need to make changes, edit the CHANGELOG and save the file.
            Then return here to continue with this commit.
          MSG
          confirm_or_exit!

          tasker["reissue:finalize"].invoke

          after_merge = <<~MSG.chomp
            Once the PR is merged, pull down #{working_branch} and run
              'rake #{name}'
            to release to production.
          MSG

          if pr_label
            syscall ["git push origin #{finish_branch} --force"]
            create_labeled_pr!(
              head: finish_branch,
              title: "Finish version #{current_version}",
              body: "Completing development for #{current_version}."
            )
            sysecho <<~MSG
              Branch #{finish_branch} pushed and its PR labeled '#{pr_label}'.

              #{after_merge}
            MSG
            syscall ["git checkout #{working_branch}"]
          else
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

                #{after_merge}
              MSG
            end
            if continue
              syscall ["git checkout #{working_branch}"],
                ["open", pr_url]
            end
          end
        end
      end
    end
  end
end

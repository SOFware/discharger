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
        reissue.retain_changelogs = task.retain_changelogs
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
      stdout, stderr, status = nil
      steps.each do |cmd|
        puts cmd.join(" ").bg(:green).black
        stdout, stderr, status = Open3.capture3(*cmd)
        unless status.success?
          error.puts stderr
          exit(status.exitstatus)
        end
        output.puts stdout
      end
      return true unless block_given?

      success = !!yield(stdout, stderr, status)
      # Bypassed branch-protection rules are intentional when merging the release
      # branch into production, so treat the command as successful.
      success = true if stderr.match?(/bypassed rule violations/i)
      abort(stderr) unless success
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

    # Locate the commit that finalized changelog_file for the current version.
    # Returns the SHA, or aborts with a clear message if it can't be found or
    # does not appear to be a finalize commit for this version.
    #
    # This is intentionally a computation, not a gate on HEAD: if another PR
    # landed on the branch after the finalize PR merged, HEAD is a merge commit
    # whose ancestry includes the unrelated work. Tagging HEAD would ship that
    # work. Tagging the finalize commit itself does not.
    def find_release_commit!(branch, output: $stdout)
      version = Object.const_get(version_constant)
      version_header = /^## \[#{Regexp.escape(version)}\] - \d{4}-\d{2}-\d{2}/
      sha = git_file_commits(branch, changelog_file).find do |candidate_sha|
        next false if git_merge_commit?(candidate_sha)

        contents = git_show_at_commit(candidate_sha, changelog_file)
        parent_contents = git_show_at_commit("#{candidate_sha}^", changelog_file)

        contents&.match?(version_header) && !parent_contents&.match?(version_header)
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

    def git_show_version(branch)
      content, _, status = Open3.capture3("git", "show", "origin/#{branch}:#{version_file}")
      return nil unless status.success?
      content[/VERSION\s*=\s*["']([^"']+)["']/, 1]
    end

    def git_file_commits(branch, path)
      stdout, _, status = Open3.capture3("git", "log", "--no-merges", branch, "--format=%H", "--", path)
      return [] unless status.success?
      stdout.lines.map(&:strip)
    end

    def git_merge_commit?(sha)
      stdout, _, status = Open3.capture3("git", "rev-list", "--parents", "-n", "1", sha)
      return false unless status.success?
      stdout.split.length > 2
    end

    def git_ancestor?(ancestor, descendant)
      _, _, status = Open3.capture3("git", "merge-base", "--is-ancestor", ancestor, descendant)
      status.success?
    end

    def delete_local_branch(branch)
      Open3.capture3("git", "branch", "-D", branch)
      true
    end

    def git_show_at_commit(sha, path)
      stdout, _, status = Open3.capture3("git", "show", "#{sha}:#{path}")
      return nil unless status.success?
      stdout
    end

    def existing_pr_number(base, head, state: "open")
      stdout, _, status = Open3.capture3(
        "gh", "pr", "list",
        "--base", base,
        "--head", head,
        "--state", state,
        "--json", "number",
        "--jq", ".[0].number // empty"
      )
      return nil unless status.success?
      pr = stdout.strip
      pr.empty? ? nil : pr
    end

    def merge_release_pr!(base:, head:)
      pr_number = existing_pr_number(base, head)
      if pr_number
        return syscall(["gh", "pr", "merge", pr_number, "--merge"])
      end

      return sysecho("Branch #{head} is already merged into #{base}. Continuing...") if git_ancestor?(head, base)

      abort <<~ERROR.bg(:red).white
        Could not find an open PR from #{head} to #{base}.

        Run: rake #{name}:stage
        Then retry: rake #{name}
      ERROR
    end

    def require_gh!(reason)
      return true if system("gh", "auth", "status", out: File::NULL, err: File::NULL)

      abort "Error: authenticated GitHub CLI (gh) is required for #{reason}. Run `gh auth login` and retry."
    end

    def validate_pr_label!
      return true unless pr_label

      _, stderr, status = Open3.capture3("gh", "label", "view", pr_label)
      return true if status.success?

      abort <<~ERROR.bg(:red).white
        Could not find GitHub label '#{pr_label}'.

        #{stderr}
      ERROR
    end

    def ensure_clean_worktree!
      stdout, _, status = Open3.capture3("git", "status", "--porcelain")
      return true if status.success? && stdout.empty?

      abort "Working tree has uncommitted changes. Commit or stash them before running rake #{name}:prepare."
    end

    # Abort if the local branch has commits not present on origin/<branch>.
    # Run after fetching to make the comparison meaningful. Prevents `git reset
    # --hard origin/<branch>` from silently discarding unpushed work.
    def ensure_branch_not_ahead!(branch)
      stdout, _, status = Open3.capture3("git", "rev-list", "--count", "origin/#{branch}..#{branch}")
      return true if status.success? && stdout.strip == "0"

      abort <<~ERROR.bg(:red).white
        Local #{branch} has commits not on origin/#{branch}. Refusing to reset --hard.

        Push or remove them before retrying.
      ERROR
    end

    def current_branch!
      stdout, _, status = Open3.capture3("git", "rev-parse", "--abbrev-ref", "HEAD")
      abort "Could not determine the current git branch." unless status.success?
      stdout.strip
    end

    def validate_pr_branch!(branch)
      return true unless branch.empty? || branch == "HEAD" || branch == working_branch

      abort "Refusing to push unsafe PR branch '#{branch}'. Run this task from the version bump branch."
    end

    def define
      require "slack-ruby-client"
      Slack.configure do |config|
        config.token = chat_token
      end

      desc <<~DESC
        ---------- STEP 3 ----------
        Release the current version to production

        This task merges the release branch into production via a GitHub pull
        request and tags the current version.

        After the release is complete, a new branch will be created to bump the
        version for the next release.
      DESC
      task "#{name}": [:environment] do
        require_gh!("the release process") if !auto_deploy_staging || pr_label
        validate_pr_label!

        current_version = Object.const_get(version_constant)

        # When auto_deploy_staging is enabled, release directly from working_branch
        # instead of staging_branch (for CI/CD pipelines that auto-deploy staging).
        release_source = auto_deploy_staging ? working_branch : staging_branch

        release_action = if auto_deploy_staging
          "This will tag the release commit on #{working_branch} and push the tag."
        else
          "This will tag the current version and push it to the production branch."
        end

        sysecho <<~MSG
          Releasing version #{current_version} to production.

          #{release_action}
          Release source: #{release_source}
        MSG
        sysecho "Are you ready to continue? (Press Enter to continue, Type 'x' and Enter to exit)".bg(:yellow).black
        input = $stdin.gets
        exit if input.chomp.match?(/^x/i)

        syscall(["git", "checkout", working_branch])

        tag_steps = []
        if auto_deploy_staging
          ensure_clean_worktree!
          syscall(["git", "fetch", "origin", working_branch])
          ensure_branch_not_ahead!(working_branch)
          syscall(["git", "reset", "--hard", "origin/#{working_branch}"])
          # tag_ref is the full SHA of the finalize commit, even if origin/working_branch
          # has since advanced. The non-auto path tags the production branch ref instead.
          tag_ref = find_release_commit!(working_branch)
        else
          delete_local_branch(staging_branch)
          delete_local_branch(production_branch)
          syscall(
            ["git", "fetch", "origin", "#{release_source}:#{release_source}", "#{production_branch}:#{production_branch}"]
          )
          validate_version_match!(staging_branch, working_branch)
          merge_release_pr!(base: production_branch, head: release_source)

          tag_ref = production_branch
          tag_steps << ["git", "fetch", "origin", "#{production_branch}:#{production_branch}"]
        end

        slack_sha = auto_deploy_staging ? tag_ref[0, 8] : commit_identifier.call
        tag_steps << ["git", "tag", "-a", "v#{current_version}", "-m", "Release #{current_version}", tag_ref]
        tag_steps << ["git", "push", "origin", "v#{current_version}"]

        continue = syscall(*tag_steps) do
          tasker["#{name}:slack"].invoke("Released #{app_name} #{current_version} (#{slack_sha}) to production.", release_message_channel, ":chipmunk:")
          if last_message_ts.present?
            # Read from the tagged commit so the posted changelog matches the released
            # version, even if working_branch has advanced past tag_ref since finalize.
            text = git_show_at_commit(tag_ref, changelog_file) || File.read(changelog_file)
            tasker["#{name}:slack"].reenable
            tasker["#{name}:slack"].invoke(text, release_message_channel, ":log:", last_message_ts)
          end
          # Signal success — no branch switch needed since we stay on working_branch throughout
          true
        end

        abort "Release failed." unless continue

        sysecho <<~MSG
          Version #{current_version} released to production.

          Preparing to bump the version for the next release.

        MSG
        tasker["reissue"].invoke

        new_version_branch = current_branch!
        validate_pr_branch!(new_version_branch)
        new_version = new_version_branch.split("/").last
        bump_pr_title = "Bump version to #{new_version}"

        if pr_label
          syscall(
            ["git", "push", "origin", new_version_branch, "--force"],
            [
              "gh", "pr", "create",
              "--base", working_branch,
              "--head", new_version_branch,
              "--title", bump_pr_title,
              "--body", "",
              "--label", pr_label
            ]
          )
        else
          params = {expand: 1, title: bump_pr_title}
          pr_url = "#{pull_request_url}/compare/#{working_branch}...#{new_version_branch}?#{params.to_query}"

          pushed = syscall(["git", "push", "origin", new_version_branch, "--force"]) do
            sysecho <<~MSG
              Branch #{new_version_branch} created.

              Open a PR to #{working_branch} to mark the version and update the changelog
              for the next release.

              Opening PR: #{pr_url}
            MSG
          end
          syscall ["open", pr_url] if pushed
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
            value = "[REDACTED]" if var == :@chat_token && value
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
            ["git", "fetch", "origin", build_branch],
            ["git", "checkout", build_branch]
          )
          # Delete after switching off staging_branch — otherwise `git branch -D`
          # silently fails when staging_branch is the current branch, and the next
          # `checkout -b` then fails because the branch still exists.
          delete_local_branch(staging_branch)
          syscall(
            ["git", "reset", "--hard", "origin/#{build_branch}"],
            ["git", "checkout", "-b", staging_branch],
            ["git", "push", "origin", staging_branch, "--force"]
          ) do
            current_version = Object.const_get(version_constant)
            tasker["#{name}:slack"].invoke("Building #{app_name} #{current_version} (#{commit_identifier.call}) on #{staging_branch}.", release_message_channel)
            syscall ["git", "checkout", build_branch]
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
          require_gh!("PR creation") if pr_label
          validate_pr_label!
          ensure_clean_worktree!

          current_version = Object.const_get(version_constant)
          finish_branch = "bump/finish-#{current_version.tr(".", "-")}"

          syscall(
            ["git", "fetch", "origin", working_branch],
            ["git", "checkout", working_branch]
          )
          ensure_branch_not_ahead!(working_branch)
          syscall(
            ["git", "reset", "--hard", "origin/#{working_branch}"],
            ["git", "checkout", "-b", finish_branch]
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

          finish_pr_title = "Finish version #{current_version}"
          finish_pr_body = "Completing development for #{current_version}."

          next_step = auto_deploy_staging ? "rake #{name}" : "rake #{name}:stage"
          next_step_desc = auto_deploy_staging ? "release to production" : "stage the release branch"

          if pr_label
            continue = syscall(
              ["git", "push", "origin", finish_branch, "--force"],
              [
                "gh", "pr", "create",
                "--base", working_branch,
                "--head", finish_branch,
                "--title", finish_pr_title,
                "--body", finish_pr_body,
                "--label", pr_label
              ]
            ) do
              sysecho <<~MSG
                Branch #{finish_branch} pushed and PR created with label '#{pr_label}'.

                Once the PR is merged, pull down #{working_branch} and run
                  '#{next_step}'
                to #{next_step_desc}.
              MSG
            end
            syscall ["git", "checkout", working_branch] if continue
          else
            params = {expand: 1, title: finish_pr_title, body: finish_pr_body + "\n"}
            pr_url = "#{pull_request_url}/compare/#{finish_branch}?#{params.to_query}"

            continue = syscall ["git", "push", "origin", finish_branch, "--force"] do
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
              syscall ["git", "checkout", working_branch],
                ["open", pr_url]
            end
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

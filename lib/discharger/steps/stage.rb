require "rainbow/refinement"
require "uri"  # Add this for URL encoding

using Rainbow

module Discharger
  module Steps
    class Stage
      def initialize(task)
        @task = task
        @tasker = task.tasker
      end

      def stage_release_branch
        @task.desc <<~DESC
          ---------- STEP 2 ----------
          Stage the current version for release

          This task creates a staging branch from the current working branch and
          pushes it to the remote repository. A pull request will be opened to merge
          the staging branch into production.
        DESC
        @task.task stage: [:environment, :build] do
          current_version = Object.const_get(@task.version_constant)
          @task.sysecho "Branch staging updated"
          @task.sysecho "Open a PR to production to release the version"
          @task.sysecho "Once the PR is **approved**, run 'rake release' to release the version"

          pr_url = "#{@task.pull_request_url}/compare/#{@task.production_branch}...#{@task.staging_branch}"
          pr_params = {
            expand: 1,
            title: URI.encode_www_form_component("Release #{current_version} to production"),
            body: URI.encode_www_form_component("Deploy #{current_version} to production.\n")
          }.map { |k, v| "#{k}=#{v}" }.join("&")

          @task.syscall ["open #{pr_url}?#{pr_params}"]
        end
      end

      private

      def method_missing(method_name, *args, &block)
        if @task.respond_to?(method_name)
          @task.send(method_name, *args, &block)
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        @task.respond_to?(method_name, include_private) || super
      end
    end
  end
end

require "rainbow/refinement"

using Rainbow

module Discharger
  module Steps
    class Prepare
      def initialize(task)
        @task = task
        @tasker = task.tasker
      end

      def prepare_for_release
        @task.desc <<~DESC
          ---------- STEP 1 ----------
          Prepare the current version for release

          This task will check that the current version is ready for release by
          verifying that the version number is valid and that the changelog is
          up to date.
        DESC
        @task.task prepare: [:environment] do
          current_version = Object.const_get(@task.version_constant)
          @task.sysecho "Preparing version #{current_version} for release"

          if @task.mono_repo && @task.gem_tag
            @task.sysecho "Checking for gem tag #{@task.gem_tag}"
            @task.syscall ["git fetch origin #{@task.gem_tag}"]
            @task.syscall ["git tag -l #{@task.gem_tag}"]
          end

          @task.syscall(
            ["git fetch origin #{@task.working_branch}"],
            ["git checkout #{@task.working_branch}"],
            ["git pull origin #{@task.working_branch}"]
          )

          @task.sysecho "Checking changelog for version #{current_version}"
          changelog = File.read(@task.changelog_file)
          unless changelog.include?(current_version.to_s)
            raise "Version #{current_version} not found in #{@task.changelog_file}"
          end

          @task.sysecho "Version #{current_version} is ready for release"
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

require "rainbow/refinement"

using Rainbow

module Stage
  def stage_release_branch
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

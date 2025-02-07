require "rainbow/refinement"

using Rainbow

module Prepare
  def prepare_for_release
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
        ["git checkout -b #{finish_branch}"],
        ["git push origin #{finish_branch} --force"]
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
  end
end

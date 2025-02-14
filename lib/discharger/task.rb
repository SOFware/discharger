require "rake/tasklib"
require "reissue/rake"
require "rainbow/refinement"
require_relative "helpers/sys_helper"
require_relative "steps/prepare"
require_relative "steps/stage"
require_relative "steps/release"

using Rainbow

module Discharger
  class Task < Rake::TaskLib
    include Rake::DSL
    include SysHelper

    # Make Rake DSL methods public
    public :desc, :task

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
    attr_reader :tasker

    # Reissue settings
    attr_accessor(
      *Reissue::Task.instance_methods(false).reject { |method|
        method.to_s.match?(/[\?=]\z/) || method_defined?(method)
      }
    )

    ## Configuration for gem tagging in monorepos
    attr_accessor :mono_repo
    attr_accessor :gem_tag
    attr_accessor :gem_name

    def initialize(name = :release, tasker: Rake::Task)
      @name = name
      @tasker = tasker
      @working_branch = "develop"
      @staging_branch = "stage"
      @production_branch = "main"
      @description = "Release the current version to #{staging_branch}"
      @mono_repo = false
      @release = Steps::Release.new(self)
      @stage = Steps::Stage.new(self)
      @prepare = Steps::Prepare.new(self)
    end

    def define
      require "slack-ruby-client"
      Slack.configure do |config|
        config.token = chat_token
      end

      @release.release_to_production
      @stage.stage_release_branch
      @prepare.prepare_for_release
    end

    # Delegate release-related attributes to the Release object
    def method_missing(method_name, *args, &block)
      if @release.respond_to?(method_name)
        @release.send(method_name, *args, &block)
      else
        super
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      @release.respond_to?(method_name, include_private) || super
    end
  end
end

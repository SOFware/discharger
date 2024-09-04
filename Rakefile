require "bundler/setup"

require "bundler/gem_tasks"

task default: :test

require "reissue/gem"

Reissue::Task.create :reissue do |task|
  task.version_file = "lib/discharger/version.rb"
  task.commit = true
end

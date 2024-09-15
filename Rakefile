require "bundler/setup"

require "bundler/gem_tasks"
require "rake/testtask"

require "reissue/gem"

Reissue::Task.create :reissue do |task|
  task.version_file = "lib/discharger/version.rb"
  task.commit = true
end

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
  t.verbose = false
end

task default: :test

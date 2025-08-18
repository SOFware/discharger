require "bundler/setup"

require "bundler/gem_tasks"
require "rake/testtask"

require "reissue/gem"

Reissue::Task.create :reissue do |task|
  task.version_file = "lib/discharger/version.rb"
  task.commit = !ENV["GITHUB_ACTIONS"]
  task.commit_finalize = !ENV["GITHUB_ACTIONS"]
  task.push_finalize = :branch
end

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
  t.verbose = false
end

task default: :test

desc "Prepare a release (bump version, finalize changelog, build gem)"
task :prepare, [:segment] do |_t, args|
  # Default to patch if no segment provided
  segment = args[:segment] || "patch"

  unless %w[major minor patch].include?(segment)
    puts "Error: Invalid version segment '#{segment}'. Must be major, minor, or patch."
    exit 1
  end

  # Run the reissue tasks
  Rake::Task["reissue"].invoke(segment)
  Rake::Task["reissue:finalize"].invoke
  Rake::Task["build:checksum"].invoke

  # Reload the version file to get the new version
  load "lib/discharger/version.rb"
  version = Discharger::VERSION

  puts "\n✅ Release v#{version} prepared!"
  puts "\nNext steps:"
  puts "1. Review changes: git diff"
  puts "2. Commit: git add -A && git commit -m 'Release v#{version}'"
  puts "3. Tag: git tag -a v#{version} -m 'Release v#{version}'"
  puts "4. Push: git push origin main --tags"
  puts "5. Release: rake release"
end

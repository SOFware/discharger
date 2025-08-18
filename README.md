# Discharger

A Ruby gem that provides Rake tasks for managing code deployment workflows with automated versioning, changelog management, and Slack notifications.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "discharger"
```

And then execute:
```bash
$ bundle install
```

Then run the install generator:
```bash
$ rails generate discharger:install
```

Or install it yourself as:
```bash
$ gem install discharger
```

## Usage

Add `require "discharger/task"` to your Rakefile, then configure the discharger task:

```ruby
require "discharger/task"

Discharger::Task.create do |task|
  # Version management
  task.version_file = "config/application.rb"
  task.version_constant = "MyApp::VERSION"
  
  # Slack integration
  task.release_message_channel = "#some-slack-channel"
  task.app_name = "My App Name"
  
  # Git integration
  task.commit_identifier = -> { `git rev-parse HEAD`.strip }
  task.pull_request_url = "https://github.com/SOFware/some-app"
  
  # Changelog management (optional)
  task.fragment_directory = "changelog.d"  # Directory for changelog fragments
end
```

### Changelog Fragments

Discharger supports changelog fragment management through the `fragment_directory` setting. When set, Discharger will look for changelog fragments in the specified directory and automatically combine them into the main changelog during releases.

```ruby
Discharger::Task.create do |task|
  # ... other configuration ...
  task.fragment_directory = "changelog.d"  # Default: nil (disabled)
end
```

With fragments enabled, you can create individual changelog files in the `changelog.d/` directory:

```
changelog.d/
├── 123-fix-login-bug.md
├── 124-add-user-profile.md
└── 125-update-dependencies.md
```

Each fragment file should contain the changelog entry for a specific change or feature.

## Available Tasks for Apps Using Discharger

When you add Discharger to your Rails application, it creates several Rake tasks for managing your deployment workflow. The specific tasks depend on your configuration in the Rakefile.

Example tasks that Discharger adds to YOUR app:
- `rake release:prepare` - Prepare a release (bump version, update changelog)
- `rake release:stage` - Stage the release
- `rake release` - Complete the release
- `rake release:slack` - Send Slack notifications

These tasks are customized based on your `Discharger::Task.create` configuration.

## Contributing

This gem is managed with [Reissue](https://github.com/SOFware/reissue).

### Development Rake Tasks

For developing the Discharger gem itself, the following rake tasks are available:

```bash
$ rake -T
rake build                            # Build discharger gem into pkg/
rake build:checksum                   # Generate SHA512 checksum
rake install                          # Build and install gem locally
rake install:local                    # Install without network access
rake prepare[segment]                 # Prepare a release (defaults to patch)
rake release[remote]                  # Create tag and push gem to RubyGems
rake test                             # Run tests

# Reissue tasks for version management
rake reissue[segment]                 # Prepare new version (major/minor/patch)
rake reissue:branch[branch_name]      # Create release branch
rake reissue:finalize[date]           # Finalize changelog with release date
rake reissue:push                     # Push branch to remote
rake reissue:reformat[version_limit]  # Reformat changelog
```

### Releasing the Gem

#### Automated Release (via GitHub Actions)

The automated workflow is currently being fixed. When working:
1. Go to Actions → "Prepare Release" → Run workflow
2. Review the created PR
3. Add the `approved-release` label and merge
4. The gem will be automatically published to RubyGems.org

#### Manual Release Process

To release a new version manually:

```bash
# 1. Prepare the release (bumps version, finalizes changelog, builds gem)
rake prepare         # defaults to patch
# or specify the version segment:
rake prepare[minor]  # for minor version bump
rake prepare[major]  # for major version bump

# 2. Review the changes
git diff

# 3. Commit the changes
git add -A
git commit -m "Release v$(ruby -r ./lib/discharger/version.rb -e 'puts Discharger::VERSION')"

# 4. Create and push a tag
git tag -a v$(ruby -r ./lib/discharger/version.rb -e 'puts Discharger::VERSION') -m "Release v$(ruby -r ./lib/discharger/version.rb -e 'puts Discharger::VERSION')"
git push origin main --tags

# 5. Release to RubyGems (requires gem credentials)
rake release
```


Bug reports and pull requests are welcome on GitHub.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

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

## Available Tasks

The gem creates several Rake tasks for managing your deployment workflow:

```bash
$ rake -T release
rake release                            # ---------- STEP 3 ----------
rake release:build                      # Release the current version to stage
rake release:config                     # Echo the configuration settings
rake release:prepare                    # ---------- STEP 1 ----------
rake release:slack[text,channel,emoji]  # Send a message to Slack
rake release:stage                      # ---------- STEP 2 ----------
```

### Workflow Steps

1. **Prepare** (`rake release:prepare`): Create a new branch to prepare the release, update the changelog, and bump the version
2. **Stage** (`rake release:stage`): Update the staging branch and create a PR to production
3. **Release** (`rake release`): Release the current version to production by tagging and pushing to the production branch

## Contributing

This gem is managed with [Reissue](https://github.com/SOFware/reissue).

### Releasing

Releases are automated via GitHub Actions:

1. Go to Actions → "Prepare Release" → Run workflow
2. Select version type (major, minor, patch, or custom)
3. Review the created PR with version bumps and changelog updates
4. Add the `approved-release` label and merge
5. The gem will be automatically published to RubyGems.org

Bug reports and pull requests are welcome on GitHub.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

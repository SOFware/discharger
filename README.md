# Discharger

Code supporting tasks that discharge code for deployment.

## Usage

Add `require "discharger/task"` to your Rakefile.

Then build the discharger task

```ruby
require "discharger/task"

Discharger::Task.create do |task|
  task.version_file = "config/application.rb"
  task.release_message_channel = "#some-slack-channel"
  task.version_constant = "MyApp::VERSION"
  task.app_name = "My App name"
  task.commit_identifier = -> { `git rev-parse HEAD`.strip }
  task.pull_request_url = "https://github.com/SOFware/some-app"

  # Optional: Enable changelog fragments
  task.changelog_fragments_enabled = true
  task.changelog_fragments_dir = "changelog/unreleased"  # default
  task.changelog_sections = ["Added", "Changed", "Deprecated", "Removed", "Fixed", "Security"]  # default
end
```

It will make Rake tasks available to push code to branches and notify Slack channels.

```bash
$ rake -T release
rake release                            # ---------- STEP 3 ----------
rake release:build                      # Release the current version to stage
rake release:config                     # Echo the configuration settings
rake release:fragments                  # List all changelog fragments
rake release:prepare                    # ---------- STEP 1 ----------
rake release:process_fragments          # Process changelog fragments manually (for testing)
rake release:slack[text,channel,emoji]  # Send a message to Slack
rake release:stage                      # ---------- STEP 2 ----------
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem "discharger"
```

And then execute:

```bash
$ bundle
```

Then run the install generator:

```bash
$ rails generate discharger:install
```

Or install it yourself as:

```bash
$ gem install discharger
```

## Changelog Fragments

Discharger supports an optional changelog fragments feature that helps reduce
merge conflicts in the CHANGELOG.md file. Instead of all developers editing the
same changelog file, each feature branch can add small fragment files that are
automatically processed during release preparation.

### Setup

Enable changelog fragments in your Discharger configuration:

```ruby
Discharger::Task.create do |task|
  # ... other configuration ...
  task.changelog_fragments_enabled = true
  task.changelog_fragments_dir = "changelog/unreleased"  # default
  task.changelog_sections = ["Added", "Changed", "Deprecated", "Removed", "Fixed", "Security"]  # default
end
```

Create the changelog fragments directory structure:

```bash
$ mkdir -p changelog/unreleased
```

### Usage

Create changelog fragments for each feature/fix by manually creating files following the naming convention:

```bash
# Create files in changelog/unreleased/ following the pattern:
# changelog/unreleased/{section}.{short-summary}.md
```

File naming convention: `{section}.{short-summary}.md`

Examples:

- `Added.new-user-authentication.md`
- `Fixed.memory-leak-in-parser.md`
- `Changed.api-response-format.md`

Each fragment file should contain bullet points describing the change:

```markdown
- Added JWT authentication for API endpoints
- Implemented password reset functionality
```

### Processing

When you run `rake release:prepare`, the fragments are:

1. Organized by section in the changelog
2. Added to the "Unreleased" section of CHANGELOG.md
3. Deleted from the fragments directory

You can also:

- List current fragments: `rake release:fragments`
- Process fragments manually: `rake release:process_fragments`

## Contributing

This gem is managed with [Reissue](https://github.com/SOFware/reissue).

Bug reports and pull requests are welcome on GitHub.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

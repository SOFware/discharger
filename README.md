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

### Building with a Working Branch

To release a specific working branch to stage instead of the default branch, use the `DISCHARGER_BUILD_BRANCH` environment variable:

```bash
DISCHARGER_BUILD_BRANCH=your-feature-branch rake build
```

This will deploy your working branch to the staging environment.

#### Configuring Branch Names

You can configure the branch names in your Rakefile when setting up the discharger task:

```ruby
require "discharger"

Discharger::Task.new do |task|
  task.app_name = "MyApp"
  task.working_branch = ENV.fetch("WORKING_BRANCH", "develop")
  task.staging_branch = ENV.fetch("STAGING_BRANCH", "stage")
  task.production_branch = ENV.fetch("PRODUCTION_BRANCH", "main")
  # ... other configuration
end
```

This allows you to use environment variables to override the default branch names, or set project-specific defaults. The `DISCHARGER_BUILD_BRANCH` environment variable (shown above) provides a runtime override specifically for the build task.

## Development Setup Automation

Discharger includes a setup script that automates your development environment configuration. When you run the install generator, it creates a `bin/setup` script and a `config/setup.yml` configuration file.

### Running Setup

After installing Discharger, run the setup script to configure your development environment:

```bash
$ bin/setup
```

This script is idempotent - you can run it multiple times safely, and it will ensure your environment is properly configured.

### Configuration

The setup process is configured through `config/setup.yml`. Here's an example configuration:

```yaml
app_name: "YourAppName"

database:
  port: 5432
  name: "db-your-app"
  version: "14"
  password: "postgres"

redis:
  port: 6379
  name: "redis-your-app"
  version: "latest"

# Built-in commands to run
steps:
  - brew
  - asdf
  - git
  - bundler
  - yarn
  - config
  - docker
  - env
  - database

# Custom commands for your application
custom_steps:
  - description: "Seed application data"
    command: "bin/rails db:seed"
```

### Using Default Steps

The `steps` array specifies which built-in setup commands to run. Available commands include:

- `brew` - Install Homebrew dependencies
- `asdf` - Setup version management with asdf
- `git` - Configure git settings
- `bundler` - Install Ruby gems
- `yarn` - Install JavaScript packages
- `config` - Copy configuration files
- `docker` - Setup Docker containers
- `env` - Configure environment variables
- `database` - Setup and migrate database

### Selecting Specific Steps

You can customize which steps run by modifying the `steps` array:

```yaml
# Only run specific setup steps
steps:
  - bundler
  - database
  - yarn
```

Leave the array empty or omit it entirely to run all available steps.

### Adding Custom Commands

Add application-specific setup tasks using the `custom_steps` section:

```yaml
custom_steps:
  # Simple command
  - description: "Compile assets"
    command: "bin/rails assets:precompile"

  # Command with condition
  - description: "Setup Elasticsearch"
    command: "bin/rails search:setup"
    condition: "defined?(Elasticsearch)"

  # Command with environment variable condition
  - description: "Import production data"
    command: "bin/rails db:import"
    condition: "ENV['IMPORT_DATA'] == 'true'"
```

Each custom step can include:
- `description` - A description shown during setup
- `command` - The command to execute
- `condition` - An optional Ruby expression that must evaluate to true for the command to run

### Creating Custom Command Classes

For more complex setup logic, you can create custom command classes that integrate with Discharger's setup system:

```ruby
# lib/setup_commands/elasticsearch_command.rb
class ElasticsearchCommand < Discharger::SetupRunner::Commands::BaseCommand
  def description
    "Configure Elasticsearch"
  end

  def can_execute?
    defined?(Elasticsearch)
  end

  def execute
    with_spinner("Setting up Elasticsearch...") do
      # Your setup logic here
      system("bin/rails search:setup")
      system("bin/rails search:reindex")
    end
    log "Elasticsearch configured successfully", emoji: "✅"
  end
end

# Register the command in an initializer or your setup script
Discharger::SetupRunner.register_command(:elasticsearch, ElasticsearchCommand)
```

Then use it in your configuration:

```yaml
steps:
  - bundler
  - database
  - elasticsearch  # Your custom command
```


## Contributing

This gem is managed with [Reissue](https://github.com/SOFware/reissue).

### Releasing

Releases are streamlined with a single GitHub Actions workflow using RubyGems Trusted Publishing:

1. Go to Actions → "Release gem to RubyGems.org" → Run workflow
2. Select version bump type (patch, minor, or major)
3. The workflow will automatically:
   - Finalize the changelog with the release date
   - Build the gem with checksum verification
   - Publish to RubyGems.org via Trusted Publishing (no API keys needed)
   - Create a git tag for the release
   - Bump to the next development version
   - Open a PR with the version bump for continued development

Bug reports and pull requests are welcome on GitHub.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

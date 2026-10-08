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
  task.fragment = "changelog.d"  # Directory for changelog fragments
end
```

### Changelog Management

Discharger supports changelog management through the `fragment` setting from [Reissue](https://github.com/SOFware/reissue?tab=readme-ov-file#configuration-options).

#### Git Commit Trailers

Document changes directly in your commit messages using git trailers. Set `task.fragment = :git` to enable this feature:

```ruby
Discharger::Task.create do |task|
  # ... other configuration ...
  task.fragment = :git  # Enable git commit trailers
end
```

This keeps changelog data coupled with your code changes in the same commit. See [Git Trailers Guide](docs/git-trailers-guide.md) for detailed usage instructions.

#### File-Based Fragments

Alternatively, you can use file-based fragments by creating individual changelog files in a directory:

```ruby
Discharger::Task.create do |task|
  # ... other configuration ...
  task.fragment = "changelog.d"  # Enable file-based fragments
end
```

With this approach, create individual changelog files in the `changelog.d/` directory:

```
changelog.d/
├── 123-fix-login-bug.md
├── 124-add-user-profile.md
└── 125-update-dependencies.md
```

Each fragment file should contain the changelog entry for a specific change or feature.

### Post-release Runbook

Some releases need manual follow-up: run a rake task, backfill data, re-index documents.
Reissue collects those steps from `Runbook:` commit trailers, and Discharger announces
them to your team in the release thread.

```ruby
Discharger::Task.create do |task|
  # ... other configuration ...
  task.runbook_file = "RUNBOOK.md"  # Default: nil (disabled)
end
```

Add steps as you work, in the same commit as the change that requires them:

```bash
git commit -m "Add data migration

Fixed: Duplicate user records
Runbook: Run \`rake data:cleanup\` after deploy"
```

`rake release:prepare` finalizes the runbook alongside the changelog, so the release tag
records exactly which steps that version needs. Discharger posts the checklist to Slack as
a reply in the release thread, right after the changelog:

```
*Post-release runbook for 1.2.3* — 2 steps

• Run `rake data:cleanup` (abc1234)
• Re-index search documents (def5678)
```

When a release needs no follow-up, the thread says so explicitly rather than staying
silent, so nobody has to wonder whether the check was skipped:

```
*Post-release runbook for 1.2.3*
No runbook tasks for this release.
```

Leave `runbook_file` unset and Discharger posts nothing extra. See the
[Reissue runbook documentation](https://github.com/SOFware/reissue#post-release-runbook)
for how items are collected and merged.

## Release Flow

Discharger assumes one long-lived branch, `main` by default. CI deploys every push to that
branch to staging, and production deploys from `v*` tags. There is no staging branch and no
production branch to keep in sync.

```bash
$ rake -T release
rake release                            # ---------- STEP 2 ----------
rake release:config                     # Echo the configuration settings
rake release:prepare                    # ---------- STEP 1 ----------
rake release:slack[text,channel,emoji]  # Send a message to Slack
```

1. **Prepare** (`rake release:prepare`): Cut a finish branch from `main`, finalize the
   changelog and runbook, and open a PR back to `main`. Merging that PR puts the finalized
   release on staging.
2. **Release** (`rake release`): Tag the release commit on `main`, push the tag, announce
   the release in Slack, then open the PR that bumps `main` to the next version.

Set `DISCHARGER_RELEASE_CONFIRM=1` to run `release:prepare` and `release` without a TTY.

`rake release` tags the newest commit that changed the current version's dated changelog
section, so work merged after finalizing (or re-finalizing for a hotfix) is left out.
Production ships the tagged commit, which can be older than what staging last ran.

### Configuring the Branch

```ruby
Discharger::Task.create do |task|
  task.app_name = "MyApp"
  task.working_branch = ENV.fetch("WORKING_BRANCH", "main")
  # ... other configuration
end
```

### Upgrading to 0.5.0

Before bumping the gem, CI must deploy every push to the working branch to staging and
every `v*` tag to production. Then:

- Remove `staging_branch`, `production_branch`, `auto_deploy_staging` and `description`
  from the Rakefile. In 0.5.0 they warn and do nothing; 0.6 removes them.
- `working_branch` now defaults to `main`. Set it if the app releases from another branch.
- `release:stage` and `release:build` are gone; nothing replaces them.

## Development Setup Automation

Discharger includes a setup script that automates your development environment configuration. When you run the install generator, it creates a `bin/setup` script and a `config/setup.yml` configuration file.

### Running Setup

After installing Discharger, run the setup script to configure your development environment:

```bash
$ bin/setup
```

You can rerun it whenever your environment drifts. Every run drops and rebuilds the development and test databases, so local data is lost.

It works on a fresh clone with no gems installed. The generated script first runs a
standard-library-only pass that stores bundler credentials for a configured
`github_packages` source (from your GitHub CLI login, only once the source
accepts that token; gh calls time out after `github_packages.gh_timeout` seconds,
15 by default, or `DISCHARGER_GH_TIMEOUT`), installs the bundle, and then
re-execs itself under `bundle exec` so default gems such as psych never clash with
`Gemfile.lock`. The `DISCHARGER_SETUP_BUNDLED` environment variable marks the second
pass; the `github_packages` step later verifies the stored credentials and warns when
the token lacks the `read:packages` scope. Before `pre_steps` or Rails run, setup
creates every missing counterpart of `config/**/*.example` and `.env.example`, so an
app whose boot needs `.env` or `config/database.yml` gets them without copying
them in `pre_steps`.

Each pre_step and step prints its elapsed time when it finishes, and the closing line
reports the total, so a slow setup shows which step to look at.

### Keeping bin/setup Generated

`bin/setup` is a verbatim copy of the gem's template and opens with a notice saying
so. Do not hand-edit it in an app: app-specific work belongs in `config/setup.yml`
(`pre_steps`, `steps`, `custom_steps`), and changes to the script itself belong in
this gem's template so every app picks them up. After bumping to a discharger
release that changed the template, regenerate the script without touching
`config/setup.yml` or the initializer:

```bash
$ bin/rails generate discharger:install --setup-only --force
```

To catch drift in CI, run the check. It exits non-zero when `bin/setup` is missing
or differs from the installed gem's template, and names the command above:

```bash
$ bin/rails discharger:setup:check
```

A script generated elsewhere takes its path as the task argument:
`discharger:setup:check[scripts/setup]`.

### Configuration

The setup process is configured through `config/setup.yml`. Here's an example configuration:

```yaml
app_name: "YourAppName"

database:
  port: 5432
  name: "db-your-app"
  version: "14"
  password: "postgres"
  # Optional. DB_NAME exported before Rails boots; defaults to the container
  # name without "db-". false leaves it to database.yml.
  # db_name: "your-app"
  # Optional. Controls how the docker step handles a native PostgreSQL
  # already listening on the configured port:
  #   omitted/nil/false - silently skip Docker and use the native instance (legacy default)
  #   true              - always create the Docker container; fail if a native instance holds the port
  #   "prompt"          - ask the developer (interactive shells only; non-interactive runs fall back to native)
  prefer_docker: "prompt"

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

### Pre-Rails Steps (Prerequisites)

The `pre_steps` array defines commands that run **before Rails loads**. These are for system dependencies and environment setup that must be in place before bundler or Rails can initialize.

Built-in pre_steps:
- `homebrew` - Installs Homebrew if not present (macOS)
- `postgresql_tools` - Optionally installs PostgreSQL client tools (`pg_dump`, `psql`) for apps that use `structure.sql` or call those tools directly

```yaml
pre_steps:
  - homebrew
  # - postgresql_tools
```

You can also define custom pre_steps with shell commands. `config/**/*.example` and
`.env.example` counterparts are created before `pre_steps` run, so a step can rely
on them, as Qualify's does here:

```yaml
pre_steps:
  - homebrew
  - description: "Check .env against .env.example"
    command: "bin/check-env"
```

### Using Default Steps

The `steps` array specifies which built-in setup commands to run. Available commands include:

- `brew` - Install Homebrew dependencies
- `asdf` - Setup version management with asdf
- `git` - Configure git settings
- `github_packages` - Check the GitHub CLI token against a private GitHub Packages gem source; the generated `bin/setup` stores the credentials (requires a `github_packages.source` config entry)
- `bundler` - Install Ruby gems; a check under the generated `bin/setup`, whose first pass already installed the bundle
- `yarn` - Install JavaScript packages
- `config` - Copy Procfile.dev to Procfile and any example config file still missing
- `docker` - Setup Docker containers
- `pg_tools` - Create Docker-aware `pg_dump` and `psql` wrappers for apps that use `structure.sql` or call those tools directly
- `env` - Create .env from .env.example if still missing
- `database` - Drop and recreate the development and test databases, load the schema, migrate, and seed. Every run resets local data.

### Selecting Specific Steps

You can customize which steps run by modifying the `steps` array:

```yaml
# Only run specific setup steps
steps:
  - bundler
  - database
  - yarn
```

Leave the array empty or omit it entirely to run all available steps, in the order listed above. Custom commands registered through `Discharger::SetupRunner.register_command` run last.

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
- `name` - An optional name that lets the step be scheduled in the `steps` list

Custom steps run after the built-in steps, in the order listed. To run one
earlier, give it a `name` and list that name in `steps`:

```yaml
custom_steps:
  - name: import_certs
    description: "Import development certificates"
    command: "bin/import-certs"

steps:
  - brew
  - import_certs  # runs between brew and bundler
  - bundler
```

A named step listed in `steps` runs only at that position; named steps that
are not listed keep the default run-last behavior. A name that collides with
a built-in step resolves to the built-in, and a warning is logged.

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

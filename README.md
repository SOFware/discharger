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
end
```

It will make Rake tasks available to push code to branches and notify Slack channels.

```bash
$ rake -T release
rake release                            # ---------- STEP 3 ----------
rake release:build                      # Release the current version to stage
rake release:prepare                    # ---------- STEP 1 ----------
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

Or install it yourself as:
```bash
$ gem install discharger
```

## Contributing

This gem is managed with [Reissue](https://github.com/SOFware/reissue).

Bug reports and pull requests are welcome on GitHub.

## License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

# Using Git Commit Trailers with Discharger

How to get git trailer support enabled.

## Enable Git Trailers

Update the Rakefile configuration:

```ruby
Reissue::Task.create :reissue do |task|
  task.version_file = "lib/discharger/version.rb"
  task.fragment = :git  # Add this line
  task.commit = !ENV["GITHUB_ACTIONS"]
  task.commit_finalize = !ENV["GITHUB_ACTIONS"]
  task.push_finalize = :branch
  task.clear_fragments = true
end
```

## Write Commits with Trailers

Add changelog sections as trailers in your commit messages:

```bash
git commit -m "Implement background job processing

Added: Async task execution
Added: Job retry mechanism
Fixed: Race condition in task queue
Security: Input sanitization for task parameters"
```

## Supported Sections

- **Added:** New features
- **Changed:** Modifications to existing functionality
- **Deprecated:** Soon-to-be removed features
- **Removed:** Deleted features
- **Fixed:** Bug fixes
- **Security:** Vulnerability patches

Trailers are extracted automatically during `rake build` and merged into CHANGELOG.md.

## Key Benefits

- Keep changelog data coupled with code changes in the same commit
- No need to maintain separate fragment files or remember to update CHANGELOG.md
- Changelog entries are automatically extracted during the build process
- Case-insensitive trailer matching for flexibility

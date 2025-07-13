# Changelog Fragments

This document describes the changelog fragments feature in Discharger, which
helps reduce merge conflicts in `CHANGELOG.md` by allowing each feature branch
to contribute small fragment files that are automatically processed during
release preparation.

## Overview

Instead of having multiple developers edit the same `CHANGELOG.md` file (which
frequently causes merge conflicts), changelog fragments allow each feature
branch to create small, focused files that describe their changes. These
fragments are automatically processed and merged into the main changelog during
the release preparation process.

## Benefits

- **Reduced merge conflicts**: No more conflicts in `CHANGELOG.md`
- **Better organization**: Changes are organized by type (Added, Fixed, etc.)
- **Cleaner history**: Each feature branch only touches its own fragment file
- **Automated processing**: Fragments are automatically merged during release
- **Consistent formatting**: Automatic bullet point formatting and section organization

## Configuration

Enable changelog fragments in your Discharger task configuration:

```ruby
# config/initializers/discharger.rb or in your Rakefile
Discharger::Task.create do |task|
  # ... other configuration ...

  # Enable changelog fragments
  task.changelog_fragments_enabled = true

  # Optional: customize the fragments directory (default: "changelog/unreleased")
  task.changelog_fragments_dir = "changelog/unreleased"

  # Optional: customize valid changelog sections (default shown below)
  task.changelog_sections = ["Added", "Changed", "Deprecated", "Removed", "Fixed", "Security"]
end
```

## Setup

### 1. Create the fragments directory structure

```bash
mkdir -p changelog/unreleased
```

You should create:

- `changelog/unreleased/` directory
- Optionally, a `.gitkeep` file to ensure the directory is tracked in git

### 2. Ensure your CHANGELOG.md has an "Unreleased" section

Your `CHANGELOG.md` should have a section like:

```markdown
# Changelog

## [1.2.0] - Unreleased

## [1.1.0] - 2024-01-15

### Added

- Previous features...
```

## Usage

### Creating Fragment Files

#### Creating Fragment Files

**Note:** Fragment file names are case-insensitive. Files named
`added.feature.md`, `fIxEd.bug.md`, or `Security.patch.md` will all work
correctly.

Create files in `changelog/unreleased/` following the naming convention:
`{section}.{short-summary}.md`

**Examples:**

- `Added.webhook-support.md`
- `Fixed.database-connection.md`
- `cHanGed.api-response-format.md`
- `Security.csrf-protection.md`

### File Content Format

Each fragment file should contain one or more bullet points describing the change:

```markdown
- Added webhook support for real-time notifications
- Implemented webhook retry mechanism with exponential backoff
```

Or for single-line changes:

```markdown
Fixed database connection pool exhaustion during high traffic periods
```

**Notes:**

- If content doesn't start with a bullet point (`-` or `*`), it will be automatically converted
- Empty lines and whitespace are automatically cleaned up
- Multiple bullet points are supported

### Valid Sections

By default, the following sections are supported:

- `Added` - for new features
- `Changed` - for changes in existing functionality
- `Deprecated` - for soon-to-be removed features
- `Removed` - for now removed features
- `Fixed` - for any bug fixes
- `Security` - in case of vulnerabilities

Files with invalid section names will be ignored during processing.

## Processing

### Automatic Processing

When you run `rake release:prepare`, changelog fragments are automatically:

1. **Collected**: All valid fragment files are read from the fragments directory
2. **Organized**: Content is grouped by changelog section
3. **Inserted**: Content is added to the "Unreleased" section of `CHANGELOG.md`
4. **Cleaned up**: Fragment files are deleted after successful processing

### Manual Processing

For testing or debugging, you can manually process fragments:

```bash
# Process fragments without running the full release preparation
rake release:process_fragments

# List all current fragment files
rake release:fragments
```

## Example Workflow

Here's a typical workflow using changelog fragments:

### 1. Developer creates a feature branch

```bash
git checkout -b feature/user-authentication
# ... develop the feature ...
```

### 2. Developer creates a changelog fragment

```bash
# Create the fragment file manually
echo "- Added JWT authentication system with refresh tokens" > changelog/unreleased/Added.user-auth.md
```

This creates `changelog/unreleased/Added.user-auth.md`:

```markdown
- Added JWT authentication system with refresh tokens
```

### 3. Developer commits the fragment with their feature

```bash
git add changelog/unreleased/Added.user-auth.md
git commit -m "Add user authentication with changelog fragment"
```

### 4. Feature branch is merged to develop

```bash
git checkout develop
git merge feature/user-authentication
```

### 5. Release manager prepares the release

```bash
rake release:prepare
```

During this process:

- The fragment file is processed and added to `CHANGELOG.md`
- The fragment file is deleted
- The changelog is updated and committed

## Advanced Usage

### Custom Sections

You can add custom sections by modifying the configuration:

```ruby
task.changelog_sections = [
  "Added", "Changed", "Deprecated", "Removed", "Fixed", "Security",
  "Performance", "Documentation"
]
```

### Custom Fragment Directory

```ruby
task.changelog_fragments_dir = "docs/changelog-fragments"
```

### Disabling Fragments

```ruby
task.changelog_fragments_enabled = false
```

## Troubleshooting

### Fragment files not being processed

- Check that `changelog_fragments_enabled = true` in your configuration
- Verify the fragment directory exists and contains `.md` files
- Ensure fragment filenames follow the `{section}.{summary}.md` pattern
- Check that the section name is in the allowed `changelog_sections` list

### CHANGELOG.md not being updated

- Verify your `CHANGELOG.md` has an "Unreleased" section
- Check that the unreleased section follows the expected format: `## [version] - Unreleased`
- Ensure the file is writable

### Fragment files not being deleted

- Check file permissions on the fragment directory
- Verify no other process is holding the files open
- Only fragments with valid section names are deleted

## Integration with Existing Workflows

### With GitHub/GitLab

Add fragment file creation to your pull request templates:

```markdown
## Changelog

- [ ] Added changelog fragment (if user-facing changes)
- [ ] Fragment file follows naming convention: `{section}.{summary}.md`
```

### With CI/CD

You can add a check to ensure fragments are created for certain types of changes:

```bash
# Check if changelog fragment exists for feature branches
if [[ $BRANCH_NAME == feature/* ]]; then
  if [ -z "$(ls changelog/unreleased/ 2>/dev/null)" ]; then
    echo "Error: Feature branch must include changelog fragment"
    exit 1
  fi
fi
```

## Migration from Manual Changelog Editing

1. Enable changelog fragments in your Discharger configuration
2. Create the fragments directory: `mkdir -p changelog/unreleased`
3. For existing unreleased changes, consider creating fragments retroactively
4. Update your team's workflow documentation
5. Add fragment creation to your PR checklist/template

## Best Practices

1. **One fragment per logical change**: Don't combine unrelated changes in a single fragment
2. **Use descriptive summaries**: The filename should clearly indicate what changed
3. **Write user-facing descriptions**: Focus on how changes affect users, not implementation details
4. **Choose the right section**: Use "Added" for new features, "Fixed" for bug fixes, etc.
5. **Review fragment content**: Ensure the content is clear and grammatically correct
6. **Include fragments in PRs**: Always commit fragment files with the changes they describe

## Example Fragment Files

### Added.webhook-support.md

```markdown
- Added webhook support for real-time notifications
- Implemented webhook retry mechanism with exponential backoff
- Added webhook signature validation for security
```

### fixed.database-connection.md (case-insensitive)

```markdown
- Fixed database connection pool exhaustion during high traffic periods
- Resolved deadlock issue in concurrent transaction handling
```

### SECURITY.csrf-protection.md (case-insensitive)

```markdown
- Enhanced CSRF protection with SameSite cookie attributes
- Added additional validation for cross-origin requests
- Updated security headers to prevent clickjacking
```

### changed.api-response-format.md (case-insensitive)

```markdown
- Updated API response format to include pagination metadata
- Changed error response structure for better client handling
- Modified timestamp format to use ISO 8601 standard
```

## Support

For questions or issues with changelog fragments:

1. Check this documentation
2. Review the example files in `examples/changelog_fragments_demo/`
3. Run `rake release:fragments` to debug current fragment files
4. Check the main Discharger documentation
5. Create an issue in the Discharger repository

# Setting up Trusted Publishing for Discharger

This guide explains how to configure GitHub Actions as a trusted publisher for the Discharger gem on RubyGems.org.

## Prerequisites

- Admin access to the Discharger gem on RubyGems.org
- Admin access to the GitHub repository

## Setup Steps

### 1. Configure RubyGems.org

1. Log in to [RubyGems.org](https://rubygems.org)
2. Navigate to your gem's page: https://rubygems.org/gems/discharger
3. Click on "Ownership" in the sidebar
4. Click on "Trusted Publishers" tab
5. Click "Create Trusted Publisher"
6. Fill in the following information:
   - **GitHub Repository**: `SOFware/discharger`
   - **Workflow filename**: `release.yml`
   - **Environment name**: Leave blank (unless you want to use environments)
7. Click "Create Trusted Publisher"

### 2. Update GitHub Actions Workflow

The release workflow has been updated to use OIDC (OpenID Connect) for authentication instead of API keys. The workflow now:

1. Runs when a PR with the `approved-release` label is merged to main
2. Uses the `id-token: write` permission to get OIDC tokens
3. Authenticates with RubyGems.org using the trusted publisher configuration

### 3. Remove API Key (Optional but Recommended)

Once trusted publishing is working:

1. Remove the `RUBYGEMS_API_KEY` secret from GitHub repository settings
2. The `GEM_HOST_API_KEY` environment variable in the workflow can be removed

## How the Release Process Works

1. **Trigger Release Preparation**:
   - Go to Actions → "Prepare Release" → Run workflow
   - Select version type (major, minor, patch, or custom)
   - This creates a PR with version bumps and changelog updates

2. **Review and Approve**:
   - Review the PR created by the workflow
   - Ensure version and changelog are correct
   - Add the `approved-release` label to the PR
   - Merge the PR

3. **Automatic Release**:
   - When the PR is merged, the release workflow automatically runs
   - It uses trusted publishing to authenticate with RubyGems.org
   - The gem is built and published

## Benefits of Trusted Publishing

- **No API keys to manage**: Authentication happens via OIDC tokens
- **More secure**: Tokens are short-lived and scoped to specific workflows
- **Audit trail**: All releases are tied to specific workflow runs
- **No secrets rotation**: No need to update secrets when they expire

## Troubleshooting

If the release fails with authentication errors:

1. Verify the trusted publisher is configured correctly on RubyGems.org
2. Ensure the workflow filename matches exactly
3. Check that the repository name is correct (case-sensitive)
4. Verify the `id-token: write` permission is present in the workflow

## References

- [RubyGems Trusted Publishing Guide](https://guides.rubygems.org/trusted-publishing/)
- [GitHub OIDC Documentation](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
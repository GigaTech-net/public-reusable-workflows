# Create Pull Request Composite Action

A comprehensive composite action for creating pull requests with advanced features including conflict detection, template-based descriptions, and conventional commit titles.

## Features

- ✅ **Conflict Detection**: Automatically detects merge conflicts before PR creation
- ✅ **Existing PR Check**: Prevents duplicate PRs by checking for existing open PRs
- ✅ **Rate Limiting**: Implements configurable delays to prevent rapid PR creation
- ✅ **Template-based Body**: Generates rich PR descriptions with change summaries and CI links
- ✅ **Conventional Commits**: Uses `chore:` prefix for maintenance PRs as per conventional commit standards
- ✅ **Flexible Conflict Handling**: Multiple strategies for handling merge conflicts

## Usage

### Basic Usage

```yaml
- name: Create Pull Request
  uses: ./.github/actions/create-pr
  with:
    base-branch: "main"
    head-branch: "development"
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Advanced Usage

```yaml
- name: Create Pull Request with Custom Settings
  uses: ./.github/actions/create-pr
  with:
    base-branch: "main"
    head-branch: "feature/updates"
    github-token: ${{ secrets.GITHUB_TOKEN }}
    pr-description: "Additional context for this PR"
    delay-seconds: "60"
    conflict-strategy: "alert"
```

## Inputs

| Input               | Description                                                         | Required | Default   |
| ------------------- | ------------------------------------------------------------------- | -------- | --------- |
| `base-branch`       | The target branch to merge into                                     | ✅       | -         |
| `head-branch`       | The source branch to merge from                                     | ✅       | -         |
| `github-token`      | GitHub token for API operations                                     | ✅       | -         |
| `pr-description`    | Additional description for the PR                                   | ❌       | `''`      |
| `delay-seconds`     | Delay before creating PR to prevent rapid creation                  | ❌       | `'30'`    |
| `conflict-strategy` | Strategy for handling conflicts: `alert`, `skip`, `attempt-resolve` | ❌       | `'alert'` |

## Outputs

| Output               | Description                           |
| -------------------- | ------------------------------------- |
| `pr-number`          | The number of the created PR          |
| `pr-url`             | The URL of the created PR             |
| `conflicts-detected` | Whether merge conflicts were detected |
| `pr-created`         | Whether a PR was successfully created |

## Conflict Handling Strategies

### `alert` (Default)

- Detects conflicts and stops execution
- Provides detailed error messages with conflicted files
- Requires manual resolution

### `skip`

- Detects conflicts and skips PR creation
- Logs warning but continues workflow

### `attempt-resolve`

- Currently logs error (auto-resolution not yet implemented)
- Future enhancement for simple conflict resolution

## Generated PR Template

The action automatically generates a comprehensive PR description including:

- **Summary of Changes**: Recent commits and file modifications
- **Files Changed**: Count and list of modified files
- **CI/CD Status**: Links to workflow runs and build status
- **Additional Notes**: Custom description if provided
- **Metadata**: Timestamp and generation info

## PR Title Convention

Follows conventional commit standards with `chore:` prefix:

```text
chore: maint - [descriptive phrase] from [head-branch] to [base-branch]
```

Examples:

- `chore: maint - update existing functionality from development to main`
- `chore: maint - add new files and features from feature/auth to main`
- `chore: maint - remove obsolete files and cleanup from hotfix to main`

## Permissions Required

The GitHub token must have the following permissions:

- `contents: write` - To access repository content
- `pull-requests: write` - To create and manage PRs

## Error Handling

The action handles various scenarios gracefully:

- **No Changes**: Skips PR creation if no differences detected
- **Existing PRs**: Prevents duplicate PRs and reports existing PR details
- **Merge Conflicts**: Detects conflicts and handles per strategy
- **API Errors**: Provides clear error messages for GitHub API issues

## Migration from Reusable Workflow

If migrating from the deprecated `rw-create-pr.yaml` workflow:

### Before (Reusable Workflow)

```yaml
jobs:
  create-pr:
    uses: ./.github/workflows/rw-create-pr.yaml
    with:
      head-branch: "development"
      base-branch: "main"
    secrets:
      GT_DEVSECOPS_PAT: ${{ secrets.GT_DEVSECOPS_PAT }}
```

### After (Composite Action)

```yaml
jobs:
  create-pr:
    runs-on: ubuntu-latest
    steps:
      - name: Create Pull Request
        uses: ./.github/actions/create-pr
        with:
          base-branch: "main"
          head-branch: "development"
          github-token: ${{ secrets.GT_DEVSECOPS_PAT }}
```

## Examples

### Cron Job Usage

Perfect for automated maintenance PRs from cron jobs:

```yaml
name: Automated Maintenance PR
on:
  schedule:
    - cron: "0 2 * * 1" # Weekly on Monday at 2 AM

jobs:
  maintenance-pr:
    runs-on: ubuntu-latest
    steps:
      - name: Create Maintenance PR
        uses: ./.github/actions/create-pr
        with:
          base-branch: "main"
          head-branch: "development"
          github-token: ${{ secrets.GITHUB_TOKEN }}
          pr-description: "Weekly maintenance sync from development branch"
          delay-seconds: "45"
```

### Feature Branch Sync

```yaml
- name: Sync Feature Branch
  uses: ./.github/actions/create-pr
  with:
    base-branch: "main"
    head-branch: "feature/new-auth"
    github-token: ${{ secrets.GITHUB_TOKEN }}
    conflict-strategy: "skip"
    pr-description: "Syncing authentication feature updates"
```

## Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure the GitHub token has required permissions
2. **Conflicts Detected**: Review conflicted files and resolve manually
3. **Existing PR Found**: Check if an open PR already exists for the branches
4. **No Changes**: Verify there are actual differences between branches

### Debug Information

The action provides comprehensive logging including:

- Change detection results
- Conflict analysis
- Existing PR checks
- PR creation status
- Summary output with all key information

## Contributing

When contributing to this action:

1. Follow the existing code style and structure
2. Add appropriate error handling and logging
3. Update documentation for any new features
4. Test with various branch scenarios
5. Ensure semantic versioning for action references (as per user preference)

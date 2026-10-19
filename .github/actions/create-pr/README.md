# Create Pull Request Composite Action

A comprehensive composite action for creating pull requests with advanced features including conflict detection, template-based descriptions, and conventional commit titles.

## Features

- ✅ **Conflict Detection**: Automatically detects merge conflicts before PR creation
- ✅ **Existing PR Check**: Prevents duplicate PRs by checking for existing open PRs
- ✅ **Rate Limiting**: Implements configurable delays to prevent rapid PR creation
- ✅ **Template-based Body**: Generates rich PR descriptions with change summaries and CI links
- ✅ **Conventional Commits**: Uses `chore:` prefix for maintenance PRs as per conventional commit standards
- ✅ **Flexible Conflict Handling**: Multiple strategies for handling merge conflicts
- ✅ **Loud Failure**: A conflict that blocks PR creation fails the job, so scheduled runs are not silently green

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

Under `alert` and `attempt-resolve` a conflict fails the action, so a caller
step that reads these outputs must opt in to running after a failure:

```yaml
- name: Create Pull Request
  id: create-pr
  continue-on-error: true
  uses: GigaTech-net/public-reusable-workflows/.github/actions/create-pr@v1
  with:
    base-branch: "main"
    head-branch: "development"
    github-token: ${{ env.GITHUB_TOKEN }}

- name: Report
  if: always()
  run: |
    echo "conflicts: ${{ steps.create-pr.outputs.conflicts-detected }}"
    echo "created:   ${{ steps.create-pr.outputs.pr-created }}"
```

`conflicts-detected` is written by the conflict-check step, which succeeds, so
it is `true` on a conflict run. `pr-created` is empty whenever no PR was
opened. Note that `continue-on-error: true` restores the silent-success
behaviour this action was changed to remove — use it only where the caller
itself fails the job on `conflicts-detected == 'true'`.

## Conflict Handling Strategies

The strategy decides one thing: whether a conflict that blocks PR creation is
an error or an expected condition.

| Strategy          | Annotation    | PR opened | Step exit | Job conclusion |
| ----------------- | ------------- | --------- | --------- | -------------- |
| `alert` (default) | `::error::`   | No        | `1`       | `failure`      |
| `attempt-resolve` | `::error::`   | No        | `1`       | `failure`      |
| `skip`            | `::warning::` | No        | `0`       | `success`      |

### `alert` (Default)

- Detects conflicts, names the conflicted files in an `::error::` annotation,
  and **exits 1**, failing the job
- Requires manual resolution

### `attempt-resolve`

- Auto-resolution is not implemented; behaves as `alert`
- Emits an `::error::` annotation and **exits 1**, failing the job

### `skip`

- Detects conflicts, names the conflicted files in a `::warning::` annotation,
  and **exits 0**
- Choose this only where a conflict on these branches is expected and
  tolerable. The run stays green and nobody is notified.

### Why a conflict fails the job

GitHub notifies the repository on a **failed** scheduled run and says nothing
about a successful one. An action whose entire purpose is to open a PR must
therefore not report success when it opened nothing: that failure mode is
invisible by construction.

It was. Across six GigaTECH repositories the weekly `development` → `main` PR
stopped being created on 2026-08-04 and nobody noticed for eleven consecutive
weekly runs, because the conflict step emitted `::error::` annotations and then
fell through to exit 0. Run
[gigatech-website #38449438059](https://github.com/GigaTech-net/gigatech-website/actions/runs/38449438059)
is a reference case: `##[error]Merge conflicts detected in files: ...` on a run
whose conclusion is `success`.

Under `alert` and `attempt-resolve` the step now exits 1. The `skip` strategy
is the deliberate opt-out.

### Green runs that open no PR

Failing on a conflict does not make every PR-less run a failure. These three
outcomes are ordinary and stay green, because in each one the action's purpose
is already served or there is nothing to do:

| Outcome             | Why it is green                                          |
| ------------------- | -------------------------------------------------------- |
| No changes detected | The branches are identical; there is nothing to merge    |
| Existing open PR    | The PR this run would create already exists              |
| Recent PR activity  | Rate limiting via `delay-seconds` suppressed a duplicate |

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
- **Merge Conflicts**: Detects conflicts and handles per strategy; `alert` and `attempt-resolve` fail the job, `skip` does not
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
    secrets: inherit
```

### After (Composite Action)

```yaml
jobs:
  create-pr:
    runs-on: ubuntu-latest
    steps:
      - name: Setup GitHub token
        # env.GITHUB_TOKEN below is written by this step. Without it the input
        # is empty and the action fails at its first API call.
        uses: GigaTech-net/public-reusable-workflows/.github/actions/setup-token@v1
        with:
          app_id: ${{ secrets.KEYROTATION_APPID_GT_GH }}
          private_key: ${{ secrets.KEYROTATION_PVTKEY_GT_GH }}

      - name: Create Pull Request
        uses: ./.github/actions/create-pr
        with:
          base-branch: "main"
          head-branch: "development"
          github-token: ${{ env.GITHUB_TOKEN }}
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

## Versioning and Release

Consumers pin the moving major tag:

```yaml
uses: GigaTech-net/public-reusable-workflows/.github/actions/create-pr@v1
```

`.github/workflows/main-release.yaml` runs on every push to `main`. It derives
the bump from the merged commits' conventional-commit types, cuts the new
semver tag, and force-pushes `v1` at the same commit. Merging a change to this
action is therefore all that is required to reach every `@v1` consumer; they
pick it up on their next scheduled run. No manual tagging step exists.

Making a conflict fail the job ships on `v1` rather than behind a `v2`. It
changes what consumers see — a conflicting branch now turns their scheduled run
red — but the previous silence was the defect, and the README already documented
`alert` as stopping execution. A consumer that genuinely wants a conflict
tolerated sets `conflict-strategy: skip` rather than pinning an older tag.

## Contributing

When contributing to this action:

1. Follow the existing code style and structure
2. Add appropriate error handling and logging
3. Update documentation for any new features
4. Test with various branch scenarios
5. Ensure semantic versioning for action references (as per user preference)

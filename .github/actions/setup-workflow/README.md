# Setup Workflow Composite Action

This composite action replaces the `rw-setup.yaml` reusable workflow to improve efficiency by running setup operations on the same runner.

## What it does

- Checks out the repository with full Git history
- Determines semantic version information using Git tags
- Extracts the current branch name

## Outputs

| Output              | Description                                                  |
| ------------------- | ------------------------------------------------------------ |
| `current-version`   | The current latest version from Git tags (SemVer format)     |
| `current-v-version` | The current latest version prefixed with 'v' (SemVer format) |
| `version`           | The incremented version number (next version, SemVer format) |
| `v-version`         | The incremented version prefixed with 'v' (SemVer format)    |
| `pre-release-label` | Prerelease label of the incremented version                  |
| `branch`            | The current GitHub branch                                    |

## Usage

```yaml
steps:
  - name: Setup workflow environment
    id: setup
    uses: GigaTech-net/public-reusable-workflows/.github/actions/setup-workflow@main

  - name: Use outputs
    run: |
      echo "Current version: ${{ steps.setup.outputs.current-version }}"
      echo "Next version: ${{ steps.setup.outputs.version }}"
      echo "Branch: ${{ steps.setup.outputs.branch }}"
```

## Efficiency Benefits

- Combines checkout, version detection, and branch extraction in a single action
- Runs on the same runner as other steps, reducing job startup overhead
- Provides same functionality as the original `rw-setup.yaml` workflow

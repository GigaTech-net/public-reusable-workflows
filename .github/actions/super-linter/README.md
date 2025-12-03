# Super Linter Composite Action

This composite action runs GitHub Super Linter with environment file support, replacing direct Super Linter usage to improve efficiency and provide better configuration management.

## What it does

- Checks out the repository with full Git history
- Loads configuration from `.github/super-linter.env` if it exists
- Runs GitHub Super Linter with the loaded configuration
- Supports environment variable overrides

## Inputs

| Input           | Description                               | Required | Default                    |
| --------------- | ----------------------------------------- | -------- | -------------------------- |
| `github_token`  | GitHub token for authentication           | No       | `${{ github.token }}`      |
| `env_file_path` | Path to the Super Linter environment file | No       | `.github/super-linter.env` |
| `run_local`     | Override RUN_LOCAL setting                | No       | `false`                    |

## Usage

```yaml
steps:
  - name: Super Linter
    uses: GigaTech-net/public-reusable-workflows/.github/actions/super-linter@main
```

### With custom parameters

```yaml
steps:
  - name: Super Linter with custom settings
    uses: GigaTech-net/public-reusable-workflows/.github/actions/super-linter@main
    with:
      github_token: ${{ secrets.GITHUB_TOKEN }}
      env_file_path: .github/custom-linter.env
      run_local: true
```

## Environment File Support

The action automatically loads environment variables from the specified env file (default: `.github/super-linter.env`). This replaces the non-functional `env-file` parameter from the original Super Linter action.

Example `.github/super-linter.env`:

```env
FILTER_REGEX_EXCLUDE=report/.*
IGNORE_GITIGNORED_FILES=true
LOG_LEVEL=WARN
RUN_LOCAL=true
USE_FIND_ALGORITHM=true
VALIDATE_ALL_CODEBASE=true
```

## Efficiency Benefits

- Combines checkout and linting in a single action
- Runs on the same runner as other steps, reducing job startup overhead
- Provides proper environment file loading that the original Super Linter lacks
- Maintains all Super Linter functionality with better configuration management

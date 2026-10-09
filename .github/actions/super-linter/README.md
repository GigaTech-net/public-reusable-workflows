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

## Upgrading Super Linter across a major version

Dependabot offers minor and patch bumps of `super-linter/super-linter` weekly
and they merge as normal. Majors are suppressed in `.github/dependabot.yml`
and are done by hand, because a major changes the version of every tool
Super Linter bundles and `v1` hands that to every consumer on the next
release.

v9.0.0 enabled no new linters and still broke three consumer files that
nobody had edited: a Checkstyle module that had been removed, a Prettier
reindent, and a hadolint rule that had become an error.

To do one:

1. Pick the candidate and run it against a consumer, from a clone with real
   Git metadata (a worktree's `.git` file does not resolve inside the
   container):

   ```bash
   docker run --rm --platform linux/amd64 \
     $(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' -e 's/^/-e /' .github/super-linter.env) \
     -e RUN_LOCAL=true -e LOG_LEVEL=NOTICE \
     -v "$PWD":/tmp/lint \
     ghcr.io/super-linter/super-linter:slim-vX.Y.Z
   ```

   The published image is `super-linter:slim-vX.Y.Z`, not
   `super-linter/slim:vX.Y.Z`.

2. Repeat for each consumer whose languages differ — a Java repository, a
   CSS one, a Terraform one. The linters that run are decided by the files
   present, so one repository does not cover another.

3. Fix the fallout in those repositories first, then bump the pin in
   `action.yaml` in its own PR. Consumers pick it up when `v1` moves.

Super Linter can apply many of its own corrections: re-run with
`FIX_<LINTER>=true` alongside `VALIDATE_<LINTER>=true` and commit what it
writes. Run it twice — a fixer can disturb formatting an earlier fixer
settled, and the second pass restores it.

## Efficiency Benefits

- Combines checkout and linting in a single action
- Runs on the same runner as other steps, reducing job startup overhead
- Provides proper environment file loading that the original Super Linter lacks
- Maintains all Super Linter functionality with better configuration management

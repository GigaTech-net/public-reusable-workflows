# Super Linter Composite Action

This composite action runs GitHub Super Linter with environment file support, replacing direct Super Linter usage to improve efficiency and provide better configuration management.

## What it does

- Loads configuration from `.github/super-linter.env` if it exists
- Runs GitHub Super Linter with the loaded configuration, started with
  `docker run` (see [How Super Linter is started](#how-super-linter-is-started))
- Supports environment variable overrides
- Skips the lint, and Super Linter's image pull, when no changed file is in an enabled language (see [When Super Linter is skipped](#when-super-linter-is-skipped))

## Inputs

| Input           | Description                                                                                            | Required | Default                    |
| --------------- | ------------------------------------------------------------------------------------------------------ | -------- | -------------------------- |
| `github_token`  | GitHub token for authentication                                                                        | No       | `${{ github.token }}`      |
| `env_file_path` | Path to the Super Linter environment file                                                              | No       | `.github/super-linter.env` |
| `run_local`     | Override RUN_LOCAL setting                                                                             | No       | `false`                    |
| `language_gate` | `true` skips Super Linter when no changed file is in an enabled language; anything else always runs it | No       | `true`                     |

## Outputs

| Output        | Description                                                           |
| ------------- | --------------------------------------------------------------------- |
| `ran`         | `false` when the language gate skipped Super Linter; `true` otherwise |
| `gate_reason` | One line explaining the gate's decision                               |

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

## When Super Linter is skipped

The action decides before it pulls the Super Linter image. It skips the step,
and the pull with it, only when all of these hold:

- The configuration enables linters with `VALIDATE_<LANGUAGE>=true` only.
- No changed path is in one of those languages.
- No changed path is lint configuration.

`VALIDATE_ALL_CODEBASE` does not matter: with no changed file in scope and no
configuration change, every file Super Linter would lint is unchanged since
the base was linted.

The `VALIDATE_*` values are read after the env file is loaded, so values set in
job-level `env:` count too.

### Lint configuration always runs

- The env file in use (`env_file_path`) and any `.github/super-linter*.env`.
- Anything under `LINTER_RULES_PATH` (default `.github/linters`). When it is
  the repository root, only the known names below apply.
- Known root config files (`LINT_CONFIG_GLOBS` in `language-gate.sh`):
  `.yamllint*`, `.markdown-lint.*`, `.shellcheckrc`, `.hadolint.*`,
  `actionlint.*`, `pyproject.toml` and the rest of that list.

### Super Linter always runs when

- A changed path is quoted by git (it holds a quote, backslash or control
  character).
- No `VALIDATE_*` language key is set.
- Only `=false` keys are set, or `=true` and `=false` are mixed.
- A value is not exactly `true` or `false`.
- An enabled key is not in the gate's table (`language_globs` in
  `language-gate.sh`).
- The change set cannot be determined: no full history (use
  `actions/checkout` with `fetch-depth: 0`), an unknown base, or an event other
  than `push` or `pull_request`.
- The change set is empty.
- `language_gate` is not `true`.

If the gate step itself crashes, the action fails rather than running Super
Linter anyway: for that one mode the gate fails closed. The gate checks its
inputs and exits 0 with `run=true` on any uncertainty, so a crash means a bug
in the gate, which should be visible.

### Notes

- Paths match the language globs case-insensitively (`README.MD` is
  Markdown).
- Shell linters treat a file with no extension, or with an extension not known
  to be non-shell (`.envrc`, `.bashrc`, `deploy.run`), as a shell script.
- When `LINTER_RULES_PATH` is the repository root, any root-level dotfile
  counts as lint configuration.
- `DEFAULT_BRANCH` set in the env file is used to find the diff base on push;
  the repository's default branch is the fallback.
- `FILTER_REGEX_EXCLUDE` and `FILTER_REGEX_INCLUDE` are not consulted, so the
  gate can run Super Linter on a change that Super Linter then filters out
  entirely.
- Workflow and action files run only when `GITHUB_ACTIONS` or
  `GITHUB_ACTIONS_ZIZMOR` is enabled. A linter turned on through a workflow's
  job-level `env:` rather than the env file is not seen as a configuration
  change.
- Run the tests with `bash .github/actions/super-linter/language-gate-test.sh`
  and `bash .github/actions/super-linter/run-super-linter-test.sh`.

## How Super Linter is started

The action runs `docker run` on `ghcr.io/super-linter/super-linter:slim-vX.Y.Z`
from a bash step (`run-super-linter.sh`), not `uses: super-linter/...`. The
runner pre-pulls the image of every Docker container action nested in a
composite action while it sets the job up, whatever the step's `if:` says, so a
skipped `uses:` step still pays the ~1 GB pull. A bash step that the gate's
`if:` skips never reaches `docker`.

The script gives the container what the runner gives a container action: the
workspace at `/github/workspace`, the runner's `_github_home`,
`_github_workflow` and `_runner_file_commands` directories at `/github/...`,
the job environment (passed by name, never on the command line) and container
paths for `GITHUB_WORKSPACE`, `GITHUB_EVENT_PATH` and the file-command files.
The exit status is Super Linter's.

**Dependabot no longer bumps Super Linter.** It reads `uses:` references, not
an image named in a script. The version is `SUPER_LINTER_IMAGE` in the "Run
Super Linter" step of `action.yaml`; a bump is that one line, by hand.

## Upgrading Super Linter across a major version

Dependabot no longer proposes Super Linter bumps (see above), so every bump is
by hand. Take a major with care: it changes the version of every tool Super
Linter bundles and `v1` hands that to every consumer on the next release.

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
   `SUPER_LINTER_IMAGE` in `action.yaml` in its own PR.
   Consumers pick it up when `v1` moves.

Super Linter can apply many of its own corrections: re-run with
`FIX_<LINTER>=true` alongside `VALIDATE_<LINTER>=true` and commit what it
writes. Run it twice — a fixer can disturb formatting an earlier fixer
settled, and the second pass restores it.

## Efficiency Benefits

- Combines checkout and linting in a single action
- Runs on the same runner as other steps, reducing job startup overhead
- Provides proper environment file loading that the original Super Linter lacks
- Maintains all Super Linter functionality with better configuration management

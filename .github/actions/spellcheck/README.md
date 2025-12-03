# Spell check Composite Action

This composite action replaces the `rw-spellcheck.yaml` reusable workflow to improve efficiency by running spell check operations on the same runner.

## What it does

- Checks out the repository with full Git history
- Installs codespell in a Python virtual environment
- Downloads the codespell dictionary
- Performs spell checking with automatic corrections
- Commits and pushes spelling corrections back to the branch

## Inputs

| Input           | Description                                        | Required | Default |
| --------------- | -------------------------------------------------- | -------- | ------- |
| `wordsToIgnore` | Comma separated words to ignore spell checking     | No       | `""`    |
| `filesToIgnore` | Comma separated filenames to ignore spell checking | No       | `""`    |
| `github_token`  | GitHub token for committing changes                | Yes      | -       |

## Default Ignored Files

The action automatically ignores these files and directories:

- `./output`
- `./input-cache`
- `./temp`
- `./template`
- `./fsh-generated`
- `./dictionary.txt`
- `.gitignore`
- `./src`
- `./venv`
- `.dockerignore`
- `Dockerfile`
- `package.json`
- `package-lock.json`

## Default Ignored Words

The action automatically ignores these technical terms:

- `ehr`
- `requestor`
- `promis`
- `loinc`
- `recengine`
- `sdvosb`

## Usage

```yaml
steps:
  - name: Spellcheck
    uses: GigaTech-net/public-reusable-workflows/.github/actions/spellcheck@main
    with:
      github_token: ${{ secrets.GITHUB_TOKEN }}
```

### With custom ignored words and files

```yaml
steps:
  - name: Spellcheck with custom ignores
    uses: GigaTech-net/public-reusable-workflows/.github/actions/spellcheck@main
    with:
      github_token: ${{ secrets.GITHUB_TOKEN }}
      wordsToIgnore: "myword,customterm,acronym"
      filesToIgnore: "CHANGELOG.md,LICENSES.txt"
```

## Automatic Corrections

The action automatically:

- Fixes common spelling mistakes
- Commits corrections with message: `fix: automatic spelling correction on branch {branch_name}`
- Pushes changes back to the current branch
- Skips commit if no changes are detected

**Note:** Developers will need to pull down any spelling corrections made by the action.

## Efficiency Benefits

- Combines checkout, spell check installation, execution, and Git operations in a single action
- Runs on the same runner as other steps, reducing job startup overhead
- Provides same functionality as the original `rw-spellcheck.yaml` workflow

# Validate PR Title Composite Action

This composite action replaces the `rw-validate-pr-title.yaml` reusable workflow to improve efficiency by running PR title validation on the same runner.

## What it does

- Checks out the repository with full Git history
- Validates PR titles against conventional commit standards
- Skips validation for dependabot PRs, bump commits, and hotfixes
- Uses configurable regular expression patterns for ticket validation

## Inputs

| Input              | Description                                                | Required | Default                                            |
| ------------------ | ---------------------------------------------------------- | -------- | -------------------------------------------------- |
| `ticket_key_regex` | The regular expression to validate ticket keys in PR title | No       | `([Pp][Rr][Oo]\|[Hh][Oo][Tt][Ff][Ii][Xx])-\d{2,5}` |
| `pr_title`         | The PR title to validate                                   | No       | `${{ github.event.pull_request.title }}`           |
| `pr_author`        | The PR author login                                        | No       | `${{ github.event.pull_request.user.login }}`      |

## Supported Task Types

The action validates against these conventional commit types:

- `feat` - New features
- `fix` - bugfixes
- `docs` - Documentation changes
- `test` - Test changes
- `ci` - CI/CD changes
- `refactor` - Code refactoring
- `perf` - Performance improvements
- `chore` - Maintenance tasks
- `revert` - Reverting changes

## Usage

```yaml
steps:
  - name: Validate PR title
    uses: GigaTech-net/public-reusable-workflows/.github/actions/validate-pr-title@main
```

### With custom ticket regular expression

```yaml
steps:
  - name: Validate PR title with custom regex
    uses: GigaTech-net/public-reusable-workflows/.github/actions/validate-pr-title@main
    with:
      ticket_key_regex: '([Jj][Ii][Rr][Aa])-\d{1,5}'
```

## Example Valid PR Titles

- `feat: PRO-123 add new authentication feature`
- `fix: HOTFIX-456 resolve critical security vulnerability`
- `docs: PRO-789 update API documentation`

## Efficiency Benefits

- Combines checkout and PR title validation in a single action
- Runs on the same runner as other steps, reducing job startup overhead
- Provides same functionality as the original `rw-validate-pr-title.yaml` workflow

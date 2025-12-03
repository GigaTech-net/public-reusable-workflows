# Secret Scan Composite Action

This composite action replaces the `rw-secret-scan.yaml` reusable workflow to improve efficiency by running secret scanning on the same runner.

## What it does

- Checks out the repository with full Git history
- Performs TruffleHog secret scanning to detect leaked credentials and secrets
- Scans only verified secrets by default

## Inputs

| Input        | Description                           | Required | Default                          |
| ------------ | ------------------------------------- | -------- | -------------------------------- |
| `path`       | Path to scan for secrets              | No       | `./`                             |
| `head`       | The head reference to scan            | No       | `${{ github.ref_name }}`         |
| `extra_args` | Extra arguments to pass to TruffleHog | No       | `--debug --json --only-verified` |

## Usage

```yaml
steps:
  - name: Secret scan
    uses: GigaTech-net/public-reusable-workflows/.github/actions/secret-scan@main
```

### With custom parameters

```yaml
steps:
  - name: Secret scan with custom path
    uses: GigaTech-net/public-reusable-workflows/.github/actions/secret-scan@main
    with:
      path: ./src
      extra_args: --debug --json
```

## Efficiency Benefits

- Combines checkout and secret scanning in a single action
- Runs on the same runner as other steps, reducing job startup overhead
- Provides same functionality as the original `rw-secret-scan.yaml` workflow

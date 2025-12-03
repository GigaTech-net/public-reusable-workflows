# TruffleHog Scan Composite Action (⚠️ DEPRECATED)

⚠️ **DEPRECATION NOTICE**: This action is deprecated. Please use [secret-scan](./../secret-scan/) action instead.

Performs TruffleHog OSS scan to detect leaked credentials and secrets.

## Usage

```yaml
- name: TruffleHog security scan (deprecated)
  uses: GigaTech-net/public-reusable-workflows/.github/actions/trufflehog-scan@main
```

## Recommended Alternative

```yaml
- name: Secret scan (recommended)
  uses: GigaTech-net/public-reusable-workflows/.github/actions/secret-scan@main
```

## Action Details

**Name**: TruffleHog Scan  
**Description**: Performs TruffleHog OSS scan to detect leaked credentials & secrets (deprecated)  
**Replaces**: rw-trufflehog-scan.yaml workflow  
**Status**: ⚠️ DEPRECATED - Use secret-scan instead

## Inputs

| Input        | Description                    | Required | Default                          |
| ------------ | ------------------------------ | -------- | -------------------------------- |
| `scan_path`  | Path to scan for secrets       | No       | `./`                             |
| `base_ref`   | Base reference for scanning    | No       | `''`                             |
| `head_ref`   | Head reference for scanning    | No       | `${{ github.ref_name }}`         |
| `extra_args` | Extra arguments for TruffleHog | No       | `--debug --json --only-verified` |

## Outputs

| Output        | Description                   |
| ------------- | ----------------------------- |
| `scan_status` | Status of the TruffleHog scan |

## Migration Guide

Instead of:

```yaml
- name: TruffleHog scan
  uses: GigaTech-net/public-reusable-workflows/.github/actions/trufflehog-scan@main
```

Use:

```yaml
- name: Secret scan
  uses: GigaTech-net/public-reusable-workflows/.github/actions/secret-scan@main
```

## Related Actions

- [secret-scan](./../secret-scan/) - **RECOMMENDED** Modern secret scanning
- [setup-workflow](./../setup-workflow/) - Common setup tasks
- [validate-pr-title](./../validate-pr-title/) - PR validation

---

**Note**: This action exists for backward compatibility but will display deprecation warnings when run. Please migrate to the secret-scan action for continued support.

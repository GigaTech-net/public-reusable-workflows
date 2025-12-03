# Dependency Check Composite Action

Performs OWASP dependency vulnerability scanning and uploads results as artifacts.

## Usage

```yaml
- name: Dependency vulnerability scan
  uses: GigaTech-net/public-reusable-workflows/.github/actions/dependency-check@main
  with:
    artifact_name: "vulnerability_report"
    retention_days: 7
    working_directory: "."
    oss_index_user: ${{ secrets.SONATYPE_OSS_INDEX_USER }}
    oss_index_api_token: ${{ secrets.SONATYPE_OSS_INDEX_API_TOKEN }}
```

## Action Details

**Name**: Dependency Check  
**Description**: Performs OWASP dependency vulnerability scanning using Dependency-Check and uploads results as artifacts  
**Replaces**: rw-dependency-check.yaml workflow

## Inputs

| Input               | Description                                                      | Required | Default             |
| ------------------- | ---------------------------------------------------------------- | -------- | ------------------- |
| `artifact_name`     | The artifact name to write to GitHub blob storage                | No       | `vulnerability_rpt` |
| `retention_days`    | The number of days to retain the artifact in GitHub blob storage | No       | `1`                 |
| `working_directory` | Working directory for the action                                 | No       | `.`                 |

## Outputs

| Output          | Description                       |
| --------------- | --------------------------------- |
| `artifact_name` | The name of the uploaded artifact |

## Example Usage

### Basic Usage

```yaml
steps:
  - name: Checkout code
    uses: actions/checkout@v5

  - name: Run dependency vulnerability scan
    uses: GigaTech-net/public-reusable-workflows/.github/actions/dependency-check@main
```

### Advanced Usage

```yaml
steps:
  - name: Checkout code
    uses: actions/checkout@v5

  - name: Run dependency vulnerability scan
    uses: GigaTech-net/public-reusable-workflows/.github/actions/dependency-check@main
    with:
      artifact_name: "security-scan-results"
      retention_days: 30
      working_directory: "./src"
```

## Integration with Other Actions

This action works well after setup actions:

```yaml
steps:
  - name: Setup workflow
    uses: GigaTech-net/public-reusable-workflows/.github/actions/setup-workflow@main

  - name: Dependency vulnerability scan
    uses: GigaTech-net/public-reusable-workflows/.github/actions/dependency-check@main
    with:
      artifact_name: "vuln-scan-${{ steps.setup.outputs.version }}"
```

## Error Handling

This action implements comprehensive error handling:

- Input validation with sensible defaults
- Always uploads artifacts even if scan partially fails
- Meaningful output for downstream processing
- Proper cleanup operations

## Development Notes

### For GitHub Copilot Users

When modifying this action, use these prompts for best results:

```text
Modify this dependency check composite action to [specific requirement], following the repository's established patterns for error handling, input validation, and output setting.
```

## Related Actions

- [setup-workflow](./../setup-workflow/) - Common setup tasks
- [secret-scan](./../secret-scan/) - Security scanning
- [validate-pr-title](./../validate-pr-title/) - PR validation

---

This action helps ensure consistency across all security scanning operations and provides optimal integration with GitHub Copilot for future development.

# Generate Global Vars Composite Action

Generates a `global_vars.hcl` file using the `gen_global_vars.sh` script from the `GigaTech-net/pm-infrastructure-shared` repository. This composite action is the recommended replacement for the deprecated reusable workflow `rw-global-vars.yaml` and allows you to explicitly provide a GitHub token, making it easy to swap tokens as needed.

## Features

- Generates `global_vars.hcl` based on provided inputs
- Explicit `github-token` input to control checkout permissions
- Prints the generated file for debugging
- Outputs the generated file path

## Usage

```yaml
- name: Generate Global Vars
  uses: ./.github/actions/global-vars
  with:
    prefix: my-prefix
    createdby: DevSecOps
    createdbytag: devsecops
    costcentertag: cc-123
    appnametag: my-app
    envnametag: dev
    gt_fhir_domain: fhir.gigatech.net
    gt_api_domain: api.gigatech.net
    pm_gateway_domain: gateway.gigatech.net
    target_dir: ./terraform/
    github-token: ${{ secrets.GT_DEVSECOPS_PAT }}
```

## Inputs

| Input               | Description                                                          | Required | Default            |
| ------------------- | -------------------------------------------------------------------- | -------- | ------------------ |
| `prefix`            | Resource name prefix                                                 | ✅       | -                  |
| `createdby`         | Created by value                                                     | ✅       | -                  |
| `createdbytag`      | Created by tag                                                       | ✅       | -                  |
| `costcentertag`     | Cost center tag                                                      | ✅       | -                  |
| `appnametag`        | Application name tag                                                 | ✅       | -                  |
| `envnametag`        | Environment name tag                                                 | ✅       | -                  |
| `gt_fhir_domain`    | GigaTech FHIR domain                                                 | ✅       | -                  |
| `gt_api_domain`     | GigaTech API domain                                                  | ❌       | `api.gigatech.net` |
| `pm_gateway_domain` | PM Gateway domain                                                    | ✅       | -                  |
| `target_dir`        | Target directory to write `global_vars.hcl` (include trailing slash) | ✅       | -                  |
| `github-token`      | Token used to checkout `pm-infrastructure-shared` (enables swapping) | ✅       | -                  |

## Outputs

| Output        | Description                         |
| ------------- | ----------------------------------- |
| `output-path` | Full path to `global_vars.hcl` file |

## Migration from Reusable Workflow

If you currently use the reusable workflow `rw-global-vars.yaml`, migrate to this composite action.

### Before (Reusable Workflow)

```yaml
jobs:
  create-global-vars:
    uses: ./.github/workflows/rw-global-vars.yaml
    with:
      prefix: my-prefix
      createdby: DevSecOps
      createdbytag: devsecops
      costcentertag: cc-123
      appnametag: my-app
      envnametag: dev
      gt_fhir_domain: fhir.gigatech.net
      gt_api_domain: api.gigatech.net
      pm_gateway_domain: gateway.gigatech.net
      target_dir: ./terraform/
    secrets:
      GT_DEVSECOPS_PAT: ${{ secrets.GT_DEVSECOPS_PAT }}
```

### After (Composite Action)

```yaml
jobs:
  create-global-vars:
    runs-on: ubuntu-latest
    steps:
      - name: Generate Global Vars
        uses: ./.github/actions/global-vars
        with:
          prefix: my-prefix
          createdby: DevSecOps
          createdbytag: devsecops
          costcentertag: cc-123
          appnametag: my-app
          envnametag: dev
          gt_fhir_domain: fhir.gigatech.net
          gt_api_domain: api.gigatech.net
          pm_gateway_domain: gateway.gigatech.net
          target_dir: ./terraform/
          github-token: ${{ secrets.GT_DEVSECOPS_PAT }}

      - name: Upload global_vars.hcl as artifact
        uses: actions/upload-artifact@v4
        with:
          name: global-vars
          path: ./terraform/global_vars.hcl
```

## Notes

- Ensure the provided `github-token` has `contents: read` access to `GigaTech-net/pm-infrastructure-shared`.
- This action does not upload artifacts. If you require artifact upload, add a separate `actions/upload-artifact@v4` step as shown above.
- References to external actions should use semantic version tags (e.g., `@v4`, `@v5`).

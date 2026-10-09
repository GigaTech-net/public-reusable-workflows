# Docs-only change

**Name**: Docs-only change  
**Description**: Decides whether the change under test touches only
documentation, so the caller can skip scans that cannot act on documentation
(Super Linter, OWASP Dependency-Check) while the job itself still runs and
reports its required status context.

The action fails open: when the diff cannot be determined, or the event is
neither `push` nor `pull_request`, `docs_only` is `false` and the full gate
runs. It requires a checkout with full history (`actions/checkout` with
`fetch-depth: 0`), because push events compare against the default branch.

## Usage

Use the output in a step-level `if:`. Skip only on a positive `true`.

```yaml
- name: Classify changed paths
  id: changes
  uses: ./.github/actions/docs-only

- name: Super Linter
  if: steps.changes.outputs.docs_only != 'true'
  uses: ./.github/actions/super-linter
```

Never put `paths:` or `paths-ignore:` on a workflow whose job is a required
check. A workflow that does not run reports no status, and the PR waits forever
for a check that never arrives.

## Inputs

| Input            | Description                                                                | Required | Default                   |
| ---------------- | -------------------------------------------------------------------------- | -------- | ------------------------- |
| `docs_paths`     | Comma- or newline-separated globs that count as documentation              | No       | `**/*.md,docs/**,LICENSE` |
| `not_docs_paths` | Globs checked first; a match is never documentation. Empty disables it     | No       | see below                 |

Glob dialect, shared with `pr-gate`'s `sensitive_paths`: `**/` is zero or more
whole directories, `**` is anything, `*` and `?` stay within one path segment.

## Outputs

| Output      | Description                                                                                          |
| ----------- | ---------------------------------------------------------------------------------------------------- |
| `docs_only` | `true` only when every changed path is documentation; `false` otherwise, including when undetermined |
| `reason`    | One line explaining the decision                                                                     |

## What counts as documentation

A change is docs-only when it is non-empty, no changed path matches the deny
list, and every changed path matches one of the default globs:

- `**/*.md`, at any depth including the root `README.md`
- `docs/**`, anchored at the repository root (`src/docs/x.py` does not match)
- `LICENSE`, the root file only

The deny list (`not_docs_paths`) is evaluated first and wins over the globs
above, so `docs/**` covers images and prose but not a manifest or code that
happens to sit under `docs/`. Its default matches, at any depth:

- dependency manifests and lockfiles: `package.json`, `package-lock.json`,
  `yarn.lock`, `pnpm-lock.yaml`, `requirements*.txt`, `Pipfile*`,
  `pyproject.toml`, `poetry.lock`, `pom.xml`, `*.gradle`, `*.gradle.kts`,
  `go.mod`, `go.sum`, `Gemfile*`, `Cargo.toml`, `Cargo.lock`, `*.csproj`,
  `Dockerfile*`
- code and configuration by extension: `*.sh`, `*.py`, `*.js`, `*.ts`,
  `*.yml`, `*.yaml`, `*.json`

Deliberately not documentation: `CODEOWNERS`, `.txt` files outside `docs/`,
a vendored `LICENSE` (such as `vendor/lib/LICENSE`), and every YAML file
including linter configs. A path not on the list means the full gate.

## Which diff it reads

| Event          | Base                                  | Command                                               |
| -------------- | ------------------------------------- | ----------------------------------------------------- |
| `pull_request` | the pull request base commit          | `git diff --name-only --no-renames BASE...HEAD`       |
| `push`         | merge base with `origin/<default>`    | `git diff --name-only --no-renames MERGE_BASE HEAD`   |
| anything else  | none                                  | not docs-only                                         |

A push compares the whole branch against the default branch, not the previous
push, so a README-only last push on a branch that changed code earlier does not
skip the gate. `--no-renames` lists both sides of a rename, so code moved into
`docs/` is not docs-only, and a deleted manifest is listed by its path.

## When it fails open

`docs_only` is `false`, with the cause in `reason`, and the script still exits 0
when any of these hold:

- the base or head commit is missing, empty, or not in the clone
- `origin/<default branch>` is absent, or there is no merge base
- `git diff` exits non-zero
- the changeset is empty
- the event is not `push` or `pull_request` (for example `workflow_dispatch`)

It exits non-zero only when its output file cannot be written.

## Running the tests

```sh
bash .github/actions/docs-only/docs-only-test.sh
```

# Workflow timeouts

**Name**: Workflow timeouts  
**Description**: Fails when a workflow in the calling repository has a job
without `timeout-minutes`, and names the file and the job.

A job with no `timeout-minutes` runs for up to six hours when a call never
returns. This action turns that into a failed check at review time.

## What it checks

- Every job under `jobs:` in each `*.yml` and `*.yaml` file directly under
  `workflows_path` has `timeout-minutes` as a direct property. An expression
  value (`${{ inputs.timeout_minutes }}`) counts as declared.
- A literal value must be a positive number: `0`, a negative number, an empty
  value and `null` are reported, since they do not bound the job. The gate sets
  no upper bound; how long a job may run is policy, set per job class in
  `CLAUDE.md`, not something the gate infers.
- A job that calls a reusable workflow (a job-level `uses:`) is exempt. GitHub
  rejects `timeout-minutes` there; the called workflow's own jobs carry the
  bound.
- A job key may carry a YAML anchor (`a: &a`) or be an alias (`b: *a`, which
  inherits the anchor's bound), and a `<<: *a` merge key inherits it too.
- A file whose `jobs:` cannot be read (a flow-style job or property, an alias
  with no anchor, a tab indent, or a parser that fails) fails as unreadable,
  naming the file and line. It never passes as having no jobs.
- A `workflows_path` that does not exist or holds no workflow file is a usage
  error, so a typo cannot disable the check.

With `check_scanner_steps: "true"` it also requires a step-level
`timeout-minutes` on each container or scanner step:

- a step whose `uses:` is `super-linter`, `dependency-check`, `secret-scan`,
  `trufflehog-scan`, `super-linter/super-linter`,
  `dependency-check/Dependency-Check_Action`, `trufflesecurity/trufflehog`,
  `zaproxy/action-*` or `docker/build-push-action`;
- a step whose `run:` body runs `docker build`, `docker buildx`, `docker run`,
  `docker pull`, `docker compose` or `docker-compose up`, including a subcommand group
  (`docker image pull`) or global flags before it (`docker -H host run`). A step name that merely mentions docker
  does not count.

## Inputs

| Input                 | Description                                                | Required | Default             |
| --------------------- | ---------------------------------------------------------- | -------- | ------------------- |
| `workflows_path`      | Directory whose workflow files are checked (not recursive) | No       | `.github/workflows` |
| `check_scanner_steps` | `true` to also check container and scanner steps           | No       | `false`             |

## Example Usage

Check out the repository first, then:

```yaml
- name: Workflow timeouts
  uses: GigaTech-net/public-reusable-workflows/.github/actions/workflow-timeouts@v1
  with:
    check_scanner_steps: "true"
```

Add it as a step of the `quality-checks` job, the one required check, rather
than as a separate job.

## Output

One annotation per violation, then a count:

```text
::error file=.github/workflows/ci.yaml,line=9::job 'build' has no timeout-minutes
::error file=.github/workflows/ci.yaml,line=21::step 'Super Linter' in job 'lint' has no timeout-minutes
1 violation(s) in 1 file(s)
```

The script exits 0 when clean, 1 on a violation or unreadable file, and 2 on a
usage error.

## Limits

Action metadata does not accept `timeout-minutes` on a composite action's
steps; only workflow steps take it. A composite action is bounded by the job
that runs it and, for a scanner, by the workflow step that calls it.

## Testing

```bash
.github/actions/workflow-timeouts/workflow-timeouts-test.sh
```

The test builds fixture workflows in a temporary directory and checks this
repository's own workflows.

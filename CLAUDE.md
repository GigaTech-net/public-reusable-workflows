# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

This is the **public mirror** of the private `GigaTech-net/reusable-workflows`. It exists
so that public consumers can reference GigaTECH's composite actions and reusable
workflows, which a private repository cannot serve.

**Content here is generated, not authored.** `mirror-public.yaml` in the private
`reusable-workflows` repository selects what is published and pushes it here. Editing an
action or workflow in this repository will be overwritten by the next mirror run — make
the change upstream in `reusable-workflows` and let it propagate.

The exception is `mirror-tag.yaml`, which is genuinely owned here; see below.

`README.md` describes this repository as based on "the internal public-reusable-workflows"
and links to itself. The upstream is `GigaTech-net/reusable-workflows`.

## Layout

| Path                                                  | Holds                                                          |
| ----------------------------------------------------- | -------------------------------------------------------------- |
| `.github/actions/*/`                                  | mirrored composite actions — the preferred consumption pattern |
| `.github/workflows/rw-*.yaml`                         | mirrored reusable workflows, kept for backward compatibility   |
| `.github/workflows/mirror-tag.yaml`                   | owned here; moves version tags after mirrored content lands    |
| `.github/workflows/main-pr.yaml`, `feature-push.yaml` | this repository's own CI                                       |
| `report/`                                             | generated jscpd copy-paste-detection output                    |

Consumers pin `@v1`, so the major tag must actually move for a release to reach them.

## How publishing works

`mirror-public.yaml` upstream has two paths. It tries a direct push, which **fails by
design** — this repository's ruleset has `bypass_actors: []` like every other, so the
GitHub App cannot bypass it. It then falls back to opening a PR here, and deliberately
does _not_ tag, because at that moment the content is not published. The mirror is
therefore not live until someone merges that PR.

`mirror-tag.yaml` closes the loop from this side. It fires on push to `main`, reads the
version out of the commit subject, then creates the release tag and moves the major tag.
Tagging from here needs no ruleset bypass because that ruleset's `target` is `branch`,
and a tag push is not governed by it.

Three constraints in that workflow are load-bearing:

- The trigger matches subjects starting `chore: mirror v` — both publish paths produce
  that subject, and the squash path appends `(#N)`. Anything else pushed to `main` is
  ignored. The `if:` must stay a folded scalar (`>-`): the literal contains `": "`, which
  YAML would otherwise read as a nested mapping.
- Checkout uses `fetch-depth: 0`. The version check compares an existing tag against
  `HEAD`, which a shallow clone cannot resolve.
- The commit subject is read through `env:`, **never interpolated into a `run:` body**.
  `${{ }}` is substituted before Bash sees it, so a crafted subject in an
  attacker-influenceable commit message would execute as shell.

`workflow_dispatch` exists to catch up tags missed while the workflow did not exist, and
as an escape hatch when a push-triggered run fails. It takes no inputs — checkov
`CKV_GHA_7` forbids them, and the version must come from the commit rather than be typed.

## CI

`main-pr.yaml` runs `quality-checks`, `auto-approve`, and `enable-auto-merge`, built from
the same composite actions this repository mirrors, pinned at `@v1`.

`concurrency: cancel-in-progress: true` on `${{ github.ref }}-${{ github.workflow }}`
means a push followed by a PR-open cancels the first run. **A cancelled run reported as a
failure is usually this** — look for a newer run on the branch before investigating.
`mirror-tag.yaml` is the exception: it uses a fixed `mirror-tag` group with
`cancel-in-progress: false`, so tag moves queue rather than cancel each other.

### Tokens

Write steps take the App token `setup-token` puts in `$GITHUB_ENV`, as
`${{ env.GITHUB_TOKEN }}`. Never a personal access token, and never override with
`secrets.GITHUB_TOKEN` on the approve step — that attributes the approval to
`github-actions[bot]`, which does not satisfy `required_approving_review_count`.

## PR titles

CI validates the format and fails the PR if it does not match:

```text
<type>: <scope>: <description>
```

`<type>` is a Conventional Commits keyword; `<scope>` is `hotfix`, `maint`, or a Jira
issue ID such as `PRO-1234`. Both colons and both spaces are required.

## Code comments

**Never write a comment whose subject is a change you made.** No "removed X", no
"switched from Y to Z", no "X is no longer used", no "was previously W".

The reason is searchability. A comment naming a removed identifier keeps that identifier
greppable forever, so every later search for it returns the epitaph alongside the real
hits with no way to tell them apart. This repository is public, so the noise is exported
to every consumer.

Document what the code **is** and does — the constraints documented above are all
properties the code still has, which is why they earn their place. The change itself
belongs in the commit message, the PR body, and the Jira ticket. Where a rejected
alternative must be recorded, describe the failure mode without naming the dead
identifier.

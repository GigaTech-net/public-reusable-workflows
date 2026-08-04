# `local-checks`

Runs the five checks CI runs, from one definition, in CI and on a developer's
machine: **markdownlint**, **yamllint**, **actionlint**, **codespell** and
**Super-Linter**.

## Why

PRs were pushed after passing markdownlint and yamllint locally, then failed CI
on checks that had never been run locally at all — codespell with the org word
list, and Super-Linter. Each cost a full CI round trip.

Checking a subset locally is worse than checking nothing: it feels like
verification while leaving the two slowest-to-discover checks unrun.

## Locally, with no copied files

`reusable-workflows` is private, so this goes through `gh` rather than `curl`.
One command, nothing added to your repository:

```sh
gh api "repos/GigaTech-net/public-reusable-workflows/contents/.github/actions/local-checks/local-checks.sh?ref=v1" \
  --jq .content | base64 -d | bash
```

Settings are environment variables, because the entry point is a pipe into bash
and positional arguments do not survive it:

```sh
FAST=true                        ... | base64 -d | bash   # skip Super-Linter
CHECKS=markdownlint,codespell    ... | base64 -d | bash   # a subset
WORDS_TO_IGNORE=iif              ... | base64 -d | bash   # this repo's extra words
```

Repositories created from `Dev-Template` get `scripts/local-checks` pre-seeded,
which is a three-line wrapper around the command above with that repository's
`WORDS_TO_IGNORE` already filled in.

### What it needs, and what it does without

Every tool is optional and reported as `skip` when absent, so a partial local
toolchain still runs what it can rather than failing:

&#124; Check &#124; Needs &#124; Install &#124;
&#124; --- &#124; --- &#124; --- &#124;
&#124; markdownlint &#124; `npx`, `.github/linters/.markdown-lint.yml` &#124; ships with Node &#124;
&#124; yamllint &#124; `python3` + `yamllint`, `.github/linters/.yaml-lint.yml` &#124; `pip install yamllint` &#124;
&#124; actionlint &#124; `actionlint` &#124; `brew install actionlint` &#124;
&#124; codespell &#124; `codespell`, network for the dictionary &#124; `pip install codespell` &#124;
&#124; super-linter &#124; Docker running &#124; Docker Desktop &#124;

## In CI

```yaml
- name: Local checks
  uses: GigaTech-net/public-reusable-workflows/.github/actions/local-checks@v1
  with:
    words_to_ignore: "iif"
```

This aggregates all five into one step. Repositories already running the
individual `spellcheck` and `super-linter` actions inside `quality-checks` do not
need it — `quality-checks` is the required status check either way.

## Inputs

&#124; Input &#124; Default &#124; Notes &#124;
&#124; --- &#124; --- &#124; --- &#124;
&#124; `checks` &#124; `all` &#124; Comma separated: `markdownlint,yamllint,actionlint,codespell,super-linter` &#124;
&#124; `fast` &#124; `false` &#124; `true` skips Super-Linter, the only check that pulls an image &#124;
&#124; `words_to_ignore` &#124; `""` &#124; Must equal what this repo passes to `spellcheck`'s `wordsToIgnore` &#124;
&#124; `files_to_ignore` &#124; `""` &#124; Mirrors `spellcheck`'s `filesToIgnore` &#124;
&#124; `super_linter_version` &#124; `slim-v8.6.0` &#124; Keep in step with the `super-linter` action &#124;

## The codespell flags are asserted, not documented

The whole point is that a local run predicts CI. That holds only while this
script's codespell invocation matches the `spellcheck` action's, so
`codespell-parity-test.sh` compares them mechanically and runs in this
repository's own CI.

It is not decoration. The prototype had already drifted before review: two extra
`--skip` entries (`./.git`, `./report`) and one extra `-L` word (`iif`) that the
action does not carry. Each looked harmless; each meant a local pass could not
predict CI.

Repository-specific words go in `words_to_ignore` / `files_to_ignore`, which land
in the same position the action puts its own inputs. They must never be added to
`CODESPELL_SKIP_BASE` / `CODESPELL_IGNORE_BASE`, which exist to stay equal to the
action.

```sh
.github/actions/local-checks/codespell-parity-test.sh
```

## Behaviours that each cost a debugging cycle

- **`-D` is not optional.** The `spellcheck` action passes codespell's master
  `dictionary.txt`, which *replaces* the built-in dictionary. Running locally
  without it checks a different word set, so the script fetches and caches the
  same file.
- **Super-Linter reads the consumer's `.github/super-linter.env`.** That is the
  only local check that catches a missing `VALIDATE_*`, and missing entries are
  how this was first noticed.
- **Super-Linter publishes no `linux/arm64` image.** Apple Silicon gets
  `--platform linux/amd64` and emulates it. Slower, and the only way to reproduce
  the CI result.
- **Do not set `DEFAULT_BRANCH` in `RUN_LOCAL` mode** alongside
  `USE_FIND_ALGORITHM=true`; Super-Linter rejects the pair.
- **`actionlint`'s embedded shellcheck stays advisory.** It reports pre-existing
  style findings CI does not fail on. Failing on them makes the tool cry wolf and
  get ignored, which is worse than not running it.
- **`shfmt` runs on shell via Super-Linter and wants tabs.** This action's own
  scripts must be `shfmt`-clean or they fail the check they are meant to
  anticipate — which is how the prototype first went red.
- **No `mapfile`.** macOS ships bash 3.2.
- **Logs go to `$RUNNER_TEMP`/`$TMPDIR`, never the checkout.** Writing them into
  the tree is how a `report/` directory once ended up committed to a PR.

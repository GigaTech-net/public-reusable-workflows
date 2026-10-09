# Secret Scan Composite Action

Scans the commits the triggering event introduced for leaked credentials with
TruffleHog. It fails when TruffleHog finds a secret, reports an error, or
inspects nothing.

## What it does

- Resolves a `base..head` commit range from the event payload (or from the
  `base` and `head` inputs).
- Runs the TruffleHog docker image over that range with `--fail`.
- Checks the scanner's log and fails the step when the scan cannot be trusted.

It does not check out the repository; run `actions/checkout` first.

## Commit range per event

Explicit `base` or `head` inputs win; `head` then defaults to `HEAD`. Inputs
may be a sha, a ref, or a branch name known to `origin`. On a pull request or
merge group event an input that does not resolve (such as `github.ref_name`,
which is `<n>/merge`) falls back to the event's own sha with a warning; on any
other event it fails.
Otherwise the range depends on the event:

| Event                                                               | base                                                                               | head                    |
| ------------------------------------------------------------------- | ---------------------------------------------------------------------------------- | ----------------------- |
| `pull_request`, `pull_request_target`                               | `pull_request.base.sha`                                                            | `pull_request.head.sha` |
| `merge_group`                                                       | `merge_group.base_sha`                                                             | `merge_group.head_sha`  |
| `push`, normal                                                      | `before`                                                                           | `after`                 |
| `push` to the default branch, first or forced                       | empty: whole history of `after`, since a fork point would equal `after`            | `after`                 |
| `push`, new branch (`before` all zeros)                             | merge-base of `after` with `origin/<default_branch>`; empty (whole branch) if none | `after`                 |
| `push`, force-push (`before` missing or not an ancestor of `after`) | same merge-base fallback                                                           | `after`                 |
| `push`, branch deletion (`after` all zeros)                         | skipped: nothing added                                                             |                         |
| anything else (`workflow_dispatch`, `schedule`, ...)                | empty: full history audit                                                          | `HEAD`                  |

## When the step fails

- TruffleHog exits 183: it reported secrets in the scanned range.
- TruffleHog exits with any other non-zero status.
- The log contains `encountered errors during scan` or `unable to resolve ref`.
- The log has no `finished scanning` summary, or its `chunks` count is not a
  positive integer. A range that adds content and scans zero chunks is a fault. This includes a
  range whose added files are all covered by `--exclude-paths` or
  `.trufflehogignore`: narrow the exclusion.

## When the step skips

The step succeeds with a `::notice::` and a job-summary line when the push
deleted a branch, the range holds no commits, or the range adds no content (merge commits and binary changes count as content).

## Checkout requirements

`fetch-depth: 0` is recommended. A shallow clone is deepened automatically,
and a missing base or head is fetched from `origin`, at the cost of a fetch.
The step needs docker, which ubuntu runners have.

## Scanner version

The scan runs TruffleHog `3.99.2`, pinned by image digest
(`ghcr.io/trufflesecurity/trufflehog@sha256:47a84bc18a0d04a165498bbbd3bacfd84176661cbc91f8e0f85467f6a771e99a`),
not `latest`, so a run of the same commit gives the same findings whenever it
runs, and neither an upstream detector change nor a re-pushed tag can change
every consuming repository's scan at once. The tag `3.99.2` is kept beside the
digest as the name of the release it was resolved from. The step's log and job
summary name the image reference it ran.

The pin is set in two constants in `secret-scan.sh`, changed together:

- `TRUFFLEHOG_VERSION`, the release tag
- `TRUFFLEHOG_DIGEST`, that release's multi-arch index digest

The `version` input defaults to empty, which means this pin; `action.yaml` does
not inject a tag that would bypass the digest.

To bump it:

1. Pick a release from
   [TruffleHog releases](https://github.com/trufflesecurity/trufflehog/releases).
   Use the tag without its `v` prefix: the image is tagged `3.99.2`, not
   `v3.99.2`.
2. Read the release notes between the current and the new version for added
   or changed detectors and verifiers.
3. Resolve the new digest with
   `docker buildx imagetools inspect ghcr.io/trufflesecurity/trufflehog:<X.Y.Z>`
   (the top-level `Digest:` line), and update `TRUFFLEHOG_VERSION` and
   `TRUFFLEHOG_DIGEST` in one commit, with the `version` input description in
   `action.yaml` and the Scanner version text above.
4. Run `secret-scan-test.sh` and `secret-scan-canary-test.sh`.
5. Open a pull request titled `fix: PRO-XXXX: bump TruffleHog to X.Y.Z` and
   list the detector changes from step 2 in its body.

A caller can still pass `version` to run another tag (`image:version`); that
choice is then visible in the caller's own workflow. An `image` that already
carries a tag or digest is used as given, and `version` is not appended.

## Inputs

| Input        | Description                                            | Required | Default                              |
| ------------ | ------------------------------------------------------ | -------- | ------------------------------------ |
| `path`       | Repository path to scan                                | No       | `./`                                 |
| `base`       | Commit to scan from (exclusive). Empty: from the event | No       | empty                                |
| `head`       | Commit to scan to (inclusive). Empty: from the event   | No       | empty                                |
| `extra_args` | Extra arguments to pass to TruffleHog                  | No       | `--debug --json --only-verified`     |
| `version`    | TruffleHog image tag. Empty: the pinned `3.99.2` release by digest (see Scanner version) | No | empty |
| `image`      | TruffleHog image, without tag                          | No       | `ghcr.io/trufflesecurity/trufflehog` |

## Usage

```yaml
steps:
  - uses: actions/checkout@v7
    with:
      fetch-depth: 0
  - name: Secret scan
    uses: GigaTech-net/public-reusable-workflows/.github/actions/secret-scan@v1
```

### With custom parameters

```yaml
steps:
  - uses: actions/checkout@v7
    with:
      fetch-depth: 0
  - name: Secret scan with custom path
    uses: GigaTech-net/public-reusable-workflows/.github/actions/secret-scan@v1
    with:
      path: ./src
      extra_args: --debug --json
```

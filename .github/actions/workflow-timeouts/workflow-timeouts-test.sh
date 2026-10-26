#!/usr/bin/env bash
# Tests for workflow-timeouts.sh: the job check and the CLI against fixture
# workflow files in a throwaway directory. No framework; bash 3.2 compatible so
# it runs on macOS as well as the runners.
#
# Run from anywhere. Exits non-zero if any case fails.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script="$here/workflow-timeouts.sh"
[ -f "$script" ] || {
	echo "missing: $script" >&2
	exit 1
}
# shellcheck source=/dev/null
. "$script"

status=0
check() {
	local label="$1" want="$2" got="$3"
	if [ "$want" = "$got" ]; then
		printf '  ok   %s\n' "$label"
	else
		printf '  FAIL %s: want %s, got %s\n' "$label" "$want" "$got"
		status=1
	fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Writes stdin to $tmp/<name>/<name>.yaml and prints that path.
fixture() {
	mkdir -p "$tmp/$1"
	cat >"$tmp/$1/$1.yaml"
	printf '%s/%s/%s.yaml' "$tmp" "$1" "$1"
}

tab=$'\t'

echo "== job check =="

f=$(fixture bounded <<'YAML'
name: x
on: push
jobs:
  a:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - run: echo a
  b:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - run: echo b
YAML
)
check "bounded: nothing reported" "" "$(missing_job_timeouts "$f")"

f=$(fixture one-missing <<'YAML'
name: x
on: push
jobs:
  a:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - run: echo a
  b:
    runs-on: ubuntu-latest
    steps:
      - run: echo b
YAML
)
check "one-missing: line and job" "9${tab}b" "$(missing_job_timeouts "$f")"

f=$(fixture four-space <<'YAML'
name: x
on: push
jobs:
    a:
        runs-on: ubuntu-latest
        timeout-minutes: 10
        steps:
            - run: echo a
    b:
        runs-on: ubuntu-latest
        steps:
            - run: echo b
YAML
)
check "four-space: line and job" "9${tab}b" "$(missing_job_timeouts "$f")"

f=$(fixture expression <<'YAML'
on: workflow_call
jobs:
  a:
    runs-on: ubuntu-latest
    timeout-minutes: ${{ inputs.t }}
    steps:
      - run: echo a
YAML
)
check "expression value counts as declared" "" "$(missing_job_timeouts "$f")"

f=$(fixture call <<'YAML'
on: push
jobs:
  c:
    uses: ./.github/workflows/x.yaml
    with:
      a: b
YAML
)
check "reusable-workflow call is exempt" "" "$(missing_job_timeouts "$f")"

f=$(fixture nested-only <<'YAML'
on: push
jobs:
  a:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        timeout-minutes: [1, 2]
    steps:
      - name: x
        timeout-minutes: 5
        run: |
          cat <<EOT
          timeout-minutes: 10
          EOT
YAML
)
check "nested-only: not the job's property" "3${tab}a" "$(missing_job_timeouts "$f")"

f=$(fixture comments <<'YAML'
on: push
jobs:  # the jobs

  # a: commented out
  #  z:
  a:
    runs-on: ubuntu-latest
    timeout-minutes: 10 # why
    steps:
      - run: echo a

  b: # second
    runs-on: ubuntu-latest
    timeout-minutes: 10
YAML
)
check "comments and blank lines ignored" "" "$(missing_job_timeouts "$f")"

f=$(fixture crlf <<'YAML'
name: x
on: push
jobs:
  a:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - run: echo a
  b:
    runs-on: ubuntu-latest
    steps:
      - run: echo b
YAML
)
sed 's/$/\r/' "$f" >"$f.crlf" && mv "$f.crlf" "$f"
check "crlf: line and job" "9${tab}b" "$(missing_job_timeouts "$f")"

f=$(fixture flow <<'YAML'
on: push
jobs: {a: {runs-on: ubuntu-latest}}
YAML
)
missing_job_timeouts "$f" >/dev/null
check "flow style: unreadable" 3 "$?"

f=$(fixture quoted-key <<'YAML'
on: push
jobs:
  "build-ig":
    runs-on: ubuntu-latest
YAML
)
check "quoted key: quotes stripped" "3${tab}build-ig" "$(missing_job_timeouts "$f")"

f=$(fixture awk-fails <<'YAML'
on: push
jobs:
  a:
    runs-on: ubuntu-latest
YAML
)
# A parser that exits non-zero must read as unreadable, never as no violations.
(
	# shellcheck disable=SC2329  # scan_file calls it in place of the real awk
	awk() { return 2; }
	missing_job_timeouts "$f" >/dev/null
	check "awk failure: job check unreadable" 3 "$?"
	unbounded_scanner_steps "$f" >/dev/null
	check "awk failure: scanner check unreadable" 3 "$?"
)
(
	# shellcheck disable=SC2329  # scan_file calls it in place of the real awk
	awk() { printf 'J\0371\037a\0370\0370\n'; return 2; }
	missing_job_timeouts "$f" >/dev/null
	check "awk failure after output: unreadable" 3 "$?"
)

f=$(fixture anchored <<'YAML'
on: push
jobs:
  a: &a
    runs-on: ubuntu-latest
    steps:
      - run: echo a
  b: &b # bounded
    runs-on: ubuntu-latest
    timeout-minutes: 10
  c: *b
  d: *a
YAML
)
check "anchored job without a timeout is reported; alias inherits" "3${tab}a
11${tab}d" "$(missing_job_timeouts "$f")"

f=$(fixture merge-key <<'YAML'
on: push
jobs:
  base: &base
    timeout-minutes: 10
  a:
    <<: *base
    runs-on: ubuntu-latest
  b:
    runs-on: ubuntu-latest
YAML
)
check "merge key inherits the anchored timeout" "8${tab}b" "$(missing_job_timeouts "$f")"

f=$(fixture unknown-alias <<'YAML'
on: push
jobs:
  a: *nowhere
YAML
)
out=$(missing_job_timeouts "$f")
check "alias of an unknown anchor: unreadable" 3 "$?"
check "alias of an unknown anchor: names the line" "3${tab}!alias *nowhere has no anchor" "$out"

f=$(fixture flow-job <<'YAML'
on: push
jobs:
  a:
    runs-on: ubuntu-latest
    timeout-minutes: 10
  b: {runs-on: ubuntu-latest}
YAML
)
out=$(missing_job_timeouts "$f")
check "flow-style job: unreadable" 3 "$?"
check "flow-style job: names the line" "6${tab}!job 'b' is not a block mapping" "$out"

f=$(fixture flow-body <<'YAML'
on: push
jobs:
  a:
    {runs-on: ubuntu-latest, timeout-minutes: 10}
YAML
)
out=$(missing_job_timeouts "$f")
check "flow-style job body: unreadable" 3 "$?"
check "flow-style job body: names the line" "4${tab}!job 'a' has a flow-style property" "$out"

f=$(fixture tab-indent <<'YAML'
on: push
jobs:
  a:
    timeout-minutes: 10
YAML
)
printf '\tb:\n' >>"$f"
out=$(missing_job_timeouts "$f")
check "tab indentation: unreadable" 3 "$?"
check "tab indentation: names the line" "5${tab}!tab indentation" "$out"

f=$(fixture non-positive <<'YAML'
on: push
jobs:
  zero:
    timeout-minutes: 0
  negative:
    timeout-minutes: -5 # off
  fraction:
    timeout-minutes: 0.0
  quoted:
    timeout-minutes: "0"
  empty:
    timeout-minutes:
  positive:
    timeout-minutes: 360
  small:
    timeout-minutes: 0.5
  expression:
    timeout-minutes: ${{ inputs.t }}
  zero-call:
    uses: ./.github/workflows/x.yaml
YAML
)
check "non-positive timeout-minutes: reported with its value" "3${tab}zero${tab}0
5${tab}negative${tab}-5
7${tab}fraction${tab}0.0
9${tab}quoted${tab}0
11${tab}empty${tab}(empty)" "$(missing_job_timeouts "$f")"

f=$(fixture zero-step <<'YAML'
on: push
jobs:
  j:
    timeout-minutes: 10
    steps:
      - name: Scan
        uses: zaproxy/action-baseline@v0.15.0
        timeout-minutes: 0
      - name: Ok
        uses: zaproxy/action-baseline@v0.15.0
        timeout-minutes: 20
      - name: Expr
        uses: zaproxy/action-baseline@v0.15.0
        timeout-minutes: ${{ inputs.t }}
YAML
)
check "scanner step with timeout-minutes 0: reported with its value" "6${tab}j${tab}Scan${tab}0" "$(unbounded_scanner_steps "$f")"

echo "== command line =="

out=$(bash "$script" "$tmp/one-missing")
check "one-missing: exit 1" 1 "$?"
case "$out" in
*"::error file=$tmp/one-missing/one-missing.yaml,line=9::job 'b' has no timeout-minutes"*) r=ok ;;
*) r=no ;;
esac
check "one-missing: names file, line and job" ok "$r"
case "$out" in *"1 violation(s) in 1 file(s)"*) r=ok ;; *) r=no ;; esac
check "one-missing: count" ok "$r"

out=$(bash "$script" "$tmp/bounded")
check "bounded: exit 0" 0 "$?"
case "$out" in *"all jobs bounded in 1 file(s)"*) r=ok ;; *) r=no ;; esac
check "bounded: message" ok "$r"

out=$(bash "$script" "$tmp/flow")
check "flow: exit 1" 1 "$?"
case "$out" in *"cannot read jobs"*) r=ok ;; *) r=no ;; esac
check "flow: unreadable message" ok "$r"
case "$out" in *"::error file=$tmp/flow/flow.yaml,line=2::cannot read jobs"*) r=ok ;; *) r=no ;; esac
check "flow: names file and line" ok "$r"

out=$(bash "$script" "$tmp/flow-job")
check "flow-job: exit 1" 1 "$?"
case "$out" in *"flow-job.yaml,line=6::cannot read jobs: job 'b' is not a block mapping"*) r=ok ;; *) r=no ;; esac
check "flow-job: names file, line and reason" ok "$r"

bash "$script" "$tmp/no-such-dir" >/dev/null 2>&1
check "missing directory: exit 2" 2 "$?"

mkdir -p "$tmp/empty-dir"
bash "$script" "$tmp/empty-dir" >/dev/null 2>&1
check "directory without workflows: exit 2" 2 "$?"

bash "$script" >/dev/null 2>&1
check "no arguments: exit 2" 2 "$?"

mkdir -p "$tmp/mixed/sub"
printf 'on: push\njobs:\n  a:\n    timeout-minutes: 1\n' >"$tmp/mixed/a.yml"
printf 'on: push\njobs:\n  a:\n    timeout-minutes: 1\n' >"$tmp/mixed/b.yaml"
printf 'on: push\njobs:\n  a:\n    runs-on: x\n' >"$tmp/mixed/sub/c.yaml"
out=$(bash "$script" "$tmp/mixed")
check "mixed: exit 0" 0 "$?"
case "$out" in *"all jobs bounded in 2 file(s)"*) r=ok ;; *) r=no ;; esac
check "mixed: .yml and .yaml read, subdirectory not" ok "$r"

echo "== scanner steps =="

for u in ./.github/actions/super-linter \
	GigaTech-net/public-reusable-workflows/.github/actions/dependency-check@v1 \
	GigaTech-net/public-reusable-workflows/.github/actions/secret-scan@v1 \
	dependency-check/Dependency-Check_Action@main \
	zaproxy/action-full-scan@v0.13.0 \
	docker/build-push-action@v6; do
	is_scanner_step "$u" ""
	check "scanner: $u" 0 "$?"
done
is_scanner_step "" "docker run --rm img"
check "scanner: run body docker run" 0 "$?"
for u in actions/checkout@v7 ./.github/actions/spellcheck; do
	is_scanner_step "$u" ""
	check "not scanner: $u" 1 "$?"
done
for b in "docker-compose up -d" "docker-compose -f ci.yml run app" "docker image pull alpine" \
	"docker container run img" "docker image build ." "docker buildx bake" \
	"docker --debug run img" "docker -H tcp://h run img" "docker --context ci pull img" \
	"echo go && docker compose up" "/usr/bin/docker run img"; do
	is_scanner_step "" "$b"
	check "scanner run body: $b" 0 "$?"
done
for b in "docker-compose config" "docker version" "docker ps" "docker login -u x" "echo docker-run" "mydocker run x"; do
	is_scanner_step "" "$b"
	check "not scanner run body: $b" 1 "$?"
done
is_scanner_step "" "bash .github/actions/super-linter/run-super-linter-test.sh"
check "not scanner: run body names a script" 1 "$?"

f=$(fixture docker-name-only <<'YAML'
on: push
jobs:
  j:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - name: Super Linter docker run tests
        run: .github/actions/super-linter/run-super-linter-test.sh
YAML
)
check "docker in a step name only: not reported" "" "$(unbounded_scanner_steps "$f")"

f=$(fixture docker-in-body <<'YAML'
on: push
jobs:
  j:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - name: Build
        run: |
          docker build -t x .
YAML
)
check "docker in the run body: reported" "7${tab}j${tab}Build" "$(unbounded_scanner_steps "$f")"

f=$(fixture scanner-bounded <<'YAML'
on: push
jobs:
  j:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: ./.github/actions/super-linter
        timeout-minutes: 8
YAML
)
check "bounded scanner step: not reported" "" "$(unbounded_scanner_steps "$f")"

f=$(fixture scanner-unbounded <<'YAML'
on: push
jobs:
  j:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v7
      - uses: zaproxy/action-baseline@v0.15.0
YAML
)
check "unnamed scanner step: reported by uses" "8${tab}j${tab}zaproxy/action-baseline@v0.15.0" "$(unbounded_scanner_steps "$f")"
f=$(fixture folded-uses <<'YAML'
on: push
jobs:
  j:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - name: Secret scan
        uses: >-
          GigaTech-net/public-reusable-workflows/.github/actions/secret-scan@v1
      - name: Bounded secret scan
        timeout-minutes: 5
        uses: >-
          GigaTech-net/public-reusable-workflows/.github/actions/secret-scan@v1
YAML
)
check "folded uses value: reported" "7${tab}j${tab}Secret scan" "$(unbounded_scanner_steps "$f")"

f=$(fixture bare-dash <<'YAML'
on: push
jobs:
  j:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      -
        name: Scan
        uses: zaproxy/action-baseline@v0.15.0
      - # a comment
        name: Build
        run: |
          docker build -t x .
      -
        name: Bounded
        timeout-minutes: 5
        uses: zaproxy/action-baseline@v0.15.0
      - name: After
        run: docker run --rm img
YAML
)
check "step opened with a bare dash: properties read" "7${tab}j${tab}Scan
10${tab}j${tab}Build
18${tab}j${tab}After" "$(unbounded_scanner_steps "$f")"

out=$(bash "$script" --scanner-steps "$tmp/zero-step")
check "zero-step: exit 1" 1 "$?"
case "$out" in *"line=6::step 'Scan' in job 'j' has timeout-minutes '0'; it must be a positive number"*) r=ok ;; *) r=no ;; esac
check "zero-step: names the step and the value" ok "$r"
out=$(bash "$script" "$tmp/non-positive")
case "$out" in *"line=3::job 'zero' has timeout-minutes '0'; it must be a positive number"*) r=ok ;; *) r=no ;; esac
check "non-positive: names the job and the value" ok "$r"
case "$out" in *"5 violation(s)"*) r=ok ;; *) r=no ;; esac
check "non-positive: five violations" ok "$r"

out=$(bash "$script" "$tmp/scanner-unbounded")
check "scanner-unbounded without flag: exit 0" 0 "$?"
out=$(bash "$script" --scanner-steps "$tmp/scanner-unbounded")
check "scanner-unbounded with flag: exit 1" 1 "$?"
case "$out" in *"step 'zaproxy/action-baseline@v0.15.0' in job 'j' has no timeout-minutes"*) r=ok ;; *) r=no ;; esac
check "scanner-unbounded: names step and job" ok "$r"

echo "== this repository =="

root=$(cd "$here/../../.." && pwd)
bash "$script" --scanner-steps "$root/.github/workflows" >/dev/null
check "own workflows bounded" 0 "$?"

echo "== action wiring =="

wf="$root/.github/workflows"
act="$here/action.yaml"
grep -q '^  workflows_path:' "$act" 2>/dev/null && grep -q 'default: ".github/workflows"' "$act"
check "action declares workflows_path" 0 "$?"
grep -q '^  check_scanner_steps:' "$act" 2>/dev/null && grep -q "default: 'false'" "$act"
check "action declares check_scanner_steps" 0 "$?"
for w in main-pr.yaml feature-push.yaml; do
	grep -q 'run: .github/actions/workflow-timeouts/workflow-timeouts-test.sh' "$wf/$w"
	check "$w runs the timeout tests" 0 "$?"
	grep -q 'uses: ./.github/actions/workflow-timeouts' "$wf/$w" &&
		grep -q 'check_scanner_steps: "true"' "$wf/$w"
	check "$w runs the gate with scanner steps" 0 "$?"
done
grep -q '^  test-workflow-timeouts:' "$wf/test-composite-actions.yaml"
check "test-composite-actions has test-workflow-timeouts" 0 "$?"

exit "$status"

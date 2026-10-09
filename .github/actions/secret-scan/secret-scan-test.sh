#!/usr/bin/env bash
# Offline tests for secret-scan.sh: commit-range resolution per event and the
# post-scan guard. Needs git and jq; no docker, no network.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091  # secret-scan.sh is resolved relative to this file
# shellcheck source=secret-scan.sh
. "$here/secret-scan.sh"

failures=0
ok() { echo "ok   - $1"; }
fail() {
	echo "FAIL - $1: $2" >&2
	failures=$((failures + 1))
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

gc() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }

# A bare origin with main (2 commits) and feature (2 commits on top of main),
# and a full clone of it in $work. Sets origin, work, main_sha, feat_sha,
# feat_parent.
make_fixture() {
	local seed="$tmp/seed"
	rm -rf "$seed" "$tmp/origin.git" "$tmp/work"
	git init -q -b main "$seed"
	(
		cd "$seed" || exit 1
		echo base >base.txt && git add base.txt && gc commit -q -m base
		echo main2 >>base.txt && gc commit -q -am main2
		git checkout -q -b feature
		echo f1 >f.txt && git add f.txt && gc commit -q -m f1
		echo f2 >>f.txt && gc commit -q -am f2
	)
	git clone -q --bare "$seed" "$tmp/origin.git"
	origin="$tmp/origin.git"
	git clone -q "$origin" "$tmp/work"
	work="$tmp/work"
	git -C "$work" checkout -q feature
	main_sha=$(git -C "$work" rev-parse origin/main)
	feat_sha=$(git -C "$work" rev-parse origin/feature)
	feat_parent=$(git -C "$work" rev-parse origin/feature~1)
}

payload() { printf '%s\n' "$2" >"$1"; }

# run_resolve EVENT PAYLOAD_JSON [BASE] [HEAD] -> sets out, rc
run_resolve() {
	payload "$tmp/event.json" "$2"
	out=$(cd "$work" && resolve_range "$1" "$tmp/event.json" "${3:-}" "${4:-}" 2>"$tmp/stderr")
	rc=$?
}

expect() { # NAME KEY VALUE
	if [ "$rc" -ne 0 ]; then
		fail "$1" "rc=$rc stderr=$(cat "$tmp/stderr")"
	elif ! grep -qx "$2=$3" <<<"$out"; then
		fail "$1" "wanted $2=$3, got: $(tr '\n' ' ' <<<"$out")"
	else
		ok "$1"
	fi
}

repo='"repository":{"default_branch":"main"}'

# --- pull_request ------------------------------------------------------------
make_fixture
run_resolve pull_request "{\"pull_request\":{\"base\":{\"sha\":\"$main_sha\"},\"head\":{\"sha\":\"$feat_sha\"}},$repo}"
expect "pull_request base is the PR base sha" BASE "$main_sha"
expect "pull_request head is the PR head sha" HEAD "$feat_sha"
expect "pull_request range has the branch's 2 commits" COMMITS 2

# --- push, ordinary ----------------------------------------------------------
run_resolve push "{\"before\":\"$feat_parent\",\"after\":\"$feat_sha\",$repo}"
expect "push scans before..after" BASE "$feat_parent"
expect "push range is the pushed commit" COMMITS 1

# --- push, new branch ----------------------------------------------------------
run_resolve push "{\"before\":\"$ZERO_SHA\",\"after\":\"$feat_sha\",$repo}"
expect "new branch falls back to merge-base with default branch" BASE "$main_sha"
expect "new branch scans only what it adds" COMMITS 2

# --- push, force-push (before unknown to the clone) ----------------------------
run_resolve push "{\"before\":\"1111111111111111111111111111111111111111\",\"after\":\"$feat_sha\",$repo}"
expect "force-push with absent before falls back to merge-base" BASE "$main_sha"

# --- push, force-push (before present but not an ancestor) ---------------------
run_resolve push "{\"before\":\"$main_sha\",\"after\":\"$feat_sha\",$repo}"
expect "ancestor before is used as-is" BASE "$main_sha"
side=$(cd "$work" && git checkout -q -b side "$main_sha" && echo s >s.txt && git add s.txt && gc commit -q -m side && git rev-parse HEAD)
git -C "$work" checkout -q feature
run_resolve push "{\"before\":\"$side\",\"after\":\"$feat_sha\",$repo}"
expect "non-ancestor before falls back to merge-base" BASE "$main_sha"

# --- push, branch deletion -----------------------------------------------------
run_resolve push "{\"before\":\"$feat_sha\",\"after\":\"$ZERO_SHA\",$repo}"
expect "branch deletion is an explicit skip" SKIP "branch deletion"

# --- push, new branch with no new commits -------------------------------------
run_resolve push "{\"before\":\"$ZERO_SHA\",\"after\":\"$main_sha\",$repo}"
expect "branch at default-branch tip is an explicit skip" SKIP "no commits in range"

# --- push to the default branch: never a silent skip (finding A) -----------------
run_resolve push "{\"ref\":\"refs/heads/main\",\"before\":\"$ZERO_SHA\",\"after\":\"$main_sha\",$repo}"
expect "first push of the default branch scans its whole history" BASE ""
expect "first push of the default branch has its commits" COMMITS 2
run_resolve push "{\"ref\":\"refs/heads/main\",\"before\":\"1111111111111111111111111111111111111111\",\"after\":\"$main_sha\",$repo}"
expect "force-push to the default branch scans its whole history" BASE ""
run_resolve push "{\"ref\":\"refs/heads/main\",\"before\":\"$side\",\"after\":\"$main_sha\",$repo}"
expect "non-ancestor force-push to the default branch scans whole history" BASE ""

# --- push, deletion-only commit ------------------------------------------------
del=$(cd "$work" && git rm -q f.txt && gc commit -q -m rm && git rev-parse HEAD)
run_resolve push "{\"before\":\"$feat_sha\",\"after\":\"$del\",$repo}"
expect "range adding no content is an explicit skip" SKIP "range adds no content"
git -C "$work" reset -q --hard "$feat_sha"

# --- binary-only and combined-commit ranges are not skipped (finding C) ----------
bin=$(cd "$work" && head -c 64 /dev/urandom >k.bin && git add k.bin && gc commit -q -m bin && git rev-parse HEAD)
run_resolve push "{\"before\":\"$feat_sha\",\"after\":\"$bin\",$repo}"
expect "a binary-only range is scanned, not skipped" COMMITS 1
git -C "$work" reset -q --hard "$feat_sha"
side2=$(cd "$work" && git checkout -q -b evil "$main_sha" && echo e >e.txt && git add e.txt && gc commit -q -m e && git rev-parse HEAD)
git -C "$work" checkout -q feature
evil=$(cd "$work" && gc merge -q --no-commit --no-ff "$side2" >/dev/null 2>&1 && echo SECRET >evil.txt && git add evil.txt && gc commit -q -m evilmerge && git rev-parse HEAD)
run_resolve push "{\"before\":\"$feat_sha\",\"after\":\"$evil\",$repo}"
if [ "$rc" -eq 0 ] && grep -qx 'COMMITS=2' <<<"$out" && ! grep -q '^SKIP=' <<<"$out"; then ok "a range of merge commits is scanned, not skipped"; else fail "merge range" "rc=$rc out=$out"; fi
# A merge range whose only added text is in the merge itself (no side-branch text).
git -C "$work" reset -q --hard "$feat_sha"
git -C "$work" checkout -q -b onlymerge "$feat_sha"
side3=$(cd "$work" && git checkout -q -b side3 "$feat_parent" && gc commit -q --allow-empty -m empty && git rev-parse HEAD)
git -C "$work" checkout -q onlymerge
om=$(cd "$work" && gc merge -q --no-commit --no-ff "$side3" >/dev/null 2>&1 && echo SECRET >om.txt && git add om.txt && gc commit -q -m onlymerge && git rev-parse HEAD)
run_resolve push "{\"before\":\"$feat_sha\",\"after\":\"$om\",$repo}"
if [ "$rc" -eq 0 ] && ! grep -q '^SKIP=' <<<"$out"; then ok "text only in a merge commit is scanned, not skipped"; else fail "evil merge" "rc=$rc out=$out"; fi
git -C "$work" checkout -q feature
git -C "$work" reset -q --hard "$feat_sha"

# --- other events: full-history audit -------------------------------------------
run_resolve workflow_dispatch "{$repo}"
expect "workflow_dispatch scans full history (empty base)" BASE ""
expect "workflow_dispatch head is HEAD" HEAD "$feat_sha"

# --- explicit inputs win ---------------------------------------------------------
run_resolve pull_request "{\"pull_request\":{\"base\":{\"sha\":\"$main_sha\"},\"head\":{\"sha\":\"$feat_sha\"}},$repo}" "$feat_parent" "$feat_sha"
expect "explicit base input overrides the event" BASE "$feat_parent"

# --- branch names as head/base, and an unresolvable ref_name (finding B) --------
pr_payload="{\"pull_request\":{\"base\":{\"sha\":\"$main_sha\"},\"head\":{\"sha\":\"$feat_sha\"}},$repo}"
git -C "$work" checkout -q --detach "$feat_sha"
run_resolve pull_request "$pr_payload" "" "feature"
expect "a branch name as head resolves through origin/<name>" HEAD "$feat_sha"
run_resolve pull_request "$pr_payload" "main" "feature"
expect "a branch name as base resolves through origin/<name>" BASE "$main_sha"
run_resolve pull_request "$pr_payload" "" "22/merge"
expect "an unresolvable <n>/merge head falls back to the event head" HEAD "$feat_sha"
expect "the event base is kept alongside the fallback head" BASE "$main_sha"
if grep -q '::warning::' "$tmp/stderr"; then ok "the fallback warns"; else fail "the fallback warns" "no warning"; fi
run_resolve push "{\"before\":\"$feat_parent\",\"after\":\"$feat_sha\",$repo}" "" "22/merge"
if [ "$rc" -ne 0 ]; then ok "an unresolvable head on a push event still fails"; else fail "push unresolvable head" "rc=$rc"; fi
git -C "$work" checkout -q feature

# --- the PRO-1297 regression: an unresolvable head fails, never passes ----------
run_resolve pull_request "{$repo}" "" "22/merge"
if [ "$rc" -ne 0 ] && grep -q '::error::' "$tmp/stderr" && grep -q 'persist-credentials' "$tmp/stderr"; then
	ok "unresolvable head fails with an error"
else
	fail "unresolvable head fails with an error" "rc=$rc out=$out"
fi

# --- shallow clone is deepened, not failed -------------------------------------
rm -rf "$tmp/work"
git clone -q --depth 1 --branch feature "file://$origin" "$tmp/work"
work="$tmp/work"
run_resolve pull_request "{\"pull_request\":{\"base\":{\"sha\":\"$main_sha\"},\"head\":{\"sha\":\"$feat_sha\"}},$repo}"
expect "shallow clone is unshallowed and resolves the PR range" COMMITS 2

# --- guard ---------------------------------------------------------------------
# run_guard NAME LOG_CONTENT STATUS WANT(pass|fail)
run_guard() {
	printf '%s\n' "$2" >"$tmp/scan.log"
	(guard "$tmp/scan.log" "$3") >/dev/null 2>"$tmp/stderr"
	local got=$?
	if { [ "$4" = pass ] && [ "$got" -eq 0 ]; } || { [ "$4" = fail ] && [ "$got" -eq 1 ] && grep -q '::error::secret-scan:' "$tmp/stderr"; }; then
		ok "$1"
	else
		fail "$1" "wanted $4, rc=$got stderr=$(cat "$tmp/stderr")"
	fi
}

# Verbatim from the PRO-1297 evidence (va-varip run 31523764066).
pr_noop='{"level":"error","logger":"trufflehog","msg":"encountered errors during scan","errors":["error chunking dir \"/tmp/trufflehog-18-2783961408\": unable to resolve ref: no base refs succeeded for base: \"22/merge\""]}
{"level":"info-0","msg":"finished scanning","chunks":0,"bytes":0,"verified_secrets":0,"unverified_secrets":0,"scan_duration":"362.345316ms"}'
good='{"level":"info-0","msg":"finished scanning","chunks":979,"bytes":4205183,"verified_secrets":0,"unverified_secrets":0}'
zero='{"level":"info-0","msg":"finished scanning","chunks":0,"bytes":0,"verified_secrets":0,"unverified_secrets":0}'

run_guard "the PRO-1297 no-op pull_request log fails" "$pr_noop" 0 fail
run_guard "a real scan with no findings passes" "$good" 0 pass
run_guard "zero chunks without an error line still fails" "$zero" 0 fail
run_guard "zero chunks names the exclusion cause" "$zero" 0 fail
grep -q 'exclude' "$tmp/stderr" || fail "zero-chunk message names exclusions" "$(cat "$tmp/stderr")"
run_guard "a log with no finished-scanning summary fails" '{"level":"info-0","msg":"starting"}' 0 fail
run_guard "findings (exit 183) fail" "$good" 183 fail
run_guard "any other scanner exit fails" "$good" 1 fail

# --- pinned scanner version --------------------------------------------------
# The default scan runs one exact TruffleHog release, pinned by image digest;
# the release tag is kept beside it as a constant naming the digest's release.
if [[ "${TRUFFLEHOG_VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	ok "TRUFFLEHOG_VERSION is an exact release"
else
	fail "TRUFFLEHOG_VERSION is an exact release" "got '${TRUFFLEHOG_VERSION:-}'"
fi
if [[ "${TRUFFLEHOG_DIGEST:-}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
	ok "TRUFFLEHOG_DIGEST is a well-formed sha256 digest"
else
	fail "TRUFFLEHOG_DIGEST is a well-formed sha256 digest" "got '${TRUFFLEHOG_DIGEST:-}'"
fi

action_default=$(awk '/^  version:/ { f = 1 } f && /default:/ { gsub(/["[:space:]]/, "", $2); print $2; exit }' "$here/action.yaml")
if [ -z "$action_default" ]; then
	ok "action.yaml version default is empty, so the digest pin applies"
else
	fail "action.yaml version default is empty, so the digest pin applies" "action.yaml default='$action_default'"
fi

# Scan every file under .github for a floating scanner reference. This test
# file names the patterns, so it is excluded. A digest ref (@sha256:) is the pin
# itself, not a float.
github_dir="$here/../.."
floats=$(grep -rnE 'trufflesecurity/trufflehog@|trufflehog:latest|:-latest' "$github_dir" 	--exclude=secret-scan-test.sh | grep -v 'trufflehog@sha256:')
if [ -z "$floats" ]; then
	ok "no file under .github floats the scanner on @ref or latest"
else
	fail "no file under .github floats the scanner on @ref or latest" "$floats"
fi

img=ghcr.io/trufflesecurity/trufflehog
got=$(scanner_ref "" "" 2>&1)
if [ "$got" = "$img@${TRUFFLEHOG_DIGEST:-}" ] && [[ "$got" =~ @sha256:[0-9a-f]{64}$ ]]; then
	ok "scanner_ref defaults to the pinned image by digest"
else
	fail "scanner_ref defaults to the pinned image by digest" "got '$got'"
fi
got=$(scanner_ref "" 3.1.0 2>&1)
if [ "$got" = "$img:3.1.0" ]; then
	ok "scanner_ref uses the tag when the caller sets version"
else
	fail "scanner_ref uses the tag when the caller sets version" "got '$got'"
fi
got=$(scanner_ref example/img 1.2.3 2>&1)
if [ "$got" = "example/img:1.2.3" ]; then
	ok "scanner_ref honours a caller's image and version"
else
	fail "scanner_ref honours a caller's image and version" "got '$got'"
fi
got=$(scanner_ref "$img@sha256:abc" 9.9.9 2>&1)
if [ "$got" = "$img@sha256:abc" ]; then
	ok "scanner_ref uses an image carrying a digest as-is"
else
	fail "scanner_ref uses an image carrying a digest as-is" "got '$got'"
fi
got=$(scanner_ref localhost:5000/img:7 "" 2>&1)
if [ "$got" = "localhost:5000/img:7" ]; then
	ok "scanner_ref uses an image carrying a tag as-is"
else
	fail "scanner_ref uses an image carrying a tag as-is" "got '$got'"
fi
got=$(scanner_ref localhost:5000/img 1.0 2>&1)
if [ "$got" = "localhost:5000/img:1.0" ]; then
	ok "scanner_ref treats a registry port as no tag"
else
	fail "scanner_ref treats a registry port as no tag" "got '$got'"
fi

readme_row=$(grep -E '^\| `version` ' "$here/README.md")
if [ -n "${TRUFFLEHOG_VERSION:-}" ] && grep -Fq "$TRUFFLEHOG_VERSION" <<<"$readme_row" && grep -qi 'digest' <<<"$readme_row"; then
	ok "README inputs table names the pinned release and the digest"
else
	fail "README inputs table names the pinned release and the digest" "row: $readme_row"
fi
if grep -q '^## Scanner version' "$here/README.md"; then
	ok "README documents how to bump the scanner"
else
	fail "README documents how to bump the scanner" "no '## Scanner version' section"
fi

if [ "$failures" -ne 0 ]; then
	echo "$failures test(s) failed" >&2
	exit 1
fi
echo "all secret-scan tests passed"

#!/usr/bin/env bash
# Docker integration test for secret-scan.sh: a private key added on a pull
# request branch must fail the scan, a clean branch must pass, and an
# unresolvable <n>/merge head must fall back to the event's head. The key is
# generated here, never committed.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script="$here/secret-scan.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0
gc() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }

seed="$tmp/seed"
git init -q -b main "$seed"
(cd "$seed" && echo base >README && git add README && gc commit -q -m base)
main_sha=$(git -C "$seed" rev-parse HEAD)
(cd "$seed" && git checkout -q -b clean && echo hello >notes.txt && git add notes.txt && gc commit -q -m clean)
clean_sha=$(git -C "$seed" rev-parse HEAD)
(cd "$seed" && git checkout -q -b leak "$main_sha" && openssl genrsa 2048 2>/dev/null >id.pem && git add id.pem && gc commit -q -m leak)
leak_sha=$(git -C "$seed" rev-parse HEAD)
git clone -q --bare "$seed" "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/work"

# scan NAME HEAD_SHA WANT(pass|fail) [INPUT_HEAD]
scan() {
	printf '{"pull_request":{"base":{"sha":"%s"},"head":{"sha":"%s"}},"repository":{"default_branch":"main"}}\n' \
		"$main_sha" "$2" >"$tmp/event.json"
	(cd "$tmp/work" && GITHUB_EVENT_NAME=pull_request GITHUB_EVENT_PATH="$tmp/event.json" \
		INPUT_HEAD="${4:-}" INPUT_EXTRA_ARGS="--json --no-verification" bash "$script") >"$tmp/out" 2>&1
	local rc=$?
	if { [ "$3" = pass ] && [ "$rc" -eq 0 ]; } || { [ "$3" = fail ] && [ "$rc" -ne 0 ]; }; then
		echo "ok   - $1"
	else
		echo "FAIL - $1 (rc=$rc)" >&2
		cat "$tmp/out" >&2
		failures=$((failures + 1))
	fi
}

scan "a pull request adding a private key fails" "$leak_sha" fail
grep -q 'reported secrets' "$tmp/out" || { echo "FAIL - leak failure names the finding" >&2; failures=$((failures + 1)); }
scan "a clean pull request passes" "$clean_sha" pass
scan "an unresolvable <n>/merge head falls back to the event head and passes" "$clean_sha" pass "22/merge"
scan "an unresolvable <n>/merge head still catches a leak in the event head" "$leak_sha" fail "22/merge"

[ "$failures" -eq 0 ] || exit 1
echo "all secret-scan canary tests passed"

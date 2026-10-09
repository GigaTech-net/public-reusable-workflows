#!/usr/bin/env bash
# Tests for docs-only.sh: path classification, and diff resolution against a
# throwaway git repository. No framework; bash 3.2 compatible so it runs on
# macOS as well as the runners.
#
# Run from anywhere. Exits non-zero if any case fails.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script="$here/docs-only.sh"
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

# classify with the default globs, paths given as arguments.
cls() {
	local p
	for p in "$@"; do printf '%s\n' "$p"; done | classify "$DEFAULT_DOCS_PATHS"
}

echo "== classification =="
check "root README.md" true "$(cls README.md)"
check "nested markdown" true "$(cls a/b/c.md)"
check "markdown under .github" true "$(cls .github/actions/x/README.md)"
check "docs tree, non-code files" true "$(cls docs/guide.md docs/img/a.png)"
check "root LICENSE" true "$(cls LICENSE)"
check "path with a space" true "$(cls 'my notes.md')"
check "markdown plus a manifest" false "$(cls README.md package.json)"
check "manifest under docs/" false "$(cls docs/package.json)"
check "requirements under docs/" false "$(cls docs/requirements.txt)"
check "pom under docs/" false "$(cls docs/site/pom.xml)"
check "lockfile under docs/" false "$(cls docs/yarn.lock)"
check "shell script under docs/" false "$(cls docs/x.sh)"
check "python under docs/" false "$(cls docs/x.py)"
check "yaml under docs/" false "$(cls docs/x.yml)"
check "json under docs/" false "$(cls docs/data.json)"
check "Dockerfile under docs/" false "$(cls docs/Dockerfile.dev)"
check "docs/ markdown beside an image" true "$(cls docs/guide.md docs/img.png)"
check "deny list wins over docs globs" false "$(cls docs/guide.md docs/x.sh)"
check "empty deny list allows docs/ files" true "$(printf 'docs/x.sh\n' | classify "$DEFAULT_DOCS_PATHS" '')"
check "custom deny list" false "$(printf 'docs/a.txt\n' | classify 'docs/**' '**/*.txt')"
check "workflow yaml" false "$(cls .github/workflows/main-pr.yaml)"
check "docs/ is anchored at the root" false "$(cls src/docs/x.py)"
check "docs- prefix is not docs/" false "$(cls docs-old/x.py)"
check "markdown backup suffix" false "$(cls notes.md.orig)"
check "vendored LICENSE" false "$(cls vendor/lib/LICENSE)"
check "LICENSE with suffix" false "$(cls LICENSE.txt)"
check "empty change" false "$(printf '' | classify "$DEFAULT_DOCS_PATHS")"
check "custom globs" true "$(printf 'a.txt\nb/c.txt\n' | classify '**/*.txt')"
check "globs split on newlines" true "$(printf 'x.rst\n' | classify "$(printf '*.md\n*.rst')")"
check "dot is literal" false "$(printf 'READMEXmd\n' | classify '*.md')"
check "no globs at all" false "$(printf 'README.md\n' | classify ' , ')"

echo "== glob_to_regex =="
check "**/ is zero or more directories" '^([^/]+/)*[^/]*\.md$' "$(glob_to_regex '**/*.md')"
check "trailing ** is anything" '^docs/.*$' "$(glob_to_regex 'docs/**')"

echo "== diff resolution =="
repo=$(mktemp -d "${TMPDIR:-/tmp}/docs-only-test.XXXXXX")
trap 'rm -rf "$repo"' EXIT
out="$repo/.output"

g() { git -C "$repo/w" -c user.name=t -c user.email=t@example.invalid "$@"; }
commit() {
	local f
	for f in "$@"; do
		mkdir -p "$repo/w/$(dirname "$f")"
		echo "$RANDOM" >>"$repo/w/$f"
	done
	g add -A && g commit -qm change
}
run() { # EVENT BASE HEAD BRANCH -> prints the docs_only value
	: >"$out"
	(cd "$repo/w" && EVENT_NAME="$1" BASE_SHA="$2" HEAD_SHA="$3" \
		DEFAULT_BRANCH="$4" GITHUB_OUTPUT="$out" bash "$script" >/dev/null)
	sed -n 's/^docs_only=//p' "$out"
}

mkdir -p "$repo/w"
git -C "$repo/w" init -q
commit app.py package.json README.md
base=$(g rev-parse HEAD)
g update-ref refs/remotes/origin/main "$base"

commit README.md docs/guide.md
docs_head=$(g rev-parse HEAD)
check "pull_request, docs only" true "$(run pull_request "$base" "$docs_head" main)"
check "push, docs only vs origin/main" true "$(run push "" "$docs_head" main)"

commit app.py
code_head=$(g rev-parse HEAD)
check "pull_request, code changed" false "$(run pull_request "$base" "$code_head" main)"

commit README.md
check "push, last commit docs but branch has code" false "$(run push "" "$(g rev-parse HEAD)" main)"

# A fixture step that silently fails would make the next case pass for the
# wrong reason, so these two abort the whole test instead.
g checkout -q -b rename "$base"
mkdir -p "$repo/w/docs"
g mv app.py docs/app.md && g commit -qm rename || exit 1
check "rename of code into docs/" false "$(run pull_request "$base" "$(g rev-parse HEAD)" main)"

# git C-quotes a path holding a newline, so it cannot be split into a
# docs-looking line plus a code line; it must fail closed.
g checkout -q -b newline "$base"
nl_dir=$(printf 'x.md\ndocs')
mkdir -p "$repo/w/$nl_dir"
echo 'echo hi' >"$repo/w/$nl_dir/run.sh"
g add -A && g commit -qm newline || exit 1
check "path containing a newline" false "$(run pull_request "$base" "$(g rev-parse HEAD)" main)"

g checkout -q -b delete "$base"
g rm -q package.json && g commit -qm delete || exit 1
check "deleting a manifest" false "$(run pull_request "$base" "$(g rev-parse HEAD)" main)"

echo "== fail open =="
check "unknown base sha" false "$(run pull_request deadbeef "$docs_head" main)"
check "empty base sha" false "$(run pull_request "" "$docs_head" main)"
check "unknown head sha" false "$(run push "" deadbeef main)"
check "no origin ref for branch" false "$(run push "" "$docs_head" trunk)"
check "workflow_dispatch" false "$(run workflow_dispatch "$base" "$docs_head" main)"
check "empty changeset" false "$(run push "" "$base" main)"

: >"$out"
(cd "$repo/w" && EVENT_NAME=pull_request BASE_SHA=deadbeef HEAD_SHA="$docs_head" \
	DEFAULT_BRANCH=main GITHUB_OUTPUT="$out" bash "$script" >/dev/null)
check "fail open exits 0" 0 "$?"
check "fail open writes a reason" 1 "$(grep -c '^reason=.\+' "$out")"
check "writes exactly two outputs" 2 "$(wc -l <"$out" | tr -d ' ')"

echo
if [ "$status" = 0 ]; then
	echo "docs-only: all cases pass"
else
	echo "docs-only: failures above" >&2
fi
exit "$status"

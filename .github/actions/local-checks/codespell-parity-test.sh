#!/usr/bin/env bash
# Asserts that local-checks.sh invokes codespell with the same flags as
# .github/actions/spellcheck/action.yaml.
#
# This exists because a comment claiming "keep these in step" is not a
# constraint. The prototype script had already drifted by the time it was
# reviewed: it carried two extra --skip entries (./.git, ./report) and one extra
# -L word (iif) that the action does not have. Both looked harmless and both
# meant a local pass could not predict CI -- which is the script's only job.
# Repository-specific words belong in WORDS_TO_IGNORE / FILES_TO_IGNORE, which
# mirror the action's inputs; they must not be baked into the base lists.
#
# Run from anywhere inside the repository. Exits non-zero on any divergence.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/../../.." && pwd)
action="$root/.github/actions/spellcheck/action.yaml"
script="$here/local-checks.sh"

for f in "$action" "$script"; do
	[ -f "$f" ] || {
		echo "missing: $f" >&2
		exit 1
	}
done

# The value inside the quotes on the action's `--skip "..."` / `-L "..."` line,
# with the trailing shell placeholder ($FILES_TO_IGNORE / $WORDS_TO_IGNORE) and
# the comma before it removed -- that placeholder is where a consumer's own
# additions land, so it is not part of the base list.
action_list() {
	grep -m1 -E "^[[:space:]]*$1 \"" "$action" |
		sed -E 's/^[^"]*"//; s/"[[:space:]]*\\?[[:space:]]*$//; s/,\$[A-Za-z_]+$//'
}

# The value of a CODESPELL_*_BASE assignment in the script.
script_list() {
	grep -m1 -E "^$1=" "$script" | sed -E "s/^$1=\"//; s/\"$//"
}

status=0
compare() {
	local label="$1" want="$2" got="$3"
	if [ "$want" = "$got" ]; then
		printf '  ok   %s matches the spellcheck action\n' "$label"
	else
		printf '  FAIL %s diverges from the spellcheck action\n' "$label"
		printf '       action: %s\n' "$want"
		printf '       script: %s\n' "$got"
		status=1
	fi
}

echo "== codespell flag parity =="
compare "--skip" "$(action_list "--skip")" "$(script_list CODESPELL_SKIP_BASE)"
compare "-L" "$(action_list "-L")" "$(script_list CODESPELL_IGNORE_BASE)"

# Comments must be stripped before scanning for a flag. Both files *discuss* -D
# in prose, so a bare grep found it even after the real flag was deleted -- the
# first negative test of this file passed when it should have failed. Comment
# lines matching the thing being searched for is a recurring way these assertions
# go quietly useless.
code_only() { grep -vE '^[[:space:]]*#' "$1"; }

# Snapshotted into variables rather than piped straight into `grep -q`. The two
# look equivalent and are not: `grep -q` exits at its first match and closes the
# pipe, so the upstream `code_only` grep can lose the race to finish writing and
# take an EPIPE (exit 2) -- and `set -o pipefail` then reports the whole pipeline
# as failed, turning a flag that IS present into `present=0`. Whichever flag
# matches earliest is the one that trips, which is why CI reported
# `-D present in action=1 script=0`: -D sits at code line 138 of local-checks.sh
# while --count and --quiet-level 2 sit at 143, late enough to usually win the
# race. A herestring has no upstream process, so there is nothing left to fail.
action_code=$(code_only "$action")
script_code=$(code_only "$script")

# The remaining flags are fixed rather than list-valued, so assert presence in
# both. -D matters most: it replaces codespell's built-in dictionary with the
# project's master copy, so omitting it locally would check different words.
for flag in "--count" "--quiet-level 2" "-D"; do
	a=0
	s=0
	grep -qE -- "$flag" <<<"$action_code" && a=1
	grep -qE -- "$flag" <<<"$script_code" && s=1
	if [ "$a" = 1 ] && [ "$s" = 1 ]; then
		printf '  ok   %s present in both\n' "$flag"
	else
		printf '  FAIL %s present in action=%s script=%s\n' "$flag" "$a" "$s"
		status=1
	fi
done

echo
if [ "$status" = 0 ]; then
	echo "codespell invocation is identical"
else
	echo "codespell invocation has diverged -- local runs no longer predict CI" >&2
fi
exit "$status"

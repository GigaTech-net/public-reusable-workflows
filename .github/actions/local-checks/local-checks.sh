#!/usr/bin/env bash
# Runs the five checks CI runs. One definition serves CI and the developer's
# machine, so "it passed locally" means the same thing in both places.
#
# Why this exists: PRs were pushed having passed markdownlint and yamllint
# locally, then failed CI on checks that were never run locally at all --
# codespell with the org word list, and Super-Linter. Each cost a full CI round
# trip. Checking a subset locally is worse than checking nothing: it feels like
# verification while leaving the two slowest-to-discover checks unrun.
#
# Usage, locally, with no copied files (reusable-workflows is private, so this
# goes through `gh` rather than curl):
#
#   gh api repos/GigaTech-net/public-reusable-workflows/contents/\
#   .github/actions/local-checks/local-checks.sh?ref=v1 --jq .content \
#     | base64 -d | bash
#
#   CHECKS=markdownlint,codespell ... | base64 -d | bash    # a subset
#   FAST=true                        ... | base64 -d | bash # skip Super-Linter
#
# In CI it is the `local-checks` composite action, which passes the same
# settings as environment variables.
#
# Everything is configured by environment variable because the local entry point
# is a pipe into bash, where positional arguments are awkward to pass.
set -uo pipefail

CHECKS="${CHECKS:-all}"
FAST="${FAST:-false}"
WORDS_TO_IGNORE="${WORDS_TO_IGNORE:-}"
FILES_TO_IGNORE="${FILES_TO_IGNORE:-}"
SUPER_LINTER_VERSION="${SUPER_LINTER_VERSION:-slim-v8.6.0}"

# ---------------------------------------------------------------------------
# The codespell base flags. These MUST equal the ones in
# .github/actions/spellcheck/action.yaml -- if the two drift, this script stops
# predicting CI, which is its only purpose. codespell-parity-test.sh asserts the
# equality mechanically and runs in this repository's own CI; it is not a comment
# asking to be trusted.
#
# Repository-specific additions belong in WORDS_TO_IGNORE / FILES_TO_IGNORE,
# mirroring the action's wordsToIgnore / filesToIgnore inputs. They are appended
# in the same position the action appends them, so a consumer that passes the
# same values gets a byte-identical invocation.
# ---------------------------------------------------------------------------
CODESPELL_SKIP_BASE="./output,./input-cache,./temp,./template,./fsh-generated,./dictionary.txt,.gitignore,./src,./venv,.dockerignore,Dockerfile,package.json,package-lock.json"
CODESPELL_IGNORE_BASE="ehr,requestor,promis,loinc,recengine,sdvosb"

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
	echo "not inside a git repository" >&2
	exit 1
}
cd "$root" || exit 1

FAILED=()
pass() { printf '  \033[32mok\033[0m   %s\n' "$1"; }
fail() {
	printf '  \033[31mFAIL\033[0m %s\n' "$1"
	FAILED+=("$1")
}
skip() { printf '  \033[33mskip\033[0m %s\n' "$1"; }

# Substring match is wrong here: `super-linter` contains `linter`, and a
# CHECKS=yamllint would then also enable anything whose name contains it.
wanted() {
	[ "$CHECKS" = all ] && return 0
	case ",${CHECKS}," in
	*",$1,"*) return 0 ;;
	esac
	return 1
}

# Log to a directory that exists on both macOS and the runners, and that is not
# inside the checkout -- writing logs into the tree is how jscpd's report/
# directory ended up committed to a PR.
LOGDIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
LOGDIR="${LOGDIR%/}"

# ---------------------------------------------------------------------------
if wanted markdownlint; then
	echo "== markdownlint =="
	cfg=.github/linters/.markdown-lint.yml
	if ! command -v npx >/dev/null 2>&1; then
		skip "markdownlint (npx not found)"
	elif [ ! -f "$cfg" ]; then
		skip "markdownlint (no $cfg)"
	elif npx --yes markdownlint-cli2 --config "$cfg" "**/*.md" \
		>"$LOGDIR/mdl.log" 2>&1; then
		pass "markdownlint-cli2"
	else
		fail "markdownlint-cli2"
		grep -E '^[^ ].*:[0-9]+' "$LOGDIR/mdl.log" | head -20
	fi
fi

# ---------------------------------------------------------------------------
if wanted yamllint; then
	echo "== yamllint =="
	cfg=.github/linters/.yaml-lint.yml
	# No mapfile: macOS ships bash 3.2.
	YAML=()
	while IFS= read -r f; do YAML+=("$f"); done < <(
		git ls-files '*.yaml' '*.yml' | grep -v '^report/'
	)
	if [ ! -f "$cfg" ]; then
		skip "yamllint (no $cfg)"
	elif [ ${#YAML[@]} -eq 0 ]; then
		skip "yamllint (no files)"
	elif ! python3 -c 'import yamllint' 2>/dev/null; then
		skip "yamllint (pip install yamllint)"
	elif python3 -m yamllint -c "$cfg" "${YAML[@]}" \
		>"$LOGDIR/yl.log" 2>&1; then
		pass "yamllint (${#YAML[@]} files)"
	else
		fail "yamllint"
		head -20 "$LOGDIR/yl.log"
	fi
fi

# ---------------------------------------------------------------------------
if wanted actionlint; then
	echo "== actionlint =="
	if ! command -v actionlint >/dev/null 2>&1; then
		skip "actionlint (not installed: brew install actionlint)"
	else
		actionlint >"$LOGDIR/al.log" 2>&1
		# Fail only on actionlint's own findings. Its embedded shellcheck
		# reports style issues that predate this tooling and that CI does not
		# fail on; treating them as errors here makes the script cry wolf and
		# get ignored, which is the failure mode that matters most.
		own=$(grep -vE 'shellcheck reported issue' "$LOGDIR/al.log" |
			grep -cE '^\S+\.ya?ml:[0-9]+:[0-9]+: ' || true)
		advisory=$(grep -cE 'shellcheck reported issue' "$LOGDIR/al.log" || true)
		if [ "$own" -gt 0 ]; then
			fail "actionlint"
			grep -vE 'shellcheck reported issue' "$LOGDIR/al.log" |
				grep -E '^\S+\.ya?ml:' | head -20
		elif [ "$advisory" -gt 0 ]; then
			pass "actionlint ($advisory pre-existing shellcheck advisories, not failing)"
		else
			pass "actionlint"
		fi
	fi
fi

# ---------------------------------------------------------------------------
# The check that caught nobody, twice.
if wanted codespell; then
	echo "== codespell (same flags as the spellcheck action) =="
	skip_list="$CODESPELL_SKIP_BASE"
	[ -n "$FILES_TO_IGNORE" ] && skip_list="$skip_list,$FILES_TO_IGNORE"

	# Gitignored paths that happen to exist in the working tree are excluded, and
	# this is a fidelity fix rather than a convenience. CI runs against a fresh
	# checkout, which contains tracked files only, so build output is not part of
	# what CI checks. Locally it is sitting right there: a stale `report/` from a
	# previous Super-Linter run produced 96 findings in minified JavaScript, none
	# of which CI could ever see.
	#
	# The prototype handled this by adding ./report to its base --skip list, which
	# is exactly the drift the parity test now forbids -- it silently changed what
	# CI was believed to check. Deriving the paths from git instead keeps the base
	# list equal to the action's while making the *file set* match CI's.
	ignored=""
	while IFS= read -r p; do
		[ -n "$p" ] && ignored="${ignored},./${p}"
	done < <(
		git ls-files --others --ignored --exclude-standard --directory 2>/dev/null |
			cut -d/ -f1 | sort -u
	)
	if [ -n "$ignored" ]; then
		skip_list="${skip_list}${ignored}"
		printf '       skipping gitignored paths absent from CI:%s\n' \
			"$(echo "$ignored" | tr ',' ' ')"
	fi
	ignore_list="$CODESPELL_IGNORE_BASE"
	[ -n "$WORDS_TO_IGNORE" ] && ignore_list="$ignore_list,$WORDS_TO_IGNORE"

	if command -v codespell >/dev/null 2>&1; then
		CS=(codespell)
	elif python3 -c 'import codespell_lib' 2>/dev/null; then
		CS=(python3 -m codespell_lib)
	else
		CS=()
	fi

	if [ ${#CS[@]} -eq 0 ]; then
		skip "codespell (pip install codespell)"
	else
		# The action passes -D pointing at codespell's master dictionary, which
		# overrides the built-in set. Using the built-in here instead would make
		# local and CI disagree on the very words being checked, so fetch the
		# same file. Cached: it is ~1 MB and changes rarely.
		dict="$LOGDIR/gt-codespell-dictionary.txt"
		if [ ! -s "$dict" ]; then
			url=https://raw.githubusercontent.com/codespell-project/codespell/master/codespell_lib/data/dictionary.txt
			if command -v curl >/dev/null 2>&1; then
				curl -fsSL -o "$dict" "$url" || true
			elif command -v wget >/dev/null 2>&1; then
				wget -q -O "$dict" "$url" || true
			fi
		fi
		DICT=()
		if [ -s "$dict" ]; then
			DICT=(-D "$dict")
		else
			echo "       NOTE: could not fetch codespell's master dictionary;"
			echo "       using the built-in one, which CI does not use"
		fi
		if "${CS[@]}" "${DICT[@]}" --count --quiet-level 2 \
			--skip "$skip_list" -L "$ignore_list" \
			>"$LOGDIR/cs.log" 2>&1; then
			pass "codespell"
		else
			fail "codespell"
			head -20 "$LOGDIR/cs.log"
			echo "       A genuine term goes in this repository's wordsToIgnore"
			echo "       input to the spellcheck action AND in WORDS_TO_IGNORE"
			echo "       here -- never in CODESPELL_IGNORE_BASE, which must stay"
			echo "       equal to the action's list."
		fi
	fi
fi

# ---------------------------------------------------------------------------
# Super-Linter reads .github/super-linter.env, so running it locally is the only
# way to catch a missing VALIDATE_* before CI does.
if wanted super-linter; then
	echo "== super-linter =="
	envfile=.github/super-linter.env
	if [ "$FAST" = true ]; then
		skip "super-linter (fast mode)"
	elif ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
		skip "super-linter (Docker not running)"
	else
		# No DEFAULT_BRANCH: RUN_LOCAL does not need it, and setting it
		# alongside USE_FIND_ALGORITHM=true is rejected outright --
		# "Super-linter doesn't consider the value DEFAULT_BRANCH when not
		# using Git."
		ARGS=(-e RUN_LOCAL=true -e VALIDATE_ALL_CODEBASE=true
			-e ENABLE_GITHUB_ACTIONS_STEP_SUMMARY=false)
		if [ -f "$envfile" ]; then
			while IFS= read -r line || [ -n "$line" ]; do
				case "$line" in
				'' | \#*) continue ;;
				# Forced above for a full local scan.
				RUN_LOCAL=* | VALIDATE_ALL_CODEBASE=*) continue ;;
				esac
				ARGS+=(-e "$line")
			done <"$envfile"
		else
			echo "       NOTE: no $envfile -- Super-Linter falls through to its"
			echo "       own defaults, which is every linter over the whole"
			echo "       codebase. See templates/super-linter.env."
		fi
		# Super-Linter publishes no linux/arm64 image, so Apple Silicon has to
		# emulate. Slower, but it is the only way to reproduce the CI result.
		PLATFORM=()
		[ "$(uname -m)" = "arm64" ] && PLATFORM=(--platform linux/amd64)
		if docker run --rm "${PLATFORM[@]}" "${ARGS[@]}" -v "$PWD:/tmp/lint" \
			"ghcr.io/super-linter/super-linter:${SUPER_LINTER_VERSION}" \
			>"$LOGDIR/sl.log" 2>&1; then
			pass "super-linter"
		else
			fail "super-linter"
			grep -E '\[ERROR\]|no matching manifest' "$LOGDIR/sl.log" |
				grep -v 'GitHub Commit Status' | head -20
			echo "       full log: $LOGDIR/sl.log"
		fi
	fi
fi

# ---------------------------------------------------------------------------
echo
if [ ${#FAILED[@]} -eq 0 ]; then
	printf '\033[32mall local checks passed\033[0m\n'
else
	printf '\033[31m%d check(s) failed: %s\033[0m\n' "${#FAILED[@]}" "${FAILED[*]}"
	exit 1
fi

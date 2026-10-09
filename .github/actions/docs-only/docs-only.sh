#!/usr/bin/env bash
# Decides whether a change touches only documentation, so the quality-checks
# job can skip the scans that cannot act on documentation while still
# reporting its required status context.
#
# Writes two outputs to $GITHUB_OUTPUT (stdout when unset):
#   docs_only=true|false
#   reason=<one line>
#
# FAILS OPEN. Any uncertainty -- a missing commit, no merge base, a failed
# diff, an empty change, an unrecognised event -- yields docs_only=false, so the
# full gate runs. It exits 0 in all of those cases: a classifier problem must
# never fail the required check by itself.
#
# Inputs, all environment variables:
#   EVENT_NAME      push | pull_request; anything else is not docs-only
#   BASE_SHA        pull_request only: the PR base commit
#   HEAD_SHA        the commit under test
#   DEFAULT_BRANCH  push only: compared against origin/<DEFAULT_BRANCH>
#   DOCS_PATHS      comma- or newline-separated globs; see DEFAULT_DOCS_PATHS
#   NOT_DOCS_PATHS  same form; a changed path matching one is never
#                   documentation, even under DOCS_PATHS. Set but empty means
#                   no deny list; unset means DEFAULT_NOT_DOCS_PATHS.
#
# Sourceable: the test sources it for classify and glob_to_regex, and main runs
# only when the file is executed. Bash 3.2 compatible (macOS).
set -uo pipefail

DEFAULT_DOCS_PATHS='**/*.md,docs/**,LICENSE'

# Paths that are never documentation, wherever they sit, including under
# docs/: dependency manifests and lockfiles, and code and configuration file
# types. The scans being skipped act on exactly these.
DEFAULT_NOT_DOCS_PATHS='**/package.json,**/package-lock.json,**/yarn.lock,**/pnpm-lock.yaml,'
DEFAULT_NOT_DOCS_PATHS+='**/requirements*.txt,**/Pipfile*,**/pyproject.toml,**/poetry.lock,'
DEFAULT_NOT_DOCS_PATHS+='**/pom.xml,**/*.gradle,**/*.gradle.kts,**/go.mod,**/go.sum,'
DEFAULT_NOT_DOCS_PATHS+='**/Gemfile*,**/Cargo.toml,**/Cargo.lock,**/*.csproj,**/Dockerfile*,'
DEFAULT_NOT_DOCS_PATHS+='**/*.sh,**/*.py,**/*.js,**/*.ts,**/*.yml,**/*.yaml,**/*.json'

# Same dialect as pr-gate's sensitive_paths: '**/' is zero or more whole
# directories, '**' is anything, '*' and '?' stay within one path segment.
# Everything else is literal.
glob_to_regex() {
	local g="$1" out="" c i=0 n=${#1}
	while [ "$i" -lt "$n" ]; do
		c="${g:$i:1}"
		if [ "${g:$i:3}" = '**/' ]; then
			out+='([^/]+/)*'
			i=$((i + 3))
			continue
		elif [ "${g:$i:2}" = '**' ]; then
			out+='.*'
			i=$((i + 2))
			continue
		fi
		case "$c" in
		'*') out+='[^/]*' ;;
		'?') out+='[^/]' ;;
		'.' | '+' | '^' | '$' | '{' | '}' | '(' | ')' | '|' | '[' | ']' | "\\") out+="\\$c" ;;
		*) out+="$c" ;;
		esac
		i=$((i + 1))
	done
	printf '^%s$' "$out"
}

# Prints one anchored regex per glob in the comma- or newline-separated list $1.
globs_to_regexes() {
	local g parts=()
	IFS=',' read -r -a parts <<<"$(printf '%s' "$1" | tr '\n' ',')"
	for g in ${parts[@]+"${parts[@]}"}; do
		g="${g#"${g%%[![:space:]]*}"}"
		g="${g%"${g##*[![:space:]]}"}"
		[ -n "$g" ] && glob_to_regex "$g" && echo
	done
	return 0
}

# Reads paths, one per line, on stdin. Prints true when there is at least one
# path, no path matches a glob in $2, and every path matches one of the globs
# in $1; false otherwise. $2 is the deny list: it is checked first, so a path
# on it is never documentation even when $1 also matches it. An explicitly
# empty $2 means no deny list; an unset $2 means DEFAULT_NOT_DOCS_PATHS.
classify() {
	local globs="${1:-$DEFAULT_DOCS_PATHS}" denied="${2-$DEFAULT_NOT_DOCS_PATHS}"
	local re path matched any=0 line
	local regexes=() deny=()
	while IFS= read -r line; do
		[ -n "$line" ] && regexes+=("$line")
	done <<<"$(globs_to_regexes "$globs")"
	while IFS= read -r line; do
		[ -n "$line" ] && deny+=("$line")
	done <<<"$(globs_to_regexes "$denied")"
	if [ ${#regexes[@]} -eq 0 ]; then
		echo false
		return 0
	fi
	while IFS= read -r path || [ -n "$path" ]; do
		[ -z "$path" ] && continue
		any=1
		for re in ${deny[@]+"${deny[@]}"}; do
			if [[ $path =~ $re ]]; then
				echo false
				return 0
			fi
		done
		matched=0
		for re in "${regexes[@]}"; do
			if [[ $path =~ $re ]]; then
				matched=1
				break
			fi
		done
		if [ "$matched" = 0 ]; then
			echo false
			return 0
		fi
	done
	if [ "$any" = 1 ]; then echo true; else echo false; fi
}

# Sets CHANGED to the changed paths, one per line, and returns 0. On any
# uncertainty sets REASON and returns 1.
#
# pull_request: three-dot diff from the PR base, i.e. the PR's own file list.
# push: the whole branch against origin/<default branch>, not the previous
# push -- a README-only last push on a branch that changed code earlier must
# not skip the gate on the head commit a PR will read.
# --no-renames lists both sides of a rename, so code moved into docs/ counts.
changed_paths() {
	local event="$1" base="$2" head="$3" branch="$4" from to
	CHANGED=""
	if [ -z "$head" ] || ! git cat-file -e "${head}^{commit}" 2>/dev/null; then
		REASON="head commit '${head}' is not in the clone"
		return 1
	fi
	case "$event" in
	pull_request)
		if [ -z "$base" ] || ! git cat-file -e "${base}^{commit}" 2>/dev/null; then
			REASON="pull request base '${base}' is not in the clone"
			return 1
		fi
		from="$base..."
		to="$head"
		;;
	push)
		if [ -z "$branch" ] ||
			! git rev-parse -q --verify "refs/remotes/origin/${branch}^{commit}" >/dev/null; then
			REASON="origin/${branch} is not in the clone"
			return 1
		fi
		if ! from=$(git merge-base "refs/remotes/origin/${branch}" "$head" 2>/dev/null); then
			REASON="no merge base between origin/${branch} and ${head}"
			return 1
		fi
		to="$head"
		;;
	*)
		REASON="event '${event}' is not push or pull_request"
		return 1
		;;
	esac
	if [ "${from%...}" != "$from" ]; then
		CHANGED=$(git -c core.quotePath=false diff --name-only --no-renames "${from}${to}") || {
			REASON="git diff failed"
			return 1
		}
	else
		CHANGED=$(git -c core.quotePath=false diff --name-only --no-renames "$from" "$to") || {
			REASON="git diff failed"
			return 1
		}
	fi
	return 0
}

main() {
	local out="${GITHUB_OUTPUT:-/dev/stdout}" result=false
	REASON=""
	if changed_paths "${EVENT_NAME:-}" "${BASE_SHA:-}" "${HEAD_SHA:-}" "${DEFAULT_BRANCH:-}"; then
		if [ -z "$CHANGED" ]; then
			REASON="no changed paths"
		else
			result=$(classify "${DOCS_PATHS:-$DEFAULT_DOCS_PATHS}" "${NOT_DOCS_PATHS-$DEFAULT_NOT_DOCS_PATHS}" <<<"$CHANGED")
			if [ "$result" = true ]; then
				REASON="every changed path is documentation"
			else
				REASON="at least one changed path is not documentation"
			fi
		fi
	fi
	if [ "$result" = true ]; then
		echo "::notice::docs-only change: Super Linter and dependency-check are skipped ($REASON)"
	else
		echo "::notice::full quality gate: $REASON"
	fi
	if ! printf 'docs_only=%s\nreason=%s\n' "$result" "$REASON" >>"$out"; then
		echo "cannot write outputs to $out" >&2
		return 2
	fi
	return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	main
	exit $?
fi

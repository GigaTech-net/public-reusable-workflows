#!/usr/bin/env bash
# Reports workflow jobs that declare no timeout-minutes, so a job that wedges
# on a call that never returns is killed at its bound instead of GitHub's
# six-hour default.
#
# A job is bounded when `timeout-minutes` is a direct property of the job; an
# expression value counts. A job that calls a reusable workflow (a direct
# `uses:`) is exempt: GitHub rejects timeout-minutes there, and the called
# workflow's own jobs carry the bound.
#
# With --scanner-steps it also reports each container or scanner step (see
# is_scanner_step) that lacks a direct step-level timeout-minutes, so the step
# fails at its own bound rather than running to the job's.
#
# Reads YAML by indentation with awk, so it needs no YAML library. It fails
# closed: a file whose top-level `jobs:` yields no readable job (flow style, for
# one) is reported as unreadable, never passed as having no jobs.
#
# Usage: workflow-timeouts.sh [--scanner-steps] PATH...
#   For each *.yml and *.yaml file directly under each PATH, prints one
#   ::error line per violation, then a count.
#   Exit 0 clean, 1 on any violation or unreadable file, 2 on usage error.
#
# Sourceable: the test sources it for the check functions, and main runs only
# when the file is executed. Bash 3.2 compatible (macOS).
set -uo pipefail

# Field separator for scan_file records; unlike a tab it is not whitespace to
# `read`, so empty fields survive.
SEP=$'\037'

# Prints one record per job:  J SEP line SEP job SEP has_timeout SEP has_uses SEP value
# one per step:  S SEP line SEP job SEP label SEP uses SEP run_body SEP has_timeout SEP value
# has_timeout is 0 when absent, 1 when declared, 2 when declared as a literal
# that is not a positive number (0, a negative, empty or null); value is that
# literal. An expression counts as declared, and no upper bound is imposed: how
# long a job may run is policy, set per job class, not something to infer here.
# (run_body is on one line, blank and comment lines dropped), U SEP line SEP
# reason for each part of `jobs:` that cannot be read, and a final Z once the
# whole file has been read. A caller treats a result without its Z as a parser failure: awk's exit
# status is lost inside a process substitution, so the sentinel is what makes a
# crashed or missing awk fail closed instead of reading as "no violations".
scan_file() {
	awk -v sep="$SEP" '
	function indent(s) { match(s, /^ */); return RLENGTH }
	function value(s) {
		sub(/^[A-Za-z-]+:[ \t]*/, "", s)
		sub(/[ \t]+#.*$/, "", s)
		gsub(/["\047]/, "", s)
		return s
	}
	function tmstate(s,   v) {
		v = value(s)
		tmval = (v == "") ? "(empty)" : v
		if (v ~ /\$\{\{/) return 1
		if (v == "" || v == "null" || v == "~") return 2
		if (v ~ /^[-+]?([0-9]+\.?[0-9]*|\.[0-9]+)$/ && v + 0 <= 0) return 2
		return 1
	}
	function fail(ln, why) { print "U" sep ln sep why; failed = 1 }
	function closestep() {
		if (stepopen) {
			label = sname
			if (label == "") label = suses
			if (label == "") label = "step " stepidx
			print "S" sep steplineno sep job sep label sep suses sep sbody sep shas sep sval
		}
		stepopen = 0
	}
	function closejob() {
		closestep()
		if (job != "" && !jobbad) {
			if (anchor != "") { ah[anchor] = has; au[anchor] = uses; av[anchor] = jval }
			print "J" sep jobline sep job sep has sep uses sep jval
		}
		job = ""
		anchor = ""
		jobbad = 0
	}
	function stepprop(s,   v) {
		inrun = 0
		inuses = 0
		if (s ~ /^name:/) sname = value(s)
		else if (s ~ /^uses:/) {
			suses = value(s)
			if (suses ~ /^[|>]/) { suses = ""; inuses = 1 }
		}
		else if (s ~ /^timeout-minutes:/) { shas = tmstate(s); sval = tmval }
		else if (s ~ /^run:/) {
			v = s
			sub(/^run:[ \t]*/, "", v)
			if (v ~ /^[|>]/) inrun = 1
			else sbody = v
		}
	}
	# Opens the job on key line T. A key may carry an anchor (&a) or be an alias
	# (*a); anything else after the colon is a flow value this reader cannot
	# follow, so the file is reported unreadable rather than the job skipped.
	function openjob(t,   k, tok, hasanchor) {
		k = t
		sub(/[ \t]+#.*$/, "", k)
		tok = ""
		if (match(k, /[ \t]+[&*][^ \t]+$/)) {
			tok = substr(k, RSTART, RLENGTH)
			sub(/^[ \t]+/, "", tok)
			k = substr(k, 1, RSTART - 1)
		}
		if (k !~ /^("[^"]+"|\047[^\047]+\047|[^ \t:#"\047]+)[ \t]*:[ \t]*$/) {
			k = t
			sub(/[ \t]*:.*$/, "", k)
			fail(NR, "job \047" k "\047 is not a block mapping")
			return
		}
		sub(/[ \t]*:[ \t]*$/, "", k)
		gsub(/["\047]/, "", k)
		job = k; jobline = NR; has = 0; uses = 0; jval = ""; propindent = -1
		insteps = 0; stepindent = -1; stepidx = 0
		opened++
		if (tok ~ /^&/) anchor = substr(tok, 2)
		else if (tok ~ /^\*/) {
			if (!(substr(tok, 2) in ah)) {
				fail(NR, "alias " tok " has no anchor")
				job = ""
				return
			}
			has = ah[substr(tok, 2)]; uses = au[substr(tok, 2)]; jval = av[substr(tok, 2)]
		}
	}
	{
		line = $0
		sub(/\r$/, "", line)
		if (line ~ /^[ \t]*(#.*)?$/) next
		if (line ~ /^\t/) {
			if (injobs) fail(NR, "tab indentation")
			next
		}
		n = indent(line)
		t = substr(line, n + 1)
		if (n == 0) {
			closejob()
			injobs = (t ~ /^jobs:[ \t]*(#.*)?$/)
			if (t ~ /^jobs:/) { seen = 1; seenline = NR }
			if (injobs) jobindent = -1
			next
		}
		if (!injobs) next
		if (jobindent < 0) jobindent = n
		if (n == jobindent) {
			closejob()
			openjob(t)
			next
		}
		if (job == "") next
		if (propindent < 0) propindent = n
		if (n == propindent && !(insteps && t ~ /^-/)) {
			closestep()
			insteps = 0; stepindent = -1
			if (t ~ /^[{\[]/) {
				fail(NR, "job \047" job "\047 has a flow-style property")
				jobbad = 1
			}
			if (t ~ /^timeout-minutes:/) { has = tmstate(t); jval = tmval }
			if (t ~ /^uses:/) uses = 1
			if (t ~ /^<<:[ \t]*\*[^ \t]+[ \t]*(#.*)?$/) {
				mk = t
				sub(/^<<:[ \t]*\*/, "", mk)
				sub(/[ \t]*(#.*)?$/, "", mk)
				if (mk in ah) {
					if (ah[mk]) { has = ah[mk]; jval = av[mk] }
					if (au[mk]) uses = 1
				} else fail(NR, "alias *" mk " has no anchor")
			}
			if (t ~ /^steps:[ \t]*(#.*)?$/) insteps = 1
			next
		}
		if (!insteps) next
		if (stepindent < 0) {
			if (t !~ /^-/) next
			stepindent = n
		}
		if (n == stepindent && t ~ /^-/) {
			closestep()
			stepopen = 1; stepidx++; steplineno = NR
			sname = ""; suses = ""; sbody = ""; shas = 0; sval = ""; inrun = 0; inuses = 0
			rest = substr(t, 2)
			sp = indent(rest)
			stepcol = n + 1 + sp
			if (rest ~ /^[ \t]*(#.*)?$/) stepcol = -1
			else stepprop(substr(rest, sp + 1))
			next
		}
		if (!stepopen) next
		if (stepcol < 0) stepcol = n
		if (n == stepcol) stepprop(t)
		else if (n > stepcol && inrun) sbody = sbody " " t
		else if (n > stepcol && inuses) suses = suses t
	}
	END {
		closejob()
		if (seen && opened == 0 && !failed) fail(seenline, "no job could be read under jobs:")
		print "Z"
	}
	' "$1"
}

# Prints LINE<TAB>JOB for each job under top-level `jobs:` that has neither a
# direct timeout-minutes nor a direct uses, and LINE<TAB>JOB<TAB>VALUE for one
# whose timeout-minutes is a literal that is not a positive number. Returns 3 when the file could not be
# read (no job under `jobs:`, or the parser failed); a parser failure also prints
# LINE<TAB>!REASON, and a job id never starts with `!`.
missing_job_timeouts() {
	local kind line job has uses val rc=0 done_=0
	while IFS="$SEP" read -r kind line job has uses val; do
		case "$kind" in
		Z) done_=1 ;;
		U)
			printf '%s\t!%s\n' "$line" "$job"
			rc=3
			;;
		J)
			if [ "$has" = 0 ] && [ "$uses" = 0 ]; then
				printf '%s\t%s\n' "$line" "$job"
			elif [ "$has" = 2 ] && [ "$uses" = 0 ]; then
				printf '%s\t%s\t%s\n' "$line" "$job" "$val"
			fi
			;;
		esac
	done < <(scan_file "$1")
	if [ "$done_" -eq 0 ]; then
		printf '0\t!the parser produced no result\n'
		rc=3
	fi
	return "$rc"
}

# True when a step builds or pulls a container image or runs an external
# scanner, which is where a call that never returns is most likely. USES is the
# step's `uses:` value; RUN_BODY is its `run:` value only, never its name.
is_scanner_step() {
	local uses="$1" body="$2"
	local uses_re='(^|/)(super-linter|dependency-check|secret-scan|trufflehog-scan)(@|$)|super-linter/super-linter|Dependency-Check_Action|trufflesecurity/trufflehog|zaproxy/action-|docker/build-push-action'
	# Global flags may sit between the command and its subcommand, each with an
	# optional argument (docker -H host run, docker-compose -f ci.yml up).
	local flags='([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*'
	local run_re="(^|[^A-Za-z0-9_-])(docker${flags}[[:space:]]+((image|container|buildx)[[:space:]]+)?(build|run|pull|compose|bake)|docker-compose${flags}[[:space:]]+(up|run|pull|build|create|start))([[:space:]]|\$)"
	if [ -n "$uses" ] && [[ $uses =~ $uses_re ]]; then
		return 0
	fi
	if [ -n "$body" ] && [[ $body =~ $run_re ]]; then
		return 0
	fi
	return 1
}

# Prints LINE<TAB>JOB<TAB>STEP for each container or scanner step without a
# direct step-level timeout-minutes. STEP is the step's name, else its uses,
# else `step N`; LINE is the line of the step's dash. Returns 3, printing
# LINE<TAB>!REASON, when the parser failed.
unbounded_scanner_steps() {
	local kind line job label uses body has val done_=0
	while IFS="$SEP" read -r kind line job label uses body has val; do
		[ "$kind" = Z ] && done_=1
		[ "$kind" = S ] || continue
		[ "$has" = 1 ] && continue
		if is_scanner_step "$uses" "$body"; then
			if [ "$has" = 2 ]; then
				printf '%s\t%s\t%s\t%s\n' "$line" "$job" "$label" "$val"
			else
				printf '%s\t%s\t%s\n' "$line" "$job" "$label"
			fi
		fi
	done < <(scan_file "$1")
	if [ "$done_" -eq 0 ]; then
		printf '0\t!the parser produced no result\n'
		return 3
	fi
}

# Prints an ::error per line of missing_job_timeouts output and counts into
# $violations (main's local, shared by dynamic scope).
report_job_lines() {
	local f="$1" lines="$2" rc="$3" line job val
	if [ -n "$lines" ]; then
		while IFS=$'\t' read -r line job val; do
			case "$job" in
			!*) echo "::error file=$f,line=$line::cannot read jobs: ${job#!}" ;;
			*)
				if [ -n "$val" ]; then
					echo "::error file=$f,line=$line::job '$job' has timeout-minutes '$val'; it must be a positive number"
				else
					echo "::error file=$f,line=$line::job '$job' has no timeout-minutes"
				fi
				;;
			esac
			violations=$((violations + 1))
		done <<<"$lines"
	fi
	if [ "$rc" -eq 3 ] && [ -z "$lines" ]; then
		echo "::error file=$f::cannot read jobs"
		violations=$((violations + 1))
	fi
}

# The same for unbounded_scanner_steps output.
report_step_lines() {
	local f="$1" lines="$2" rc="$3" line job step val
	if [ -n "$lines" ]; then
		while IFS=$'\t' read -r line job step val; do
			case "$job" in
			!*) echo "::error file=$f,line=$line::cannot read steps: ${job#!}" ;;
			*)
				if [ -n "$val" ]; then
					echo "::error file=$f,line=$line::step '$step' in job '$job' has timeout-minutes '$val'; it must be a positive number"
				else
					echo "::error file=$f,line=$line::step '$step' in job '$job' has no timeout-minutes"
				fi
				;;
			esac
			violations=$((violations + 1))
		done <<<"$lines"
	fi
	if [ "$rc" -eq 3 ] && [ -z "$lines" ]; then
		echo "::error file=$f::cannot read steps"
		violations=$((violations + 1))
	fi
}

main() {
	local p f dir files=0 violations=0 lines rc scanner=0
	if [ "${1:-}" = "--scanner-steps" ]; then
		scanner=1
		shift
	fi
	[ "$#" -gt 0 ] || {
		echo "usage: workflow-timeouts.sh [--scanner-steps] PATH..." >&2
		return 2
	}
	for p in "$@"; do
		[ -d "$p" ] || {
			echo "not a directory: $p" >&2
			return 2
		}
	done
	for p in "$@"; do
		dir="${p%/}"
		for f in "$dir"/*.yml "$dir"/*.yaml; do
			[ -f "$f" ] || continue
			files=$((files + 1))
			lines=$(missing_job_timeouts "$f")
			rc=$?
			report_job_lines "$f" "$lines" "$rc"
			if [ "$scanner" -eq 1 ]; then
				lines=$(unbounded_scanner_steps "$f")
				rc=$?
				report_step_lines "$f" "$lines" "$rc"
			fi
		done
	done
	if [ "$files" -eq 0 ]; then
		echo "no workflow files found under: $*" >&2
		return 2
	fi
	if [ "$violations" -gt 0 ]; then
		echo "$violations violation(s) in $files file(s)"
		return 1
	fi
	echo "all jobs bounded in $files file(s)"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	main "$@"
fi

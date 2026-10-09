#!/usr/bin/env bash
# Secret scan for the GigaTECH secret-scan composite action.
#
# Resolves the commit range the triggering event introduced, scans it with the
# TruffleHog docker image, and fails when the scan found a secret, reported an
# error, or inspected nothing. The range contract is documented in README.md
# beside this file.
#
# Sourceable: tests source this file and call the functions directly; main runs
# only when the file is executed.
set -uo pipefail

ZERO_SHA=0000000000000000000000000000000000000000

# The scan runs this image by digest when the caller sets neither image nor
# version. TRUFFLEHOG_VERSION names the release the digest was resolved from; it
# is the tag shown for humans and is the tag a custom image falls back to. Both
# constants change together in one reviewed commit; README.md, "Scanner
# version", has the bump procedure.
TRUFFLEHOG_VERSION=3.99.2 # the release tag for the digest below
TRUFFLEHOG_DIGEST=sha256:47a84bc18a0d04a165498bbbd3bacfd84176661cbc91f8e0f85467f6a771e99a
TRUFFLEHOG_IMAGE=ghcr.io/trufflesecurity/trufflehog

# scanner_ref [IMAGE] [VERSION]: the image reference to run.
#   - an IMAGE already carrying a digest (@) or a tag (a ':' after the last '/')
#     is used as-is;
#   - no VERSION: the pinned digest (default image) or the pinned release tag
#     (a custom image, which the digest does not belong to);
#   - VERSION set: IMAGE:VERSION, the caller's visible choice.
scanner_ref() {
	local image=${1:-$TRUFFLEHOG_IMAGE} version=${2:-}
	if [[ "$image" == *@* || "${image##*/}" == *:* ]]; then
		echo "$image"
	elif [ -n "$version" ]; then
		echo "$image:$version"
	elif [ "$image" = "$TRUFFLEHOG_IMAGE" ]; then
		echo "$image@$TRUFFLEHOG_DIGEST"
	else
		echo "$image:$TRUFFLEHOG_VERSION"
	fi
}

die() {
	echo "::error::secret-scan: $*" >&2
	exit 1
}

note() { echo "::notice::secret-scan: $*" >&2; }

# ensure_commit REV: succeed when REV names a commit in this clone, deepening a
# shallow clone and fetching REV from origin when it is absent.
ensure_commit() {
	local rev=$1
	if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = true ]; then
		git fetch --quiet --no-tags --unshallow origin 2>/dev/null || true
	fi
	git rev-parse --quiet --verify "${rev}^{commit}" >/dev/null 2>&1 && return 0
	git fetch --quiet --no-tags origin "$rev" 2>/dev/null || true
	git rev-parse --quiet --verify "${rev}^{commit}" >/dev/null 2>&1
}

# resolve_rev REV: print the commit sha REV names, or fail. REV may be a sha, a
# local ref, or a branch name known only to origin (the old head/base contract
# took github.ref_name).
resolve_rev() {
	local rev=$1
	if ensure_commit "$rev"; then
		git rev-parse --verify "${rev}^{commit}"
		return
	fi
	git rev-parse --verify --quiet "refs/remotes/origin/${rev}^{commit}" && return 0
	git fetch --quiet --no-tags origin "$rev" 2>/dev/null &&
		git rev-parse --verify --quiet "FETCH_HEAD^{commit}"
}

# fork_point HEAD_SHA DEFAULT_BRANCH: the merge-base of HEAD_SHA with the
# default branch on origin, or empty when there is none.
fork_point() {
	local head=$1 default=$2
	[ -n "$default" ] || return 0
	git fetch --quiet --no-tags origin "$default" 2>/dev/null || true
	git merge-base "origin/$default" "$head" 2>/dev/null || true
}

# resolve_range EVENT_NAME EVENT_PATH INPUT_BASE INPUT_HEAD
# Prints SKIP=<reason>, or BASE=, HEAD=, COMMITS=, ADDED= lines.
resolve_range() {
	local event=$1 payload=$2 in_base=$3 in_head=$4
	local base="" head="" default before after ref
	default=$(jq -r '.repository.default_branch // empty' "$payload" 2>/dev/null)

	# The commits the event itself names (pull request and merge group events).
	local ev_base="" ev_head=""
	case "$event" in
	pull_request | pull_request_target)
		ev_base=$(jq -r '.pull_request.base.sha // empty' "$payload" 2>/dev/null)
		ev_head=$(jq -r '.pull_request.head.sha // empty' "$payload" 2>/dev/null)
		;;
	merge_group)
		ev_base=$(jq -r '.merge_group.base_sha // empty' "$payload" 2>/dev/null)
		ev_head=$(jq -r '.merge_group.head_sha // empty' "$payload" 2>/dev/null)
		;;
	esac

	local hint="is the checkout shallow, or was it made with persist-credentials: false so a fetch could not authenticate? Use fetch-depth: 0"
	if [ -n "$in_base" ] || [ -n "$in_head" ]; then
		if ! head=$(resolve_rev "${in_head:-HEAD}"); then
			# github.ref_name is "<n>/merge" on a pull request: not a ref anyone can resolve.
			[ -n "$ev_head" ] || die "cannot resolve head '${in_head:-HEAD}' in the clone ($hint)"
			echo "::warning::secret-scan: head input '$in_head' does not resolve; scanning the event's head $ev_head" >&2
			head=$ev_head
			base=$ev_base
		fi
		if [ -n "$in_base" ]; then
			if ! base=$(resolve_rev "$in_base"); then
				[ -n "$ev_base" ] || die "cannot resolve base '$in_base' in the clone ($hint)"
				echo "::warning::secret-scan: base input '$in_base' does not resolve; using the event's base $ev_base" >&2
				base=$ev_base
			fi
		fi
	else
		case "$event" in
		pull_request | pull_request_target | merge_group)
			base=$ev_base
			head=$ev_head
			;;
		push)
			before=$(jq -r '.before // empty' "$payload")
			after=$(jq -r '.after // empty' "$payload")
			ref=$(jq -r '.ref // empty' "$payload")
			if [ "$after" = "$ZERO_SHA" ]; then
				echo "SKIP=branch deletion"
				return 0
			fi
			head=$after
			ensure_commit "$head" || die "push head $head is not in the clone ($hint)"
			if [ -n "$default" ] && [ "$ref" = "refs/heads/$default" ] &&
				{ [ -z "$before" ] || [ "$before" = "$ZERO_SHA" ] || ! ensure_commit "$before" || ! git merge-base --is-ancestor "$before" "$head"; }; then
				# The default branch has no older branch to fork from: origin/<default>
				# already equals head, so a fork-point range would be empty and the
				# rewritten or first-pushed history would go unscanned.
				base=""
				note "default branch ${default}: first push or force-push; scanning its whole history"
			elif [ -z "$before" ] || [ "$before" = "$ZERO_SHA" ]; then
				base=$(fork_point "$head" "$default")
				note "new branch: scanning from its fork point with ${default:-the default branch} (${base:-whole history})"
			elif ! ensure_commit "$before" || ! git merge-base --is-ancestor "$before" "$head"; then
				base=$(fork_point "$head" "$default")
				note "force-push: $before is not an ancestor of $head; scanning from the fork point (${base:-whole history})"
			else
				base=$before
			fi
			;;
		*)
			head=HEAD
			note "event $event: scanning full history"
			;;
		esac
	fi

	[ -n "$head" ] || die "event $event gave no head commit to scan"
	ensure_commit "$head" || die "cannot resolve head '$head' in the clone ($hint)"
	head=$(git rev-parse --verify "${head}^{commit}")
	if [ -n "$base" ]; then
		ensure_commit "$base" || die "cannot resolve base '$base' in the clone ($hint)"
		base=$(git rev-parse --verify "${base}^{commit}")
	fi

	local range commits added
	if [ -n "$base" ]; then range="$base..$head"; else range=$head; fi
	commits=$(git rev-list --count "$range")
	if [ "$commits" -eq 0 ]; then
		echo "SKIP=no commits in range"
		return 0
	fi
	# -m shows merge commits' diffs too (an evil merge), and a binary row ('-')
	# counts as added content: only a range adding no content at all is skipped.
	added=$(git log -m --format= --numstat "$range" | awk '$1 ~ /^[0-9]+$/ { s += $1 } $1 == "-" { s += 1 } END { print s + 0 }')
	if [ "$added" -eq 0 ]; then
		echo "SKIP=range adds no content"
		return 0
	fi
	printf 'BASE=%s\nHEAD=%s\nCOMMITS=%s\nADDED=%s\n' "$base" "$head" "$commits" "$added"
}

# guard LOG_FILE SCAN_STATUS: fail unless the scan ran, resolved its refs,
# inspected a positive number of chunks, and found nothing.
guard() {
	local log=$1 status=$2 summary chunks
	if [ "$status" -eq 183 ]; then
		die "TruffleHog reported secrets in the scanned range (see the findings above)"
	elif [ "$status" -ne 0 ]; then
		die "TruffleHog exited $status"
	fi
	if grep -Eq 'encountered errors during scan|unable to resolve ref' "$log"; then
		die "TruffleHog reported scan errors, so the scan cannot be trusted"
	fi
	summary=$(grep '"msg":"finished scanning"' "$log" | tail -n 1)
	[ -n "$summary" ] || die "TruffleHog printed no finished-scanning summary"
	chunks=$(jq -r '.chunks // empty' <<<"$summary" 2>/dev/null)
	[[ "$chunks" =~ ^[0-9]+$ ]] || die "cannot read the chunk count from: $summary"
	[ "$chunks" -gt 0 ] || die "TruffleHog scanned 0 chunks of a range that adds content: it inspected nothing (if every added file is covered by --exclude-paths or .trufflehogignore, narrow the exclusion)"
	echo "secret-scan: scanned $chunks chunks, no secrets found"
}

# run_scan REF BASE HEAD LOG_FILE [EXTRA_ARGS...]: REF is image:tag or image@digest.
run_scan() {
	local ref=$1 base=$2 head=$3 log=$4
	shift 4
	local extra=("$@") args=(git file:///repo --branch "$head" --fail --no-update)
	[ -n "$base" ] && args+=(--since-commit "$base")
	local a has_json=false
	for a in ${extra[@]+"${extra[@]}"}; do [ "$a" = --json ] && has_json=true; done
	$has_json || args+=(--json)
	docker run --rm -v "$PWD:/repo:ro" -w /repo "$ref" "${args[@]}" ${extra[@]+"${extra[@]}"} 2>&1 | tee "$log"
	return "${PIPESTATUS[0]}"
}

summary_line() {
	[ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "$*" >>"$GITHUB_STEP_SUMMARY"
	return 0
}

main() {
	: "${GITHUB_EVENT_NAME:?}" "${GITHUB_EVENT_PATH:?}"
	cd "${INPUT_PATH:-.}" || die "cannot enter path '${INPUT_PATH:-.}'"
	local range key value base="" head="" commits="" skip=""
	range=$(resolve_range "$GITHUB_EVENT_NAME" "$GITHUB_EVENT_PATH" "${INPUT_BASE:-}" "${INPUT_HEAD:-}") || exit 1
	while IFS='=' read -r key value; do
		case "$key" in
		SKIP) skip=$value ;;
		BASE) base=$value ;;
		HEAD) head=$value ;;
		COMMITS) commits=$value ;;
		esac
	done <<<"$range"
	if [ -n "$skip" ]; then
		note "nothing to scan: $skip"
		summary_line "Secret scan skipped: $skip"
		return 0
	fi
	local ref extra=() log status
	ref=$(scanner_ref "${INPUT_IMAGE:-}" "${INPUT_VERSION:-}")
	echo "secret-scan: event=$GITHUB_EVENT_NAME base=${base:-<full history>} head=$head commits=$commits scanner=$ref"
	read -r -a extra <<<"${INPUT_EXTRA_ARGS:-}"
	log=$(mktemp)
	run_scan "$ref" "$base" "$head" "$log" ${extra[@]+"${extra[@]}"}
	status=$?
	summary_line "Secret scan: ${base:-full history}..$head ($commits commits), $ref exit $status"
	guard "$log" "$status"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	main "$@"
fi

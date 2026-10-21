#!/usr/bin/env bash
# Runs Super Linter in docker the way the Actions runner runs a Docker
# container action, so the action can start the container from a `run:` step
# that an `if:` guards.
#
# Why not `uses: super-linter/super-linter/slim@...`: the runner pre-pulls the
# image of every Docker container action nested in a composite action while it
# sets the job up, before any step runs and whatever `if:` says, so a skipped
# step still paid the ~1 GB pull (common-tools-ai run 38798031571, job
# quality-checks, step "Pull ghcr.io/super-linter/super-linter:slim-v9.0.0").
# `docker run` pulls only when this script reaches it.
#
# Inputs, all environment variables:
#   SUPER_LINTER_IMAGE  the image to run, version tag included (required)
#   GITHUB_WORKSPACE, RUNNER_TEMP (required)
# and the job environment, which is passed through by name: every exported
# variable whose name is a valid identifier, except the host's own PATH, HOME
# and the like. Values never appear on the command line.
#
# What the runner does for a container action, and this reproduces:
#   - mounts the workspace at /github/workspace and starts there
#   - mounts $RUNNER_TEMP/_github_home, _github_workflow and
#     _runner_file_commands at /github/home, /github/workflow and
#     /github/file_commands
#   - sets HOME=/github/home, GITHUB_ACTIONS=true, CI=true
#   - rewrites GITHUB_WORKSPACE, GITHUB_EVENT_PATH and the file-command paths
#     (GITHUB_OUTPUT, GITHUB_ENV, GITHUB_PATH, GITHUB_STEP_SUMMARY,
#     GITHUB_STATE) to their container paths
# It does not mount the Docker socket (Super Linter does not use it) or join
# the job's container network.
#
# Exits with docker's status, so the linter's result is the step's result.
# Exits 2 when an input is missing; Bash 3.2 compatible.
set -uo pipefail

if [ -z "${SUPER_LINTER_IMAGE:-}" ]; then
	echo "::error::SUPER_LINTER_IMAGE is not set" >&2
	exit 2
fi
if [ -z "${GITHUB_WORKSPACE:-}" ] || [ -z "${RUNNER_TEMP:-}" ]; then
	echo "::error::GITHUB_WORKSPACE and RUNNER_TEMP must be set" >&2
	exit 2
fi

workspace="$GITHUB_WORKSPACE"
temp="${RUNNER_TEMP%/}"

# Prints $1 as the container sees it: a path under a mounted host directory is
# moved to the mount point; anything else is returned unchanged.
to_container_path() {
	case "$1" in
	"$temp"/_github_workflow/*) printf '/github/workflow/%s' "${1#"$temp"/_github_workflow/}" ;;
	"$temp"/_runner_file_commands/*) printf '/github/file_commands/%s' "${1#"$temp"/_runner_file_commands/}" ;;
	"$temp"/_github_home/*) printf '/github/home/%s' "${1#"$temp"/_github_home/}" ;;
	"$workspace"/*) printf '/github/workspace/%s' "${1#"$workspace"/}" ;;
	*) printf '%s' "$1" ;;
	esac
}

for name in GITHUB_EVENT_PATH GITHUB_OUTPUT GITHUB_ENV GITHUB_PATH GITHUB_STEP_SUMMARY GITHUB_STATE; do
	if [ -n "${!name:-}" ]; then
		export "$name=$(to_container_path "${!name}")"
	fi
done
export GITHUB_WORKSPACE=/github/workspace

args=(
	run --rm
	-w /github/workspace
	-v "$workspace:/github/workspace"
	-v "$temp/_github_home:/github/home"
	-v "$temp/_github_workflow:/github/workflow"
	-v "$temp/_runner_file_commands:/github/file_commands"
	-e HOME=/github/home
	-e GITHUB_ACTIONS=true
	-e CI=true
)

# By name only: docker takes the value from this process's environment, so a
# token, a multi-line value or one with shell metacharacters never reaches a
# command line, a log or a shell parser.
while IFS= read -r name; do
	case "$name" in
	[A-Za-z_]*) ;;
	*) continue ;;
	esac
	case "$name" in
	*[!A-Za-z0-9_]*) continue ;;
	PATH | HOME | PWD | OLDPWD | SHLVL | _ | HOSTNAME | USER | LOGNAME | SHELL | TERM | TMPDIR | \
		IFS | BASH* | SUPER_LINTER_IMAGE | GITHUB_ACTIONS | CI)
		continue
		;;
	esac
	args+=(-e "$name")
done < <(compgen -e)

args+=("$SUPER_LINTER_IMAGE")
exec docker "${args[@]}"

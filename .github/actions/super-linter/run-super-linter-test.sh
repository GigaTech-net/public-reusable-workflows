#!/usr/bin/env bash
# Tests for run-super-linter.sh against a fake `docker` that records how it was
# called. No framework; bash 3.2 compatible. Run from anywhere. Exits non-zero
# if any case fails.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script="$here/run-super-linter.sh"
[ -f "$script" ] || {
	echo "missing: $script" >&2
	exit 1
}

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

work=$(mktemp -d "${TMPDIR:-/tmp}/run-super-linter-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cat >"$work/bin/docker" <<'FAKE'
#!/usr/bin/env bash
# Records its arguments, one per line, and its environment; exits with
# FAKE_DOCKER_EXIT.
printf '%s\n' "$@" >"$FAKE_DOCKER_DIR/args"
env >"$FAKE_DOCKER_DIR/env"
: >"$FAKE_DOCKER_DIR/called"
exit "${FAKE_DOCKER_EXIT:-0}"
FAKE
chmod +x "$work/bin/docker"

RT=/home/runner/work/_temp
BASE=(
	"PATH=$work/bin:/usr/bin:/bin"
	"FAKE_DOCKER_DIR=$work"
	"SUPER_LINTER_IMAGE=ghcr.io/super-linter/super-linter:slim-vX.Y.Z"
	"GITHUB_WORKSPACE=/home/runner/work/r/r"
	"RUNNER_TEMP=$RT"
	"GITHUB_EVENT_PATH=$RT/_github_workflow/event.json"
	"GITHUB_OUTPUT=$RT/_runner_file_commands/set_output_1"
	"GITHUB_STEP_SUMMARY=$RT/_runner_file_commands/step_summary_1"
	"GITHUB_ENV=$RT/_runner_file_commands/set_env_1"
	"GITHUB_PATH=$RT/_runner_file_commands/add_path_1"
	"GITHUB_TOKEN=s3cr3t-token-value"
	"HOME=/home/runner"
	"RUN_LOCAL=false"
	"VALIDATE_YAML=true"
)

# run [NAME=value ...] runs the script under a clean environment: BASE plus the
# arguments. Prints nothing; records the fake's view in $work and sets $rc.
rc=0
run() {
	rm -f "$work/args" "$work/env" "$work/called"
	env -i "${BASE[@]}" "$@" bash "$script" >"$work/out" 2>&1
	rc=$?
}
args() { cat "$work/args" 2>/dev/null; }
has_arg() { args | grep -Fxq -- "$1" && echo yes || echo no; }
env_of() { sed -n "s/^$1=//p" "$work/env" | head -1; }

echo "== command line =="
run
check "exits 0" 0 "$rc"
check "docker was called" yes "$([ -f "$work/called" ] && echo yes || echo no)"
check "first argument is run" run "$(args | head -1)"
check "removes the container" yes "$(has_arg --rm)"
check "image is the last argument" "ghcr.io/super-linter/super-linter:slim-vX.Y.Z" "$(args | tail -1)"
check "workdir flag" yes "$(has_arg -w)"
check "workdir is the workspace mount" yes "$(has_arg /github/workspace)"
check "workspace mount" yes "$(has_arg /home/runner/work/r/r:/github/workspace)"
check "home mount" yes "$(has_arg $RT/_github_home:/github/home)"
check "workflow mount" yes "$(has_arg $RT/_github_workflow:/github/workflow)"
check "file commands mount" yes "$(has_arg $RT/_runner_file_commands:/github/file_commands)"
check "HOME points into the container" yes "$(has_arg HOME=/github/home)"
check "GITHUB_ACTIONS set" yes "$(has_arg GITHUB_ACTIONS=true)"
check "CI set" yes "$(has_arg CI=true)"

echo "== environment passes by name =="
check "token passed by name" yes "$(has_arg GITHUB_TOKEN)"
check "token value is not on the command line" 0 "$(args | grep -c 's3cr3t-token-value')"
check "token value reaches docker's environment" s3cr3t-token-value "$(env_of GITHUB_TOKEN)"
check "env file value passed by name" yes "$(has_arg VALIDATE_YAML)"
check "RUN_LOCAL passed by name" yes "$(has_arg RUN_LOCAL)"
# shellcheck disable=SC2016  # the value is literal on purpose
run 'EVIL=$(touch /tmp/x); a "b" `c`'
check "hostile value is not on the command line" 0 "$(args | grep -c 'touch')"
# shellcheck disable=SC2016  # the value is literal on purpose
check "hostile value arrives intact" 'EVIL=$(touch /tmp/x); a "b" `c`' "EVIL=$(env_of EVIL)"
check "hostile name is passed by name only" yes "$(has_arg EVIL)"
run "MULTI=line one
line two"
check "multi-line value is not split across arguments" 0 "$(args | grep -c 'line two')"
check "multi-line value arrives" "line one" "$(env_of MULTI)"
run 'BAD-NAME=1' 'ALSO BAD=1'
check "invalid names are dropped" 0 "$(args | grep -c 'BAD')"
check "PATH is not passed" no "$(has_arg PATH)"
check "host HOME is not passed by name" no "$(has_arg HOME)"
check "the image variable is not passed" no "$(has_arg SUPER_LINTER_IMAGE)"
check "the fake's directory variable is passed (job env)" yes "$(has_arg FAKE_DOCKER_DIR)"

echo "== paths become container paths =="
run
check "GITHUB_WORKSPACE" /github/workspace "$(env_of GITHUB_WORKSPACE)"
check "GITHUB_EVENT_PATH" /github/workflow/event.json "$(env_of GITHUB_EVENT_PATH)"
check "GITHUB_OUTPUT" /github/file_commands/set_output_1 "$(env_of GITHUB_OUTPUT)"
check "GITHUB_STEP_SUMMARY" /github/file_commands/step_summary_1 "$(env_of GITHUB_STEP_SUMMARY)"
check "GITHUB_ENV" /github/file_commands/set_env_1 "$(env_of GITHUB_ENV)"
check "GITHUB_PATH" /github/file_commands/add_path_1 "$(env_of GITHUB_PATH)"
run GITHUB_STATE=/elsewhere/state
check "a path outside the mounts is left alone" /elsewhere/state "$(env_of GITHUB_STATE)"
run GITHUB_EVENT_PATH=
check "an empty path stays empty" "" "$(env_of GITHUB_EVENT_PATH)"

echo "== exit status =="
run FAKE_DOCKER_EXIT=0
check "success propagates" 0 "$rc"
run FAKE_DOCKER_EXIT=1
check "lint failure propagates" 1 "$rc"
run FAKE_DOCKER_EXIT=137
check "other status propagates" 137 "$rc"

echo "== missing inputs fail closed =="
run SUPER_LINTER_IMAGE=
check "no image: exits 2" 2 "$rc"
check "no image: docker not called" no "$([ -f "$work/called" ] && echo yes || echo no)"
run GITHUB_WORKSPACE=
check "no workspace: exits 2" 2 "$rc"
check "no workspace: docker not called" no "$([ -f "$work/called" ] && echo yes || echo no)"
run RUNNER_TEMP=
check "no runner temp: exits 2" 2 "$rc"

echo "== action wiring =="
action="$here/action.yaml"
check "no container action is declared" 0 "$(grep -c '^ *uses: super-linter/' "$action")"
# shellcheck disable=SC2016  # the pattern is a literal shell line
check "the run step calls the script" 1 "$(grep -c '^ *run: bash "${ACTION_PATH}/run-super-linter.sh"' "$action")"
check "the image is set in one place" 1 "$(grep -c '^ *SUPER_LINTER_IMAGE: ghcr.io/super-linter/super-linter:slim-v' "$action")"
check "the run step is guarded by the gate" 1 "$(grep -c "if: steps.gate.outputs.run != 'false'" "$action")"
# shellcheck disable=SC2016  # the pattern is a literal workflow expression
check "the token comes from the input" 1 "$(grep -c 'GITHUB_TOKEN: ${{ inputs.github_token }}' "$action")"

echo
if [ "$status" = 0 ]; then
	echo "run-super-linter: all cases pass"
else
	echo "run-super-linter: failures above" >&2
fi
exit "$status"

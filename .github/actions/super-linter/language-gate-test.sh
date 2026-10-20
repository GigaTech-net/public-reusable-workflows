#!/usr/bin/env bash
# Tests for language-gate.sh: configuration modes, the language table, and
# (later sections) end-to-end runs against a throwaway git repository. No
# framework; bash 3.2 compatible so it runs on macOS as well as the runners.
#
# Run from anywhere. Exits non-zero if any case fails.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script="$here/language-gate.sh"
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

# Clears every variable the gate reads from a subshell, then exports the
# space-separated NAME=value pairs in $1.
clean_env() {
	local v kv
	for v in $(compgen -e); do
		case "$v" in
		VALIDATE_* | LANGUAGE_GATE | LINTER_RULES_PATH | ENV_FILE_PATH | GITHUB_WORKSPACE)
			unset "$v"
			;;
		esac
	done
	for kv in $1; do export "${kv?}"; done
}

# dec "NAME=value ..." path... -> prints RUN from decide
dec() {
	local vars="$1"
	shift
	(
		clean_env "$vars"
		printf '%s\n' "$@" | {
			decide
			echo "$RUN"
		}
	)
}

# mode "NAME=value ..." -> prints MODE from enabled_mode
mode() {
	(
		clean_env "$1"
		enabled_mode
		echo "$MODE"
	)
}

ALLOW_CTA='VALIDATE_ALL_CODEBASE=false VALIDATE_YAML=true VALIDATE_BASH_EXEC=true VALIDATE_GITHUB_ACTIONS=true'

echo "== modes =="
check "nothing set" none "$(mode '')"
check "allow only" allow "$(mode 'VALIDATE_YAML=true')"
check "deny only" deny "$(mode 'VALIDATE_YAML=false VALIDATE_JSON=false')"
check "mixed" mixed "$(mode 'VALIDATE_YAML=true VALIDATE_JSON=false')"
check "odd value" invalid "$(mode 'VALIDATE_YAML=TRUE')"
check "quoted value" invalid "$(mode 'VALIDATE_YAML="true"')"
check "ALL_CODEBASE is not a language key" none "$(mode 'VALIDATE_ALL_CODEBASE=false')"

echo "== VALIDATE_ALL_CODEBASE does not decide =="
check "ALL_CODEBASE unset gates" false "$(dec 'VALIDATE_YAML=true' README.md)"
check "ALL_CODEBASE=true gates" false "$(dec 'VALIDATE_ALL_CODEBASE=true VALIDATE_YAML=true' README.md)"
check "ALL_CODEBASE=FALSE gates" false "$(dec 'VALIDATE_ALL_CODEBASE=FALSE VALIDATE_YAML=true' README.md)"

echo "== configuration fails open =="
check "no language keys runs" true "$(dec 'VALIDATE_ALL_CODEBASE=false' README.md)"
check "deny mode runs" true "$(dec 'VALIDATE_ALL_CODEBASE=false VALIDATE_YAML=false' README.md)"
check "mixed mode runs" true "$(dec 'VALIDATE_ALL_CODEBASE=false VALIDATE_YAML=true VALIDATE_JSON=false' README.md)"
check "odd value runs" true "$(dec 'VALIDATE_ALL_CODEBASE=false VALIDATE_YAML=yes' README.md)"
check "unknown enabled key runs" true "$(dec 'VALIDATE_ALL_CODEBASE=false VALIDATE_NOT_A_LINTER=true' README.md)"
check "gate input off runs" true "$(dec "$ALLOW_CTA LANGUAGE_GATE=false" README.md)"
check "empty change runs" true "$(dec "$ALLOW_CTA")"

echo "== allow mode, common-tools-ai set =="
check "markdown only skips" false "$(dec "$ALLOW_CTA" README.md docs/guide.md)"
check "image only skips" false "$(dec "$ALLOW_CTA" docs/img/a.png)"
check "yaml runs" true "$(dec "$ALLOW_CTA" README.md config/a.yaml)"
check "yml runs" true "$(dec "$ALLOW_CTA" a.yml)"
check "workflow runs" true "$(dec "$ALLOW_CTA" .github/workflows/x.yml)"
check "action.yaml runs" true "$(dec "$ALLOW_CTA" .github/actions/x/action.yaml)"
check "shell script runs" true "$(dec "$ALLOW_CTA" scripts/run.sh)"
check "extensionless file runs (shebang)" true "$(dec "$ALLOW_CTA" bin/tool)"
check "python is not enabled" false "$(dec "$ALLOW_CTA" src/app.py)"
check "path with a space skips" false "$(dec "$ALLOW_CTA" 'my notes.md')"
check "gate input true is default" false "$(dec "$ALLOW_CTA LANGUAGE_GATE=true" README.md)"

echo "== git-quoted paths fail open =="
# git prints a path with a quote, backslash or control character quoted and
# C-escaped, starting with a double quote, so no glob matches it.
check "quoted path runs" true "$(dec "$ALLOW_CTA" 'docs/a"b.yaml' '"docs/a\"b.yaml"')"
check "quoted path among skippable paths runs" true "$(dec "$ALLOW_CTA" README.md '"we\tird.yaml"')"
check "quoted path runs when its key is off" true "$(dec "$ALLOW_CTA" '"src/\"x.py"')"

echo "== globs are case-insensitive =="
check "README.MD runs for MARKDOWN" true "$(dec 'VALIDATE_ALL_CODEBASE=false VALIDATE_MARKDOWN=true' README.MD)"
check "a.YML runs for YAML" true "$(dec 'VALIDATE_ALL_CODEBASE=false VALIDATE_YAML=true' conf/a.YML)"
check "x.PY runs for PYTHON" true "$(dec 'VALIDATE_ALL_CODEBASE=false VALIDATE_PYTHON_RUFF=true' src/x.PY)"
check "DOCKERFILE runs for hadolint" true "$(dec 'VALIDATE_ALL_CODEBASE=false VALIDATE_DOCKERFILE_HADOLINT=true' svc/DOCKERFILE)"
check "upper-case config name runs" true "$(dec 'VALIDATE_ALL_CODEBASE=true VALIDATE_PYTHON_RUFF=true' PYPROJECT.TOML)"
check "case folding does not widen the extension" false "$(dec 'VALIDATE_ALL_CODEBASE=false VALIDATE_YAML=true' a.YAML.BAK)"
path_matches_key README.MD MARKDOWN
is_config_trigger RUFF.TOML
check "nocasematch is restored" off "$(shopt -q nocasematch && echo on || echo off)"

echo "== shell keys: dotted scripts fail open =="
SHELLK='VALIDATE_ALL_CODEBASE=false VALIDATE_BASH_EXEC=true'
check ".envrc runs" true "$(dec "$SHELLK" .envrc)"
check ".bashrc runs" true "$(dec "$SHELLK" home/.bashrc)"
check "deploy.run runs" true "$(dec "$SHELLK" ci/deploy.run)"
check "SHFMT key sees .envrc" true "$(dec 'VALIDATE_ALL_CODEBASE=false VALIDATE_SHELL_SHFMT=true' .envrc)"
check "BASH key sees .zshrc" true "$(dec 'VALIDATE_ALL_CODEBASE=false VALIDATE_BASH=true' .zshrc)"
check "unknown extension runs" true "$(dec "$SHELLK" tools/entrypoint.dev)"
check "known non-shell extension skips" false "$(dec "$SHELLK" README.md img/a.png data.json src/a.py)"
check "known non-shell extension, upper case, skips" false "$(dec "$SHELLK" IMG/A.PNG)"
check "non-shell key ignores dotted names" false "$(dec 'VALIDATE_ALL_CODEBASE=false VALIDATE_CLOJURE=true' .envrc)"

echo "== allow mode, other keys =="
check "universal key runs on an image" true "$(dec 'VALIDATE_ALL_CODEBASE=false VALIDATE_GITLEAKS=true' a.png)"
check "python key runs on .py" true "$(dec 'VALIDATE_ALL_CODEBASE=false VALIDATE_PYTHON_RUFF=true' src/app.py)"
check "python key skips markdown" false "$(dec 'VALIDATE_ALL_CODEBASE=false VALIDATE_PYTHON_RUFF=true' README.md)"
check "dockerfile key runs" true "$(dec 'VALIDATE_ALL_CODEBASE=false VALIDATE_DOCKERFILE_HADOLINT=true' svc/Dockerfile)"
check "terraform key runs" true "$(dec 'VALIDATE_ALL_CODEBASE=false VALIDATE_TERRAFORM_TFLINT=true' infra/main.tf)"
check "clojure key skips this repo's kinds" false "$(dec 'VALIDATE_ALL_CODEBASE=false VALIDATE_CLOJURE=true' a.yaml b.sh README.md)"
check "markdown key runs on markdown" true "$(dec 'VALIDATE_ALL_CODEBASE=false VALIDATE_MARKDOWN=true' README.md)"
check "yaml glob does not match yaml.bak" false "$(dec 'VALIDATE_ALL_CODEBASE=false VALIDATE_YAML=true' a.yaml.bak)"

echo "== common-tools-ai env (whole codebase, three linters) =="
CTA_FULL='VALIDATE_ALL_CODEBASE=true VALIDATE_YAML=true VALIDATE_BASH_EXEC=true VALIDATE_GITHUB_ACTIONS=true'
check "python only skips" false "$(dec "$CTA_FULL" src/app.py)"
check "markdown only skips" false "$(dec "$CTA_FULL" README.md)"
check "python and markdown skip" false "$(dec "$CTA_FULL" src/app.py docs/notes.md)"
check "yaml-lint config change runs" true "$(dec "$CTA_FULL" .github/linters/.yaml-lint.yml)"
check "with LINTER_RULES_PATH=/, python skips" false "$(dec "$CTA_FULL LINTER_RULES_PATH=/" src/app.py)"
check "with LINTER_RULES_PATH=/, root .yamllint runs" true "$(dec "$CTA_FULL LINTER_RULES_PATH=/" .yamllint)"

echo "== lint configuration always runs =="
RUFF='VALIDATE_ALL_CODEBASE=true VALIDATE_PYTHON_RUFF=true'
check "default rules dir" true "$(dec "$RUFF" .github/linters/.markdown-lint.yml)"
check "default rules dir, any file" true "$(dec "$RUFF" .github/linters/words.txt)"
check "custom rules dir" true "$(dec "$RUFF LINTER_RULES_PATH=config/lint" config/lint/.markdown-lint.yml)"
check "custom rules dir with ./ and /" true "$(dec "$RUFF LINTER_RULES_PATH=./config/lint/" config/lint/x.txt)"
check "custom rules dir moves the default away" false "$(dec "$RUFF LINTER_RULES_PATH=config/lint" .github/linters/words.txt)"
check "rules dir under the workspace path" true "$(dec "$RUFF GITHUB_WORKSPACE=/w LINTER_RULES_PATH=/w/config/lint" config/lint/x.txt)"
check "root rules path is not every path" false "$(dec "$RUFF LINTER_RULES_PATH=/" docs/notes.md)"
check "root rules path keeps known names" true "$(dec "$RUFF LINTER_RULES_PATH=." ruff.toml)"
check "env file in use" true "$(dec "$RUFF ENV_FILE_PATH=ci/lint.env" ci/lint.env)"
check "env file in use, ./ form" true "$(dec "$RUFF ENV_FILE_PATH=./ci/lint.env" ci/lint.env)"
check "env file outside the workspace never matches" false "$(dec "$RUFF ENV_FILE_PATH=/tmp/x/gate.env" docs/notes.md)"
check "default env file" true "$(dec "$RUFF" .github/super-linter.env)"
check "push env file" true "$(dec "$RUFF" .github/super-linter-push.env)"
check "actionlint config in .github" true "$(dec "$RUFF" .github/actionlint.yaml)"
check "root shellcheckrc" true "$(dec "$RUFF" .shellcheckrc)"
check "pyproject.toml" true "$(dec "$RUFF" pyproject.toml)"
check "nested pyproject.toml is not root config" false "$(dec "$RUFF" docs/example/pyproject.toml)"
check "workflow with GITHUB_ACTIONS off skips" false "$(dec "$RUFF" .github/workflows/x.yml)"
check "action with GITHUB_ACTIONS on runs" true "$(dec 'VALIDATE_GITHUB_ACTIONS=true' .github/actions/x/action.yaml)"
check "config file among skippable paths runs" true "$(dec "$RUFF" README.md .hadolint.yaml)"

echo "== more lint configuration names =="
for f in .python-black .rubocop.yml .golangci.yml .golangci.yaml tsconfig.json tsconfig.build.json \
	package.json .prettierrc.json .prettierignore .eslintrc.json .eslintignore .markdownlintignore \
	.stylelintignore .stylelintrc.json stylelint.config.js eslint.config.mjs .flake8 .pylintrc \
	.isort.cfg setup.cfg .ruff.toml ruff.toml .editorconfig .gitleaks.toml .jscpd.json \
	.textlintrc.json .checkov.yaml .checkov.yml .trivyignore; do
	check "default rules dir: $f runs" true "$(dec "$RUFF" "$f")"
	check "root rules dir: $f runs" true "$(dec "$RUFF LINTER_RULES_PATH=/" "$f")"
done
check "nested package.json is not root config" false "$(dec "$RUFF" docs/x/package.json)"

echo "== root rules path: any root dotfile configures a linter =="
check "root .gitignore runs" true "$(dec "$RUFF LINTER_RULES_PATH=/" .gitignore)"
check "root unknown dotfile runs" true "$(dec "$RUFF LINTER_RULES_PATH=." .somelintrc)"
check "root dotfile with the ./ form" true "$(dec "$RUFF LINTER_RULES_PATH=./" .linter-thing)"
check "nested dotfile is not root config" false "$(dec "$RUFF LINTER_RULES_PATH=/" docs/.hidden)"
check "dotted directory file is not a root dotfile" false "$(dec "$RUFF LINTER_RULES_PATH=/" .vscode/settings.json)"
check "default rules dir: unknown root dotfile skips" false "$(dec "$RUFF" .somelintrc)"
check "custom rules dir: root dotfile skips" false "$(dec "$RUFF LINTER_RULES_PATH=config/lint" .somelintrc)"

echo "== zizmor also audits dependabot.yml =="
check "dependabot.yml runs for ZIZMOR" true "$(dec 'VALIDATE_ALL_CODEBASE=false VALIDATE_GITHUB_ACTIONS_ZIZMOR=true' .github/dependabot.yml)"
check "dependabot.yaml runs for ZIZMOR" true "$(dec 'VALIDATE_ALL_CODEBASE=false VALIDATE_GITHUB_ACTIONS_ZIZMOR=true' .github/dependabot.yaml)"
check "dependabot.yml skips for GITHUB_ACTIONS" false "$(dec 'VALIDATE_ALL_CODEBASE=false VALIDATE_GITHUB_ACTIONS=true' .github/dependabot.yml)"
check "ZIZMOR still runs for workflows" true "$(dec 'VALIDATE_ALL_CODEBASE=false VALIDATE_GITHUB_ACTIONS_ZIZMOR=true' .github/workflows/x.yml)"

echo "== table =="
check "unknown key returns 1" 1 "$(language_globs NOT_A_LINTER >/dev/null; echo $?)"
check "universal key is **" '**' "$(language_globs GITLEAKS)"
check "normalize strips workspace, slashes and ./" 'a/b' "$(GITHUB_WORKSPACE=/w normalize_path '/w/./a/b/')"
check "normalize root is empty" '' "$(normalize_path /)"

echo "== end to end =="
repo=$(mktemp -d "${TMPDIR:-/tmp}/language-gate-test.XXXXXX")
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
# gate "NAME=value ..." EVENT BASE HEAD BRANCH [REPO_BRANCH] -> prints the run value
gate() {
	local vars="$1"
	shift
	: >"$out"
	(
		clean_env "$vars"
		cd "$repo/w" && EVENT_NAME="$1" BASE_SHA="$2" HEAD_SHA="$3" \
			DEFAULT_BRANCH="$4" REPO_DEFAULT_BRANCH="${5:-}" GITHUB_OUTPUT="$out" GITHUB_STEP_SUMMARY=/dev/null \
			bash "$script" >/dev/null
	)
	sed -n 's/^run=//p' "$out"
}

ALLOW_YAML='VALIDATE_ALL_CODEBASE=false VALIDATE_YAML=true'

mkdir -p "$repo/w"
git -C "$repo/w" init -q
commit app.yaml README.md
base=$(g rev-parse HEAD)
g update-ref refs/remotes/origin/main "$base"

commit README.md docs/img.png
md_head=$(g rev-parse HEAD)
check "pull_request, markdown only, allow YAML" false "$(gate "$ALLOW_YAML" pull_request "$base" "$md_head" main)"
check "push, markdown only, allow YAML" false "$(gate "$ALLOW_YAML" push "" "$md_head" main)"
check "pull_request, markdown only, ALL_CODEBASE=true" false "$(gate 'VALIDATE_ALL_CODEBASE=true VALIDATE_YAML=true' pull_request "$base" "$md_head" main)"

commit config/new.yml
yml_head=$(g rev-parse HEAD)
check "pull_request, adds a yml" true "$(gate "$ALLOW_YAML" pull_request "$base" "$yml_head" main)"

g checkout -q -b rules "$md_head"
commit .github/linters/.markdown-lint.yml || exit 1
check "pull_request, rules dir changed" true "$(gate 'VALIDATE_ALL_CODEBASE=true VALIDATE_PYTHON_RUFF=true' pull_request "$base" "$(g rev-parse HEAD)" main)"

echo "== end to end fails open =="
check "unknown base sha" true "$(gate "$ALLOW_YAML" pull_request deadbeef "$md_head" main)"
check "empty base sha" true "$(gate "$ALLOW_YAML" pull_request "" "$md_head" main)"
check "no origin ref for branch" true "$(gate "$ALLOW_YAML" push "" "$md_head" trunk)"
check "workflow_dispatch" true "$(gate "$ALLOW_YAML" workflow_dispatch "$base" "$md_head" main)"
g update-ref refs/remotes/origin/other "$md_head"
check "push, repository default branch is used" false "$(gate "$ALLOW_YAML" push "" "$md_head" "" main)"
check "push, env file DEFAULT_BRANCH wins over the repository's" true "$(gate "$ALLOW_YAML" push "" "$md_head" other main)"
check "push, no branch at all" true "$(gate "$ALLOW_YAML" push "" "$md_head" "" "")"
check "empty changeset" true "$(gate "$ALLOW_YAML" push "" "$base" main)"

: >"$out"
(
	clean_env "$ALLOW_YAML"
	cd "$repo/w" && EVENT_NAME=pull_request BASE_SHA="$base" HEAD_SHA="$md_head" \
		DEFAULT_BRANCH=main GITHUB_OUTPUT="$out" GITHUB_STEP_SUMMARY=/dev/null \
		bash "$script" >/dev/null
)
check "skip exits 0" 0 "$?"
check "skip writes a reason" 1 "$(grep -c '^reason=.\+' "$out")"
check "writes exactly two outputs" 2 "$(wc -l <"$out" | tr -d ' ')"

check "unwritable output exits 2" 2 "$(
	clean_env "$ALLOW_YAML"
	cd "$repo/w" && EVENT_NAME=pull_request BASE_SHA="$base" HEAD_SHA="$md_head" \
		DEFAULT_BRANCH=main GITHUB_OUTPUT="$repo/no/such/dir/out" \
		bash "$script" >/dev/null 2>&1
	echo $?
)"

echo "== action wiring =="
action="$here/action.yaml"
check "action runs the gate script" 1 "$(grep -c 'language-gate.sh' "$action")"
check "gate step has id gate" 1 "$(grep -c '^ *id: gate$' "$action")"
check "Super Linter skips only on a positive false" 1 \
	"$(grep -c "if: steps.gate.outputs.run != 'false'" "$action")"
check "language_gate input defaults to true" 1 \
	"$(sed -n '/^  language_gate:/,/^  [a-z_]*:$/p' "$action" | grep -c 'default: "true"')"
check "ran output exposed" 1 "$(grep -c 'steps.gate.outputs.run }}' "$action")"
# The env file's own DEFAULT_BRANCH reaches the gate through GITHUB_ENV; a
# step-level DEFAULT_BRANCH would override it.
check "gate step does not override DEFAULT_BRANCH" 0 "$(grep -c '^ *DEFAULT_BRANCH:' "$action")"
check "gate gets the repository default branch" 1 "$(grep -c '^ *REPO_DEFAULT_BRANCH:' "$action")"
# The loader step and the gate step each pass the env file path.
# shellcheck disable=SC2016  # the pattern is a literal workflow expression
check "gate gets the env file path" 2 "$(grep -c 'ENV_FILE_PATH: ${{ inputs.env_file_path }}' "$action")"

echo
if [ "$status" = 0 ]; then
	echo "language-gate: all cases pass"
else
	echo "language-gate: failures above" >&2
fi
exit "$status"

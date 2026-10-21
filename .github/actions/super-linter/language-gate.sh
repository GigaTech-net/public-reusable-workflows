#!/usr/bin/env bash
# Decides whether Super Linter has anything to lint in the change under test,
# so the super-linter composite action can skip the step, and its image pull,
# when no changed file is in a language the configuration enables.
#
# Writes two outputs to $GITHUB_OUTPUT (stdout when unset):
#   run=true|false
#   reason=<one line>
#
# FAILS OPEN. run=false only when all of these hold:
#   - LANGUAGE_GATE is exactly 'true' (unset counts as 'true')
#   - every VALIDATE_<KEY> language variable is 'true' (allow mode), and each
#     such KEY has an entry in language_globs
#   - the changed paths are known and non-empty
#   - no changed path is lint configuration (is_config_trigger)
#   - no changed path matches an enabled KEY
# VALIDATE_ALL_CODEBASE does not enter into it: when no changed file is in an
# enabled language and no lint configuration changed, every file Super Linter
# would lint is unchanged since the base was linted.
# Anything else is run=true, with exit 0: a gate problem must never fail or
# silently skip the lint.
#
# Inputs, all environment variables: every VALIDATE_* Super Linter will see,
# LANGUAGE_GATE, LINTER_RULES_PATH, ENV_FILE_PATH (the env file the action
# loaded), GITHUB_WORKSPACE, and for the diff EVENT_NAME, BASE_SHA, HEAD_SHA
# and DEFAULT_BRANCH as docs-only.sh defines them. DEFAULT_BRANCH is also a
# Super Linter setting, so a value the env file set wins; REPO_DEFAULT_BRANCH,
# the repository's default branch, is the fallback.
#
# Sourceable: the test sources it, and main runs only when the file is
# executed. Bash 3.2 compatible (macOS).
set -uo pipefail

LANGUAGE_GATE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LANGUAGE_GATE_DEPS=missing
# changed_paths, glob_to_regex and globs_to_regexes: one diff and one glob
# dialect across this repository's actions.
if [ -f "$LANGUAGE_GATE_DIR/../docs-only/docs-only.sh" ]; then
	# shellcheck source-path=SCRIPTDIR source=../docs-only/docs-only.sh
	if . "$LANGUAGE_GATE_DIR/../docs-only/docs-only.sh"; then
		LANGUAGE_GATE_DEPS=ok
	fi
fi

# Globs of the paths each Super Linter language key lints, in the docs-only
# dialect. Ties go broad: a glob that is too wide costs a run, one that is too
# narrow costs a missed lint. Keys that scan every file or the whole workspace
# are '**'. Returns 1 for a key not listed, which the caller treats as run.
language_globs() {
	case "$1" in
	CHECKOV | EDITORCONFIG | GITLEAKS | GIT_MERGE_CONFLICT_MARKERS | JSCPD | \
		NATURAL_LANGUAGE | PRE_COMMIT | SPELL_CODESPELL | TRIVY)
		echo '**' ;;
	BASH | BASH_EXEC | SHELL_SHFMT) echo '**/*.sh,**/*.bash,**/*.dash,**/*.ksh' ;;
	CLOJURE) echo '**/*.clj,**/*.cljs,**/*.cljc,**/*.edn' ;;
	CSS | CSS_PRETTIER) echo '**/*.css,**/*.scss,**/*.sass,**/*.less' ;;
	DOCKERFILE_HADOLINT) echo '**/Dockerfile,**/Dockerfile.*,**/*.dockerfile,**/Containerfile' ;;
	GITHUB_ACTIONS) echo '.github/workflows/**,**/action.yml,**/action.yaml' ;;
	# zizmor also audits Dependabot configuration.
	GITHUB_ACTIONS_ZIZMOR)
		echo '.github/workflows/**,**/action.yml,**/action.yaml,.github/dependabot.y*ml' ;;
	GO) echo '**/*.go' ;;
	GO_MODULES) echo '**/go.mod,**/go.sum,**/*.go' ;;
	GOOGLE_JAVA_FORMAT | JAVA) echo '**/*.java' ;;
	HTML | HTML_PRETTIER) echo '**/*.html,**/*.htm' ;;
	JAVASCRIPT_ES | JAVASCRIPT_PRETTIER) echo '**/*.js,**/*.mjs,**/*.cjs' ;;
	JSON | JSON_PRETTIER) echo '**/*.json' ;;
	JSONC | JSONC_PRETTIER) echo '**/*.jsonc,**/*.json5' ;;
	JSX | JSX_PRETTIER) echo '**/*.jsx' ;;
	MARKDOWN | MARKDOWN_PRETTIER) echo '**/*.md,**/*.markdown' ;;
	POWERSHELL) echo '**/*.ps1,**/*.psm1,**/*.psd1' ;;
	PYTHON_BLACK | PYTHON_FLAKE8 | PYTHON_ISORT | PYTHON_MYPY | PYTHON_PYLINT | \
		PYTHON_RUFF | PYTHON_RUFF_FORMAT)
		echo '**/*.py,**/*.pyi' ;;
	RUBY) echo '**/*.rb,**/Gemfile,**/Rakefile,**/*.gemspec' ;;
	RUST_2015 | RUST_2018 | RUST_2021 | RUST_CLIPPY) echo '**/*.rs,**/Cargo.toml' ;;
	SQLFLUFF) echo '**/*.sql' ;;
	TERRAFORM_FMT | TERRAFORM_TFLINT | TERRAGRUNT) echo '**/*.tf,**/*.tfvars,**/*.hcl' ;;
	TSX) echo '**/*.tsx' ;;
	TYPESCRIPT_ES | TYPESCRIPT_PRETTIER) echo '**/*.ts,**/*.mts,**/*.cts' ;;
	XML) echo '**/*.xml' ;;
	YAML | YAML_PRETTIER) echo '**/*.yml,**/*.yaml' ;;
	*) return 1 ;;
	esac
}

# Returns 0 when PATH ($1) matches any of the anchored regexes, one per line,
# in $2, ignoring case: README.MD, a.YML and x.PY are linted like their
# lower-case twins, and a case-sensitive miss would skip a lint. Leaves
# nocasematch as it found it.
matches_any_regex() {
	local path="$1" re found=1 had=0
	shopt -q nocasematch && had=1
	shopt -s nocasematch
	while IFS= read -r re; do
		if [ -n "$re" ] && [[ $path =~ $re ]]; then
			found=0
			break
		fi
	done <<<"$2"
	[ "$had" = 1 ] || shopt -u nocasematch
	return "$found"
}

# Extensions that are certainly not shell scripts. Super Linter recognises a
# shell script by shebang as well as by extension, so a file named .envrc,
# .bashrc or deploy.run can be one; the gate cannot see the shebang, so for a
# shell key any extension outside this list counts as a match.
NON_SHELL_EXTENSIONS=' md markdown txt rst adoc png jpg jpeg gif svg ico webp bmp pdf '
NON_SHELL_EXTENSIONS+='json jsonc json5 yml yaml xml html htm css scss sass less '
NON_SHELL_EXTENSIONS+='js mjs cjs jsx ts mts cts tsx py pyi rb go java kt rs toml ini cfg '
NON_SHELL_EXTENSIONS+='lock csv tsv zip gz tgz tar woff woff2 ttf otf eot mp3 mp4 mov '
NON_SHELL_EXTENSIONS+='tf tfvars hcl sql ps1 psm1 psd1 clj cljs cljc edn properties gradle log map '

# Returns 0 when Super Linter's KEY ($2) would lint PATH ($1). Shell keys also
# match a file whose name has no dot, or whose extension is not a known
# non-shell one (NON_SHELL_EXTENSIONS).
path_matches_key() {
	local path="$1" key="$2" globs name ext
	case "$key" in
	BASH | BASH_EXEC | SHELL_SHFMT)
		name="${path##*/}"
		case "$name" in
		*.*)
			ext=$(printf '%s' "${name##*.}" | tr '[:upper:]' '[:lower:]')
			case "$NON_SHELL_EXTENSIONS" in *" $ext "*) ;; *) return 0 ;; esac
			;;
		*) return 0 ;;
		esac
		;;
	esac
	globs=$(language_globs "$key") || return 0
	matches_any_regex "$path" "$(globs_to_regexes "$globs")"
}

# Root-level files that configure a linter, plus the two .github/ ones that
# do, and every Super Linter env file. A change to one can alter the result on
# files the change did not touch, so it always runs. Applied whatever
# LINTER_RULES_PATH is.
LINT_CONFIG_GLOBS='.yamllint,.yamllint.*,.yaml-lint.*,.markdown-lint.*,.markdownlint*,'
LINT_CONFIG_GLOBS+='.shellcheckrc,.hadolint.*,.zizmor.*,zizmor.*,actionlint.*,'
LINT_CONFIG_GLOBS+='.github/actionlint.*,.github/zizmor.*,.github/super-linter*.env,'
LINT_CONFIG_GLOBS+='.editorconfig,.gitleaks.toml,.checkov.*,.jscpd.json,.textlintrc*,'
LINT_CONFIG_GLOBS+='.eslintrc*,eslint.config.*,.prettierrc*,prettier.config.*,'
LINT_CONFIG_GLOBS+='.flake8,.isort.cfg,.mypy.ini,mypy.ini,.ruff.toml,ruff.toml,.pylintrc,'
LINT_CONFIG_GLOBS+='.python-lint,pyproject.toml,setup.cfg,tox.ini,.stylelintrc*,'
LINT_CONFIG_GLOBS+='stylelint.config.*,.htmlhintrc,.sqlfluff,.tflint.hcl,'
LINT_CONFIG_GLOBS+='.python-black,.rubocop.yml,.golangci.y*ml,tsconfig*.json,package.json,'
LINT_CONFIG_GLOBS+='.prettierignore,.eslintignore,.stylelintignore,.trivyignore'

# Prints $1 relative to the workspace: a leading $GITHUB_WORKSPACE/, a leading
# '/' and any leading './' removed, a trailing '/' removed. The workspace root
# itself prints as empty. Super Linter resolves LINTER_RULES_PATH the same way.
normalize_path() {
	local p="$1"
	if [ -n "${GITHUB_WORKSPACE:-}" ]; then
		p="${p#"$GITHUB_WORKSPACE"/}"
	fi
	p="${p#/}"
	while [ "${p#./}" != "$p" ]; do p="${p#./}"; done
	p="${p%/}"
	[ "$p" = . ] && p=""
	printf '%s' "$p"
}

# Returns 0 when PATH ($1) is lint configuration: the env file in use, a path
# under LINTER_RULES_PATH (default .github/linters), or a LINT_CONFIG_GLOBS
# match. A LINTER_RULES_PATH at the workspace root would make every path
# configuration, so there only LINT_CONFIG_GLOBS and root-level dotfiles
# (.gitignore too: IGNORE_GITIGNORED_FILES makes it relevant) apply.
is_config_trigger() {
	local path="$1" rules env
	rules=$(normalize_path "${LINTER_RULES_PATH:-.github/linters}")
	if [ -n "$rules" ]; then
		case "$path" in "$rules"/*) return 0 ;; esac
	else
		case "$path" in */*) ;; .*) return 0 ;; esac
	fi
	env=$(normalize_path "${ENV_FILE_PATH:-}")
	if [ -n "$env" ] && [ "$path" = "$env" ]; then
		return 0
	fi
	matches_any_regex "$path" "$(globs_to_regexes "$LINT_CONFIG_GLOBS")"
}

# Reads every exported VALIDATE_* except VALIDATE_ALL_CODEBASE, as Super
# Linter does. Sets MODE:
#   none     no language key set: every linter runs
#   allow    only '=true' keys: exactly those run
#   deny     only '=false' keys: every other linter runs
#   mixed    both: Super Linter rejects the configuration
#   invalid  a value other than exactly 'true' or 'false'
# and ENABLED_KEYS to the space-separated keys set to 'true', prefix removed.
enabled_mode() {
	local name val t=0 f=0 bad=0
	ENABLED_KEYS=""
	for name in $(compgen -e); do
		case "$name" in
		VALIDATE_ALL_CODEBASE) continue ;;
		VALIDATE_*) ;;
		*) continue ;;
		esac
		val="${!name}"
		case "$val" in
		true)
			t=1
			ENABLED_KEYS="${ENABLED_KEYS:+$ENABLED_KEYS }${name#VALIDATE_}"
			;;
		false) f=1 ;;
		*) bad=1 ;;
		esac
	done
	if [ "$bad" = 1 ]; then
		MODE=invalid
	elif [ "$t" = 1 ] && [ "$f" = 1 ]; then
		MODE=mixed
	elif [ "$t" = 1 ]; then
		MODE=allow
	elif [ "$f" = 1 ]; then
		MODE=deny
	else
		MODE=none
	fi
}

# Returns 0 when the configuration lets the gate look at paths at all.
# Otherwise sets RUN=true and REASON and returns 1.
gate_config() {
	local key
	RUN=true
	if [ "${LANGUAGE_GATE:-true}" != true ]; then
		REASON="language_gate is '${LANGUAGE_GATE}'"
		return 1
	fi
	enabled_mode
	case "$MODE" in
	none)
		REASON="no VALIDATE_* language key is set, so every linter is enabled"
		return 1
		;;
	deny)
		REASON="only VALIDATE_*=false keys are set, so every other linter is enabled"
		return 1
		;;
	mixed)
		REASON="VALIDATE_*=true and VALIDATE_*=false are both set; Super Linter reports that itself"
		return 1
		;;
	invalid)
		REASON="a VALIDATE_* value is not exactly true or false"
		return 1
		;;
	esac
	for key in $ENABLED_KEYS; do
		if ! language_globs "$key" >/dev/null; then
			REASON="VALIDATE_${key}=true is not in the gate's language table"
			return 1
		fi
	done
	return 0
}

# Reads changed paths, one per line, on stdin. Sets RUN and REASON.
decide() {
	local path key any=0
	REASON=""
	gate_config || return 0
	while IFS= read -r path || [ -n "$path" ]; do
		[ -z "$path" ] && continue
		any=1
		# git quotes a path holding a quote, backslash or control character
		# ("..." with C escapes), so no glob matches it. Fail open.
		case "$path" in
		'"'*)
			RUN=true
			REASON="path requires quoting: ${path}"
			return 0
			;;
		esac
		if is_config_trigger "$path"; then
			RUN=true
			REASON="${path} configures a linter"
			return 0
		fi
		for key in $ENABLED_KEYS; do
			if path_matches_key "$path" "$key"; then
				RUN=true
				REASON="${path} is linted by VALIDATE_${key}"
				return 0
			fi
		done
	done
	if [ "$any" = 0 ]; then
		RUN=true
		REASON="no changed paths"
		return 0
	fi
	RUN=false
	REASON="no changed path is in an enabled language (${ENABLED_KEYS})"
}

main() {
	local out="${GITHUB_OUTPUT:-/dev/stdout}"
	RUN=true
	REASON=""
	if [ "$LANGUAGE_GATE_DEPS" != ok ]; then
		REASON="cannot load ../docs-only/docs-only.sh for change detection"
	elif gate_config; then
		if changed_paths "${EVENT_NAME:-}" "${BASE_SHA:-}" "${HEAD_SHA:-}" "${DEFAULT_BRANCH:-${REPO_DEFAULT_BRANCH:-}}"; then
			decide <<<"$CHANGED"
		else
			RUN=true
		fi
	fi
	if [ "$RUN" = false ]; then
		echo "::notice::Super Linter skipped: $REASON"
		[ -n "${GITHUB_STEP_SUMMARY:-}" ] &&
			printf 'Super Linter skipped: %s\n' "$REASON" >>"$GITHUB_STEP_SUMMARY" 2>/dev/null
	else
		echo "::notice::Super Linter runs: $REASON"
	fi
	if ! printf 'run=%s\nreason=%s\n' "$RUN" "$REASON" >>"$out" 2>/dev/null; then
		echo "cannot write outputs to $out" >&2
		return 2
	fi
	return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	main
	exit $?
fi


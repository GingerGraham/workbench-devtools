#!/usr/bin/env bash
# tests/check-manifest-structure.sh — workbench-devtools
# Plain bash, numbered OK:/FAIL: checks, matching workbench-core's
# tests/check-*.sh convention (no framework). Structural checks only.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }

# Manifest discovery, duplicated inline rather than sourced from
# workbench-core — this script runs standalone in this module's own CI,
# the same "must work without workbench-core installed alongside it"
# constraint lib/manifest/validate.sh's own header documents for its
# identical duplication (workbench-core ARCHITECTURE.md §12 D46). Checked
# in precedence order; .dotfiles-sync.yml is accepted unconditionally,
# the four new names only if they declare a top-level version: key.
_MANIFEST_CANDIDATES="workbench.yml workbench.yaml wb.yml wb.yaml .dotfiles-sync.yml"
MANIFEST=""
for _name in ${_MANIFEST_CANDIDATES}; do
    _candidate="${REPO_ROOT}/${_name}"
    [[ -f "${_candidate}" ]] || continue
    if [[ "${_name}" == ".dotfiles-sync.yml" ]]; then
        MANIFEST="${_candidate}"
        break
    fi
    grep -q '^version:' "${_candidate}" && { MANIFEST="${_candidate}"; break; }
done

if [[ -n "${MANIFEST}" ]]; then
    ok "manifest found ($(basename "${MANIFEST}"))"
else
    fail "no manifest found (checked ${_MANIFEST_CANDIDATES})"
fi

for key in version core_api register; do
    if [[ -n "${MANIFEST}" ]] && grep -q "^${key}:" "${MANIFEST}"; then
        ok "manifest declares '${key}:'"
    else
        fail "manifest missing '${key}:'"
    fi
done

# Core API 1.8 generates get-devtools-functions from register.getters[]
# (workbench-core docs/decisions-log.md D89) and ships
# _wb_gh_release_asset_url (D90), both of which this module relies on.
if [[ -n "${MANIFEST}" ]] && grep -qE '^core_api:[[:space:]]*">=1\.8 <2\.0"[[:space:]]*$' "${MANIFEST}"; then
    ok "manifest declares core_api \">=1.8 <2.0\""
else
    fail "manifest core_api is not \">=1.8 <2.0\""
fi

if [[ -n "${MANIFEST}" ]]; then
    while IFS= read -r src; do
        [[ -z "${src}" ]] && continue
        if [[ -f "${REPO_ROOT}/${src}" ]]; then
            ok "referenced file exists: ${src}"
        else
            fail "manifest references missing file: ${src}"
        fi
    done < <(grep -E '^[[:space:]]*(-[[:space:]]*)?src:' "${MANIFEST}" | sed -E 's/^[[:space:]]*-?[[:space:]]*src:[[:space:]]*//')
fi

# list-edit-releases is a read-only interactive helper -- must live in a
# register.shell file, not register.installers (wb tools only sources the
# latter transiently to invoke one install-<name> function).
# shellcheck disable=SC2043 # one name today; a list so more can be added
for fn in list-edit-releases; do
    if grep -qE "^${fn}[[:space:]]*\(\)" "${REPO_ROOT}/shell/devtools.sh" 2>/dev/null; then
        ok "${fn} is in shell/devtools.sh (register.shell)"
    else
        fail "${fn} not found in shell/devtools.sh -- would be unreachable interactively if only in installers.sh"
    fi
done

# No hand-written getter: core defines get-devtools-functions from the
# manifest, and works in zsh. A hand-written one would win over core's, and
# the old one used ${BASH_SOURCE[0]} inside a function, which zsh doesn't set.
if ! grep -rqE '^[[:space:]]*(function[[:space:]]+)?get-[a-z-]+-functions' "${REPO_ROOT}/shell/"; then
    ok "shell/ defines no get-*-functions getter (core generates it)"
else
    fail "shell/ defines a get-*-functions getter -- delete it; core generates it from register.getters[]"
fi

# The module's getter is declared in the manifest, for core to generate.
if [[ -n "${MANIFEST}" ]] && grep -qE '^[[:space:]]*function:[[:space:]]*get-devtools-functions[[:space:]]*$' "${MANIFEST}"; then
    ok "manifest declares register.getters[] get-devtools-functions"
else
    fail "manifest does not declare get-devtools-functions in register.getters[]"
fi

# The shared helper comes from core; no private copy.
if ! grep -rqE '^[[:space:]]*_gh_release_asset_url[[:space:]]*\(\)' "${REPO_ROOT}/shell/"; then
    ok "no private _gh_release_asset_url (uses core's _wb_gh_release_asset_url)"
else
    fail "shell/ defines a private _gh_release_asset_url -- call core's _wb_gh_release_asset_url"
fi

# tenv auto-install is opt-in (workbench-iac), never forced on by this module.
if grep -vE '^[[:space:]]*#' "${REPO_ROOT}/shell/development.sh" | grep -q 'TENV_AUTO_INSTALL'; then
    fail "shell/development.sh sets TENV_AUTO_INSTALL -- it is the user's opt-in"
else
    ok "shell/development.sh leaves TENV_AUTO_INSTALL to the user"
fi

# _dotfiles_init_python_manager must NOT be auto-invoked at source time --
# workbench-core's loader has no post-local-overrides hook to call it safely,
# so it stays opt-in from the user's own local settings.sh.
if grep -vE '^[[:space:]]*#' "${REPO_ROOT}/shell/development.sh" \
    | grep -qE '^[[:space:]]*_dotfiles_init_python_manager[[:space:]]*$'; then
    fail "_dotfiles_init_python_manager is auto-invoked in shell/development.sh -- must stay opt-in"
else
    ok "_dotfiles_init_python_manager is not auto-invoked"
fi

# No DOTFILES_* leftovers from the precursor -- everything should be WORKBENCH_*.
# (excludes comment lines, which legitimately name the old var in rename notes)
if find "${REPO_ROOT}/shell" -type f -print0 2>/dev/null \
    | xargs -0 grep -vE '^[[:space:]]*#' 2>/dev/null \
    | grep -qE 'DOTFILES_(OS|DISTRO|SHELL|ARCH)'; then
    fail "found leftover DOTFILES_* Core API references in shell/ -- should be WORKBENCH_*"
else
    ok "no leftover DOTFILES_* Core API references"
fi

# No grep -P (GNU-only PCRE) -- must use portable sed/grep -E instead.
# (excludes comment lines, and this file's own checks below)
if find "${REPO_ROOT}/shell" -type f -print0 2>/dev/null \
    | xargs -0 grep -vE '^[[:space:]]*#' 2>/dev/null \
    | grep -qE 'grep[[:space:]]+(-[a-zA-Z]*P|--perl-regexp)'; then
    fail "found grep -P (GNU-only PCRE) -- not portable to BSD grep"
else
    ok "no grep -P usage"
fi

declare -a _bash32_patterns=(
    "declare -A (associative arrays, bash 4+)|declare[[:space:]]+-A"
    "mapfile/readarray (bash 4+)|(^|[^[:alnum:]_])(mapfile|readarray)([^[:alnum:]_]|\$)"
    "shopt -s globstar (bash 4+)|shopt[[:space:]]+-s[[:space:]]+globstar"
    "\${var,,} / \${var^^} case conversion (bash 4+)|\\\$\\{[a-zA-Z_][a-zA-Z0-9_]*(,,|\\^\\^)"
    "declare -n nameref (bash 4.3+)|declare[[:space:]]+-n"
)
for entry in "${_bash32_patterns[@]}"; do
    desc="${entry%%|*}"
    pattern="${entry#*|}"
    hit=""
    while IFS= read -r -d '' f; do
        grep -vE '^[[:space:]]*#' "${f}" | grep -qE "${pattern}" && hit="${hit}${f}\n"
    done < <(find "${REPO_ROOT}/shell" -type f -print0 2>/dev/null)
    if [[ -n "${hit}" ]]; then
        fail "found ${desc} in: $(printf '%b' "${hit}" | tr '\n' ' ')"
    else
        ok "no ${desc}"
    fi
done

echo
echo "==============================="
echo "Total OK/FAIL checks: ${check_no}, failed: ${FAILED}"
echo "==============================="
[[ "${FAILED}" -eq 0 ]]

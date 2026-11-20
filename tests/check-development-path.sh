#!/usr/bin/env bash
# tests/check-development-path.sh — workbench-devtools
# Plain bash, numbered OK:/FAIL: checks, matching workbench-core's
# tests/check-*.sh convention (no framework). shell/development.sh adds the
# directories the user owns (~/go/bin, ~/.pyenv/bin, ~/.cargo/bin) to the END
# of PATH, so nothing in them can shadow a system command. Every case runs in
# `env -i` with a fake HOME: nothing real is touched.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEV_SH="${REPO_ROOT}/shell/development.sh"

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/devtools-path.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

HOME_DIR="${WORK}/home"
mkdir -p "${HOME_DIR}/go/bin" "${HOME_DIR}/.pyenv/bin" "${HOME_DIR}/.cargo/bin"
EMPTY_HOME="${WORK}/empty-home"
mkdir -p "${EMPTY_HOME}"

# _path_after <shell> <home> <starting PATH> <repeat-count>
# Sources development.sh <repeat-count> times and prints the resulting PATH.
# /usr/local/go/bin is root-owned and kept at the front on purpose, and
# whether it exists depends on the machine running this test, so it is left
# out of what is printed.
_path_after() {
    local sh="$1" home="$2" start="$3" repeat="${4:-1}" result
    # shellcheck disable=SC2016 # expanded by the inner shell, not here
    result="$(env -i HOME="${home}" START="${start}" DEV_SH="${DEV_SH}" REPEAT="${repeat}" \
        "${sh}" -c '
            log_debug() { :; }
            PATH="${START}"
            i=0
            while [ "${i}" -lt "${REPEAT}" ]; do
                . "${DEV_SH}" >/dev/null 2>&1
                i=$((i + 1))
            done
            printf "%s" "${PATH}"
        ')"
    printf '%s' "${result//\/usr\/local\/go\/bin:/}"
}

SHELLS="bash"
command -v zsh &>/dev/null && SHELLS="bash zsh"

for sh in ${SHELLS}; do
    want="/usr/bin:/bin:${HOME_DIR}/go/bin:${HOME_DIR}/.pyenv/bin:${HOME_DIR}/.cargo/bin"
    got="$(_path_after "${sh}" "${HOME_DIR}" "/usr/bin:/bin" 1)"
    if [[ "${got}" == "${want}" ]]; then
        ok "${sh}: go, pyenv and cargo directories come after the system directories"
    else
        fail "${sh}: expected ${want}, got ${got}"
    fi

    got="$(_path_after "${sh}" "${HOME_DIR}" "/usr/bin:/bin" 3)"
    if [[ "${got}" == "${want}" ]]; then
        ok "${sh}: sourcing three times adds each directory once"
    else
        fail "${sh}: repeated sourcing changed PATH to ${got}"
    fi

    start="${HOME_DIR}/.cargo/bin:/usr/bin:/bin"
    got="$(_path_after "${sh}" "${HOME_DIR}" "${start}" 1)"
    if [[ "${got}" == "${HOME_DIR}/.cargo/bin:/usr/bin:/bin:${HOME_DIR}/go/bin:${HOME_DIR}/.pyenv/bin" ]]; then
        ok "${sh}: a directory already on PATH keeps its position and is not repeated"
    else
        fail "${sh}: pre-existing cargo entry moved or duplicated: ${got}"
    fi

    got="$(_path_after "${sh}" "${EMPTY_HOME}" "/usr/bin:/bin" 1)"
    if [[ "${got}" == "/usr/bin:/bin" ]]; then
        ok "${sh}: directories that don't exist are not added"
    else
        fail "${sh}: PATH changed with no tool directories present: ${got}"
    fi

    got="$(_path_after "${sh}" "${HOME_DIR}" "" 1)"
    if [[ "${got}" == "${HOME_DIR}/go/bin:${HOME_DIR}/.pyenv/bin:${HOME_DIR}/.cargo/bin" ]]; then
        ok "${sh}: an empty PATH gets no leading colon (an empty entry means the current directory)"
    else
        fail "${sh}: empty PATH produced '${got}'"
    fi
done

# The helper is scaffolding: it must not stay defined in the user's shell.
# shellcheck disable=SC2016 # expanded by the inner shell, not here
leaked="$(env -i HOME="${HOME_DIR}" DEV_SH="${DEV_SH}" bash -c 'log_debug() { :; }; PATH=/usr/bin:/bin; . "${DEV_SH}" >/dev/null 2>&1; declare -F _wb_dev_path_append')"
if [[ -z "${leaked}" ]]; then
    ok "_wb_dev_path_append is not left defined after sourcing"
else
    fail "_wb_dev_path_append leaked into the shell"
fi

echo
if [[ "${FAILED}" -eq 0 ]]; then
    echo "All ${check_no} checks passed."
    exit 0
else
    echo "${FAILED} of ${check_no} checks failed."
    exit 1
fi

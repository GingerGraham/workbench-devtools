#!/usr/bin/env bash
# tests/check-development-nvm.sh — workbench-devtools
# Plain bash, numbered OK:/FAIL: checks, matching workbench-core's
# tests/check-*.sh convention (no framework). shell/development.sh defines
# lazy-load stubs for nvm/node/npm/npx; it must not do so when nvm is
# already active in the shell (a real `nvm` function, or a non-empty
# NVM_BIN), and it must behave the same under zsh. Every case runs in
# `env -i` with a fake HOME and a fake nvm.sh: nothing real is touched.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEV_SH="${REPO_ROOT}/shell/development.sh"

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/devtools-nvm.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

HOME_DIR="${WORK}/home"
mkdir -p "${HOME_DIR}/.nvm"
# A fake nvm.sh that does nothing but must be non-empty (the guard is -s).
echo '# fake nvm.sh' > "${HOME_DIR}/.nvm/nvm.sh"

# _probe <shell> <setup-snippet> <repeat-count>
# Runs <setup-snippet>, sources development.sh <repeat-count> times, then
# prints one line:
#   stubs=<n> nvm_sum=<cksum of declare -f nvm> var=<yes|no>
# stubs is how many of nvm/node/npm/npx are functions, nvm_sum identifies
# the nvm function's body, and var says whether a variable named nvm exists.
_probe() {
    local sh="$1" setup="$2" repeat="${3:-1}"
    # shellcheck disable=SC2016 # expanded by the inner shell, not here
    env -i PATH="${PATH}" HOME="${HOME_DIR}" SETUP="${setup}" DEV_SH="${DEV_SH}" REPEAT="${repeat}" \
        "${sh}" -c '
            log_debug() { :; }
            eval "${SETUP}"
            i=0
            while [ "${i}" -lt "${REPEAT}" ]; do
                . "${DEV_SH}" >/dev/null 2>&1
                i=$((i + 1))
            done
            n=0
            for f in nvm node npm npx; do
                declare -f "${f}" >/dev/null 2>&1 && n=$((n + 1))
            done
            sum="$(declare -f nvm 2>/dev/null | cksum)"
            if typeset -p nvm >/dev/null 2>&1; then v=yes; else v=no; fi
            echo "stubs=${n} nvm_sum=${sum% *} var=${v}"
        ' 2>&1
}

# The body of a real nvm function, as a user's rc would have defined it.
REAL_NVM='nvm() { echo "real nvm"; }'
# What `declare -f nvm` reports for it, per shell, measured before sourcing.
_before_sum() {
    local sh="$1"
    # shellcheck disable=SC2016 # expanded by the inner shell, not here
    env -i PATH="${PATH}" HOME="${HOME_DIR}" REAL="${REAL_NVM}" "${sh}" -c \
        'eval "${REAL}"; sum="$(declare -f nvm | cksum)"; echo "${sum% *}"' 2>&1
}

_field() { # _field <line> <name>
    printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p"
}

for sh in bash zsh; do
    if ! command -v "${sh}" >/dev/null 2>&1; then
        echo "SKIP: ${sh} not installed -- development.sh nvm checks"
        continue
    fi

    # 1. Plain host: nvm.sh present, no nvm function, no NVM_BIN -> stubs.
    out="$(_probe "${sh}" ':' 1)"
    if [[ "$(_field "${out}" stubs)" == "4" ]]; then
        ok "${sh}: nvm.sh present, nvm not loaded: nvm/node/npm/npx stubs are defined"
    else
        fail "${sh}: expected 4 stubs on a plain host, got: ${out}"
    fi
    if [[ "$(_field "${out}" var)" == "no" ]]; then
        ok "${sh}: no variable named nvm exists after sourcing (plain host)"
    else
        fail "${sh}: a variable named nvm exists after sourcing (plain host): ${out}"
    fi

    # 2. A real nvm() already defined -> no stubs, same function afterwards.
    before="$(_before_sum "${sh}")"
    out="$(_probe "${sh}" "${REAL_NVM}" 1)"
    if [[ "$(_field "${out}" stubs)" == "1" && "$(_field "${out}" nvm_sum)" == "${before}" ]]; then
        ok "${sh}: a loaded nvm function is left alone (no node/npm/npx stubs, nvm unchanged)"
    else
        fail "${sh}: loaded nvm function was replaced or stubs were added (before sum ${before}): ${out}"
    fi
    if [[ "$(_field "${out}" var)" == "no" ]]; then
        ok "${sh}: no variable named nvm exists after sourcing (nvm function loaded)"
    else
        fail "${sh}: a variable named nvm exists after sourcing (nvm function loaded): ${out}"
    fi

    # 3. NVM_BIN set, no nvm function -> no stubs.
    out="$(_probe "${sh}" 'export NVM_BIN=/somewhere/node/bin' 1)"
    if [[ "$(_field "${out}" stubs)" == "0" ]]; then
        ok "${sh}: NVM_BIN set, no nvm function: no stubs are defined"
    else
        fail "${sh}: NVM_BIN is set but stubs were defined: ${out}"
    fi
    if [[ "$(_field "${out}" var)" == "no" ]]; then
        ok "${sh}: no variable named nvm exists after sourcing (NVM_BIN set)"
    else
        fail "${sh}: a variable named nvm exists after sourcing (NVM_BIN set): ${out}"
    fi

    # An empty NVM_BIN does not count as "nvm is loaded".
    out="$(_probe "${sh}" 'export NVM_BIN=' 1)"
    if [[ "$(_field "${out}" stubs)" == "4" ]]; then
        ok "${sh}: an empty NVM_BIN still gets the stubs"
    else
        fail "${sh}: empty NVM_BIN suppressed the stubs: ${out}"
    fi

    # 4. Sourcing twice gives the same result as sourcing once.
    for case_setup in ':' "${REAL_NVM}" 'export NVM_BIN=/somewhere/node/bin'; do
        once="$(_probe "${sh}" "${case_setup}" 1)"
        twice="$(_probe "${sh}" "${case_setup}" 2)"
        if [[ "${once}" == "${twice}" ]]; then
            ok "${sh}: sourcing twice changes nothing (setup: ${case_setup})"
        else
            fail "${sh}: second source changed the result (setup: ${case_setup}): once='${once}' twice='${twice}'"
        fi
    done
done

echo
echo "==============================="
echo "Total OK/FAIL checks: ${check_no}, failed: ${FAILED}"
echo "==============================="
[[ "${FAILED}" -eq 0 ]]

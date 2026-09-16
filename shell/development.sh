#!/usr/bin/env bash
# shell/development.sh — workbench-devtools
# Cross-cutting dev-environment PATH/env wiring: Go, Python (uv/pyenv), Node
# (nvm), tfenv, Cargo, asdf, tenv. Registered at tier: env
# (.dotfiles-sync.yml) — runs early, alongside workbench-core's own env
# tier, so these exports are in place before tools/platform/distro/lazy
# tiers load.
#
# Ported from workbench-precursor's shell/config/env/20-development.sh.
#
# WORKBENCH_SHELL replaces DOTFILES_SHELL (Core API rename,
# contracts/core-api.md).
#
# _dotfiles_init_python_manager is intentionally NOT auto-invoked here.
# In the precursor, loader.sh called it explicitly *after* sourcing
# 90-local.sh (local overrides), so a user's DOTFILES_PYTHON_MANAGER
# setting could still steer it. workbench-core's loader has no equivalent
# "run this after local overrides" hook for module-registered content — only
# core's own dedupe-path gets that special post-tier treatment (D19-adjacent;
# see ARCHITECTURE.md). Rather than force a hook into the engine for one
# module's one function, this is left as a function a user opts into calling
# themselves, from their own ~/.config/workbench/local/settings.sh, after
# setting WORKBENCH_PYTHON_MANAGER there:
#
#   WORKBENCH_PYTHON_MANAGER=pyenv
#   _dotfiles_init_python_manager
#
# If this pattern turns out to be needed by other modules too, promoting a
# generic post-local-overrides hook to the Core API is the right fix —
# log it as a new decision in workbench-core's ARCHITECTURE.md §12 rather
# than reinventing it per-module.

# ── Go ──
if [[ -d "${HOME}/go" ]]; then
    export GOPATH="${HOME}/go"
    [[ -d "${GOPATH}/bin" ]] && PATH="${GOPATH}/bin:${PATH}"
fi
[[ -d "/usr/local/go/bin" ]] && PATH="/usr/local/go/bin:${PATH}"

# ── Python: uv / pyenv ──
# WORKBENCH_PYTHON_MANAGER (set in ~/.config/workbench/local/settings.sh):
# auto|uv|pyenv|both
if [[ -d "${HOME}/.pyenv" ]]; then
    export PYENV_ROOT="${HOME}/.pyenv"
    PATH="${PYENV_ROOT}/bin:${PATH}"
fi

_dotfiles_init_python_manager() {
    local uv_present=false
    command -v uv &>/dev/null && uv_present=true
    if [[ "${uv_present}" == "true" ]]; then
        export UV_TOOL_BIN_DIR="${HOME}/.local/bin"
    fi
    local manager="${WORKBENCH_PYTHON_MANAGER:-auto}"
    local init_pyenv_shims=false
    case "${manager}" in
        uv)         ;;
        pyenv|both) init_pyenv_shims=true ;;
        *)          [[ "${uv_present}" == "false" ]] && init_pyenv_shims=true ;;
    esac
    [[ -d "${HOME}/.pyenv" ]] && command -v pyenv &>/dev/null || return 0
    if [[ "${init_pyenv_shims}" == "true" ]]; then
        eval "$(pyenv init - "${WORKBENCH_SHELL:-bash}")"
        if pyenv commands 2>/dev/null | grep -q virtualenv-init; then
            eval "$(pyenv virtualenv-init -)"
        fi
        log_debug "python manager: pyenv (WORKBENCH_PYTHON_MANAGER=${manager}, uv present=${uv_present})"
    else
        log_debug "python manager: uv (pyenv shims not initialised — WORKBENCH_PYTHON_MANAGER=${manager})"
    fi
}

# ── Node / nvm ──
export NVM_DIR="${NVM_DIR:-${HOME}/.nvm}"

# nvm/node/npm/npx below are only ever defined once the nvm.sh presence
# check passes, but get-devtools-functions' static-grep listing can't see
# that runtime guard, so without this it would list all four even on
# hosts without nvm installed. Declared unconditionally, ahead of the
# guard, so the predicate itself still exists (and correctly says
# "unavailable") on a host without nvm — declaring it inside the guard
# would mean it's never defined there either, and an undeclared predicate
# defaults to available.
_nvm_present() { [[ -s "${NVM_DIR}/nvm.sh" ]]; }
_wb_alias_availability _nvm_present nvm node npm npx

if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
    _load_nvm() {
        for _nvm_fn in nvm node npm npx yarn pnpm; do
            declare -f "${_nvm_fn}" &>/dev/null && unset -f "${_nvm_fn}"
        done
        unset _nvm_fn
        # shellcheck disable=SC1091
        source "${NVM_DIR}/nvm.sh"
        # shellcheck disable=SC1091
        [[ -s "${NVM_DIR}/bash_completion" ]] && source "${NVM_DIR}/bash_completion"
    }
    nvm()  { _load_nvm; nvm  "$@"; }
    node() { _load_nvm; node "$@"; }
    npm()  { _load_nvm; npm  "$@"; }
    npx()  { _load_nvm; npx  "$@"; }
fi

# ── tfenv ──
if [[ -d "${HOME}/.tfenv" ]]; then
    export TFENV_ROOT="${HOME}/.tfenv"
    PATH="${TFENV_ROOT}/bin:${PATH}"
fi

# ── Cargo (Rust) ──
[[ -d "${HOME}/.cargo/bin" ]] && PATH="${HOME}/.cargo/bin:${PATH}"

# ── asdf ──
# shellcheck disable=SC1091
[[ -s "${HOME}/.asdf/asdf.sh" ]] && source "${HOME}/.asdf/asdf.sh"

# ── tenv ──
command -v tenv &>/dev/null && export TENV_AUTO_INSTALL=true

export PATH

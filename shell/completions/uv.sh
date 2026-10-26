#!/usr/bin/env bash
# uv completions — version-stamped cache.

_uv_cache_dir="${XDG_CACHE_HOME:-${HOME}/.cache}/workbench/completions"
_uv_version="$(uv --version 2>/dev/null | awk '{print $2}')"

if [[ -n "${_uv_version}" ]]; then
    _uv_cache="${_uv_cache_dir}/uv.${WORKBENCH_SHELL}.${_uv_version}.sh"

    if [[ ! -f "${_uv_cache}" ]]; then
        mkdir -p "${_uv_cache_dir}"
        # nullglob: unmatched glob expands to nothing instead of erroring (zsh nomatch)
        if [[ -n "${ZSH_VERSION}" ]]; then
            setopt nullglob
        else
            shopt -s nullglob
        fi
        for _stale in "${_uv_cache_dir}"/uv."${WORKBENCH_SHELL}".*.sh; do
            [[ "${_stale}" != "${_uv_cache}" ]] && rm -f "${_stale}"
        done
        if [[ -n "${ZSH_VERSION}" ]]; then
            unsetopt nullglob
        else
            shopt -u nullglob
        fi
        unset _stale
        uv generate-shell-completion "${WORKBENCH_SHELL}" 2>/dev/null > "${_uv_cache}" \
            || rm -f "${_uv_cache}"
    fi

    # The generated zsh script calls compdef, which needs zsh's completion
    # system initialised first. Same idempotent guard as workbench-core's
    # shell/completions/wb.sh: -C reuses the existing dump, so this is a
    # no-op once compinit has run (e.g. from workbench-shell's zsh.sh).
    if [[ -n "${ZSH_VERSION:-}" ]] && ! command -v compdef &>/dev/null; then
        autoload -Uz compinit
        compinit -C
    fi

    # shellcheck disable=SC1090
    [[ -f "${_uv_cache}" ]] && source "${_uv_cache}"
fi

unset _uv_cache_dir _uv_version _uv_cache

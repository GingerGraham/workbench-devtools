#!/usr/bin/env bash
# shell/devtools.sh — workbench-devtools
# list-edit-releases. Registered at tier: tools (.dotfiles-sync.yml) so this
# is reachable interactively — unlike the install-* functions in
# shell/installers.sh, which `wb tools` only sources transiently, this is a
# read-only informational helper meant to be called directly from the shell.
# Ported from workbench-precursor's lazy/installers-dev.sh.

# nvm/node/npm/npx are only defined when nvm is installed; the predicate
# _nvm_present lives in shell/development.sh (tier: env). Wired up here, at
# tier: tools, because _wb_alias_availability (Core API 1.2) comes from
# core's core-tier files, which load after the env tier.
_wb_alias_availability _nvm_present nvm node npm npx

list-edit-releases() {
    curl -s https://api.github.com/repos/microsoft/edit/releases \
        | grep -o '"tag_name": *"[^"]*"' \
        | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/' \
        | head -10
}

get-devtools-functions() {
    local _dir; _dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # installers.sh is deliberately excluded -- its install-* functions are
    # surfaced via `wb tools list`, not this getter (they're never sourced
    # into the interactive shell; see shell/devtools.sh's header comment and
    # workbench-shell's shell/aliases.sh for the same convention).
    _get_functions_in "Devtools functions" "" \
        "${_dir}/go.sh" "${_dir}/development.sh" "${_dir}/devtools.sh"
}

#!/usr/bin/env bash
# shell/devtools.sh — workbench-devtools
# list-edit-releases. Registered at tier: tools (workbench.yml) so this
# is reachable interactively — unlike the install-* functions in
# shell/installers.sh, which `wb tools` only sources transiently, this is a
# read-only informational helper meant to be called directly from the shell.
# Ported from workbench-precursor's lazy/installers-dev.sh.

# nvm/node/npm/npx are only defined when nvm is installed; the predicate
# _nvm_present lives in shell/development.sh (tier: env). Wired up here, at
# tier: tools, because _wb_alias_availability (Core API 1.2) comes from
# core's core-tier files, which load after the env tier.
_wb_alias_availability --needs "nvm (~/.nvm/nvm.sh)" --install nvm _nvm_present nvm node npm npx

list-edit-releases() {
    curl -fsS https://api.github.com/repos/microsoft/edit/releases \
        | grep -o '"tag_name": *"[^"]*"' \
        | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/' \
        | head -10
}

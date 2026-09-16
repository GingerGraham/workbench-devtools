#!/usr/bin/env bash
# shell/go.sh — workbench-devtools
# Go version helpers. Registered at tier: tools (.dotfiles-sync.yml), sourced
# unconditionally; guards internally on `command -v go`.
# Ported from workbench-precursor's shell/config/tools/go.sh, unchanged
# other than the log_debug call moving inline (no behaviour change).

# get-go-version is only ever defined once the `command -v go` guard below
# has passed, but get-devtools-functions' static-grep listing can't see
# that runtime guard, so without this it would list get-go-version even on
# hosts without go. Declared unconditionally, ahead of the guard, so the
# predicate itself still exists (and correctly says "unavailable") on a
# host without go — declaring it inside the guard would mean it's never
# defined there either, and an undeclared predicate defaults to available.
_wb_declare_availability go get-go-version

if command -v go &>/dev/null; then

    # Populate GO_VERSION, stripping the leading "go" and any build/experiment
    # suffix Go appends after a hyphen or plus, e.g.:
    #   go1.26.5-X:nodwarf5  ->  1.26.5
    #   go1.22.0             ->  1.22.0
    _set-go-version() {
        local field
        field="$(go version 2>/dev/null | awk '{print $3}')"
        field="${field#go}"        # strip leading "go"
        field="${field%%[-+]*}"    # strip "-X:..." / "+build" style suffixes
        GO_VERSION="${field}"
        export GO_VERSION
    }

    get-go-version() {
        _set-go-version
        log_info "Go version: ${GO_VERSION}"
    }

    _set-go-version
    log_debug "Go version: ${GO_VERSION}"

fi

#!/usr/bin/env bash
# tests/check-cd-wrapper.sh — workbench-core docs/decisions-log.md D110
# acceptance check, adapted for this module.
#
# Behavioural half of tests/check-no-bare-cd.sh. Builds a shell the way a
# host with its own profile builds one — `ls`/`cp`/`find` aliased to
# something noisy, `cd` both aliased and wrapped by a function — and then
# sources every shell file this module registers. None of the host wrappers
# may run, and none of the text of a wrapper may end up inside a function
# these files define.
#
# An alias is expanded when a line is read, so a function body is read —
# and the alias baked into it — when the function is DEFINED. A bare `cd`
# in a function therefore does not misbehave while the file is sourced; it
# shows up later, on every call. So besides watching the output of sourcing,
# this check dumps each function the file defined (`declare -f`) and looks
# for the alias text in the body.
#
# Module shell files expect Core API functions (log_info, ...) that are
# absent here. Errors from that are fine: the check is about the wrappers.
set -uo pipefail

SCRIPT_DIR="$(builtin cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(builtin cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/wb-cd-wrapper.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

export HOME="${WORK}/home"
export XDG_DATA_HOME="${WORK}/data"
export XDG_CONFIG_HOME="${WORK}/config"
export XDG_CACHE_HOME="${WORK}/cache"
mkdir -p "${HOME}" "${XDG_DATA_HOME}" "${XDG_CONFIG_HOME}" "${XDG_CACHE_HOME}"
: > "${HOME}/.bashrc"

# The host's wrappers, in a file each fixture shell sources first. The
# function comes before the aliases: once the `cd` alias exists, the line
# `cd() {` would itself be alias-expanded and fail to parse.
cat > "${WORK}/host-wrappers.sh" <<'WRAPPERS_EOF'
shopt -s expand_aliases
cd() { printf 'WRAPPER-CALLED\n' >&2; return 1; }
alias ls='printf "ALIAS-LS-RAN\n"; command ls -1 --'
alias cd='printf "ALIAS-CD-RAN\n" >&2; false; :'
alias cp='printf "ALIAS-CP-RAN\n" >&2; cp -i'
alias find='printf "ALIAS-FIND-RAN\n" >&2; find'
WRAPPERS_EOF

MARKERS_RE='ALIAS-LS-RAN|ALIAS-CD-RAN|ALIAS-CP-RAN|ALIAS-FIND-RAN|WRAPPER-CALLED'

# fixture_source <file> — in a clean bash that has the host wrappers
# installed first, source <file>, then print every function it defined
# (`declare -f`). The wrappers are defined before the snapshot, so they are
# not counted as the file's own functions. Prints stdout and stderr together.
fixture_source() {
    local file="$1"
    env -i \
        HOME="${HOME}" \
        XDG_DATA_HOME="${XDG_DATA_HOME}" \
        XDG_CONFIG_HOME="${XDG_CONFIG_HOME}" \
        XDG_CACHE_HOME="${XDG_CACHE_HOME}" \
        PATH="${PATH}" \
        bash -c ". '${WORK}/host-wrappers.sh'
before=\" \$(compgen -A function | tr '\\n' ' ')\"
set --
. '${file}' 2>&1
echo '--- FUNCTIONS DEFINED BY THE FILE ---'
for fn in \$(compgen -A function); do
    case \"\${before}\" in *\" \${fn} \"*) continue ;; esac
    declare -f \"\${fn}\"
done" 2>&1
}

# check_file <label> <file> — assert no marker in the sourcing output and
# none in any function body the file defined.
check_file() {
    local label="$1" file="$2" out sourcing bodies
    out="$(fixture_source "${file}")"
    sourcing="${out%%--- FUNCTIONS DEFINED BY THE FILE ---*}"
    bodies="${out#*--- FUNCTIONS DEFINED BY THE FILE ---}"
    if printf '%s\n' "${sourcing}" | grep -Eq "${MARKERS_RE}"; then
        fail "${label}: a host alias or wrapper ran while sourcing:"
        printf '%s\n' "${sourcing}" | grep -E "${MARKERS_RE}" | sort | uniq -c
    else
        ok "${label}: no host alias or wrapper ran while sourcing"
    fi
    if printf '%s\n' "${bodies}" | grep -Eq "${MARKERS_RE}"; then
        fail "${label}: a host alias is baked into a function the file defines:"
        printf '%s\n' "${bodies}" | grep -E "${MARKERS_RE}" | sort | uniq -c
    else
        ok "${label}: no function body the file defines contains a host alias"
    fi
}

# ── The check has to see what it claims to see. ─────────────────────────────
# A fixture that catches nothing passes forever, so prove it catches a bare
# cd, ls, cp and find in a function body, and accepts the guarded forms.
cat > "${WORK}/bare-sample.sh" <<'SAMPLE_EOF'
bare_fn() { cd /tmp; ls /tmp; cp /dev/null /dev/null; find /tmp -maxdepth 0; }
SAMPLE_EOF
cat > "${WORK}/guarded-sample.sh" <<'SAMPLE_EOF'
guarded_fn() { builtin cd /tmp; command ls /tmp; command cp /dev/null /dev/null; command find /tmp -maxdepth 0; }
SAMPLE_EOF
bare_out="$(fixture_source "${WORK}/bare-sample.sh")"
bare_hits="$(printf '%s\n' "${bare_out}" | grep -oE "${MARKERS_RE}" | sort -u | wc -l | tr -d ' ')"
if [[ "${bare_hits}" -eq 4 ]]; then
    ok "self-test: a function with bare cd/ls/cp/find has all 4 alias texts baked into its body"
else
    fail "self-test: expected 4 distinct alias texts in the bare sample's function body, saw ${bare_hits}"
    printf '%s\n' "${bare_out}"
fi
guarded_out="$(fixture_source "${WORK}/guarded-sample.sh")"
if printf '%s\n' "${guarded_out}" | grep -Eq "${MARKERS_RE}"; then
    fail "self-test: builtin cd / command ls|cp|find still picked up an alias text:"
    printf '%s\n' "${guarded_out}"
else
    ok "self-test: builtin cd / command ls|cp|find in a function body pick up no alias text"
fi

# ── Every shell file this module registers. ─────────────────────────────────
for f in "${REPO_ROOT}"/shell/*.sh "${REPO_ROOT}"/shell/completions/*.sh; do
    [[ -f "${f}" ]] || continue
    check_file "sourcing ${f#"${REPO_ROOT}"/}" "${f}"
done

echo
if [[ "${FAILED}" -eq 0 ]]; then
    echo "All ${check_no} checks passed."
    exit 0
else
    echo "${FAILED} of ${check_no} checks failed."
    exit 1
fi

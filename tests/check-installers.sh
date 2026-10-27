#!/usr/bin/env bash
# tests/check-installers.sh — workbench-devtools
# Plain bash, numbered OK:/FAIL: checks, matching workbench-core's
# tests/check-*.sh convention (no framework). Runs the installers and shell
# files against stubbed commands: no network, no root, nothing installed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/devtools-installers.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT
CALLS="${WORK}/calls.log"

# A PATH of the host's tools minus snap: a runner with snapd installed
# (GitHub's ubuntu images) would otherwise make install-snapd skip
# straight to "snap binary already present".
SANDBOX_BIN="${WORK}/bin"
mkdir -p "${SANDBOX_BIN}"
for _tool in /usr/bin/* /bin/*; do
    _name="$(basename "${_tool}")"
    case "${_name}" in snap|snapctl) continue ;; esac
    [[ -e "${SANDBOX_BIN}/${_name}" ]] || ln -s "${_tool}" "${SANDBOX_BIN}/${_name}"
done
unset _tool _name

# _run <snippet>
# Runs <snippet> in a fresh bash with Core API and external commands
# stubbed; every stubbed command appends "<name> <args>" to ${CALLS}.
# Prints the snippet's output (logs included); returns its status.
_run() {
    : > "${CALLS}"
    # shellcheck disable=SC2016 # expanded by the inner shell, not here
    env -i PATH="${SANDBOX_BIN}" HOME="${WORK}/home" CALLS="${CALLS}" \
        INSTALLERS="${REPO_ROOT}/shell/installers.sh" SNIPPET="$1" \
        bash -c '
            log_info()  { echo "[INFO] $*"; }
            log_warn()  { echo "[WARN] $*"; }
            log_error() { echo "[ERROR] $*"; }
            log_debug() { :; }
            get-elevation-command() { echo ""; }
            for _c in curl zypper yay makepkg git pacman apt-get dnf yum systemctl; do
                eval "${_c}() { echo \"${_c} \$*\" >> \"\${CALLS}\"; return 1; }"
            done
            source "${INSTALLERS}"
            eval "${SNIPPET}"
        ' 2>&1
}

mkdir -p "${WORK}/home"

# ── Microsoft Edit: EDIT_VERSION, no positional arguments (D102) ──

if _run 'declare -f install-edit-version >/dev/null' >/dev/null; then
    fail "install-edit-version still defined -- the version pin is EDIT_VERSION"
else
    ok "install-edit-version is gone"
fi

out="$(_run 'WORKBENCH_OS=Linux WORKBENCH_ARCH=x86_64 EDIT_VERSION="v2; rm -rf x" install-edit')"; rc=$?
if [[ "${rc}" -ne 0 ]] && grep -q 'EDIT_VERSION must look like v2.0.0' <<<"${out}" && ! grep -q '^curl' "${CALLS}"; then
    ok "install-edit rejects a malformed EDIT_VERSION before any request"
else
    fail "install-edit with a malformed EDIT_VERSION: rc=${rc}, calls: $(tr '\n' ';' < "${CALLS}") output: ${out}"
fi

_run 'WORKBENCH_OS=Linux WORKBENCH_ARCH=x86_64 EDIT_VERSION=v2.0.0 install-edit' >/dev/null
if grep -q '^curl -fsS https://api.github.com/repos/microsoft/edit/releases/tags/v2.0.0$' "${CALLS}"; then
    ok "EDIT_VERSION=v2.0.0 queries that release's tag"
else
    fail "EDIT_VERSION=v2.0.0 did not query releases/tags/v2.0.0: $(tr '\n' ';' < "${CALLS}")"
fi

out="$(_run 'WORKBENCH_OS=Linux WORKBENCH_ARCH=x86_64 install-edit')"; rc=$?
if [[ "${rc}" -ne 0 ]] \
    && grep -q '^curl -fsS https://api.github.com/repos/microsoft/edit/releases/latest$' "${CALLS}" \
    && grep -q 'could not query the latest release' <<<"${out}"; then
    ok "without EDIT_VERSION, install-edit queries the latest release and fails loudly when that fails"
else
    fail "install-edit without EDIT_VERSION: rc=${rc}, calls: $(tr '\n' ';' < "${CALLS}") output: ${out}"
fi

# ── snapd on openSUSE: never auto-import the repo's key (N8) ──

if grep -vE '^[[:space:]]*#' "${REPO_ROOT}/shell/installers.sh" | grep -q -- '--gpg-auto-import-keys'; then  # pattern-scan:ignore -- test asserts the flag is absent
    fail "shell/installers.sh still passes --gpg-auto-import-keys"  # pattern-scan:ignore -- test failure message
else
    ok "no --gpg-auto-import-keys in shell/installers.sh"  # pattern-scan:ignore -- test success message
fi

# shellcheck disable=SC2016 # expanded by the inner shell, not here
out="$(_run 'zypper() { echo "zypper $*" >> "${CALLS}"; [[ "$1" == lr ]] && echo "1 | repo-oss | Main"; return 0; }
             WORKBENCH_OS=Linux WORKBENCH_DISTRO=suse install-snapd')"; rc=$?
if [[ "${rc}" -ne 0 ]] && ! grep -qE '^zypper (addrepo|.*refresh|install)' "${CALLS}" \
    && grep -q 'zypper addrepo --refresh https://download.opensuse.org/repositories/system:/snappy/' <<<"${out}" \
    && grep -q "run 'wb tools install snapd' again" <<<"${out}"; then
    ok "openSUSE without the snappy repo: prints the commands, adds nothing, returns 1"
else
    fail "openSUSE without the snappy repo: rc=${rc}, calls: $(tr '\n' ';' < "${CALLS}") output: ${out}"
fi

# shellcheck disable=SC2016 # expanded by the inner shell, not here
out="$(_run 'zypper() { echo "zypper $*" >> "${CALLS}"; [[ "$1" == lr ]] && echo "9 | snappy | snappy"; return 0; }
             WORKBENCH_OS=Linux WORKBENCH_DISTRO=suse install-snapd')"
if grep -q '^zypper install -y snapd$' "${CALLS}" && ! grep -qE '^zypper (addrepo|.*refresh)' "${CALLS}"; then
    ok "openSUSE with the snappy repo present: installs snapd, touches no repo or key"
else
    fail "openSUSE with the snappy repo present: calls: $(tr '\n' ';' < "${CALLS}") output: ${out}"
fi

# ── snapd on Arch: AUR only with WORKBENCH_ALLOW_AUR=true (D100) ──

out="$(_run 'WORKBENCH_OS=Linux WORKBENCH_DISTRO=arch install-snapd')"; rc=$?
if [[ "${rc}" -ne 0 ]] && ! grep -qE '^(yay|git|makepkg) ' "${CALLS}" \
    && grep -q 'yay -S snapd' <<<"${out}" && grep -q 'WORKBENCH_ALLOW_AUR=true' <<<"${out}"; then
    ok "Arch without WORKBENCH_ALLOW_AUR: prints 'yay -S snapd', builds nothing, returns 1"
else
    fail "Arch without WORKBENCH_ALLOW_AUR: rc=${rc}, calls: $(tr '\n' ';' < "${CALLS}") output: ${out}"
fi

_run 'WORKBENCH_OS=Linux WORKBENCH_DISTRO=arch WORKBENCH_ALLOW_AUR=true install-snapd' >/dev/null
if grep -q '^yay -S --noconfirm snapd$' "${CALLS}"; then
    ok "Arch with WORKBENCH_ALLOW_AUR=true: uses yay"
else
    fail "Arch with WORKBENCH_ALLOW_AUR=true did not run yay: $(tr '\n' ';' < "${CALLS}")"
fi

# ── shell/development.sh: no tfenv wiring (D103) ──

mkdir -p "${WORK}/home/.tfenv/bin"
for sh in bash zsh; do
    command -v "${sh}" &>/dev/null || { echo "SKIP: ${sh} not installed -- development.sh tfenv check"; continue; }
    # shellcheck disable=SC2016 # expanded by the inner shell, not here
    out="$(env -i PATH="${SANDBOX_BIN}" HOME="${WORK}/home" "${sh}" -c \
        'log_debug() { :; }; source "$1"; printf "%s|%s\n" "${TFENV_ROOT:-}" "${PATH}"' _ \
        "${REPO_ROOT}/shell/development.sh" 2>&1)"
    if [[ "${out}" != *".tfenv"* ]]; then
        ok "${sh}: development.sh leaves ~/.tfenv off PATH and TFENV_ROOT unset"
    else
        fail "${sh}: development.sh still wires tfenv: ${out}"
    fi
done

# ── shell/devtools.sh: nvm availability carries its reason ──

for sh in bash zsh; do
    command -v "${sh}" &>/dev/null || { echo "SKIP: ${sh} not installed -- devtools.sh availability check"; continue; }
    # shellcheck disable=SC2016 # expanded by the inner shell, not here
    out="$(env -i PATH="${SANDBOX_BIN}" HOME="${WORK}/home" "${sh}" -c \
        '_wb_alias_availability() { printf "<%s>" "$@"; echo; }; source "$1"' _ \
        "${REPO_ROOT}/shell/devtools.sh" 2>&1)"
    if [[ "${out}" == "<--needs><nvm (~/.nvm/nvm.sh)><--install><nvm><_nvm_present><nvm><node><npm><npx>" ]]; then
        ok "${sh}: nvm/node/npm/npx declare --needs \"nvm (~/.nvm/nvm.sh)\" --install nvm"
    else
        fail "${sh}: devtools.sh availability declaration: ${out}"
    fi
done

echo
echo "==============================="
echo "Total OK/FAIL checks: ${check_no}, failed: ${FAILED}"
echo "==============================="
[[ "${FAILED}" -eq 0 ]]

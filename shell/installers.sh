#!/usr/bin/env bash
# shell/installers.sh — workbench-devtools
# install-nvm, install-edit, install-edit-version, install-jq, install-uv,
# install-snapd. (list-edit-releases lives in shell/devtools.sh instead —
# register.shell content, not register.installers, since `wb tools` only
# sources this file transiently to invoke one install-<name> function; that
# one is a read-only helper meant to be called directly from an interactive
# shell.)
#
# Ported from workbench-precursor's lazy/installers-dev.sh,
# lazy/installers-python.sh, and lazy/installers-system.sh (snapd slice —
# flatpak went to workbench-desktop, per the module map).
#
# WORKBENCH_OS/WORKBENCH_DISTRO/WORKBENCH_ARCH are workbench-core Core API
# platform facts (contracts/core-api.md), replacing the precursor's
# DOTFILES_OS/DOTFILES_DISTRO. _download_file_robust/get-elevation-command/
# detect-package-manager/_str_lower/_read_prompt come from workbench-core's
# Core API (lib/core/installers-common.sh). _gh_release_asset_url is
# duplicated locally below (small enough that per-module duplication is the
# accepted norm here — see workbench-git's/workbench-desktop's own copies
# and ARCHITECTURE.md §12 D34 for the bar actually applied to promote a
# helper to Core API instead).
#
# _restore_managed_shell_files (called at the end of the precursor's
# install-nvm, to reset installer-injected PATH lines in git-tracked rc
# files so the sync timer wasn't blocked) is dropped throughout: unlike the
# precursor, workbench-core's rc files are plain stubs written once by
# `wb install`/`wb apply`, not live symlinks into a git working tree, so
# there is nothing to restore.

_gh_release_asset_url() {
    local api_response="$1" pattern="$2"
    printf '%s' "${api_response}" \
        | grep -Eo '"browser_download_url": *"[^"]+"' \
        | sed -E 's/.*"(https[^"]+)"/\1/' \
        | grep -E "${pattern}" \
        | head -1
}

# ── nvm install ──────────────────────────────────────────────────────────────

_nvm_latest_version() {
    curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest 2>/dev/null \
        | grep '"tag_name":' \
        | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/' \
        | head -1
}

# Detect a manually-installed system Node and, interactively, offer to remove
# it so nvm becomes the sole manager. No-op for nvm-managed or
# non-interactive cases.
_nvm_handle_system_node() {
    local node_path npm_path
    node_path="$(command -v node 2>/dev/null)"
    npm_path="$(command -v npm 2>/dev/null)"

    # Only act on a real on-disk binary (skip nvm stub *functions* and nvm paths).
    [[ "${node_path}" == */* && -x "${node_path}" ]] || return 0
    case "${node_path}" in
        *"/.nvm/"*) return 0 ;;
    esac

    log_warn "A manually-installed Node.js was found:"
    log_warn "  node: ${node_path}"
    [[ -n "${npm_path}" ]] && log_warn "  npm:  ${npm_path}"
    log_warn "nvm works best as the sole Node.js manager; a system Node on PATH can shadow"
    log_warn "nvm's versions in non-login contexts."

    if [[ ! -e /dev/tty ]]; then
        log_info "Non-interactive shell — leaving the system Node in place."
        return 0
    fi

    local reply
    _read_prompt "Remove the system Node.js/npm via the package manager and use nvm instead? [y/N]: " reply
    case "$(_str_lower "${reply}")" in
        y|yes) ;;
        *) log_info "Keeping the system Node.js. nvm will install alongside it."; return 0 ;;
    esac

    [[ -z "${PACKAGE_MANAGER:-}" ]] && { detect-package-manager || return 0; }
    local elevation_cmd
    elevation_cmd="$(get-elevation-command)" || { log_warn "No elevation available — cannot remove system Node."; return 0; }
    log_warn "Removing system nodejs/npm — this may also remove packages that depend on them."
    case "${PACKAGE_MANAGER}" in
        dnf)    ${elevation_cmd} dnf remove -y nodejs npm ;;
        yum)    ${elevation_cmd} yum remove -y nodejs npm ;;
        apt)    ${elevation_cmd} apt-get remove -y nodejs npm ;;
        zypper) ${elevation_cmd} zypper remove -y nodejs npm ;;
        pacman) ${elevation_cmd} pacman -Rs --noconfirm nodejs npm ;;
        brew)   brew uninstall node 2>/dev/null || true ;;
        *) log_warn "Unknown package manager — remove Node.js manually if desired." ;;
    esac
}

install-nvm() {
    log_info "Installing or updating nvm (Node Version Manager)..."
    command -v curl &>/dev/null || { log_error "curl is required"; return 1; }
    command -v git  &>/dev/null || log_warn "git not found — nvm self-update will be unavailable"

    export NVM_DIR="${NVM_DIR:-${HOME}/.nvm}"
    mkdir -p "${NVM_DIR}" || { log_error "Failed to create ${NVM_DIR}"; return 1; }

    _nvm_handle_system_node

    # Version is embedded in the install URL and changes over time — detect it,
    # falling back to a pinned version if the API is unreachable / rate-limited.
    local nvm_ver
    nvm_ver="$(_nvm_latest_version)"
    if [[ -z "${nvm_ver}" ]]; then
        nvm_ver="v0.40.5"
        log_warn "Could not query the latest nvm version (GitHub API rate limit?) — using ${nvm_ver}"
    fi
    log_info "Target nvm version: ${nvm_ver}"

    local install_url="https://raw.githubusercontent.com/nvm-sh/nvm/${nvm_ver}/install.sh"
    local tmp_script
    if ! tmp_script="$(mktemp)"; then
        log_error "nvm: mktemp failed — cannot create a temp file for the install script"
        return 1
    fi
    if ! _download_file_robust "${install_url}" "${tmp_script}" || [[ ! -s "${tmp_script}" ]]; then
        log_error "nvm: install script download failed or was empty"
        rm -f "${tmp_script}"
        return 1
    fi
    if ! bash "${tmp_script}"; then
        log_error "nvm install script failed"
        rm -f "${tmp_script}"
        return 1
    fi
    rm -f "${tmp_script}"

    # Load nvm now (replacing the lazy stubs from shell/development.sh).
    if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
        unset -f nvm node npm npx yarn pnpm 2>/dev/null || true
        # shellcheck disable=SC1091
        source "${NVM_DIR}/nvm.sh"
    else
        log_error "nvm.sh not found at ${NVM_DIR} after install"
        return 1
    fi

    # Install current LTS if nothing is in use; set a default for new shells.
    local current
    current="$(nvm current 2>/dev/null)"
    if [[ -z "${current}" || "${current}" == "none" || "${current}" == "system" ]]; then
        log_info "No nvm-managed Node in use — installing latest LTS..."
        nvm install --lts || { log_error "nvm install --lts failed"; return 1; }
        nvm use --lts
        nvm alias default 'lts/*'
    else
        log_info "nvm already managing Node ${current} — keeping it as the active version"
        nvm alias default &>/dev/null || nvm alias default "${current}"
    fi

    log_info "nvm ready — node $(node --version 2>/dev/null), npm $(npm --version 2>/dev/null)"

    echo
    echo "  nvm is loaded in this shell and lazy-loads in new shells. Common commands:"
    echo "    nvm install --lts      # install the latest LTS"
    echo "    nvm install 20         # install a specific major"
    echo "    nvm use 20             # switch versions"
    echo "    nvm alias default 20   # set the default for new shells"
}

# NOT `command -v nvm` — nvm is a shell FUNCTION sourced from
# ${NVM_DIR}/nvm.sh, never an on-disk executable. `wb tools` sources this
# file transiently in an isolated subprocess that never sources nvm.sh
# itself, so `command -v nvm` would report "not found" unconditionally
# regardless of whether nvm is actually installed — a systematic false
# negative, not a usable check. The on-disk artifact install-nvm itself
# checks (`[[ -s "${NVM_DIR}/nvm.sh" ]]`) is the only reliable signal.
installed-nvm() {
    [[ -s "${NVM_DIR:-${HOME}/.nvm}/nvm.sh" ]]
}

# ── Microsoft Edit install ────────────────────────────────────────────────────

# _edit_arch_stem <version_string>
#   Prints the platform-specific asset stem, e.g. "edit-2.0.0-x86_64-linux-gnu"
#   Returns 1 on unsupported platform so callers can bail early.
_edit_arch_stem() {
    local normalized_ver="$1"
    local machine="${WORKBENCH_ARCH}"

    local arch os_tag
    case "${machine}" in
        x86_64)         arch="x86_64"  ;;
        aarch64|arm64)  arch="aarch64" ;;
        *) log_error "Unsupported architecture: ${machine}"; return 1 ;;
    esac

    case "${WORKBENCH_OS}" in
        Linux) os_tag="linux-gnu"    ;;
        Mac)   os_tag="apple-darwin" ;;
        *) log_error "Unsupported OS: ${WORKBENCH_OS}"; return 1 ;;
    esac

    printf 'edit-%s-%s-%s' "${normalized_ver}" "${arch}" "${os_tag}"
}

# _edit_asset_url <api_response> <stem>
_edit_asset_url() {
    local api_response="$1" stem="$2"
    _gh_release_asset_url "${api_response}" "${stem}"
}

# _edit_extract <archive> <dest_dir>
#   Extracts .tar.gz, .tar.zst, or .zip into dest_dir.
_edit_extract() {
    local archive="$1" dest="$2"
    case "${archive}" in
        *.tar.gz)  tar -xzf "${archive}" -C "${dest}" ;;
        *.tar.zst)
            if command -v zstd &>/dev/null; then
                tar -I zstd -xf "${archive}" -C "${dest}"
            else
                # tar on recent Linux/macOS handles zstd natively
                tar -xf "${archive}" -C "${dest}"
            fi
            ;;
        *.zip) unzip -q "${archive}" -d "${dest}" ;;
        *) log_error "Unrecognised archive format: $(basename "${archive}")"; return 1 ;;
    esac
}

# _edit_install_from_api_response <api_response> <display_version>
#   Shared implementation used by both install-edit and install-edit-version.
_edit_install_from_api_response() {
    local api_response="$1" display_ver="$2"
    local normalized_ver="${display_ver#v}"

    local stem
    stem="$(_edit_arch_stem "${normalized_ver}")" || return 1

    local download_url
    download_url="$(_edit_asset_url "${api_response}" "${stem}")"
    if [[ -z "${download_url}" ]]; then
        log_error "No release asset matching '${stem}' found for ${display_ver}"
        log_info "Assets available in this release:"
        printf '%s' "${api_response}" \
            | grep -Eo '"browser_download_url": *"[^"]+"' \
            | sed -E 's/.*"(https[^"]+)"/  \1/'
        return 1
    fi

    # Derive the archive filename from the URL so extraction uses the right handler
    local asset_name; asset_name="$(basename "${download_url}")"
    local tmp_dir;    tmp_dir="$(mktemp -d)"

    log_info "Downloading ${asset_name}..."
    if ! _download_file_robust "${download_url}" "${tmp_dir}/${asset_name}"; then
        rm -rf "${tmp_dir}"; return 1
    fi

    log_info "Extracting ${asset_name}..."
    if ! _edit_extract "${tmp_dir}/${asset_name}" "${tmp_dir}"; then
        log_error "Extraction failed for ${asset_name}"
        rm -rf "${tmp_dir}"; return 1
    fi

    # -perm -u+x, not GNU-only -executable: this module targets macOS (BSD
    # find) too, per _edit_arch_stem's apple-darwin branch below.
    local binary; binary="$(find "${tmp_dir}" -name "edit" -type f -perm -u+x | head -1)"
    if [[ -z "${binary}" ]]; then
        log_error "edit binary not found in archive — contents:"
        find "${tmp_dir}" -type f | sed 's/^/  /'
        rm -rf "${tmp_dir}"; return 1
    fi

    mkdir -p "${HOME}/.local/bin"
    cp "${binary}" "${HOME}/.local/bin/edit"
    chmod +x "${HOME}/.local/bin/edit"
    rm -rf "${tmp_dir}"
    log_info "Microsoft Edit ${normalized_ver} installed to ~/.local/bin/edit"
}

install-edit() {
    log_info "Installing or updating Microsoft Edit..."
    command -v curl &>/dev/null || { log_error "curl is required"; return 1; }
    command -v tar  &>/dev/null || { log_error "tar is required"; return 1; }

    local api_response ver
    api_response="$(curl -s https://api.github.com/repos/microsoft/edit/releases/latest)"
    ver="$(printf '%s' "${api_response}" | grep '"tag_name":' \
        | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')"
    [[ -z "${ver}" ]] && { log_error "Could not determine latest edit version"; return 1; }

    log_info "Latest version: ${ver}"
    _edit_install_from_api_response "${api_response}" "${ver}"
}

installed-edit() {
    command -v edit &>/dev/null
}

install-edit-version() {
    local target_version="$1"
    [[ -z "${target_version}" ]] && { log_error "Usage: install-edit-version <version>  (e.g. v2.0.0)"; return 1; }

    command -v curl &>/dev/null || { log_error "curl is required"; return 1; }
    command -v tar  &>/dev/null || { log_error "tar is required"; return 1; }

    log_info "Installing Microsoft Edit ${target_version}..."
    local api_response
    api_response="$(curl -s "https://api.github.com/repos/microsoft/edit/releases/tags/${target_version}")"
    printf '%s' "${api_response}" | grep -q '"message": *"Not Found"' \
        && { log_error "Version ${target_version} not found on GitHub"; return 1; }

    _edit_install_from_api_response "${api_response}" "${target_version}"
}

# ── jq install ─────────────────────────────────────────────────────────────────

_jq-install-rhel() {
    local elevation_cmd; elevation_cmd="$(get-elevation-command)" || return 1
    if command -v dnf &>/dev/null; then
        ${elevation_cmd} dnf install -y jq
    else
        ${elevation_cmd} yum install -y jq
    fi
}

_jq-install-debian() {
    local elevation_cmd; elevation_cmd="$(get-elevation-command)" || return 1
    ${elevation_cmd} apt-get update
    ${elevation_cmd} apt-get install -y jq
}

_jq-install-suse() {
    local elevation_cmd; elevation_cmd="$(get-elevation-command)" || return 1
    ${elevation_cmd} zypper install -y jq
}

_jq-install-arch() {
    local elevation_cmd; elevation_cmd="$(get-elevation-command)" || return 1
    ${elevation_cmd} pacman -S --noconfirm jq
}

_jq-install-mac() {
    command -v brew &>/dev/null || { log_error "brew is required on macOS"; return 1; }
    if command -v jq &>/dev/null; then brew upgrade jq; else brew install jq; fi
}

_jq-install-binary() {
    log_info "jq: falling back to binary install from GitHub releases..."
    command -v curl &>/dev/null || { log_error "curl is required"; return 1; }

    local api_response ver arch url tmp_dir
    api_response="$(curl -s https://api.github.com/repos/jqlang/jq/releases/latest)"
    # jq tags are `jq-1.7.1`, not `v1.7.1`
    ver="$(printf '%s' "${api_response}" | grep '"tag_name":' \
        | sed -E 's/.*"tag_name": *"jq-([^"]+)".*/\1/' | head -1)"
    [[ -z "${ver}" ]] && { log_error "jq: could not determine latest version"; return 1; }

    case "${WORKBENCH_ARCH}" in
        x86_64)        arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) log_error "jq: unsupported architecture ${WORKBENCH_ARCH}"; return 1 ;;
    esac

    # Asset naming changed in 1.7: jq-linux64 → jq-linux-amd64
    url="$(_gh_release_asset_url "${api_response}" "jq-linux-(${arch}|64)$")"
    [[ -z "${url}" ]] && { log_error "jq: no matching asset for linux/${arch}"; return 1; }

    tmp_dir="$(mktemp -d)"
    _download_file_robust "${url}" "${tmp_dir}/jq" || { rm -rf "${tmp_dir}"; return 1; }
    mkdir -p "${HOME}/.local/bin"
    install -m 755 "${tmp_dir}/jq" "${HOME}/.local/bin/jq"
    rm -rf "${tmp_dir}"
    log_info "jq ${ver} installed to ~/.local/bin/jq"
}

install-jq() {
    log_info "Installing or updating jq..."

    case "${WORKBENCH_OS}" in
        Mac) _jq-install-mac; return $? ;;
        Linux) ;;
        *) log_error "Unsupported OS for jq install"; return 1 ;;
    esac

    local ok=1
    case "${WORKBENCH_DISTRO}" in
        rhel)   _jq-install-rhel   && ok=0 ;;
        debian) _jq-install-debian && ok=0 ;;
        suse)   _jq-install-suse   && ok=0 ;;
        arch)   _jq-install-arch   && ok=0 ;;
        *)      log_warn "jq: unknown distro (${WORKBENCH_DISTRO}) — trying binary install" ;;
    esac
    [[ "${ok}" -ne 0 ]] && { _jq-install-binary || return 1; }

    # shellcheck disable=SC2015
    command -v jq &>/dev/null \
        && log_info "jq installed: $(jq --version 2>/dev/null)" \
        || log_warn "jq not on PATH after install — check ~/.local/bin is in PATH"
}

installed-jq() {
    command -v jq &>/dev/null
}

# ── uv install ────────────────────────────────────────────────────────────────
#
# Fedora's own dnf repository, then a Homebrew formula on macOS, then a
# verified GitHub release tarball — never astral.sh's installer, which
# piped straight into a shell with no chance to verify anything first
# (security review M3).
#
# No UV_INSTALL_DIR-equivalent override needed: ~/.local/bin (the release
# tarball's install target below) is already on PATH via workbench-core's
# own env tier (shell/development.sh).

install-uv() {
    log_info "Installing or updating uv..."

    # Fedora ships uv in its own signed repositories (security review M3).
    if [[ -f /etc/fedora-release ]] && command -v dnf &>/dev/null; then
        local elevation_cmd; elevation_cmd="$(get-elevation-command)" || return 1
        if ${elevation_cmd} dnf install -y uv; then
            log_info "uv installed: $(uv --version 2>/dev/null)"
            return 0
        fi
        log_warn "uv not available from Fedora repositories — falling back to the GitHub release"
    fi

    if [[ "${WORKBENCH_OS}" == "Mac" ]] && command -v brew &>/dev/null; then
        if brew list uv &>/dev/null; then brew upgrade uv; else brew install uv; fi
        return $?
    fi

    _uv-install-release
}

# _uv-install-release
# Latest GitHub release archive, verified against its published .sha256,
# installed to ~/.local/bin (the same place astral's script used).
_uv-install-release() {
    local api_response tag triple asset url tmp_dir dir
    api_response="$(curl -fsS https://api.github.com/repos/astral-sh/uv/releases/latest)" \
        || { log_error "uv: could not query the latest release (network or GitHub API rate limit)"; return 1; }
    tag="$(printf '%s' "${api_response}" | grep '"tag_name":' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/' | head -1)"
    [[ -z "${tag}" ]] && { log_error "uv: could not determine the latest version"; return 1; }

    case "${WORKBENCH_OS}/${WORKBENCH_ARCH}" in
        Linux/x86_64)          triple="x86_64-unknown-linux-gnu" ;;
        Linux/aarch64)         triple="aarch64-unknown-linux-gnu" ;;
        Mac/x86_64)            triple="x86_64-apple-darwin" ;;
        Mac/arm64|Mac/aarch64) triple="aarch64-apple-darwin" ;;
        *) log_error "uv: unsupported platform ${WORKBENCH_OS}/${WORKBENCH_ARCH}"; return 1 ;;
    esac

    asset="uv-${triple}.tar.gz"
    url="https://github.com/astral-sh/uv/releases/download/${tag}/${asset}"
    tmp_dir="$(mktemp -d)" || return 1
    _wb_fetch_verified "${url}" "${tmp_dir}/${asset}" "hashfile:${url}.sha256" \
        || { rm -rf "${tmp_dir}"; return 1; }
    tar -xzf "${tmp_dir}/${asset}" -C "${tmp_dir}" \
        || { log_error "uv: failed to extract ${asset}"; rm -rf "${tmp_dir}"; return 1; }

    dir="${tmp_dir}/uv-${triple}"
    [[ -x "${dir}/uv" && -x "${dir}/uvx" ]] \
        || { log_error "uv: binaries not found in ${asset}"; rm -rf "${tmp_dir}"; return 1; }
    mkdir -p "${HOME}/.local/bin"
    install -m 755 "${dir}/uv" "${HOME}/.local/bin/uv"
    install -m 755 "${dir}/uvx" "${HOME}/.local/bin/uvx"
    rm -rf "${tmp_dir}"
    log_info "uv ${tag} installed to ~/.local/bin"
}

installed-uv() {
    command -v uv &>/dev/null
}

# ── snapd install ─────────────────────────────────────────────────────────────
install-snapd() {
    log_info "Installing or configuring snapd..."
    [[ "${WORKBENCH_OS}" != "Linux" ]] && { log_error "snapd is Linux-only"; return 1; }

    local elevation_cmd; elevation_cmd="$(get-elevation-command)" || return 1
    local snap_present=false
    command -v snap &>/dev/null && snap_present=true

    # ── Package install ───────────────────────────────────────────────────────
    if [[ "${snap_present}" == "false" ]]; then
        case "${WORKBENCH_DISTRO}" in
            rhel)
                if command -v dnf &>/dev/null; then
                    ${elevation_cmd} dnf install -y epel-release 2>/dev/null || true
                    ${elevation_cmd} dnf install -y snapd
                elif command -v yum &>/dev/null; then
                    ${elevation_cmd} yum install -y epel-release 2>/dev/null || true
                    ${elevation_cmd} yum install -y snapd
                else
                    log_error "snapd: neither dnf nor yum found"; return 1
                fi
                ;;
            debian)
                ${elevation_cmd} apt-get update
                ${elevation_cmd} apt-get install -y snapd
                ;;
            suse)
                # Tumbleweed and Leap use different repo URLs; Tumbleweed also
                # needs snapd.apparmor enabled.
                local os_name opensuse_repo_url
                # shellcheck disable=SC1091
                os_name="$(. /etc/os-release 2>/dev/null && echo "${NAME:-}")"

                if echo "${os_name}" | grep -qi 'tumbleweed'; then
                    opensuse_repo_url="https://download.opensuse.org/repositories/system:/snappy/openSUSE_Tumbleweed/"
                else
                    # Leap (and any other SUSE variant) — version-specific URL
                    local opensuse_ver
                    # shellcheck disable=SC1091
                    opensuse_ver="$(. /etc/os-release 2>/dev/null && echo "${VERSION_ID:-15.6}")"
                    opensuse_repo_url="https://download.opensuse.org/repositories/system:/snappy/openSUSE_Leap_${opensuse_ver}/"
                fi

                if ! zypper lr 2>/dev/null | grep -qi 'snappy'; then
                    ${elevation_cmd} zypper addrepo --refresh "${opensuse_repo_url}" snappy
                    ${elevation_cmd} zypper --gpg-auto-import-keys refresh snappy
                else
                    log_info "snapd: snappy repo already present"
                fi
                ${elevation_cmd} zypper install -y snapd
                ;;
            arch)
                if command -v yay &>/dev/null; then
                    yay -S --noconfirm snapd
                else
                    log_info "snapd: yay not found — cloning snapd from AUR..."
                    local tmp_dir; tmp_dir="$(mktemp -d)"
                    git clone https://aur.archlinux.org/snapd.git "${tmp_dir}/snapd" \
                        || { log_error "Failed to clone snapd AUR package"; rm -rf "${tmp_dir}"; return 1; }
                    ( cd "${tmp_dir}/snapd" && makepkg -si --noconfirm )
                    rm -rf "${tmp_dir}"
                fi
                ;;
            *)
                log_error "snapd: unsupported distro (${WORKBENCH_DISTRO})"; return 1
                ;;
        esac
        command -v snap &>/dev/null && snap_present=true
    else
        log_info "snapd: snap binary already present — skipping package install"
    fi

    [[ "${snap_present}" == "false" ]] \
        && { log_error "snapd: snap not on PATH after install"; return 1; }

    # ── systemd socket ────────────────────────────────────────────────────────
    if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null; then
        if ! systemctl is-enabled snapd.socket &>/dev/null; then
            log_info "snapd: enabling snapd.socket..."
            ${elevation_cmd} systemctl enable --now snapd.socket
        else
            log_info "snapd: snapd.socket already enabled"
        fi

        # Tumbleweed requires snapd.apparmor in addition to snapd.socket
        local os_name
        # shellcheck disable=SC1091
        os_name="$(. /etc/os-release 2>/dev/null && echo "${NAME:-}")"
        if echo "${os_name}" | grep -qi 'tumbleweed'; then
            if ! systemctl is-enabled snapd.apparmor &>/dev/null; then
                log_info "snapd: enabling snapd.apparmor (Tumbleweed)..."
                ${elevation_cmd} systemctl enable --now snapd.apparmor
            else
                log_info "snapd: snapd.apparmor already enabled"
            fi
        fi
    else
        log_warn "snapd: systemd not active — start snapd.socket manually when available"
    fi

    # ── Classic confinement symlink ───────────────────────────────────────────
    if [[ ! -e /snap ]]; then
        log_info "snapd: creating /snap symlink for classic confinement..."
        ${elevation_cmd} ln -s /var/lib/snapd/snap /snap
    else
        log_info "snapd: /snap already exists"
    fi

    log_info "snapd ready: $(snap version 2>/dev/null | grep snapd | awk '{print $2}')"
    log_info "You may need to log out and back in for PATH changes to take effect."
}

# snapd's CLI command is `snap`, not `snapd` (that's the daemon name) —
# mirrors install-snapd's own check.
installed-snapd() {
    command -v snap &>/dev/null
}

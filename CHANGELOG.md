# Changelog

All notable changes to `workbench-devtools` are documented here.

## [Unreleased]

### Added

- Initial decomposition from `workbench-precursor` (Wave C):
  Go/Python/Node/tfenv/Cargo/asdf/tenv environment wiring (`shell/go.sh`,
  `shell/development.sh`), `uv` completions, `list-edit-releases`
  (interactive), `install-nvm`/`install-edit`/`install-edit-version`/
  `install-jq`/`install-uv`/`install-snapd` (`wb tools`).

### Changed

- Split `list-edit-releases` out of `installers.sh` into a new
  `shell/devtools.sh` (`register.shell`, tier: tools) — `wb tools` only
  sources `register.installers[].src` files transiently, to invoke one
  `install-<name>` function at a time, so a read-only helper living only in
  `installers.sh` would never actually be reachable from an interactive
  shell.
- `_dotfiles_init_python_manager` is no longer auto-invoked by the loader
  (no equivalent post-local-overrides hook exists in `workbench-core`) —
  it is defined but left as an opt-in call from the user's own
  `~/.config/workbench/local/settings.sh`. `DOTFILES_PYTHON_MANAGER` is
  renamed `WORKBENCH_PYTHON_MANAGER` to match.
- Dropped `_restore_managed_shell_files` from `install-nvm` — moot under
  `workbench-core`'s model, where rc files are plain stubs written once by
  `wb install`/`wb apply`, not git-tracked symlinks that an installer's
  unmanaged PATH edits could dirty.
- `WORKBENCH_OS`/`WORKBENCH_DISTRO`/`WORKBENCH_ARCH`/`WORKBENCH_SHELL`
  replace `DOTFILES_OS`/`DOTFILES_DISTRO`/`DOTFILES_SHELL`.
- `install-flatpak` moved to `workbench-desktop` (its actual consumer
  domain) rather than living here with the rest of the precursor's
  `installers-system.sh` slice.

### Fixed

- `install-edit`'s binary lookup used GNU-only `find -executable`, which
  BSD `find` (macOS — a target platform per `_edit_arch_stem`'s
  `apple-darwin` branch) doesn't support. Switched to the portable
  `-perm -u+x`, matching `workbench-git`'s `gh`/`glab` binary lookups.
- `get-devtools-functions` no longer scans `shell/installers.sh` — its
  `install-*` functions are never sourced into the interactive shell (only
  `wb tools` sources that file, transiently, one function at a time), so
  advertising them there was misleading. Matches the convention already
  used by `workbench-shell`/`workbench-git`/`workbench-gpg`/`workbench-ssh`.

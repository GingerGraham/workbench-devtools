# Changelog

All notable changes to `workbench-devtools` are documented here.

## [Unreleased]

### Changed

- **`jq`'s and Microsoft Edit's GitHub-release binary fallbacks are now
  verified against the release's published SHA-256** (via
  workbench-core's `_wb_gh_asset_digest`/`_wb_fetch_verified`) before
  being installed, instead of downloaded and trusted outright. Edit's
  fallback refuses to install when no digest is published. `jq`'s falls
  back to its upstream `sha256sum.txt` when the GitHub API digest is
  absent. GitHub API calls across `install-edit`,
  `install-edit-version`, `_jq-install-binary`, and `_nvm_latest_version`
  now fail loudly (`curl -fsS`) instead of silently continuing on error.
  Requires `workbench-core` Core API `>=1.4` (security review M3).

## [0.3.0] - 2026-09-23

### Added

- **Manual `workflow_dispatch` release override.** `release.yml` now
  accepts a `bump_type` (patch/minor/major) input to force a release
  through `workbench-core`'s reusable `module-release.yml`, regardless of
  what Conventional Commits since the last tag would compute — a floor,
  never a downgrade of a higher severity already pending. Manual dispatch
  only runs from `main`. See `workbench-core`'s `docs/decisions-log.md` D67.

## [0.2.2] - 2026-09-16

### Fixed

- **`get-devtools-functions` no longer lists `get-go-version`, `nvm`,
  `node`, `npm`, or `npx` on hosts where they can't actually be
  called** — all five are defined only behind a runtime guard (`go`
  present, or `nvm.sh` present) that the getter's static listing
  can't see. Each now carries an availability predicate
  (`_wb_declare_availability`/`_wb_alias_availability`, from
  `workbench-core`'s function-availability-gating convention) so the
  listing matches what's actually usable. Set
  `WORKBENCH_FUNCTIONS_SHOW_ALL=true` to see hidden entries anyway.

## [0.2.1] - 2026-09-15

### Added

- **Agent-instruction files** (`AGENTS.md`, `CLAUDE.md`,
  `.github/copilot-instructions.md`,
  `.claude/skills/conventional-commits/SKILL.md`) — ports
  `workbench-core`'s D32 agent-instruction topology to this repo. See
  `workbench-core`'s `docs/decisions-log.md` D58.
- **Repo governance files** (`.github/PULL_REQUEST_TEMPLATE.md`,
  `.github/ISSUE_TEMPLATE/{bug_report,feature_request,config}.yml`,
  `.github/CODEOWNERS`, `CONTRIBUTING.md`, `SECURITY.md`) — ports
  `workbench-core`'s D31 governance-file topology to this repo,
  piloted on `workbench-git` first. See `workbench-core`'s
  `docs/decisions-log.md` D60.

### Fixed

- **`install-nvm` no longer pipes the nvm install script straight into
  `bash`** — it now downloads to a temp file via `_download_file_robust`,
  verifies the download landed and is non-empty, then executes the file.
  Closes a `scan-patterns` CI finding (remote-script-execution pattern).

## [0.2.0] - 2026-09-09

### Added

- Added `installed-nvm`, `installed-edit`, `installed-jq`, `installed-uv`,
  `installed-snapd` — reports install status to `wb tools upgrade`/
  `wb tools list --status` (workbench-core §12 D43). `install-edit-version`
  deliberately has no predicate — see shell/installers.sh comment for why.

## [0.1.0] - 2026-09-09

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

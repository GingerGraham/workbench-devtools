# workbench-devtools

General dev-environment tooling — Go, Python (uv/pyenv), Node (nvm) PATH/env
wiring, plus installers for nvm, Microsoft Edit, jq, uv, and snapd — for the
[`workbench`](https://github.com/GingerGraham/workbench-core) ecosystem.

An **ecosystem module** (`workbench-core` ARCHITECTURE.md §2) — meaningless
standalone. Requires `workbench-core` installed first:

```sh
wb add devtools
```

## What this gives you

- Go/Python/Node/Cargo/asdf PATH and environment wiring, loaded
  at tier `env` (before `tools`/`platform`/`distro`/`lazy`).
- `get-go-version` — prints the active Go toolchain version.
- `uv` shell completions (version-stamped cache, refreshed on upgrade).
- `list-edit-releases` — interactive helper.
- Installers for `nvm`, `edit` (Microsoft Edit), `jq`, `uv` and `snapd` —
  run `wb tools install <name>` (and `wb tools upgrade <name>` later).

The `flatpak` installer lives in `workbench-desktop` instead: Flatpak exists
specifically to distribute GUI applications, so it belongs with its
consumers rather than here.

## Installer options

Installers take no arguments (workbench-core `docs/decisions-log.md` D102).
Options are environment variables:

| Variable | Installer | Effect |
|---|---|---|
| `EDIT_VERSION` | `edit` | Install that release instead of the latest, e.g. `EDIT_VERSION=v2.0.0 wb tools install edit`. `list-edit-releases` shows recent tags. |
| `WORKBENCH_ALLOW_AUR` | `snapd` | On Arch, snapd comes only from the AUR. Set `WORKBENCH_ALLOW_AUR=true` in `~/.config/workbench/local/settings.sh` to let the installer build it (with `yay`, or `makepkg`). Without it, the installer prints the command to run yourself and stops (D100). |

On openSUSE, `wb tools install snapd` needs the `snappy` repository added
first. It doesn't add it for you: there's no pinned key for that repository,
and auto-importing whatever key it serves would make that key trusted for
every package. Add it and accept its key yourself
([snapcraft.io/docs/installing-snap-on-opensuse](https://snapcraft.io/docs/installing-snap-on-opensuse)),
then run the installer again. It prints the exact `zypper` commands.

## Python manager control

`_dotfiles_init_python_manager` (in `shell/development.sh`) is defined but
**not** auto-invoked. The precursor's `loader.sh` called it explicitly after
sourcing local overrides, so a user's manager preference could still steer
pyenv-shim initialisation; `workbench-core`'s loader has no equivalent
"run this after local overrides" hook for module-registered content. If you
want pyenv shims initialised, opt in from your own
`~/.config/workbench/local/settings.sh`:

```sh
WORKBENCH_PYTHON_MANAGER=pyenv
command -v _dotfiles_init_python_manager &>/dev/null && _dotfiles_init_python_manager
```

The `command -v` guard is needed: the loader sources `settings.sh` once
before the module tiers, when the function isn't defined yet, and again
after them, when it is. Unguarded, the first pass prints an error on every
shell start.

`WORKBENCH_PYTHON_MANAGER` accepts `auto` (default — pyenv shims only if
`uv` is absent), `uv`, `pyenv`, or `both`.

## Requires

Nothing at install time — each tool is installed on demand with
`wb tools install <name>`.

## tfenv and tenv

workbench no longer manages tfenv (D103). `wb tools install terraform`
(workbench-iac) installs terraform directly, and `wb tools install tenv`
installs tenv. To keep using tfenv, put it on `PATH` yourself in
`~/.config/workbench/local/settings.sh`:

```sh
[ -d "$HOME/.tfenv/bin" ] && PATH="$HOME/.tfenv/bin:$PATH"
```

This module no longer turns on tenv's auto-install. To have tenv install
missing versions on demand, set it yourself in
`~/.config/workbench/local/settings.sh`:

```sh
export TENV_AUTO_INSTALL=true
```

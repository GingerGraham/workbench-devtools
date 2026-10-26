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

- Go/Python/Node/tfenv/Cargo/asdf PATH and environment wiring, loaded
  at tier `env` (before `tools`/`platform`/`distro`/`lazy`).
- `get-go-version` — prints the active Go toolchain version.
- `uv` shell completions (version-stamped cache, refreshed on upgrade).
- `list-edit-releases` — interactive helper.
- `install-nvm`, `install-edit`, `install-edit-version`, `install-jq`,
  `install-uv`, `install-snapd` — via `wb tools install <name>` (and
  `wb tools upgrade <name>` later).

`install-flatpak` lives in `workbench-desktop` instead: Flatpak exists
specifically to distribute GUI applications, so it belongs with its
consumers rather than here.

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

Nothing at install time — each tool is installed via its own
`install-<name>` function (`wb tools install <name>`).

## tenv

This module no longer turns on tenv's auto-install. To have tenv install
missing versions on demand, set it yourself in
`~/.config/workbench/local/settings.sh`:

```sh
export TENV_AUTO_INSTALL=true
```

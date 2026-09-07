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

- Go/Python/Node/tfenv/Cargo/asdf/tenv PATH and environment wiring, loaded
  at tier `env` (before `tools`/`platform`/`distro`/`lazy`).
- `get-go-version` — prints the active Go toolchain version.
- `uv` shell completions (version-stamped cache, refreshed on upgrade).
- `list-edit-releases` — interactive helper.
- `install-nvm`, `install-edit`, `install-edit-version`, `install-jq`,
  `install-uv`, `install-snapd` — via `wb tools update`.

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
_dotfiles_init_python_manager
```

`WORKBENCH_PYTHON_MANAGER` accepts `auto` (default — pyenv shims only if
`uv` is absent), `uv`, `pyenv`, or `both`.

## Requires

Nothing at install time — each tool is installed via its own
`install-<name>` function (`wb tools update`).

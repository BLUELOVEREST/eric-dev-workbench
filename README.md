# eric-dev-workbench

Single-entry installer for Eric's `zsh`, `mihomo`, and `codex` environment bootstrap on Linux and macOS.

## Included Environments

- `zsh`: install/configure zsh, oh-my-zsh, powerlevel10k, and shell plugins
- `mihomo`: deploy a user-space mihomo binary, config, and daemon helper into `~/.uenv`
- `codex`: install `nvm`, Node `16.20.2`, and `@openai/codex`

## Repository Layout

- `install.sh`: the only public installer entrypoint
- `assets/mihomo/`: platform-specific mihomo binaries
- `assets/config/mihomo-config.yaml`: default mihomo config
- `assets/themes/p10k.zsh.template`: default powerlevel10k config template

## Quick Start

Local checkout:

```bash
./install.sh install
```

Remote bootstrap:

```bash
curl -fsSL https://raw.githubusercontent.com/BLUELOVEREST/eric-dev-workbench/main/install.sh | bash -s -- install
```

The remote bootstrap path clones the repository with `git` into a temporary directory and runs the same installer there.

## Common Usage

```bash
# Install only zsh
./install.sh install --with zsh

# Install mihomo and codex
./install.sh install --with mihomo,codex

# Use a custom install root
./install.sh install --root "$HOME/.uenv"

# Install codex and import auth in one command
./install.sh install --with codex --codex-auth /path/to/auth.json
```

## Platform Notes

- Supported install targets are Linux and macOS.
- The bundled Linux x86_64 mihomo binary lives at `assets/mihomo/linux-amd64/mihomo`.
- Add other platform binaries under `assets/mihomo/<platform>/mihomo`:
  - `linux-arm64`
  - `darwin-amd64`
  - `darwin-arm64`
- If the current platform asset is missing, the installer fails with the expected path.

## Notes

- The installer is designed to be idempotent.
- Shell configuration is managed through a single block in `~/.zshrc`.
- For older Linux environments, the codex install defaults to Node `16.20.2`.
- `mihomo` config security is not auto-modified; the installer only warns for risky settings.

## Docker Test Image

Build the Ubuntu non-root test image:

```bash
docker build -t eric-dev-workbench-test -f Dockerfile.test .
```

Start an interactive shell as the normal `tester` user:

```bash
docker run --rm -it eric-dev-workbench-test bash
```

Run the remote installer directly in one shot:

```bash
docker run --rm -it eric-dev-workbench-test \
  bash -lc 'curl -fsSL https://raw.githubusercontent.com/BLUELOVEREST/eric-dev-workbench/main/install.sh | bash -s -- install'
```

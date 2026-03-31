# Remote Install Refactor Design

## Summary

Refactor this repository into a single public installer entrypoint centered on `install.sh`.
The installer should support both local execution and remote bootstrap execution via:

```bash
curl -fsSL https://raw.githubusercontent.com/BLUELOVEREST/eric-dev-workbench/main/install.sh | bash -s -- install
```

The supported environment setup scope is limited to:

- `zsh`
- `mihomo`
- `codex`

`tmux`, the custom plugin module, and the current multi-script deploy pipeline are out of scope for the refactor and should be removed from the main installation flow.

## Goals

- Keep exactly one public installer entrypoint: `install.sh`
- Preserve a simple user experience for both local and remote installation
- Reduce repository complexity by removing the current `install.sh -> deploy.sh -> scripts/modules/*` execution chain
- Keep the codebase maintainable by organizing installer logic into clear functions inside `install.sh`
- Support Linux and macOS as target operating systems
- Make `mihomo` resource selection explicit by platform and architecture
- Keep installation idempotent, especially for shell configuration updates

## Non-Goals

- Adding new modules beyond `zsh`, `mihomo`, and `codex`
- Introducing GitHub Releases, artifact publishing, or versioned package distribution
- Supporting Windows
- Preserving backward compatibility for `tmux` and custom plugin installation in the default flow
- Turning the repository into a fully generic environment manager

## User Experience

### Local execution

Users in a checked-out repository run:

```bash
./install.sh install
```

Optional flags remain limited to the minimum needed for the retained modules, such as:

- `--with`
- `--root`
- `--codex-auth`

### Remote execution

Users run:

```bash
curl -fsSL https://raw.githubusercontent.com/BLUELOVEREST/eric-dev-workbench/main/install.sh | bash -s -- install
```

When executed outside a full repository checkout, `install.sh` will:

1. Detect that repository assets are not locally available
2. Require `git` to be present
3. Create a temporary working directory
4. Run `git clone --depth=1 https://github.com/BLUELOVEREST/eric-dev-workbench.git`
5. Enter the cloned repository
6. Run the same installer flow from the cloned `install.sh`
7. Clean up the temporary clone when installation completes

From the user's perspective, the process remains a single command that downloads the repository contents and installs the selected environments.

## Repository Structure

The repository should be simplified toward this structure:

```text
eric-dev-workbench/
├── install.sh
├── README.md
├── assets/
│   ├── mihomo/
│   │   ├── linux-amd64/
│   │   │   └── mihomo
│   │   ├── linux-arm64/
│   │   │   └── mihomo
│   │   ├── darwin-amd64/
│   │   │   └── mihomo
│   │   └── darwin-arm64/
│   │       └── mihomo
│   ├── config/
│   │   └── mihomo-config.yaml
│   └── themes/
│       └── p10k.zsh.template
└── docs/
    └── superpowers/
        └── specs/
```

The old execution-layer files should be folded into `install.sh` or removed:

- `deploy.sh`
- `scripts/modules/*`
- `scripts/helpers/*`
- `scripts/runtime/*`

## Installer Architecture

`install.sh` remains the only public entrypoint, but its internal implementation should be structured into focused function groups.

### 1. Core utility functions

Responsibilities:

- logging
- fatal error handling
- command existence checks
- platform and architecture detection
- temporary directory creation and cleanup
- download and clone helpers
- repository root and asset path detection

These functions should isolate Linux/macOS differences so platform-specific shell behavior does not leak across the installer.

### 2. Bootstrap functions

Responsibilities:

- determine whether the current process is running inside a full repository checkout
- clone the repository into a temporary directory when invoked remotely
- re-enter the installer flow inside the cloned repository

This layer should be implementation-focused and invisible to users.

### 3. Argument parsing

Retained interface:

- `install`
- `--with zsh,mihomo,codex`
- `--root PATH`
- `--codex-auth PATH`
- `-h|--help`

Removed interface:

- flags that only served removed modules
- legacy options that no longer contribute to the retained environment scope

### 4. Installation functions

Responsibilities:

- `install_zsh_env`
- `install_mihomo_env`
- `install_codex_env`

Each installation function should be responsible for one environment only and avoid directly editing shared shell configuration unless routed through shared config helpers.

### 5. Shell configuration functions

Responsibilities:

- manage a single controlled block in `~/.zshrc`
- add `PATH` for `~/.uenv/bin`
- add `nvm` bootstrap lines
- define proxy helper functions
- load `oh-my-zsh` and `powerlevel10k`

All shell changes must be idempotent and must not duplicate blocks across repeated installs.

## Module Design

### Zsh

The retained `zsh` installation flow should:

- detect whether system `zsh` satisfies the minimum required version
- install a user-space `zsh` under `~/.uenv` when needed
- install `oh-my-zsh`
- install `powerlevel10k`
- install `zsh-autosuggestions`
- install `zsh-syntax-highlighting`
- install the default `p10k` template when absent
- update `~/.zshrc` through one managed configuration block

The logic should stay automatic where practical. If system installation is not possible, the script should fall back to user-space installation where supported by available toolchains.

### Mihomo

The `mihomo` installation flow should:

- select a bundled binary based on OS and CPU architecture
- copy the selected binary into the `~/.uenv` runtime tree
- copy the default config into the runtime tree
- install the daemon management script
- maintain a `current` symlink for the active version
- warn on insecure config defaults such as `allow-lan: true` or `external-controller: 0.0.0.0`

Platform mapping should be explicit. The installer must map:

- Linux x86_64 -> `assets/mihomo/linux-amd64/mihomo`
- Linux arm64/aarch64 -> `assets/mihomo/linux-arm64/mihomo`
- macOS x86_64 -> `assets/mihomo/darwin-amd64/mihomo`
- macOS arm64 -> `assets/mihomo/darwin-arm64/mihomo`

If a platform-specific binary is not present, the installer should fail with a clear message identifying the expected asset path.

This design allows the macOS binary to be added later without changing installer structure.

### Codex

The `codex` installation flow should:

- install `nvm` if absent
- load `nvm` in the current shell
- install Node `16.20.2` by default
- set the default Node version through `nvm`
- globally install `@openai/codex`
- optionally copy `auth.json` into `~/.codex/auth.json`
- ensure `~/.zshrc` includes `nvm` initialization lines

The script should continue to assume older Linux environments may require Node `16.20.2`, since this is a validated compatibility baseline in the current repository.

## Platform Compatibility

Target operating systems:

- Linux
- macOS

Compatibility rules:

- `bash` is the required shell runtime
- `curl` is preferred; `wget` may remain a fallback where practical
- `git` is required for remote bootstrap execution
- `tar` remains acceptable for local build steps such as user-space `zsh`
- cross-platform shell differences such as `sed -i`, `mktemp`, and path resolution must be handled through helper functions rather than inline ad hoc commands

The installer does not need to support every POSIX edge case. It should focus on common Linux distributions and standard macOS environments.

## Error Handling

The installer should fail fast with clear messages for these cases:

- remote install requested but `git` is missing
- required platform asset for `mihomo` is missing
- `curl` and `wget` are both unavailable when a download is required
- build prerequisites for user-space `zsh` are unavailable
- `nvm` installation or loading fails
- `@openai/codex` installation fails

Warnings, rather than hard failures, are acceptable for:

- potentially insecure `mihomo` config settings
- non-critical configuration files that already exist and are intentionally preserved

## Idempotency Requirements

Repeated runs should be safe.

Required idempotent behaviors:

- `~/.zshrc` contains one controlled installer block, not duplicates
- existing `~/.p10k.zsh` is preserved unless explicitly replaced
- repeated `mihomo` installs reuse the same target layout and update symlinks cleanly
- repeated `codex` installs do not produce duplicate `nvm` shell lines

## Implementation Constraints

- Keep installer behavior understandable from reading `install.sh`
- Prefer function-level structure over many small shell files
- Keep asset files external to the script
- Do not reintroduce a parallel deploy entrypoint such as `deploy.sh`
- Remove default-flow references to `tmux` and the custom plugin

## Verification Plan

At minimum, verify:

1. Local repository execution works for `./install.sh install`
2. Remote bootstrap works for `curl ... | bash -s -- install`
3. Linux platform detection selects the expected `mihomo` asset path
4. macOS platform detection selects the expected `mihomo` asset path
5. Repeated runs keep `~/.zshrc` stable and non-duplicated
6. `codex` installation still loads `nvm` correctly in a fresh shell

## Open Asset Work

The installer structure should support all four `mihomo` asset directories immediately.

If the macOS `mihomo` binary cannot be added during implementation, the repository should still keep the target directory structure so the missing binary can be placed later without redesigning the installer.

## Result

After the refactor, the repository should behave as a focused personal environment installer with:

- one public entrypoint
- one retained installation scope (`zsh`, `mihomo`, `codex`)
- one remote bootstrap story based on cloning the repository
- one clear place to maintain installer logic

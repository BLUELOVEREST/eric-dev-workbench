# Remote Install Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the repository into a single public `install.sh` entrypoint that installs `zsh`, `mihomo`, and `codex`, while supporting remote bootstrap via `curl | bash` and `git clone`.

**Architecture:** Consolidate installer logic into `install.sh`, keep runtime assets in `assets/`, and replace the current multi-script deploy chain with clear installer functions. Add shell smoke tests that exercise local execution, bootstrap guards, argument parsing, platform-specific `mihomo` asset resolution, and idempotent shell config updates.

**Tech Stack:** Bash, git, curl/wget, tar, mktemp, shell smoke tests

---

## File Structure

**Create:**
- `docs/superpowers/plans/2026-03-31-remote-install-refactor.md`
- `tests/smoke/install_smoke_test.sh`
- `tests/fixtures/fake_bin/git`
- `tests/fixtures/fake_bin/curl`
- `tests/fixtures/fake_bin/wget`
- `tests/fixtures/fake_bin/npm`
- `tests/fixtures/fake_bin/node`
- `tests/fixtures/fake_bin/zsh`
- `tests/fixtures/fake_repo/assets/mihomo/linux-amd64/mihomo`
- `tests/fixtures/fake_repo/assets/mihomo/darwin-arm64/mihomo`

**Modify:**
- `install.sh`
- `README.md`

**Delete:**
- `deploy.sh`
- `scripts/modules/common.sh`
- `scripts/modules/01_zsh_ohmyzsh.sh`
- `scripts/modules/02_mihomo.sh`
- `scripts/modules/03_codex.sh`
- `scripts/modules/04_tmux.sh`
- `scripts/modules/05_custom_plugin.sh`
- `scripts/helpers/create_uenv_dirs.sh`
- `scripts/helpers/deploy_mihomo_env.sh`
- `scripts/helpers/install_tmux.sh`
- `scripts/runtime/mihomo-daemon.sh`
- `assets/plugins/codex-workflow/codex-workflow.plugin.zsh`
- `CODEX_SETUP.md`

### Task 1: Establish Test Harness And Target Layout

**Files:**
- Create: `tests/smoke/install_smoke_test.sh`
- Create: `tests/fixtures/fake_bin/git`
- Create: `tests/fixtures/fake_bin/curl`
- Create: `tests/fixtures/fake_bin/wget`
- Create: `tests/fixtures/fake_bin/npm`
- Create: `tests/fixtures/fake_bin/node`
- Create: `tests/fixtures/fake_bin/zsh`
- Create: `tests/fixtures/fake_repo/assets/mihomo/linux-amd64/mihomo`
- Create: `tests/fixtures/fake_repo/assets/mihomo/darwin-arm64/mihomo`
- Modify: `README.md`
- Test: `tests/smoke/install_smoke_test.sh`

- [ ] **Step 1: Write the failing smoke test skeleton**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_TMP="${TMPDIR:-/tmp}/eric-dev-workbench-tests"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected to find [$needle] in [$haystack]"
}

test_usage_shows_install_entrypoint() {
  local output
  output="$(bash "$ROOT_DIR/install.sh" --help 2>&1 || true)"
  assert_contains "$output" "install.sh install"
}

test_usage_shows_install_entrypoint
echo "smoke tests passed"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/smoke/install_smoke_test.sh`
Expected: FAIL because the old help text and flow still describe `deploy.sh` and the old module surface.

- [ ] **Step 3: Add fixture stubs for command interception**

```bash
#!/usr/bin/env bash
set -euo pipefail
echo "fixture git: $*" >>"${TEST_LOG:-/tmp/fixture.log}"
```

Repeat the same minimal pattern for `curl`, `wget`, `npm`, `node`, and `zsh` under `tests/fixtures/fake_bin/`. Mark them executable.

For `tests/fixtures/fake_repo/assets/mihomo/linux-amd64/mihomo` and `tests/fixtures/fake_repo/assets/mihomo/darwin-arm64/mihomo`, add tiny executable placeholder scripts:

```bash
#!/usr/bin/env bash
echo "Mihomo Meta v1.0.0"
```

- [ ] **Step 4: Update README heading to match the new target scope**

```markdown
# eric-dev-workbench

Single-entry installer for Eric's `zsh`, `mihomo`, and `codex` environment bootstrap on Linux and macOS.
```

- [ ] **Step 5: Run the smoke test again**

Run: `bash tests/smoke/install_smoke_test.sh`
Expected: still FAIL, but now the test harness and fixtures exist and are ready for the next task.

- [ ] **Step 6: Commit**

```bash
git add README.md tests/smoke/install_smoke_test.sh tests/fixtures
git commit -m "test: add installer smoke test harness"
```

### Task 2: Collapse Entrypoint Logic Into `install.sh`

**Files:**
- Modify: `install.sh`
- Delete: `deploy.sh`
- Test: `tests/smoke/install_smoke_test.sh`

- [ ] **Step 1: Extend the smoke test with local and remote mode expectations**

```bash
test_help_omits_deploy_entrypoint() {
  local output
  output="$(bash "$ROOT_DIR/install.sh" --help 2>&1 || true)"
  [[ "$output" != *"deploy.sh"* ]] || fail "help should not mention deploy.sh"
  assert_contains "$output" "--with zsh,mihomo,codex"
}

test_remote_mode_requires_git() {
  local tmp_home
  tmp_home="$(mktemp -d)"
  local output
  output="$(HOME="$tmp_home" PATH="/usr/bin:/bin" bash "$ROOT_DIR/install.sh" install 2>&1 || true)"
  assert_contains "$output" "git is required for remote bootstrap"
  rm -rf "$tmp_home"
}

test_help_omits_deploy_entrypoint
test_remote_mode_requires_git
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/smoke/install_smoke_test.sh`
Expected: FAIL because `install.sh` still shells out to `deploy.sh`.

- [ ] **Step 3: Replace `install.sh` with a single-entry bootstrap implementation**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/BLUELOVEREST/eric-dev-workbench.git}"
SCRIPT_NAME="install.sh"
COMMAND="${1:-install}"

log() {
  echo "[eric-dev-workbench] $*"
}

die() {
  log "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  install.sh install [--with zsh,mihomo,codex] [--root PATH] [--codex-auth PATH]
  install.sh --help
EOF
}

is_repo_checkout() {
  [[ -f "${PACKAGE_ROOT:-}/install.sh" ]] && [[ -d "${PACKAGE_ROOT:-}/assets" ]]
}

bootstrap_repo() {
  command -v git >/dev/null 2>&1 || die "git is required for remote bootstrap"
  local workdir
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' EXIT
  git clone --depth=1 "$REPO_URL" "$workdir/repo" >/dev/null 2>&1
  cd "$workdir/repo"
  PACKAGE_ROOT="$PWD" bash "$PWD/install.sh" "$@"
}
```

Complete the file by parsing `install`, `--help`, `--with`, `--root`, and `--codex-auth`, and by routing local checkout execution to installer functions that will be added in later tasks.

- [ ] **Step 4: Run the smoke test to verify it passes for entrypoint behavior**

Run: `bash tests/smoke/install_smoke_test.sh`
Expected: PASS for the help and remote bootstrap guard assertions.

- [ ] **Step 5: Commit**

```bash
git add install.sh deploy.sh tests/smoke/install_smoke_test.sh
git commit -m "refactor: collapse installer entrypoint into install.sh"
```

### Task 3: Move Shared Shell And Runtime Helpers Into `install.sh`

**Files:**
- Modify: `install.sh`
- Delete: `scripts/modules/common.sh`
- Delete: `scripts/helpers/create_uenv_dirs.sh`
- Delete: `scripts/runtime/mihomo-daemon.sh`
- Test: `tests/smoke/install_smoke_test.sh`

- [ ] **Step 1: Add failing tests for shared helpers**

```bash
test_zsh_block_is_idempotent() {
  local tmp_home
  tmp_home="$(mktemp -d)"
  HOME="$tmp_home" PACKAGE_ROOT="$ROOT_DIR" bash "$ROOT_DIR/install.sh" install --with codex >/dev/null 2>&1 || true
  HOME="$tmp_home" PACKAGE_ROOT="$ROOT_DIR" bash "$ROOT_DIR/install.sh" install --with codex >/dev/null 2>&1 || true
  local count
  count="$(grep -c '# >>> eric-dev-workbench >>>' "$tmp_home/.zshrc" 2>/dev/null || true)"
  [[ "$count" == "1" ]] || fail "expected one managed zsh block, got $count"
  rm -rf "$tmp_home"
}

test_zsh_block_is_idempotent
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/smoke/install_smoke_test.sh`
Expected: FAIL because the new managed zsh block does not exist yet.

- [ ] **Step 3: Inline shared helper functions and daemon template into `install.sh`**

```bash
ensure_uenv_dirs() {
  local root="$1"
  local dirs=(
    bin etc etc/profile.d etc/clash opt opt/clash opt/zsh src var var/log var/run state state/current
  )
  local dir
  for dir in "${dirs[@]}"; do
    mkdir -p "$root/$dir"
  done
}

ensure_zsh_block() {
  local zshrc="$1"
  local block="$2"
  local start="# >>> eric-dev-workbench >>>"
  local end="# <<< eric-dev-workbench <<<"
  touch "$zshrc"
  awk -v s="$start" -v e="$end" -v b="$block" '
    BEGIN { inblock=0; done=0 }
    $0==s { print s; print b; inblock=1; done=1; next }
    $0==e { inblock=0; print e; next }
    { if (!inblock) print }
    END { if (!done) { print s; print b; print e } }
  ' "$zshrc" >"$zshrc.tmp"
  mv "$zshrc.tmp" "$zshrc"
}

write_mihomo_daemon() {
  local target="$1"
  cat >"$target" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ACTION="${1:-}"
RUNTIME_ROOT="${RUNTIME_ROOT:-$HOME/.uenv}"
MIHOMO_BIN="${MIHOMO_BIN:-$RUNTIME_ROOT/opt/clash/current/bin/mihomo}"
CONFIG_FILE="${CONFIG_FILE:-$RUNTIME_ROOT/etc/clash/config.yaml}"
PID_FILE="${PID_FILE:-$RUNTIME_ROOT/var/run/mihomo.pid}"
LOG_FILE="${LOG_FILE:-$RUNTIME_ROOT/var/log/mihomo.log}"
EOF
  chmod 755 "$target"
}
```

Complete the daemon body by preserving the existing `start|stop|restart|status` behavior.

- [ ] **Step 4: Run the smoke test to verify the helper behavior passes**

Run: `bash tests/smoke/install_smoke_test.sh`
Expected: PASS for the idempotent zsh block assertion.

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/smoke/install_smoke_test.sh
git rm scripts/modules/common.sh scripts/helpers/create_uenv_dirs.sh scripts/runtime/mihomo-daemon.sh
git commit -m "refactor: inline shared installer helpers"
```

### Task 4: Rebuild `zsh` Installation Inside The Single Script

**Files:**
- Modify: `install.sh`
- Delete: `scripts/modules/01_zsh_ohmyzsh.sh`
- Modify: `README.md`
- Test: `tests/smoke/install_smoke_test.sh`

- [ ] **Step 1: Add a failing test for `zsh` flow selection**

```bash
test_zsh_install_writes_theme_block() {
  local tmp_home
  tmp_home="$(mktemp -d)"
  HOME="$tmp_home" PACKAGE_ROOT="$ROOT_DIR" PATH="$ROOT_DIR/tests/fixtures/fake_bin:/usr/bin:/bin" \
    bash "$ROOT_DIR/install.sh" install --with zsh >/dev/null 2>&1 || true
  local content
  content="$(cat "$tmp_home/.zshrc" 2>/dev/null || true)"
  assert_contains "$content" 'export ZSH="$HOME/.oh-my-zsh"'
  assert_contains "$content" 'export ZSH_THEME="powerlevel10k/powerlevel10k"'
  rm -rf "$tmp_home"
}

test_zsh_install_writes_theme_block
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/smoke/install_smoke_test.sh`
Expected: FAIL because `install_zsh_env` is not yet implemented in the new script.

- [ ] **Step 3: Implement `install_zsh_env` and its support functions**

```bash
install_zsh_env() {
  local effective_mode
  effective_mode="$(detect_effective_mode)"
  local current_ver=""
  if command -v zsh >/dev/null 2>&1; then
    current_ver="$(get_zsh_version || true)"
  fi
  if [[ -z "$current_ver" ]] || ! version_ge "$current_ver" "${MIN_ZSH_VERSION:-5.8}"; then
    install_zsh_user
  fi
  ensure_ohmyzsh
  ensure_theme_and_plugins
  ensure_p10k_config
  write_shell_config
}
```

Include `get_zsh_version`, `version_ge`, `install_zsh_user`, `ensure_ohmyzsh`, `ensure_theme_and_plugins`, and `ensure_p10k_config`, migrated from the old module and adapted to the new asset layout.

- [ ] **Step 4: Update README usage examples**

```markdown
```bash
./install.sh install --with zsh
curl -fsSL https://raw.githubusercontent.com/BLUELOVEREST/eric-dev-workbench/main/install.sh | bash -s -- install --with zsh
```
```

- [ ] **Step 5: Run the smoke test**

Run: `bash tests/smoke/install_smoke_test.sh`
Expected: PASS for the `zsh` config assertions.

- [ ] **Step 6: Commit**

```bash
git add install.sh README.md tests/smoke/install_smoke_test.sh
git rm scripts/modules/01_zsh_ohmyzsh.sh
git commit -m "feat: migrate zsh environment install into main installer"
```

### Task 5: Rebuild `mihomo` Installation With Platform-Specific Assets

**Files:**
- Modify: `install.sh`
- Modify: `README.md`
- Delete: `scripts/modules/02_mihomo.sh`
- Delete: `scripts/helpers/deploy_mihomo_env.sh`
- Modify: `assets/config.yaml`
- Create: `assets/config/mihomo-config.yaml`
- Test: `tests/smoke/install_smoke_test.sh`

- [ ] **Step 1: Add failing tests for platform asset mapping**

```bash
test_mihomo_linux_amd64_asset_path() {
  local output
  output="$(PACKAGE_ROOT="$ROOT_DIR/tests/fixtures/fake_repo" FAKE_UNAME_S=Linux FAKE_UNAME_M=x86_64 \
    bash "$ROOT_DIR/install.sh" internal-print-mihomo-asset 2>&1)"
  assert_contains "$output" "assets/mihomo/linux-amd64/mihomo"
}

test_mihomo_darwin_arm64_asset_path() {
  local output
  output="$(PACKAGE_ROOT="$ROOT_DIR/tests/fixtures/fake_repo" FAKE_UNAME_S=Darwin FAKE_UNAME_M=arm64 \
    bash "$ROOT_DIR/install.sh" internal-print-mihomo-asset 2>&1)"
  assert_contains "$output" "assets/mihomo/darwin-arm64/mihomo"
}

test_mihomo_linux_amd64_asset_path
test_mihomo_darwin_arm64_asset_path
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/smoke/install_smoke_test.sh`
Expected: FAIL because the platform-specific asset resolver does not exist yet.

- [ ] **Step 3: Implement explicit `mihomo` asset resolution and deployment**

```bash
detect_os() {
  echo "${FAKE_UNAME_S:-$(uname -s)}"
}

detect_arch() {
  echo "${FAKE_UNAME_M:-$(uname -m)}"
}

resolve_mihomo_asset() {
  local os arch key
  os="$(detect_os)"
  arch="$(detect_arch)"
  case "$os:$arch" in
    Linux:x86_64) key="linux-amd64" ;;
    Linux:aarch64|Linux:arm64) key="linux-arm64" ;;
    Darwin:x86_64) key="darwin-amd64" ;;
    Darwin:arm64) key="darwin-arm64" ;;
    *) die "unsupported mihomo platform: $os/$arch" ;;
  esac
  echo "$PACKAGE_ROOT/assets/mihomo/$key/mihomo"
}

install_mihomo_env() {
  local source_bin target_bin version
  source_bin="$(resolve_mihomo_asset)"
  [[ -f "$source_bin" ]] || die "missing mihomo asset: $source_bin"
  version="$("$source_bin" -v 2>/dev/null | head -n1 | grep -Eo 'v[0-9]+(\.[0-9]+){1,3}' | head -n1 || true)"
  version="${version#v}"
}
```

Complete the function by copying the binary into `~/.uenv/opt/clash/<version>/bin/mihomo`, copying `assets/config/mihomo-config.yaml` to `~/.uenv/etc/clash/config.yaml`, writing the daemon script, and updating the `current` symlink.

- [ ] **Step 4: Move the default config into its new path**

```bash
mkdir -p assets/config
mv assets/config.yaml assets/config/mihomo-config.yaml
```

- [ ] **Step 5: Run the smoke test**

Run: `bash tests/smoke/install_smoke_test.sh`
Expected: PASS for the Linux/macOS asset path assertions.

- [ ] **Step 6: Commit**

```bash
git add install.sh README.md assets/config/mihomo-config.yaml tests/smoke/install_smoke_test.sh tests/fixtures/fake_repo
git rm scripts/modules/02_mihomo.sh scripts/helpers/deploy_mihomo_env.sh assets/config.yaml
git commit -m "feat: add platform-aware mihomo asset installation"
```

### Task 6: Rebuild `codex` Installation Inside The Single Script

**Files:**
- Modify: `install.sh`
- Delete: `scripts/modules/03_codex.sh`
- Delete: `CODEX_SETUP.md`
- Modify: `README.md`
- Test: `tests/smoke/install_smoke_test.sh`

- [ ] **Step 1: Add a failing test for `codex` shell setup**

```bash
test_codex_install_adds_nvm_bootstrap() {
  local tmp_home
  tmp_home="$(mktemp -d)"
  HOME="$tmp_home" PACKAGE_ROOT="$ROOT_DIR" PATH="$ROOT_DIR/tests/fixtures/fake_bin:/usr/bin:/bin" \
    bash "$ROOT_DIR/install.sh" install --with codex >/dev/null 2>&1 || true
  local content
  content="$(cat "$tmp_home/.zshrc" 2>/dev/null || true)"
  assert_contains "$content" 'export NVM_DIR="$HOME/.nvm"'
  assert_contains "$content" '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"'
  rm -rf "$tmp_home"
}

test_codex_install_adds_nvm_bootstrap
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/smoke/install_smoke_test.sh`
Expected: FAIL because the consolidated `codex` installation path is not implemented yet.

- [ ] **Step 3: Implement `install_codex_env`**

```bash
install_nvm() {
  if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    return
  fi
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
  else
    die "curl or wget is required to install nvm"
  fi
}

install_codex_env() {
  install_nvm
  load_nvm
  command -v nvm >/dev/null 2>&1 || die "nvm load failed"
  nvm install "${NODE_VERSION:-16.20.2}"
  nvm use "${NODE_VERSION:-16.20.2}"
  nvm alias default "${NODE_VERSION:-16.20.2}"
  npm install -g "${CODEX_NPM_PACKAGE:-@openai/codex}"
  install_codex_auth
  write_shell_config
}
```

Also add `install_codex_auth` and preserve `auth.json` permission handling.

- [ ] **Step 4: Fold `CODEX_SETUP.md` content into README**

```markdown
## Codex Notes

The installer uses `nvm` and defaults to Node `16.20.2` because it is the validated compatibility baseline for older Linux environments in this repository.
```

- [ ] **Step 5: Run the smoke test**

Run: `bash tests/smoke/install_smoke_test.sh`
Expected: PASS for the `codex` shell bootstrap assertions.

- [ ] **Step 6: Commit**

```bash
git add install.sh README.md tests/smoke/install_smoke_test.sh
git rm scripts/modules/03_codex.sh CODEX_SETUP.md
git commit -m "feat: migrate codex install flow into main installer"
```

### Task 7: Remove Out-Of-Scope Modules And Finalize Docs

**Files:**
- Modify: `README.md`
- Delete: `scripts/modules/04_tmux.sh`
- Delete: `scripts/modules/05_custom_plugin.sh`
- Delete: `scripts/helpers/install_tmux.sh`
- Delete: `assets/plugins/codex-workflow/codex-workflow.plugin.zsh`
- Test: `tests/smoke/install_smoke_test.sh`

- [ ] **Step 1: Add a failing test for the supported module list**

```bash
test_help_lists_only_supported_modules() {
  local output
  output="$(bash "$ROOT_DIR/install.sh" --help 2>&1 || true)"
  assert_contains "$output" "supported: zsh,mihomo,codex"
  [[ "$output" != *"tmux"* ]] || fail "help should not mention tmux"
  [[ "$output" != *"plugin"* ]] || fail "help should not mention plugin"
}

test_help_lists_only_supported_modules
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/smoke/install_smoke_test.sh`
Expected: FAIL because the help text and docs still mention removed modules.

- [ ] **Step 3: Update docs and remove out-of-scope files**

```markdown
## Included environments

- `zsh`
- `mihomo`
- `codex`
```

Delete the tmux and plugin module scripts and remove all references to them from README examples and option descriptions.

- [ ] **Step 4: Run the smoke test**

Run: `bash tests/smoke/install_smoke_test.sh`
Expected: PASS for the supported module list assertions.

- [ ] **Step 5: Commit**

```bash
git add README.md tests/smoke/install_smoke_test.sh
git rm scripts/modules/04_tmux.sh scripts/modules/05_custom_plugin.sh scripts/helpers/install_tmux.sh assets/plugins/codex-workflow/codex-workflow.plugin.zsh
git commit -m "chore: remove tmux and plugin install flow"
```

### Task 8: Final Verification And Cleanup

**Files:**
- Modify: `install.sh`
- Modify: `README.md`
- Test: `tests/smoke/install_smoke_test.sh`

- [ ] **Step 1: Add a final integration-oriented smoke test**

```bash
test_with_parsing_rejects_unknown_module() {
  local output
  output="$(PACKAGE_ROOT="$ROOT_DIR" bash "$ROOT_DIR/install.sh" install --with zsh,unknown 2>&1 || true)"
  assert_contains "$output" "unsupported module: unknown"
}

test_with_parsing_rejects_unknown_module
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/smoke/install_smoke_test.sh`
Expected: FAIL until the final argument parsing and validation pass is complete.

- [ ] **Step 3: Finalize argument parsing, cleanup, and comments**

```bash
validate_modules() {
  local module
  IFS=',' read -r -a modules <<<"$WITH"
  for module in "${modules[@]}"; do
    case "$module" in
      zsh|mihomo|codex) ;;
      *) die "unsupported module: $module" ;;
    esac
  done
}
```

Also remove stale comments, ensure `README.md` examples match the final interface, and keep comments limited to non-obvious shell behavior.

- [ ] **Step 4: Run the full smoke suite**

Run: `bash tests/smoke/install_smoke_test.sh`
Expected: `smoke tests passed`

- [ ] **Step 5: Manual verification of the two entrypoints**

Run: `bash install.sh --help`
Expected: usage text mentioning only `zsh,mihomo,codex`

Run: `bash install.sh install --with codex`
Expected: installer enters the consolidated local flow

Run: `curl -fsSL https://raw.githubusercontent.com/BLUELOVEREST/eric-dev-workbench/main/install.sh | bash -s -- --help`
Expected: remote bootstrap help path succeeds once the branch is pushed

- [ ] **Step 6: Commit**

```bash
git add install.sh README.md tests/smoke/install_smoke_test.sh
git commit -m "test: finalize single-entry installer verification"
```

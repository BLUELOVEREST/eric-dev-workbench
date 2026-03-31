#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

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

test_help_omits_deploy_entrypoint() {
  local output
  output="$(bash "$ROOT_DIR/install.sh" --help 2>&1 || true)"
  [[ "$output" != *"deploy.sh"* ]] || fail "help should not mention deploy.sh"
  assert_contains "$output" "--with zsh,mihomo,codex"
}

test_remote_mode_requires_git() {
  local tmp_home
  tmp_home="$(mktemp -d)"
  cp "$ROOT_DIR/install.sh" "$tmp_home/install.sh"
  mkdir -p "$tmp_home/bin"
  ln -sf /usr/bin/dirname "$tmp_home/bin/dirname"
  local output
  output="$(HOME="$tmp_home" PATH="$tmp_home/bin" /bin/bash "$tmp_home/install.sh" install 2>&1 || true)"
  assert_contains "$output" "git is required for remote bootstrap"
  rm -rf "$tmp_home"
}

test_zsh_install_writes_theme_block() {
  local tmp_home
  tmp_home="$(mktemp -d)"
  HOME="$tmp_home" PACKAGE_ROOT="$ROOT_DIR" PATH="$ROOT_DIR/tests/fixtures/fake_bin:/usr/bin:/bin" \
    bash "$ROOT_DIR/install.sh" install --with zsh >/dev/null 2>&1 || true
  local content
  content="$(cat "$tmp_home/.zshrc" 2>/dev/null || true)"
  assert_contains "$content" 'export ZSH="$HOME/.oh-my-zsh"'
  assert_contains "$content" 'export ZSH_THEME="powerlevel10k/powerlevel10k"'
  assert_contains "$content" 'export http_proxy="http://127.0.0.1:56666"'
  assert_contains "$content" 'export all_proxy="socks5://127.0.0.1:58888"'
  rm -rf "$tmp_home"
}

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

test_zsh_block_is_idempotent() {
  local tmp_home
  tmp_home="$(mktemp -d)"
  HOME="$tmp_home" PACKAGE_ROOT="$ROOT_DIR" PATH="$ROOT_DIR/tests/fixtures/fake_bin:/usr/bin:/bin" \
    bash "$ROOT_DIR/install.sh" install --with codex >/dev/null 2>&1 || true
  HOME="$tmp_home" PACKAGE_ROOT="$ROOT_DIR" PATH="$ROOT_DIR/tests/fixtures/fake_bin:/usr/bin:/bin" \
    bash "$ROOT_DIR/install.sh" install --with codex >/dev/null 2>&1 || true
  local count
  count="$(grep -c '# >>> eric-dev-workbench >>>' "$tmp_home/.zshrc" 2>/dev/null || true)"
  [[ "$count" == "1" ]] || fail "expected one managed zsh block, got $count"
  rm -rf "$tmp_home"
}

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

test_help_lists_only_supported_modules() {
  local output
  output="$(bash "$ROOT_DIR/install.sh" --help 2>&1 || true)"
  assert_contains "$output" "supported: zsh,mihomo,codex"
  [[ "$output" != *"tmux"* ]] || fail "help should not mention tmux"
  [[ "$output" != *"plugin"* ]] || fail "help should not mention plugin"
}

test_with_parsing_rejects_unknown_module() {
  local output
  output="$(PACKAGE_ROOT="$ROOT_DIR" bash "$ROOT_DIR/install.sh" install --with zsh,unknown 2>&1 || true)"
  assert_contains "$output" "unsupported module: unknown"
}

test_usage_shows_install_entrypoint
test_help_omits_deploy_entrypoint
test_remote_mode_requires_git
test_zsh_install_writes_theme_block
test_codex_install_adds_nvm_bootstrap
test_zsh_block_is_idempotent
test_mihomo_linux_amd64_asset_path
test_mihomo_darwin_arm64_asset_path
test_help_lists_only_supported_modules
test_with_parsing_rejects_unknown_module
echo "smoke tests passed"

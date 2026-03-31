#!/usr/bin/env bash
set -euo pipefail

if [[ "${0:-bash}" == "bash" || "${0:-bash}" == "-bash" ]]; then
  SCRIPT_DIR="$(pwd)"
else
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi
PACKAGE_ROOT="${PACKAGE_ROOT:-$SCRIPT_DIR}"
REPO_URL="${REPO_URL:-https://github.com/BLUELOVEREST/eric-dev-workbench.git}"

WITH="zsh,mihomo,codex"
UENV_ROOT="${UENV_ROOT:-$HOME/.uenv}"
CODEX_AUTH_SRC="${CODEX_AUTH_SRC:-}"
NODE_VERSION="${NODE_VERSION:-16.20.2}"
CODEX_NPM_PACKAGE="${CODEX_NPM_PACKAGE:-@openai/codex}"
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
MIN_ZSH_VERSION="${MIN_ZSH_VERSION:-5.8}"

log() {
  echo "[eric-dev-workbench] $*"
}

die() {
  log "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  install.sh install [--with zsh,mihomo,codex] [--root PATH] [--codex-auth PATH]
  install.sh help

Options:
  --with LIST         supported: zsh,mihomo,codex
  --root PATH         user prefix root (default: ~/.uenv)
  --codex-auth PATH   auth.json to copy into ~/.codex/auth.json
  -h, --help          show this help

Examples:
  ./install.sh install
  ./install.sh install --with codex,mihomo
  curl -fsSL https://raw.githubusercontent.com/BLUELOVEREST/eric-dev-workbench/main/install.sh | bash -s -- install
USAGE
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

ensure_uenv_dirs() {
  local root="$1"
  local dirs=(
    bin
    etc
    etc/profile.d
    etc/clash
    opt
    opt/clash
    opt/zsh
    src
    var
    var/log
    var/run
    state
    state/current
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

write_shell_config() {
  local zshrc="$HOME/.zshrc"
  local block
  local mihomo_http_port
  local mihomo_socks_port
  mihomo_http_port="$(get_mihomo_http_port)"
  mihomo_socks_port="$(get_mihomo_socks_port)"
  block='export ZSH="$HOME/.oh-my-zsh"
export ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting z)
typeset -g POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
if [ -f "$ZSH/oh-my-zsh.sh" ]; then
  source "$ZSH/oh-my-zsh.sh"
fi
[[ -f "$HOME/.p10k.zsh" ]] && source "$HOME/.p10k.zsh"

if [ -d "$HOME/.uenv/bin" ]; then
  export PATH="$HOME/.uenv/bin:$PATH"
fi

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

proxy_on() {
  export http_proxy="http://127.0.0.1:'"$mihomo_http_port"'"
  export https_proxy="http://127.0.0.1:'"$mihomo_http_port"'"
  export all_proxy="socks5://127.0.0.1:'"$mihomo_socks_port"'"
  export HTTP_PROXY="$http_proxy"
  export HTTPS_PROXY="$https_proxy"
  export ALL_PROXY="$all_proxy"
  export no_proxy="localhost,127.0.0.1,::1"
  export NO_PROXY="$no_proxy"
}

proxy_off() {
  unset http_proxy https_proxy all_proxy
  unset HTTP_PROXY HTTPS_PROXY ALL_PROXY
  unset no_proxy NO_PROXY
}'
  ensure_zsh_block "$zshrc" "$block"
}

get_mihomo_config_path() {
  echo "$PACKAGE_ROOT/assets/config/mihomo-config.yaml"
}

get_mihomo_http_port() {
  local cfg
  cfg="$(get_mihomo_config_path)"
  if [[ -f "$cfg" ]]; then
    awk -F': *' '/^port:/ {print $2; exit}' "$cfg"
    return 0
  fi
  echo "7890"
}

get_mihomo_socks_port() {
  local cfg
  cfg="$(get_mihomo_config_path)"
  if [[ -f "$cfg" ]]; then
    awk -F': *' '/^socks-port:/ {print $2; exit}' "$cfg"
    return 0
  fi
  echo "7891"
}

get_zsh_version() {
  if ! command -v zsh >/dev/null 2>&1; then
    return 1
  fi
  zsh --version 2>/dev/null | awk '{print $2}' | sed 's/[^0-9.].*$//'
}

version_ge() {
  local ver="$1"
  local min="$2"
  [[ "$(printf '%s\n%s\n' "$min" "$ver" | sort -V | head -n1)" == "$min" ]]
}

fetch_to_file() {
  local url="$1"
  local out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$out"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$out" "$url"
  else
    die "curl or wget is required"
  fi
}

install_zsh_user() {
  local zver="5.9"
  local src="$UENV_ROOT/src/zsh-$zver"
  local tgz="$UENV_ROOT/src/zsh-$zver.tar.xz"
  local prefix="$UENV_ROOT/opt/zsh/$zver"

  if [[ -x "$prefix/bin/zsh" ]]; then
    ln -sfn "$prefix/bin/zsh" "$UENV_ROOT/bin/zsh"
    return 0
  fi

  ensure_uenv_dirs "$UENV_ROOT"
  mkdir -p "$UENV_ROOT/src"
  fetch_to_file "https://www.zsh.org/pub/zsh-$zver.tar.xz" "$tgz"
  rm -rf "$src"
  tar -xf "$tgz" -C "$UENV_ROOT/src"
  (
    cd "$src"
    ./configure --prefix="$prefix"
    make -j"${JOBS:-2}"
    make install
  )
  ln -sfn "$prefix/bin/zsh" "$UENV_ROOT/bin/zsh"
}

ensure_ohmyzsh() {
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    return 0
  fi
  need_cmd git
  git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh" >/dev/null 2>&1
}

ensure_theme_and_plugins() {
  local zsh_custom_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  local p10k_dir="$zsh_custom_dir/themes/powerlevel10k"
  local autosuggest_dir="$zsh_custom_dir/plugins/zsh-autosuggestions"
  local syntax_dir="$zsh_custom_dir/plugins/zsh-syntax-highlighting"

  mkdir -p "$zsh_custom_dir/themes" "$zsh_custom_dir/plugins"

  [[ -d "$p10k_dir" ]] || git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir" >/dev/null 2>&1
  [[ -d "$autosuggest_dir" ]] || git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git "$autosuggest_dir" >/dev/null 2>&1
  [[ -d "$syntax_dir" ]] || git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$syntax_dir" >/dev/null 2>&1
}

ensure_p10k_config() {
  local template="$PACKAGE_ROOT/assets/themes/p10k.zsh.template"
  local target="$HOME/.p10k.zsh"
  [[ -f "$template" ]] || return 0
  [[ -f "$target" ]] || cp "$template" "$target"
}

install_zsh_env() {
  local current_ver=""
  if command -v zsh >/dev/null 2>&1; then
    current_ver="$(get_zsh_version || true)"
  fi
  if [[ -z "$current_ver" ]] || ! version_ge "$current_ver" "$MIN_ZSH_VERSION"; then
    install_zsh_user
  fi
  ensure_ohmyzsh
  ensure_theme_and_plugins
  ensure_p10k_config
  write_shell_config
}

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

write_mihomo_daemon() {
  local target="$1"
  cat >"$target" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$HOME/.uenv"
if [[ "$(basename "$SCRIPT_DIR")" == "bin" ]]; then
  DEFAULT_ROOT="$(dirname "$SCRIPT_DIR")"
fi

RUNTIME_ROOT="${RUNTIME_ROOT:-$DEFAULT_ROOT}"
MIHOMO_BIN="${MIHOMO_BIN:-$RUNTIME_ROOT/opt/clash/current/bin/mihomo}"
CONFIG_FILE="${CONFIG_FILE:-$RUNTIME_ROOT/etc/clash/config.yaml}"
PID_FILE="${PID_FILE:-$RUNTIME_ROOT/var/run/mihomo.pid}"
LOG_FILE="${LOG_FILE:-$RUNTIME_ROOT/var/log/mihomo.log}"
CONFIG_DIR="$(dirname "$CONFIG_FILE")"

usage() {
  echo "Usage: $0 {start|stop|restart|status}"
}

is_running() {
  if [[ ! -f "$PID_FILE" ]]; then
    return 1
  fi
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

start() {
  [[ -f "$CONFIG_FILE" ]] || { echo "Config file not found: $CONFIG_FILE" >&2; exit 1; }
  [[ -x "$MIHOMO_BIN" ]] || { echo "mihomo binary not found or not executable: $MIHOMO_BIN" >&2; exit 1; }
  mkdir -p "$(dirname "$PID_FILE")" "$(dirname "$LOG_FILE")"
  if is_running; then
    echo "mihomo is already running (pid=$(cat "$PID_FILE"))."
    exit 0
  fi
  nohup "$MIHOMO_BIN" -d "$CONFIG_DIR" >>"$LOG_FILE" 2>&1 &
  echo $! >"$PID_FILE"
  sleep 1
  if is_running; then
    echo "mihomo started (pid=$(cat "$PID_FILE"))."
    echo "log: $LOG_FILE"
  else
    echo "mihomo failed to start. Last log lines:" >&2
    tail -n 40 "$LOG_FILE" >&2 || true
    exit 1
  fi
}

stop() {
  if ! is_running; then
    echo "mihomo is not running."
    rm -f "$PID_FILE"
    exit 0
  fi
  local pid
  pid="$(cat "$PID_FILE")"
  kill "$pid" 2>/dev/null || true
  for _ in {1..20}; do
    if ! kill -0 "$pid" 2>/dev/null; then
      rm -f "$PID_FILE"
      echo "mihomo stopped."
      exit 0
    fi
    sleep 0.5
  done
  kill -9 "$pid" 2>/dev/null || true
  rm -f "$PID_FILE"
  echo "mihomo stopped (forced)."
}

status() {
  if is_running; then
    echo "mihomo is running (pid=$(cat "$PID_FILE"))."
    echo "config: $CONFIG_FILE"
    echo "log:    $LOG_FILE"
  else
    echo "mihomo is not running."
    echo "config: $CONFIG_FILE"
    echo "log:    $LOG_FILE"
    exit 1
  fi
}

case "$ACTION" in
  start) start ;;
  stop) stop ;;
  restart) stop || true; start ;;
  status) status ;;
  *) usage >&2; exit 2 ;;
esac
EOF
  chmod 755 "$target"
}

warn_mihomo_config_risks() {
  local cfg="$1"
  if grep -Eq "^allow-lan:[[:space:]]*true[[:space:]]*$" "$cfg"; then
    log "warning: allow-lan is true in $cfg"
  fi
  if grep -Eq "^external-controller:[[:space:]]*0\\.0\\.0\\.0:" "$cfg"; then
    log "warning: external-controller listens on 0.0.0.0 in $cfg"
  fi
}

install_mihomo_env() {
  local source_bin source_config version install_dir target_bin target_config target_daemon
  source_bin="$(resolve_mihomo_asset)"
  [[ -f "$source_bin" ]] || die "missing mihomo asset: $source_bin"
  source_config="$PACKAGE_ROOT/assets/config/mihomo-config.yaml"
  [[ -f "$source_config" ]] || die "missing mihomo config: $source_config"

  version="$("$source_bin" -v 2>/dev/null | head -n1 | grep -Eo 'v[0-9]+(\.[0-9]+){1,3}([._-][A-Za-z0-9]+)?' | head -n1 || true)"
  version="${version#v}"
  [[ -n "$version" ]] || version="manual-$(date +%Y%m%d)"

  ensure_uenv_dirs "$UENV_ROOT"
  install_dir="$UENV_ROOT/opt/clash/$version"
  target_bin="$install_dir/bin/mihomo"
  target_config="$UENV_ROOT/etc/clash/config.yaml"
  target_daemon="$UENV_ROOT/bin/mihomo-daemon.sh"

  mkdir -p "$install_dir/bin" "$(dirname "$target_config")" "$(dirname "$target_daemon")"
  cp "$source_bin" "$target_bin"
  chmod 755 "$target_bin"
  cp "$source_config" "$target_config"
  chmod 600 "$target_config"
  write_mihomo_daemon "$target_daemon"
  ln -sfn "$version" "$UENV_ROOT/opt/clash/current"
  ln -sfn "$UENV_ROOT/opt/clash/current/bin/mihomo" "$UENV_ROOT/bin/mihomo"
  warn_mihomo_config_risks "$target_config"
}

install_nvm() {
  if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    return 0
  fi
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
  else
    die "curl or wget is required to install nvm"
  fi
}

load_nvm() {
  # shellcheck disable=SC1090
  [[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
}

install_codex_auth() {
  if [[ -z "$CODEX_AUTH_SRC" ]]; then
    return 0
  fi
  [[ -f "$CODEX_AUTH_SRC" ]] || die "auth source does not exist: $CODEX_AUTH_SRC"
  mkdir -p "$HOME/.codex"
  cp "$CODEX_AUTH_SRC" "$HOME/.codex/auth.json"
  chmod 700 "$HOME/.codex"
  chmod 600 "$HOME/.codex/auth.json"
}

install_codex_env() {
  install_nvm
  load_nvm
  command -v nvm >/dev/null 2>&1 || die "nvm load failed"
  nvm install "$NODE_VERSION"
  nvm use "$NODE_VERSION"
  nvm alias default "$NODE_VERSION"
  npm install -g "$CODEX_NPM_PACKAGE"
  install_codex_auth
  write_shell_config
}

validate_modules() {
  local module
  IFS=',' read -r -a MODULES <<<"$WITH"
  for module in "${MODULES[@]}"; do
    case "$module" in
      zsh|mihomo|codex) ;;
      *) die "unsupported module: $module" ;;
    esac
  done
}

parse_install_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --with)
        WITH="$2"
        shift 2
        ;;
      --root)
        UENV_ROOT="$2"
        shift 2
        ;;
      --codex-auth)
        CODEX_AUTH_SRC="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

run_local_install() {
  local module
  validate_modules
  for module in "${MODULES[@]}"; do
    case "$module" in
      zsh) install_zsh_env ;;
      mihomo) install_mihomo_env ;;
      codex) install_codex_env ;;
    esac
  done
}

is_repo_checkout() {
  [[ -f "$PACKAGE_ROOT/install.sh" ]] && [[ -d "$PACKAGE_ROOT/assets" ]]
}

bootstrap_repo() {
  command -v git >/dev/null 2>&1 || die "git is required for remote bootstrap"

  local workdir
  local args
  workdir="$(mktemp -d)"
  trap "rm -rf '$workdir'" EXIT

  git clone --depth=1 "$REPO_URL" "$workdir/repo" >/dev/null 2>&1 || die "failed to clone repository: $REPO_URL"
  args=(install --with "$WITH" --root "$UENV_ROOT")
  if [[ -n "$CODEX_AUTH_SRC" ]]; then
    args+=(--codex-auth "$CODEX_AUTH_SRC")
  fi
  PACKAGE_ROOT="$workdir/repo" bash "$workdir/repo/install.sh" "${args[@]}"
}

main() {
  local command_name="${1:-install}"
  case "$command_name" in
    install)
      shift || true
      parse_install_args "$@"
      if is_repo_checkout; then
        run_local_install
      else
        bootstrap_repo
      fi
      ;;
    help|-h|--help)
      usage
      ;;
    internal-print-mihomo-asset)
      echo "$(resolve_mihomo_asset)"
      ;;
    *)
      die "Unknown command: $command_name"
      ;;
  esac
}

main "$@"

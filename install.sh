#!/usr/bin/env bash
# One-click installer for Claude Code (Linux / macOS).
# - Detects OS + architecture
# - Detects whether you're on a China IP and, if so, uses mirror sources
# - Installs Node.js (direct binary download, mirror-supported) if it's missing
# - Installs @anthropic-ai/claude-code globally via npm
set -euo pipefail

PKG="@anthropic-ai/claude-code"
MIN_NODE_MAJOR=18
NPM_MIRROR="https://registry.npmmirror.com"
NODE_DIST="https://nodejs.org/dist"
NODE_MIRROR="https://npmmirror.com/mirrors/node"
NODE_INST_DIR="$HOME/.local/node"

info()  { printf '\033[0;34m[*]\033[0m %s\n' "$*"; }
ok()    { printf '\033[0;32m[+]\033[0m %s\n' "$*"; }
warn()  { printf '\033[0;33m[!]\033[0m %s\n' "$*"; }
err()   { printf '\033[0;31m[x]\033[0m %s\n' "$*" >&2; }
die()   { err "$*"; exit 1; }

# --- detect OS ---------------------------------------------------------------
detect_os() {
  local u; u="$(uname -s)"
  case "$u" in
    Linux*)  OS="linux" ;;
    Darwin*) OS="darwin" ;;
    *) die "Unsupported OS: $u (this script handles Linux/macOS; use install.ps1 on Windows)" ;;
  esac
}

# --- detect architecture -----------------------------------------------------
detect_arch() {
  local m; m="$(uname -m)"
  case "$m" in
    x86_64|amd64)  ARCH="x64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    armv7l)        ARCH="armv7l" ;;
    *) ARCH="$m"; warn "Unrecognized architecture '$m' — continuing anyway." ;;
  esac
}

# --- detect China IP ---------------------------------------------------------
is_china() {
  local loc country
  loc="$(curl -fsS --max-time 3 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null \
        | sed -n 's/^loc=//p' || true)"
  if [ -n "$loc" ]; then
    [ "$loc" = "CN" ] && return 0 || return 1
  fi
  country="$(curl -fsS --max-time 3 https://ipinfo.io/country 2>/dev/null | tr -d '[:space:]' || true)"
  if [ -n "$country" ]; then
    [ "$country" = "CN" ] && return 0 || return 1
  fi
  if ! curl -fsS --max-time 2 -o /dev/null https://www.google.com 2>/dev/null \
     && curl -fsS --max-time 2 -o /dev/null "$NPM_MIRROR" 2>/dev/null; then
    return 0
  fi
  return 1
}

# --- node version check ------------------------------------------------------
node_ok() {
  command -v node >/dev/null 2>&1 || return 1
  local major
  major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  [ "$major" -ge "$MIN_NODE_MAJOR" ] 2>/dev/null
}

# --- get latest LTS version --------------------------------------------------
get_lts_version() {
  local base_url
  base_url="$([ "$CHINA" = "1" ] && echo "$NODE_MIRROR" || echo "$NODE_DIST")"
  local json
  json="$(curl -fsS --max-time 10 "$base_url/index.json" 2>/dev/null || true)"
  if [ -z "$json" ]; then
    die "Failed to fetch Node.js LTS version from $base_url/index.json."
  fi
  # Parse index.json: find first entry with a non-empty lts field, extract version
  local ver
  ver="$(echo "$json" | grep -o '"version":"v[^"]*"' | head -20 | while read -r line; do
    # We need to check if the corresponding lts field is non-empty.
    # Simpler approach: use awk/sed to find objects with lts != false/""
    echo "$line"
  done)"
  # More robust: use python if available, otherwise awk
  if command -v python3 >/dev/null 2>&1; then
    ver="$(python3 -c "import json,sys; d=json.load(sys.stdin); v=[x for x in d if x.get('lts') and x['lts']!=False]; print(v[0]['version'] if v else '')" <<< "$json")"
  elif command -v python >/dev/null 2>&1; then
    ver="$(python -c "import json,sys; d=json.load(sys.stdin); v=[x for x in d if x.get('lts') and x['lts']!=False]; print(v[0]['version'] if v else '')" <<< "$json")"
  else
    # Fallback: awk-based parsing
    ver="$(awk 'BEGIN{RS="}"; FS="\""} {for(i=1;i<=NF;i++) if($i=="lts"){lts=$(i+2)} if($i=="version"){ver=$(i+2)} if(lts!="" && lts!="false" && ver!=""){print ver; exit}}' <<< "$json")"
  fi
  [ -n "$ver" ] || die "Failed to parse LTS version from index.json."
  echo "$ver"
}

# --- install node via direct binary download ---------------------------------
install_node() {
  info "Node.js >= $MIN_NODE_MAJOR not found. Downloading and installing..."

  if ! command -v curl >/dev/null 2>&1; then
    die "curl is required. Install curl, or install Node $MIN_NODE_MAJOR+ manually, then re-run."
  fi

  local ver base_url tar_name tar_url tar_path
  ver="$(get_lts_version)"
  base_url="$([ "$CHINA" = "1" ] && echo "$NODE_MIRROR" || echo "$NODE_DIST")"

  # Build tar filename: node-v22.16.0-linux-x64.tar.xz (or darwin-arm64 etc.)
  local arch_suffix="$ARCH"
  # macOS uses "darwin" as OS string in Node filenames
  tar_name="node-${ver}-${OS}-${arch_suffix}.tar.xz"
  tar_url="${base_url}/${ver}/${tar_name}"
  tar_path="/tmp/${tar_name}"

  info "Downloading $tar_url ..."
  curl -fsSL --max-time 120 -o "$tar_path" "$tar_url" \
    || die "Failed to download Node.js from $tar_url. Install Node $MIN_NODE_MAJOR+ manually and re-run."

  # Extract: the tar contains a single folder like node-v22.16.0-linux-x64
  info "Extracting to $NODE_INST_DIR ..."
  if [ -d "$NODE_INST_DIR" ]; then rm -rf "$NODE_INST_DIR"; fi
  mkdir -p "$NODE_INST_DIR"
  tar -xJf "$tar_path" -C "$NODE_INST_DIR" --strip-components=1
  rm -f "$tar_path"

  # Add to PATH (permanent via profile + current session)
  local profile_file
  for profile_file in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [ -f "$profile_file" ]; then
      if ! grep -q "$NODE_INST_DIR/bin" "$profile_file" 2>/dev/null; then
        printf '\n# Added by Claude Code installer\nexport PATH="%s/bin:$PATH"\n' "$NODE_INST_DIR" >> "$profile_file"
        info "Added PATH to $profile_file"
      fi
    fi
  done
  export PATH="$NODE_INST_DIR/bin:$PATH"

  node_ok || die "Node.js still not available after install. Open a new shell and re-run."
  ok "Node.js installed: $(node -v)"
}

# --- main --------------------------------------------------------------------
main() {
  detect_os
  detect_arch
  info "Platform: $OS/$ARCH"

  if command -v claude >/dev/null 2>&1; then
    ok "Claude Code already installed: $(claude --version 2>/dev/null || echo 'present')"
    info "Nothing to do. To upgrade, run: npm update -g $PKG"
    exit 0
  fi

  if is_china; then CHINA=1; else CHINA=0; fi
  if [ "$CHINA" = "1" ]; then
    ok "China IP detected — using mirror sources."
  else
    info "Non-China IP (or undetermined) — using default sources."
  fi

  if node_ok; then
    ok "Node.js present: $(node -v)"
  else
    install_node
  fi

  command -v npm >/dev/null 2>&1 || die "npm not found even though Node is installed. Re-open your shell and re-run."

  local reg_args=()
  if [ "$CHINA" = "1" ]; then
    reg_args=(--registry "$NPM_MIRROR")
    info "Installing $PKG via npmmirror registry..."
  else
    info "Installing $PKG via default npm registry..."
  fi

  if npm install -g "$PKG" "${reg_args[@]}"; then
    :
  else
    die "npm install failed. If it's a permissions error, see https://docs.npmjs.com/cli/v10/using-npm/resolving-eacces-permissions-errors-when-installing-packages-globally"
  fi

  if command -v claude >/dev/null 2>&1; then
    ok "Done. Installed: $(claude --version 2>/dev/null || echo "$PKG")"
    info "Run 'claude' to get started."
  else
    ok "Package installed."
    warn "'claude' isn't on PATH yet — open a new terminal, then run: claude"
  fi
}

main "$@"

#!/usr/bin/env bash
# One-click installer for Claude Code (Linux / macOS).
# - Detects OS + architecture
# - Detects whether you're on a China IP and, if so, uses mirror sources
# - Installs Node.js (via fnm) if it's missing
# - Installs @anthropic-ai/claude-code globally via npm
set -euo pipefail

PKG="@anthropic-ai/claude-code"
MIN_NODE_MAJOR=18
NPM_MIRROR="https://registry.npmmirror.com"
NODE_DIST_MIRROR="https://npmmirror.com/mirrors/node"
FNM_INSTALL_URL="https://fnm.vercel.app/install"

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
    Darwin*) OS="macos" ;;
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
    *) ARCH="$m"; warn "Unrecognized architecture '$m' — continuing, fnm/npm will pick the right binary." ;;
  esac
}

# --- detect China IP ---------------------------------------------------------
# Returns 0 (true) if we appear to be on a China IP. Network probes with short
# timeouts; defaults to NOT-China if every probe is inconclusive.
is_china() {
  local loc country
  # Probe 1: Cloudflare trace (fast, returns loc=XX)
  loc="$(curl -fsS --max-time 3 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null \
        | sed -n 's/^loc=//p' || true)"
  if [ -n "$loc" ]; then
    [ "$loc" = "CN" ] && return 0 || return 1
  fi
  # Probe 2: ipinfo country
  country="$(curl -fsS --max-time 3 https://ipinfo.io/country 2>/dev/null | tr -d '[:space:]' || true)"
  if [ -n "$country" ]; then
    [ "$country" = "CN" ] && return 0 || return 1
  fi
  # Probe 3: mirror-vs-google reachability heuristic
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

# --- install node via fnm ----------------------------------------------------
install_node() {
  info "Node.js >= $MIN_NODE_MAJOR not found. Installing via fnm..."

  if ! command -v curl >/dev/null 2>&1; then
    die "curl is required to install Node.js automatically. Install curl, or install Node $MIN_NODE_MAJOR+ manually, then re-run."
  fi

  if [ "$CHINA" = "1" ]; then
    export FNM_NODE_DIST_MIRROR="$NODE_DIST_MIRROR"
    info "China mirror enabled for Node downloads: $FNM_NODE_DIST_MIRROR"
  fi

  if ! command -v fnm >/dev/null 2>&1; then
    curl -fsSL "$FNM_INSTALL_URL" | bash
    export PATH="$HOME/.local/share/fnm:$HOME/.fnm:$PATH"
    eval "$(fnm env 2>/dev/null || true)"
  fi

  command -v fnm >/dev/null 2>&1 || die "fnm install failed. Install Node $MIN_NODE_MAJOR+ manually and re-run."

  fnm install --lts
  fnm use --lts || fnm use lts-latest || true
  eval "$(fnm env 2>/dev/null || true)"

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
    die "npm install failed. If it's a permissions error, see https://docs.npmjs.com/resolving-eacces-permissions-errors"
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

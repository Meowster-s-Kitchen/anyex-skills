#!/usr/bin/env bash
# AnyEx Polymarket — Claude Code skill installer
#
# Installs:
#   1. kpass (Kite Passport CLI) — if not already present
#   2. The Anyex-prediction-market-delegate-with-KiteAI skill into
#      ~/.claude/skills/
#   3. (optional) registers the AnyEx MCP server in Claude Desktop config
#
# Usage:
#   curl -fsSL https://install.anyex.ai/polymarket | bash
#
# Env overrides:
#   ANYEX_SKILL_REPO_RAW   — raw GitHub URL for the skill files
#                            (default: https://raw.githubusercontent.com/Meowster-s-Kitchen/anyex-skills/main)
#   ANYEX_MCP_URL          — MCP server URL (default https://mcp.anyex.ai/anyex/v1/mcp/kite)
#   ANYEX_SKIP_KPASS       — set to 1 to skip kpass install
#   ANYEX_SKIP_MCP         — set to 1 to skip Claude Desktop MCP registration prompt
#   ANYEX_NONINTERACTIVE   — set to 1 to never prompt (skips MCP registration)

set -euo pipefail

SKILL_NAME="Anyex-prediction-market-delegate-with-KiteAI"
SKILL_DIR="$HOME/.claude/skills/$SKILL_NAME"
REPO_RAW="${ANYEX_SKILL_REPO_RAW:-https://raw.githubusercontent.com/Meowster-s-Kitchen/anyex-skills/main}"
MCP_URL="${ANYEX_MCP_URL:-https://mcp.anyex.ai/anyex/v1/mcp/kite}"
KPASS_INSTALL_URL="https://install.kite.ai"

# ── Output helpers ──────────────────────────────────────────────────────────
c_reset='\033[0m'; c_dim='\033[2m'; c_bold='\033[1m'
c_green='\033[32m'; c_yellow='\033[33m'; c_red='\033[31m'; c_blue='\033[34m'
say() { printf "%b\n" "$*"; }
ok()  { say "${c_green}✓${c_reset} $*"; }
warn(){ say "${c_yellow}!${c_reset} $*"; }
err() { say "${c_red}✗${c_reset} $*" 1>&2; }
hdr() { say ""; say "${c_bold}${c_blue}▸${c_reset} ${c_bold}$*${c_reset}"; }

# Detect interactive shell (curl|bash gives us a non-tty stdin)
IS_TTY=0
[ -t 0 ] && IS_TTY=1
[ "${ANYEX_NONINTERACTIVE:-0}" = "1" ] && IS_TTY=0

prompt_yn() {
  local prompt="$1" default="${2:-N}" ans=""
  if [ "$IS_TTY" != "1" ]; then echo "$default"; return; fi
  # Read from /dev/tty so we work under `curl | bash`
  read -rp "$prompt " ans < /dev/tty || ans="$default"
  echo "${ans:-$default}"
}

# ── Platform detection ──────────────────────────────────────────────────────
OS="$(uname -s)"
case "$OS" in
  Darwin|Linux) ;;
  *)
    err "Unsupported OS: $OS (this installer supports macOS and Linux)."
    err "Windows users: install kpass manually from https://install.kite.ai, then download"
    err "$REPO_RAW/$SKILL_NAME/SKILL.md into %USERPROFILE%\\.claude\\skills\\$SKILL_NAME\\"
    exit 1
    ;;
esac

# ── Sanity checks ───────────────────────────────────────────────────────────
for cmd in curl mkdir; do
  command -v "$cmd" >/dev/null 2>&1 || { err "Required command '$cmd' not found in PATH."; exit 1; }
done

hdr "AnyEx Polymarket — Claude Code skill installer"
say "${c_dim}Repo:   $REPO_RAW${c_reset}"
say "${c_dim}Target: $SKILL_DIR${c_reset}"

# ── 1. kpass (Kite Passport CLI) ────────────────────────────────────────────
hdr "Step 1/3 — kpass (Kite Passport CLI)"
if [ "${ANYEX_SKIP_KPASS:-0}" = "1" ]; then
  warn "ANYEX_SKIP_KPASS=1 — skipping kpass install/check"
elif command -v kpass >/dev/null 2>&1; then
  ok "kpass already installed: $(kpass --version 2>/dev/null | head -1)"
else
  warn "kpass not found in PATH. Installing from $KPASS_INSTALL_URL ..."
  if ! curl -fsSL "$KPASS_INSTALL_URL" | bash; then
    err "kpass install failed. See https://docs.gokite.ai/passport for manual instructions."
    exit 1
  fi
  # The kpass installer typically drops the binary under ~/.local/bin
  export PATH="$HOME/.local/bin:$PATH"
  if command -v kpass >/dev/null 2>&1; then
    ok "kpass installed: $(kpass --version 2>/dev/null | head -1)"
  else
    err "kpass installer finished but 'kpass' is still not on PATH."
    err "Add \$HOME/.local/bin to PATH and retry."
    exit 1
  fi
fi

# ── 2. Skill file ───────────────────────────────────────────────────────────
hdr "Step 2/3 — Claude Code skill"
mkdir -p "$SKILL_DIR"
SKILL_URL="$REPO_RAW/$SKILL_NAME/SKILL.md"
if curl -fsSL "$SKILL_URL" -o "$SKILL_DIR/SKILL.md"; then
  ok "Skill installed: $SKILL_DIR/SKILL.md"
else
  err "Failed to download $SKILL_URL"
  exit 1
fi

# ── 3. MCP server registration (optional, Claude Desktop only) ──────────────
hdr "Step 3/3 — Claude Desktop MCP server (optional)"

CONFIG=""
case "$OS" in
  Darwin) CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json" ;;
  Linux)  CONFIG="$HOME/.config/Claude/claude_desktop_config.json" ;;
esac

if [ "${ANYEX_SKIP_MCP:-0}" = "1" ]; then
  warn "ANYEX_SKIP_MCP=1 — skipping MCP registration"
elif [ ! -f "$CONFIG" ]; then
  warn "Claude Desktop config not found at: $CONFIG"
  say "${c_dim}  (skipping; Claude Code CLI users don't need this.)${c_reset}"
elif grep -q '"anyex-kite"' "$CONFIG"; then
  ok "anyex-kite MCP server already registered in $(basename "$CONFIG")"
else
  ans="$(prompt_yn "Register the AnyEx MCP server (anyex-kite) in Claude Desktop? [y/N]" "N")"
  case "$ans" in
    [Yy]*)
      if command -v jq >/dev/null 2>&1; then
        tmp="$(mktemp)"
        jq --arg url "$MCP_URL" \
          '(.mcpServers // {}) as $m | .mcpServers = ($m + {"anyex-kite": {type:"http", url:$url}})' \
          "$CONFIG" > "$tmp" && mv "$tmp" "$CONFIG"
        ok "Added anyex-kite to $CONFIG"
        warn "Restart Claude Desktop to load the new MCP server."
      else
        warn "'jq' not installed — skipping automatic registration."
        say "  Add this to $CONFIG manually:"
        printf '%s\n' '    "mcpServers": {'
        printf '%s\n' '      "anyex-kite": {'
        printf '%s\n' '        "type": "http",'
        printf '%s\n' "        \"url\": \"$MCP_URL\""
        printf '%s\n' '      }'
        printf '%s\n' '    }'
      fi
      ;;
    *) warn "Skipped MCP registration." ;;
  esac
fi

# ── Next steps card ─────────────────────────────────────────────────────────
say ""
say "${c_bold}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${c_reset}"
say "${c_bold}🎯 AnyEx Polymarket — installed${c_reset}"
say "${c_bold}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${c_reset}"
say ""
say "${c_bold}Next steps${c_reset}"
say ""
say "  ${c_bold}1.${c_reset} Sign in to Kite Passport (one-time)"
say "       ${c_dim}kpass signup init --email you@example.com${c_reset}"
say "       ${c_dim}# or, if you already have an account:${c_reset}"
say "       ${c_dim}kpass login init --email you@example.com${c_reset}"
say ""
say "  ${c_bold}2.${c_reset} Fund your Kite wallet with USDC.e on Kite mainnet (chain 2366)"
say "       ${c_dim}kpass wallet balance${c_reset}  # shows your wallet address"
say "       ${c_dim}# Bridge USDC.e from Polygon, or use a Kite ramp${c_reset}"
say ""
say "  ${c_bold}3.${c_reset} In Claude, try:"
say "       ${c_dim}\"Buy me \$5 of Polymarket YES on <a live market>\"${c_reset}"
say ""
say "${c_bold}Costs to expect${c_reset}"
say "  ${c_dim}• One-time DepositWallet setup:${c_reset}  ~\$0.05 USDC"
say "  ${c_dim}• Per BUY:${c_reset}                      order amount + Polymarket fee"
say "  ${c_dim}• Per SELL:${c_reset}                     ~\$0.01 flat"
say ""
say "${c_bold}Docs${c_reset}  ${c_dim}https://anyex.ai/polymarket${c_reset}"
say "${c_bold}Issues${c_reset} ${c_dim}https://github.com/Meowster-s-Kitchen/anyex-skills/issues${c_reset}"
say ""

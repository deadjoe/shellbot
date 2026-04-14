#!/usr/bin/env bash
SHELLBOT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELLBOT_VERSION="0.2.0"

# ===== API =====
OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"
OPENROUTER_BASE_URL="${OPENROUTER_BASE_URL:-https://openrouter.ai/api/v1}"
DEFAULT_MODEL="${DEFAULT_MODEL:-deepseek/deepseek-chat-v3-0324}"

# ===== Tavily =====
TAVILY_API_KEY="${TAVILY_API_KEY:-}"

# ===== JINA Reader =====
JINA_API_KEY="${JINA_API_KEY:-}"

# ===== Red Hat SSO =====
RH_USERNAME="${RH_USERNAME:-}"
RH_PASSWORD="${RH_PASSWORD:-}"
RH_COOKIE_JAR="${RH_COOKIE_JAR:-$HOME/.shellbot/rh_cookies.jar}"
RH_SSO_BASE="https://sso.redhat.com/auth/realms/redhat-external"
RH_PORTAL_BASE="https://access.redhat.com"

# ===== Loop Control =====
REACT_MAX_ITERATIONS="${REACT_MAX_ITERATIONS:-8}"
LOOP_MAX_ITERATIONS="${LOOP_MAX_ITERATIONS:-10}"
API_TIMEOUT="${API_TIMEOUT:-120}"
TOOL_TIMEOUT="${TOOL_TIMEOUT:-60}"
API_MAX_RETRIES="${API_MAX_RETRIES:-3}"

# ===== Security =====
SHELL_CONFIRM="${SHELL_CONFIRM:-auto}"
SHELL_DANGEROUS_PATTERNS="rm -rf |rm -f /|mkfs|dd if=|> /dev/sd|shutdown|reboot|init 0|init 6|:(){:|:&};:|chmod -R 777 /|chown -R|passwd|userdel|groupdel"

# ===== Data =====

SHELLBOT_DATA_DIR="${SHELLBOT_DATA_DIR:-$HOME/.shellbot}"
HISTORY_FILE="$SHELLBOT_DATA_DIR/history.json"
CONTEXT_FILE="$SHELLBOT_DATA_DIR/context.json"

MEMORY_DB="$SHELLBOT_DATA_DIR/memories.db"
HISTORY_COMPRESS_THRESHOLD="${HISTORY_COMPRESS_THRESHOLD:-30000}"
HISTORY_COMPRESS_KEEP="${HISTORY_COMPRESS_KEEP:-10}"


# ===== Load .env =====
load_env() {
  local env_file="${1:-$SHELLBOT_DATA_DIR/.env}"
  if [ -f "$env_file" ]; then
    while IFS='=' read -r key value; do
      [[ "$key" =~ ^#.*$ ]] && continue
      [[ -z "$key" ]] && continue
      value="${value%\"}" value="${value#\"}"
      value="${value%\'}" value="${value#\'}"
      export "$key=$value"
    done < "$env_file"
  fi
}

# ===== Load from macOS Keychain =====
load_keychain() {
  local key label
  for label in openrouter tavily jina rh; do
    key=$(security find-generic-password -s "shellbot-$label" -w 2>/dev/null) || continue
    case "$label" in
      openrouter) [ -z "$OPENROUTER_API_KEY" ] && OPENROUTER_API_KEY="$key" ;;
      tavily)     [ -z "$TAVILY_API_KEY" ]     && TAVILY_API_KEY="$key" ;;
      jina)       [ -z "$JINA_API_KEY" ]       && JINA_API_KEY="$key" ;;
      rh)         [ -z "$RH_PASSWORD" ]        && RH_PASSWORD="$key" ;;
    esac
  done
}

# ===== Init =====
config_init() {
  mkdir -p "$SHELLBOT_DATA_DIR"
  load_env
  load_keychain
  export OPENROUTER_API_KEY TAVILY_API_KEY JINA_API_KEY RH_USERNAME RH_PASSWORD
}

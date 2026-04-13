#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"

history_init() {
  mkdir -p "$(dirname "$HISTORY_FILE")"
  [ -f "$HISTORY_FILE" ] || > "$HISTORY_FILE"
}

history_append() {
  local role="$1"
  local content="$2"
  jq -n --arg role "$role" --arg content "$content" \
    --argjson ts "$(date +%s)" \
    '{role: $role, content: $content, timestamp: $ts}' \
    >> "$HISTORY_FILE"
}

history_get_messages() {
  local limit="${1:-20}"
  tail -n "$limit" "$HISTORY_FILE" | jq -s 'map({role: .role, content: .content})'
}

history_get_messages_trimmed() {
  local max_chars="${1:-30000}"
  local messages
  messages=$(history_get_messages 50)

  local total_chars
  total_chars=$(echo "$messages" | jq '[.[].content | length] | add // 0')

  if [ "$total_chars" -gt "$max_chars" ]; then
    echo "$messages" | jq 'if length > 10 then .[-10:] else . end'
  else
    echo "$messages"
  fi
}

history_clear() {
  > "$HISTORY_FILE"
}

history_count() {
  wc -l < "$HISTORY_FILE" | tr -d ' '
}

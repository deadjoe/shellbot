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

# Calculate total character count of history messages
history_total_chars() {
  if [ ! -f "$HISTORY_FILE" ] || [ ! -s "$HISTORY_FILE" ]; then
    echo 0
    return
  fi
  tail -n 100 "$HISTORY_FILE" | jq -s '[.[].content | length] | add // 0'
}

# Compress history: summarize early messages, keep recent ones
history_compress() {
  local keep="${1:-$HISTORY_COMPRESS_KEEP}"
  local threshold="${2:-$HISTORY_COMPRESS_THRESHOLD}"

  local total
  total=$(history_total_chars)

  if [ "$total" -lt "$threshold" ]; then
    return 0  # No compression needed
  fi

  # Load compressor lazily (avoids circular source)
  source "$SHELLBOT_HOME/lib/compressor.sh"
  source "$SHELLBOT_HOME/lib/ui.sh"

  ui_info "Compressing conversation history (${total} chars)..."

  # Read all messages
  local all_messages
  all_messages=$(history_get_messages 1000)
  local total_count
  total_count=$(echo "$all_messages" | jq 'length')

  if [ "$total_count" -le "$keep" ]; then
    return 0  # Not enough messages to compress
  fi

  # Split: early messages for summarization, keep recent ones
  local early_messages
  early_messages=$(echo "$all_messages" | jq --argjson keep "$keep" '.[:-($keep)]')

  local recent_messages
  recent_messages=$(echo "$all_messages" | jq --argjson keep "$keep" '.[-($keep):]')

  # Summarize early messages via LLM
  local summary
  summary=$(compress_summarize "$early_messages")

  if [ -z "$summary" ]; then
    ui_warning "Compression failed: could not generate summary"
    return 1
  fi

  # Rebuild history file: summary + recent messages
  > "$HISTORY_FILE"

  # Write summary as a system message
  jq -nc --arg content "[Summary of earlier conversation] $summary" \
    --argjson ts "$(date +%s)" \
    '{role: "system", content: $content, timestamp: $ts}' >> "$HISTORY_FILE"

  # Write recent messages
  echo "$recent_messages" | jq -c '.[]' | while IFS= read -r msg; do
    echo "$msg" >> "$HISTORY_FILE"
  done

  ui_success "History compressed: $total_count messages → summary + $keep recent"
  return 0
}

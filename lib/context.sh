#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"

context_init() {
  local goal="$1"
  jq -n --arg goal "$goal" \
    '{goal: $goal, steps: [], iteration: 0}' \
    > "$CONTEXT_FILE"
}

context_record_step() {
  local step="$1"
  local rationale="${2:-}"

  local current
  current=$(cat "$CONTEXT_FILE" 2>/dev/null || echo '{}')
  local next_id
  next_id=$(echo "$current" | jq '.steps | length + 1')

  echo "$current" | jq \
    --arg step "$step" \
    --arg rationale "$rationale" \
    --argjson id "$next_id" \
    --argjson iter "$(($(echo "$current" | jq '.iteration') + 1))" \
    '.steps += [{id: $id, step: $step, rationale: $rationale}] |
     .iteration = $iter' \
    > "$CONTEXT_FILE"
}

context_summary() {
  if [ ! -f "$CONTEXT_FILE" ]; then
    echo ""
    return
  fi
  jq -r '
    "Goal: \(.goal)\n" +
    "Steps:\n" +
    (.steps | map("  [\(.id)] \(.step)\(if .rationale then " — \(.rationale)" else "" end)") | join("\n"))
  ' "$CONTEXT_FILE" 2>/dev/null
}

context_is_done() {
  [ ! -f "$CONTEXT_FILE" ] && return 1
  local total
  total=$(jq '.steps | length' "$CONTEXT_FILE")
  [ "$total" -eq 0 ] && return 1
  return 0
}

context_clear() {
  rm -f "$CONTEXT_FILE"
}

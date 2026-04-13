#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"

context_init() {
  local goal="$1"
  jq -n --arg goal "$goal" \
    '{goal: $goal, sub_goals: [], reflections: [], iteration: 0}' \
    > "$CONTEXT_FILE"
}

context_record() {
  local desc="$1"
  local result="$2"
  local status="${3:-done}"

  local current
  current=$(cat "$CONTEXT_FILE" 2>/dev/null || echo '{}')
  local next_id
  next_id=$(echo "$current" | jq '.sub_goals | length + 1')

  echo "$current" | jq \
    --arg desc "$desc" \
    --arg result "$result" \
    --arg status "$status" \
    --argjson id "$next_id" \
    --argjson iter "$(($(echo "$current" | jq '.iteration') + 1))" \
    '.sub_goals += [{id: $id, desc: $desc, status: $status, result: $result}] |
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
    "Sub-goals:\n" +
    (.sub_goals | map("  [\(.status)] \(.desc): \(.result // "pending")") | join("\n")) +
    (if (.reflections | length) > 0 then
      "\nReflections:\n" +
      (.reflections | map("  - \(.reason) -> \(.revised_approach)") | join("\n"))
    else "" end)
  ' "$CONTEXT_FILE" 2>/dev/null
}

context_record_reflection() {
  local reason="$1"
  local revised="$2"
  local failed_sub="$3"

  local current
  current=$(cat "$CONTEXT_FILE" 2>/dev/null || echo '{}')
  local iter
  iter=$(echo "$current" | jq '.iteration')

  echo "$current" | jq \
    --arg reason "$reason" \
    --arg revised "$revised" \
    --arg failed "$failed_sub" \
    --argjson iter "$iter" \
    '.reflections += [{iteration: $iter, failed_sub_goal: $failed, reason: $reason, revised_approach: $revised}]' \
    > "$CONTEXT_FILE"
}

context_is_done() {
  [ ! -f "$CONTEXT_FILE" ] && return 1
  local goal
  goal=$(jq -r '.goal' "$CONTEXT_FILE")
  local total
  total=$(jq '.sub_goals | length' "$CONTEXT_FILE")
  [ "$total" -eq 0 ] && return 1
  return 0
}

context_clear() {
  rm -f "$CONTEXT_FILE"
}

#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/api.sh"
source "$(dirname "${BASH_SOURCE[0]}")/context.sh"
source "$(dirname "${BASH_SOURCE[0]}")/ui.sh"

reflector_analyze() {
  local ctx
  ctx=$(context_summary)

  local last_sub_goal
  last_sub_goal=$(jq -r '.sub_goals[-1].desc // "unknown"' "$CONTEXT_FILE" 2>/dev/null)
  local last_result
  last_result=$(jq -r '.sub_goals[-1].result // "no result"' "$CONTEXT_FILE" 2>/dev/null)

  local prompt
  prompt="You are a reflection engine for a system operations agent. The following approach did not achieve the desired result:

Failed sub-goal: $last_sub_goal
Result: $last_result

$ctx

Analyze WHY this approach failed and suggest a different approach.
Output TWO lines:
Line 1: the reason for failure (starting with \"Reason: \")
Line 2: the revised approach (starting with \"Revised: \")"

  local messages
  messages=$(jq -n --arg prompt "$prompt" \
    '[{role: "user", content: $prompt}]')

  local result
  result=$(api_chat "$messages")
  if [ $? -ne 0 ]; then
    context_record_reflection "LLM call failed" "Retry the same sub-goal" "$last_sub_goal"
    return 1
  fi

  local reason
  reason=$(echo "$result" | awk '/^Reason:/ {sub(/^Reason:[[:space:]]*/, ""); print; exit}')
  local revised
  revised=$(echo "$result" | awk '/^Revised:/ {sub(/^Revised:[[:space:]]*/, ""); print; exit}')

  [ -z "$reason" ] && reason=$(echo "$result" | sed -n '1p')
  [ -z "$revised" ] && revised=$(echo "$result" | sed -n '2p')

  ui_info "Reflection: $reason"
  ui_info "Revised approach: $revised"

  context_record_reflection "$reason" "$revised" "$last_sub_goal"
}

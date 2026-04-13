#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/api.sh"
source "$(dirname "${BASH_SOURCE[0]}")/context.sh"
source "$(dirname "${BASH_SOURCE[0]}")/ui.sh"

planner_next_subgoal() {
  local ctx
  ctx=$(context_summary)

  local prompt
  prompt="You are a task planner for a system operations agent. Given the overall goal and completed sub-goals, determine the NEXT sub-goal to work on.

$ctx

Output ONLY the next sub-goal as a single line of text. If the overall goal is fully achieved, output exactly: DONE"

  local messages
  messages=$(jq -n --arg prompt "$prompt" \
    '[{role: "user", content: $prompt}]')

  local result
  result=$(api_chat "$messages")
  if [ $? -ne 0 ]; then
    echo "Error: Planner LLM call failed"
    return 1
  fi

  echo "$result" | head -5 | head -c 500
}

planner_evaluate() {
  local ctx
  ctx=$(context_summary)

  local prompt
  prompt="You are a task evaluator for a system operations agent. Given the overall goal and all results so far, determine if the task is complete.

$ctx

Output ONLY ONE of these single words:
- DONE (if the goal is fully achieved)
- CONTINUE (if more work is needed)
- REVISE (if the approach is failing and needs adjustment)"

  local messages
  messages=$(jq -n --arg prompt "$prompt" \
    '[{role: "user", content: $prompt}]')

  local result
  result=$(api_chat "$messages")
  if [ $? -ne 0 ]; then
    echo "CONTINUE"
    return 0
  fi

  local state
  state=$(echo "$result" | awk '{print $1}' | tr '[:lower:]' '[:upper:]')

  case "$state" in
    DONE|CONTINUE|REVISE) echo "$state" ;;
    *) echo "CONTINUE" ;;
  esac
}

planner_summarize() {
  local ctx
  ctx=$(context_summary)

  local prompt
  prompt="You are a summarizer for a system operations agent. Given the completed task results, provide a clear, structured final summary for the user.

$ctx

Provide a concise summary of findings, recommendations, and any action items. Use markdown formatting."

  local messages
  messages=$(jq -n --arg prompt "$prompt" \
    '[{role: "user", content: $prompt}]')

  local result
  result=$(api_chat "$messages")
  if [ $? -ne 0 ]; then
    echo "Task completed but summary generation failed. See sub-goal results above."
    return 0
  fi

  echo "$result"
}

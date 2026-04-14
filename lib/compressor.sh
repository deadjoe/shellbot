#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/api.sh"

# Compress messages by summarizing early ones
compress_summarize() {
  local messages="$1"

  local compress_prompt='Summarize the conversation above. Preserve:
- Key findings and discoveries
- Completed steps and their results
- User preferences and constraints
- Unresolved issues or errors
- Important context for continuing the task

Be concise. Output only the summary.'

  local request_messages
  request_messages=$(jq -n --argjson msgs "$messages" --arg prompt "$compress_prompt" \
    '$msgs + [{role: "user", content: $prompt}]')

  api_chat_simple "$request_messages"
}

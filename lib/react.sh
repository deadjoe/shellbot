#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/ui.sh"
source "$(dirname "${BASH_SOURCE[0]}")/api.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tools.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tools_schema.sh"
source "$(dirname "${BASH_SOURCE[0]}")/history.sh"
source "$SHELLBOT_HOME/prompts/system.sh"

# Build messages array for ReAct loop with function calling
build_react_messages() {
  local user_msg="$1"
  local context="${2:-}"

  local system_prompt
  system_prompt="$(prompt_system)"

  if [ -n "$context" ]; then
    system_prompt="$system_prompt

Current task context:
$context"
  fi

  local history_messages
  history_messages=$(history_get_messages_trimmed)

  local messages
  messages=$(jq -n --arg system "$system_prompt" \
    '[{role: "system", content: $system}]')

  if [ -n "$history_messages" ] && [ "$history_messages" != "null" ] && [ "$history_messages" != "[]" ]; then
    messages=$(echo "$messages" | jq --argjson hist "$history_messages" '. + $hist')
  fi

  messages=$(echo "$messages" | jq --arg user "$user_msg" '. + [{role: "user", content: $user}]')

  echo "$messages"
}

# Main ReAct loop using function calling
react_run() {
  local user_msg="$1"
  local context="${2:-}"
  local messages
  messages=$(build_react_messages "$user_msg" "$context")

  local tools_schema
  tools_schema=$(tools_get_schema)

  local iteration=0
  while [ $iteration -lt $REACT_MAX_ITERATIONS ]; do
    iteration=$((iteration + 1))
    ui_iteration "$iteration" "$REACT_MAX_ITERATIONS"
    ui_thinking

    local response api_exit
    if [ "$SHELLBOT_STREAM" = "true" ]; then
      response=$(api_chat_stream_with_tools "$messages" "$tools_schema")
      api_exit=$?
      ui_done_thinking
    else
      response=$(api_chat_with_tools "$messages" "$tools_schema")
      api_exit=$?
      ui_done_thinking
    fi

    if [ $api_exit -ne 0 ]; then
      echo "ERROR: LLM call failed"
      return 1
    fi

    # Extract content and tool_calls from response
    local content tool_calls

    if [ "$SHELLBOT_STREAM" = "true" ]; then
      content=$(echo "$response" | jq -r '.content // empty')
      tool_calls=$(echo "$response" | jq '.tool_calls // empty')
    else
      content=$(echo "$response" | jq -r '.choices[0].message.content // empty')
      tool_calls=$(echo "$response" | jq '.choices[0].message.tool_calls // empty')
    fi

    ui_debug "Content: ${content:0:100}"
    ui_debug "Tool calls: $tool_calls"

    # Check if there are tool calls
    local has_tool_calls=false
    if [ -n "$tool_calls" ] && [ "$tool_calls" != "null" ] && [ "$tool_calls" != "[]" ]; then
      has_tool_calls=true
    fi

    if [ "$has_tool_calls" = true ]; then
      # Process each tool call
      local assistant_msg
      if [ "$SHELLBOT_STREAM" = "true" ]; then
        assistant_msg=$(echo "$tool_calls" | jq \
          --arg content "$content" \
          '{role: "assistant", content: ($content // null), tool_calls: .}')
      else
        assistant_msg=$(echo "$response" | jq '.choices[0].message')
      fi

      messages=$(echo "$messages" | jq --argjson msg "$assistant_msg" '. + [$msg]')

      # Execute each tool call and append results
      local tc_count
      tc_count=$(echo "$tool_calls" | jq 'length')
      local tc_idx=0

      while [ $tc_idx -lt $tc_count ]; do
        local tc_id tc_name tc_args
        tc_id=$(echo "$tool_calls" | jq -r ".[$tc_idx].id")
        tc_name=$(echo "$tool_calls" | jq -r ".[$tc_idx].function.name")
        tc_args=$(echo "$tool_calls" | jq -r ".[$tc_idx].function.arguments")

        # Show what the agent is doing
        ui_action "$tc_name" "$tc_args"

        # Parse arguments using shared function
        local tool_input
        tool_input=$(parse_tool_input "$tc_name" "$tc_args")

        # Execute tool
        local obs
        obs=$(tool_execute "$tc_name" "$tool_input" 2>&1)
        local tool_exit=$?

        if [ $tool_exit -ne 0 ] && [ -z "$obs" ]; then
          obs="Error: Tool '$tc_name' failed with exit code $tool_exit"
        fi

        ui_observation "$obs"

        # Append tool result message
        messages=$(echo "$messages" | jq \
          --arg tc_id "$tc_id" \
          --arg obs "$obs" \
          '. + [{role: "tool", tool_call_id: $tc_id, content: $obs}]')

        tc_idx=$((tc_idx + 1))
      done

    elif [ -n "$content" ]; then
      # No tool calls, has content → Final Answer
      ui_final "$content"
      history_append "user" "$user_msg"
      history_append "assistant" "$content"
      return 0
    else
      # No content and no tool calls — shouldn't happen, treat as final
      ui_warning "Empty response from LLM"
      return 1
    fi
  done

  ui_warning "Reached max ReAct iterations ($REACT_MAX_ITERATIONS)"
  return 2
}

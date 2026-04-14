#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/ui.sh"
source "$(dirname "${BASH_SOURCE[0]}")/api.sh"
source "$(dirname "${BASH_SOURCE[0]}")/context.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tools.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tools_schema.sh"
source "$(dirname "${BASH_SOURCE[0]}")/history.sh"
source "$(dirname "${BASH_SOURCE[0]}")/memory.sh"
source "$SHELLBOT_HOME/prompts/loop_system.sh"

LOOP_SKIP_REQUESTED=false
LOOP_STOP_REQUESTED=false

loop_skip() {
  LOOP_SKIP_REQUESTED=true
}

loop_stop() {
  LOOP_STOP_REQUESTED=true
}

# Build initial messages for loop mode with goal as system prompt
build_loop_messages() {
  local goal="$1"

  local system_prompt
  system_prompt="$(prompt_loop_system "$goal")"

  # Inject relevant memories
  local mem_context
  mem_context=$(memory_prefetch "$goal")
  if [ -n "$mem_context" ]; then
    system_prompt="$system_prompt

$mem_context"
  fi

  local messages
  messages=$(jq -n --arg system "$system_prompt" \
    '[{role: "system", content: $system}]')

  echo "$messages"
}

# Main loop — single conversation flow with plan_step
loop_run() {
  local goal="$1"

  context_init "$goal"
  ui_goal "$goal"

  local messages
  messages=$(build_loop_messages "$goal")

  local tools_schema
  tools_schema=$(tools_get_schema)

  local iteration=0
  while [ $iteration -lt $LOOP_MAX_ITERATIONS ]; do
    if [ "$LOOP_STOP_REQUESTED" = true ]; then
      ui_info "Loop stopped by user"
      break
    fi

    iteration=$((iteration + 1))

    # Check if history needs compression
    history_compress

    ui_loop_header "$iteration" "$LOOP_MAX_ITERATIONS"
    LOOP_SKIP_REQUESTED=false

    # Call LLM with tools
    local response api_exit
    if [ "$SHELLBOT_STREAM" = "true" ]; then
      response=$(api_chat_stream_with_tools "$messages" "$tools_schema")
      api_exit=$?
    else
      response=$(api_chat_with_tools "$messages" "$tools_schema")
      api_exit=$?
    fi

    if [ $api_exit -ne 0 ]; then
      ui_error "LLM call failed"
      break
    fi

    # Extract content and tool_calls
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

    # Check for tool calls
    local has_tool_calls=false
    if [ -n "$tool_calls" ] && [ "$tool_calls" != "null" ] && [ "$tool_calls" != "[]" ]; then
      has_tool_calls=true
    fi

    if [ "$has_tool_calls" = true ]; then
      # Build assistant message and append to conversation
      local assistant_msg
      if [ "$SHELLBOT_STREAM" = "true" ]; then
        assistant_msg=$(echo "$tool_calls" | jq \
          --arg content "$content" \
          '{role: "assistant", content: ($content // null), tool_calls: .}')
      else
        assistant_msg=$(echo "$response" | jq '.choices[0].message')
      fi
      messages=$(echo "$messages" | jq --argjson msg "$assistant_msg" '. + [$msg]')

      # Execute each tool call
      local tc_count
      tc_count=$(echo "$tool_calls" | jq 'length')
      local tc_idx=0

      while [ $tc_idx -lt $tc_count ]; do
        local tc_id tc_name tc_args
        tc_id=$(echo "$tool_calls" | jq -r ".[$tc_idx].id")
        tc_name=$(echo "$tool_calls" | jq -r ".[$tc_idx].function.name")
        tc_args=$(echo "$tool_calls" | jq -r ".[$tc_idx].function.arguments")

        # Handle plan_step specially — record to context, return confirmation
        local obs
        if [ "$tc_name" = "plan_step" ]; then
          local step rationale
          step=$(echo "$tc_args" | jq -r '.step // empty')
          rationale=$(echo "$tc_args" | jq -r '.rationale // empty')
          context_record_step "$step" "$rationale"
          ui_plan_step "$step" "$rationale"
          obs="Step recorded. Now execute this step by calling the appropriate tool (e.g., run_shell, read_file). Do NOT just plan — take action."
        else
          # Regular tool execution
          ui_action "$tc_name" "$tc_args"

          local tool_input
          tool_input=$(parse_tool_input "$tc_name" "$tc_args")

          obs=$(tool_execute "$tc_name" "$tool_input" 2>&1)
          local tool_exit=$?
          if [ $tool_exit -ne 0 ] && [ -z "$obs" ]; then
            obs="Error: Tool '$tc_name' failed with exit code $tool_exit"
          fi
          ui_observation "$obs"
        fi

        # Append tool result to messages
        messages=$(echo "$messages" | jq \
          --arg tc_id "$tc_id" \
          --arg obs "$obs" \
          '. + [{role: "tool", tool_call_id: $tc_id, content: $obs}]')

        tc_idx=$((tc_idx + 1))
      done

      # Check skip/stop after tool execution
      if [ "$LOOP_SKIP_REQUESTED" = true ]; then
        ui_info "Skipping remaining work on this step"
        continue
      fi

    elif [ -n "$content" ]; then
      # No tool calls → Final Answer
      ui_loop_done
      ui_final "$content"
      history_append "user" "$goal"
      history_append "assistant" "$content"
      return 0
    else
      ui_warning "Empty response from LLM"
      break
    fi
  done

  # Loop ended without final answer
  ui_loop_timeout
  local partial
  partial=$(context_summary)
  ui_final "Partial results:\n$partial"
  return 2
}

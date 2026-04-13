#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/ui.sh"
source "$(dirname "${BASH_SOURCE[0]}")/api.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tools.sh"
source "$(dirname "${BASH_SOURCE[0]}")/history.sh"
source "$SHELLBOT_HOME/prompts/system.sh"
source "$SHELLBOT_HOME/prompts/react_format.sh"
source "$SHELLBOT_HOME/prompts/tools_desc.sh"

react_parse() {
  local response="$1"

  local final_answer
  final_answer=$(echo "$response" | awk '/^[Ff]inal [Aa]nswer:/ {sub(/^[Ff]inal [Aa]nswer:[[:space:]]*/, ""); print; exit}')

  if [ -n "$final_answer" ]; then
    echo "FINAL"
    echo "$final_answer"
    return 0
  fi

  local thought=""
  local action=""
  local action_input=""

  local in_thought=false
  local in_action=false
  local in_action_input=false

  while IFS= read -r line; do
    if [[ "$line" =~ ^[Tt]hought:[[:space:]]*(.*) ]]; then
      thought="${BASH_REMATCH[1]}"
      in_thought=true
      in_action=false
      in_action_input=false
    elif [[ "$line" =~ ^[Aa]ction\ [Ii]nput:[[:space:]]*(.*) ]]; then
      action_input="${BASH_REMATCH[1]}"
      in_thought=false
      in_action=false
      in_action_input=true
    elif [[ "$line" =~ ^[Aa]ction:[[:space:]]*(.*) ]]; then
      local captured="${BASH_REMATCH[1]}"
      if [[ "$captured" =~ ^(.*)[Aa]ction\ [Ii]nput:[[:space:]]*(.*) ]]; then
        action="${BASH_REMATCH[1]}"
        action="$(echo "$action" | sed 's/[[:space:]]*$//')"
        action_input="${BASH_REMATCH[2]}"
      else
        action="$captured"
        action="$(echo "$action" | sed 's/[[:space:]]*$//')"
      fi
      in_thought=false
      in_action=false
      in_action_input=true
    elif [ "$in_action_input" = true ] && [[ "$line" =~ ^[[:space:]]+(.*) ]]; then
      action_input="$action_input ${BASH_REMATCH[1]}"
    fi
  done <<< "$response"

  action_input="$(echo "$action_input" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  if [ -z "$action" ]; then
    echo "FINAL"
    echo "$response"
    return 0
  fi

  echo "ACTION"
  echo "$thought"
  echo "$action"
  echo "$action_input"
  return 0
}

build_react_messages() {
  local user_msg="$1"
  local context="${2:-}"

  local system_prompt
  system_prompt="$(prompt_system)

$(prompt_tools_desc)

$(prompt_react_format)"

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

react_run() {
  local user_msg="$1"
  local context="${2:-}"
  local messages
  messages=$(build_react_messages "$user_msg" "$context")

  local iteration=0
  while [ $iteration -lt $REACT_MAX_ITERATIONS ]; do
    iteration=$((iteration + 1))
    ui_iteration "$iteration" "$REACT_MAX_ITERATIONS"
    ui_thinking

    local llm_response api_exit
    if [ "$SHELLBOT_STREAM" = "true" ]; then
      llm_response=$(api_chat_stream "$messages")
      api_exit=$?
      ui_done_thinking
    else
      llm_response=$(api_chat "$messages")
      api_exit=$?
      ui_done_thinking
    fi

    if [ $api_exit -ne 0 ]; then
      echo "ERROR: LLM call failed"
      return 1
    fi

    ui_debug "LLM response: $llm_response"

    local parsed
    parsed=$(react_parse "$llm_response")
    local parse_type
    parse_type=$(echo "$parsed" | head -1)

    case "$parse_type" in
      FINAL)
        local answer
        answer=$(echo "$parsed" | tail -n +2)
        if [ "$SHELLBOT_STREAM" != "true" ]; then
          local thought_line
          thought_line=$(echo "$llm_response" | awk '/^[Tt]hought:/ {sub(/^[Tt]hought:[[:space:]]*/, ""); print; exit}')
          [ -n "$thought_line" ] && ui_thought "$thought_line"
        fi
        echo "" >&2
        ui_final "$answer"
        history_append "user" "$user_msg"
        history_append "assistant" "$answer"
        return 0
        ;;
      ACTION)
        local thought
        thought=$(echo "$parsed" | sed -n '2p')
        local action
        action=$(echo "$parsed" | sed -n '3p')
        local action_input
        action_input=$(echo "$parsed" | sed -n '4p')

        if [ "$SHELLBOT_STREAM" != "true" ]; then
          [ -n "$thought" ] && ui_thought "$thought"
          ui_action "$action" "$action_input"
        fi

        local obs
        obs=$(tool_execute "$action" "$action_input" 2>&1)
        local tool_exit=$?

        if [ $tool_exit -ne 0 ] && [ -z "$obs" ]; then
          obs="Error: Tool '$action' failed with exit code $tool_exit"
        fi

        obs="Observation: $obs"
        ui_observation "$obs"

        messages=$(echo "$messages" | jq \
          --arg assistant "$llm_response" \
          --arg user "$obs" \
          '. + [{"role":"assistant","content":$assistant}, {"role":"user","content":$user}]')
        ;;
      *)
        ui_warning "Unexpected parse result, treating as final answer"
        ui_final "$llm_response"
        return 0
        ;;
    esac
  done

  ui_warning "Reached max ReAct iterations ($REACT_MAX_ITERATIONS)"
  return 2
}

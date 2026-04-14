#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"

SHELLBOT_STREAM="${SHELLBOT_STREAM:-true}"

# API call with function calling support (non-streaming)
# Usage: api_chat_with_tools <messages> [tools_json]
# Returns raw API response JSON (not just content)
api_chat_with_tools() {
  local messages="$1"
  local tools="${2:-}"
  local model="${3:-$DEFAULT_MODEL}"
  local attempt=0
  local delay=1

  while [ $attempt -lt $API_MAX_RETRIES ]; do
    attempt=$((attempt + 1))

    local request_body
    if [ -n "$tools" ] && [ "$tools" != "[]" ]; then
      request_body=$(jq -n \
        --arg model "$model" \
        --argjson messages "$messages" \
        --argjson tools "$tools" \
        '{model: $model, messages: $messages, tools: $tools, temperature: 0.3, max_tokens: 4096}')
    else
      request_body=$(jq -n \
        --arg model "$model" \
        --argjson messages "$messages" \
        '{model: $model, messages: $messages, temperature: 0.3, max_tokens: 4096}')
    fi

    local http_code
    local response
    response=$(curl -sS -w "\n%{http_code}" --max-time "$API_TIMEOUT" \
      "$OPENROUTER_BASE_URL/chat/completions" \
      -H "Authorization: Bearer $OPENROUTER_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$request_body" 2>/dev/null)

    http_code=$(echo "$response" | tail -1)
    local body
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" = "200" ]; then
      local error
      error=$(echo "$body" | jq -r '.error.message // empty' 2>/dev/null)
      if [ -n "$error" ]; then
        echo "ERROR: API error: $error" >&2
        return 1
      fi
      echo "$body"
      return 0
    fi

    if [ "$http_code" = "429" ]; then
      echo "WARNING: Rate limited, retrying in ${delay}s... (attempt $attempt/$API_MAX_RETRIES)" >&2
      sleep "$delay"
      delay=$((delay * 2))
      continue
    fi

    if [ "$http_code" = "000" ]; then
      echo "WARNING: Network error (attempt $attempt/$API_MAX_RETRIES)" >&2
      sleep "$delay"
      delay=$((delay * 2))
      continue
    fi

    echo "ERROR: API returned HTTP $http_code" >&2
    echo "$body" | jq -r '.error.message // "Unknown error"' 2>/dev/null >&2
    sleep "$delay"
    delay=$((delay * 2))
  done

  echo "ERROR: API call failed after $API_MAX_RETRIES retries" >&2
  return 1
}

# Stream API call with function calling support
# Returns: full accumulated content (tool_calls are handled differently)
api_chat_stream_with_tools() {
  local messages="$1"
  local tools="${2:-}"
  local model="${3:-$DEFAULT_MODEL}"
  local attempt=0
  local delay=1

  while [ $attempt -lt $API_MAX_RETRIES ]; do
    attempt=$((attempt + 1))

    local request_body
    if [ -n "$tools" ] && [ "$tools" != "[]" ]; then
      request_body=$(jq -n \
        --arg model "$model" \
        --argjson messages "$messages" \
        --argjson tools "$tools" \
        '{model: $model, messages: $messages, tools: $tools, temperature: 0.3, max_tokens: 4096, stream: true}')
    else
      request_body=$(jq -n \
        --arg model "$model" \
        --argjson messages "$messages" \
        '{model: $model, messages: $messages, temperature: 0.3, max_tokens: 4096, stream: true}')
    fi

    local tmp_sse="/tmp/shellbot_stream_sse_$$.txt"
    local tmp_err="/tmp/shellbot_stream_err_$$.txt"

    curl -sS -N --max-time "$API_TIMEOUT" \
      "$OPENROUTER_BASE_URL/chat/completions" \
      -H "Authorization: Bearer $OPENROUTER_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$request_body" \
      2>"$tmp_err" > "$tmp_sse"

    local curl_exit=$?

    if [ $curl_exit -eq 0 ] && [ -s "$tmp_sse" ]; then
      local content_accumulated=""
      local in_reasoning=false

      # Collect tool calls from stream
      local tool_calls_json="{}"

      while IFS= read -r line; do
        line="${line%$'\r'}"
        [[ "$line" != data:* ]] && continue
        local payload="${line#data:}"
        payload="${payload# }"
        [ "$payload" = "[DONE]" ] && break

        # Content delta
        local content
        content=$(echo "$payload" | jq -r '.choices[0].delta.content // empty' 2>/dev/null)
        # Reasoning delta
        local reasoning
        reasoning=$(echo "$payload" | jq -r '.choices[0].delta.reasoning // empty' 2>/dev/null)

        if [ -n "$reasoning" ]; then
          if [ "$in_reasoning" = false ]; then
            printf '\033[2K%s' "${DIM}" >&2
            in_reasoning=true
          fi
          printf '%s' "$reasoning" >&2
        fi

        if [ -n "$content" ]; then
          if [ "$in_reasoning" = true ]; then
            printf '%s' "${NC}" >&2
            echo "" >&2
            in_reasoning=false
          fi
          printf '%s' "$content" >&2
          content_accumulated="${content_accumulated}${content}"
        fi

        # Tool calls delta - accumulate function name and arguments
        local tc_index tc_name tc_args
        tc_index=$(echo "$payload" | jq -r '.choices[0].delta.tool_calls[0].index // empty' 2>/dev/null)
        if [ -n "$tc_index" ]; then
          tc_name=$(echo "$payload" | jq -r '.choices[0].delta.tool_calls[0].function.name // empty' 2>/dev/null)
          tc_args=$(echo "$payload" | jq -r '.choices[0].delta.tool_calls[0].function.arguments // empty' 2>/dev/null)
          local tc_id
          tc_id=$(echo "$payload" | jq -r '.choices[0].delta.tool_calls[0].id // empty' 2>/dev/null)

          # Accumulate into tool_calls_json
          local existing_args
          existing_args=$(echo "$tool_calls_json" | jq -r ".[\"$tc_index\"].arguments // empty" 2>/dev/null)
          local new_args="${existing_args}${tc_args}"

          if [ -n "$tc_id" ]; then
            tool_calls_json=$(echo "$tool_calls_json" | jq \
              --arg idx "$tc_index" \
              --arg id "$tc_id" \
              --arg name "$tc_name" \
              --arg args "$new_args" \
              '. + {($idx): {id: $id, name: $name, arguments: $args}}')
          elif [ -n "$tc_name" ]; then
            tool_calls_json=$(echo "$tool_calls_json" | jq \
              --arg idx "$tc_index" \
              --arg name "$tc_name" \
              --arg args "$new_args" \
              '. + {($idx): {name: $name, arguments: $args}}')
          elif [ -n "$tc_args" ]; then
            tool_calls_json=$(echo "$tool_calls_json" | jq \
              --arg idx "$tc_index" \
              --arg args "$new_args" \
              '.[$idx].arguments = $args')
          fi
        fi
      done < "$tmp_sse"
      echo "" >&2

      if [ "$in_reasoning" = true ]; then
        printf '%s' "${NC}" >&2
      fi

      rm -f "$tmp_err" "$tmp_sse"

      # Return JSON with content and tool_calls
      local tool_calls_array
      tool_calls_array=$(echo "$tool_calls_json" | jq 'to_entries | map({id: .value.id, type: "function", function: {name: .value.name, arguments: .value.arguments}})')

      jq -n \
        --arg content "$content_accumulated" \
        --argjson tool_calls "$tool_calls_array" \
        '{content: $content, tool_calls: $tool_calls}'
      return 0
    fi

    local err_content
    err_content=$(cat "$tmp_err" 2>/dev/null)
    rm -f "$tmp_err" "$tmp_sse"

    if echo "$err_content" | grep -q "429"; then
      echo "" >&2
      echo "WARNING: Rate limited, retrying in ${delay}s..." >&2
      sleep "$delay"
      delay=$((delay * 2))
      continue
    fi

    echo "" >&2
    echo "WARNING: Stream failed (attempt $attempt/$API_MAX_RETRIES)" >&2
    sleep "$delay"
    delay=$((delay * 2))
  done

  echo "ERROR: Stream failed after $API_MAX_RETRIES retries" >&2
  return 1
}

# Simple API call for summarization/compression (no tools, returns content only)
api_chat_simple() {
  local messages="$1"
  local model="${2:-$DEFAULT_MODEL}"

  local response
  response=$(curl -sS --max-time "$API_TIMEOUT" \
    "$OPENROUTER_BASE_URL/chat/completions" \
    -H "Authorization: Bearer $OPENROUTER_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg model "$model" \
      --argjson messages "$messages" \
      '{model: $model, messages: $messages, temperature: 0.1, max_tokens: 1024}')" 2>/dev/null)

  echo "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null
}

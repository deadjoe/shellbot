#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"

SHELLBOT_STREAM="${SHELLBOT_STREAM:-true}"

api_chat() {
  local messages="$1"
  local model="${2:-$DEFAULT_MODEL}"
  local attempt=0
  local delay=1

  while [ $attempt -lt $API_MAX_RETRIES ]; do
    attempt=$((attempt + 1))

    local http_code
    local response
    response=$(curl -sS -w "\n%{http_code}" --max-time "$API_TIMEOUT" \
      "$OPENROUTER_BASE_URL/chat/completions" \
      -H "Authorization: Bearer $OPENROUTER_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$(jq -n \
        --arg model "$model" \
        --argjson messages "$messages" \
        '{model: $model, messages: $messages, temperature: 0.3, max_tokens: 4096}')" 2>/dev/null)

    http_code=$(echo "$response" | tail -1)
    local body=$(echo "$response" | sed '$d')

    if [ "$http_code" = "200" ]; then
      local error=$(echo "$body" | jq -r '.error.message // empty' 2>/dev/null)
      if [ -n "$error" ]; then
        echo "ERROR: API error: $error" >&2
        return 1
      fi
      echo "$body" | jq -r '.choices[0].message.content'
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

api_chat_stream() {
  local messages="$1"
  local model="${2:-$DEFAULT_MODEL}"
  local attempt=0
  local delay=1

  while [ $attempt -lt $API_MAX_RETRIES ]; do
    attempt=$((attempt + 1))

    local request_body
    request_body=$(jq -n \
      --arg model "$model" \
      --argjson messages "$messages" \
      '{model: $model, messages: $messages, temperature: 0.3, max_tokens: 4096, stream: true}')

    local tmp_err=/tmp/shellbot_stream_err_$$.txt
    local tmp_sse=/tmp/shellbot_stream_sse_$$.txt

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

      while IFS= read -r line; do
        line="${line%$'\r'}"
        [[ "$line" != data:* ]] && continue
        local payload="${line#data:}"
        payload="${payload# }"
        [ "$payload" = "[DONE]" ] && break
        local content
        content=$(echo "$payload" | jq -r '.choices[0].delta.content // empty' 2>/dev/null)
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
      done < "$tmp_sse"
      echo "" >&2

      if [ "$in_reasoning" = true ]; then
        printf '%s' "${NC}" >&2
      fi

      rm -f "$tmp_err" "$tmp_sse"
      echo "$content_accumulated"
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

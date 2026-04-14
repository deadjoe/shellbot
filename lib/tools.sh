#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/ui.sh"
source "$(dirname "${BASH_SOURCE[0]}")/security.sh"

TOOL_NAMES="calc list_files read_file read_rhkb read_webpage run_shell search_files search_rhkb search_web write_file"

tools_list() {
  echo "$TOOL_NAMES" | tr ' ' '\n' | sort
}

_tool_get_script() {
  local name="$1"
  echo "$SHELLBOT_HOME/tools/${name}.sh"
}

# Cross-platform timeout wrapper (macOS lacks GNU timeout)
_run_with_timeout() {
  local timeout_sec="$1"; shift
  local cmd=("$@")

  # Try GNU timeout first (Linux), then gtimeout (macOS coreutils)
  if command -v timeout &>/dev/null; then
    timeout "$timeout_sec" "${cmd[@]}"
  elif command -v gtimeout &>/dev/null; then
    gtimeout "$timeout_sec" "${cmd[@]}"
  else
    # Pure bash fallback: run in background, kill after timeout
    local pid
    "${cmd[@]}" &
    pid=$!
    local elapsed=0
    while kill -0 "$pid" 2>/dev/null && [ $elapsed -lt $timeout_sec ]; do
      sleep 1
      elapsed=$((elapsed + 1))
    done
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 124
    fi
    wait "$pid"
    return $?
  fi
}

tool_execute() {
  local tool_name="$1"
  local tool_input="$2"

  if ! echo "$TOOL_NAMES" | grep -qw "$tool_name"; then
    echo "Error: Unknown tool '$tool_name'. Available: $(tools_list | tr '\n' ' ')"
    return 1
  fi

  local script
  script=$(_tool_get_script "$tool_name")

  if [ ! -f "$script" ]; then
    echo "Error: Tool script not found: $script"
    return 1
  fi

  if ! security_check "$tool_name" "$tool_input"; then
    echo "Action blocked by security policy."
    return 1
  fi

  local result
  result=$(_run_with_timeout "$TOOL_TIMEOUT" bash "$script" "$tool_input" 2>&1)
  local exit_code=$?

  if [ $exit_code -eq 124 ]; then
    echo "Error: Tool execution timed out (${TOOL_TIMEOUT}s)"
    return 1
  fi

  echo "$result"
  return $exit_code
}

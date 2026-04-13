#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/ui.sh"

security_check() {
  local tool_name="$1"
  local tool_input="$2"

  if [ "$tool_name" = "run_shell" ]; then
    if echo "$tool_input" | grep -qE "$SHELL_DANGEROUS_PATTERNS"; then
      ui_warning "Dangerous command detected: $tool_input"
      read -p "Allow execution? [y/N] " confirm
      if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        return 1
      fi
      return 0
    fi

    if [ "$SHELL_CONFIRM" = "true" ]; then
      ui_info "Will execute: $tool_input"
      read -p "Execute? [Y/n] " confirm
      if [ "$confirm" = "n" ] || [ "$confirm" = "N" ]; then
        return 1
      fi
    fi
  fi

  if [ "$tool_name" = "write_file" ]; then
    local path
    path=$(echo "$tool_input" | jq -r '.path // empty' 2>/dev/null)
    if [ -n "$path" ] && [ -f "$path" ]; then
      ui_warning "Will overwrite: $path"
      read -p "Allow? [y/N] " confirm
      if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        return 1
      fi
    fi
  fi

  return 0
}

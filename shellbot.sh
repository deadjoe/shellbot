#!/usr/bin/env bash

SHELLBOT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SHELLBOT_HOME

source "$SHELLBOT_HOME/config.sh"
source "$SHELLBOT_HOME/lib/ui.sh"
source "$SHELLBOT_HOME/lib/api.sh"
source "$SHELLBOT_HOME/lib/react.sh"
source "$SHELLBOT_HOME/lib/loop.sh"
source "$SHELLBOT_HOME/lib/context.sh"
source "$SHELLBOT_HOME/lib/history.sh"
source "$SHELLBOT_HOME/lib/memory.sh"
source "$SHELLBOT_HOME/lib/tools.sh"
source "$SHELLBOT_HOME/lib/tools_schema.sh"
source "$SHELLBOT_HOME/lib/security.sh"
source "$SHELLBOT_HOME/prompts/system.sh"

LOOP_MODE=false
NON_INTERACTIVE=false
LAST_USER_MSG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --loop|-l)       LOOP_MODE=true; shift ;;
    --model|-m)      DEFAULT_MODEL="$2"; shift 2 ;;
    --no-interactive) NON_INTERACTIVE=true; shift ;;
    --debug|-d)      SHELLBOT_DEBUG=true; shift ;;
    --help|-h)       echo "Usage: shellbot [--loop] [--model MODEL] [--debug] [--no-interactive]"; exit 0 ;;
    *)               echo "Unknown option: $1"; exit 1 ;;
  esac
done

config_init
history_init
memory_init

# Cleanup: auto-extract memories on exit
_shellbot_exit() {
  if [ -n "$LAST_USER_MSG" ]; then
    local hist
    hist=$(history_get_messages 10)
    memory_extract "$hist" 2>/dev/null
  fi
}
trap _shellbot_exit EXIT

if [ "$NON_INTERACTIVE" = true ]; then
  input=$(cat)
  LAST_USER_MSG="$input"
  if [ "$LOOP_MODE" = true ]; then
    loop_run "$input"
  else
    react_run "$input"
  fi
  exit $?
fi

ui_welcome

while true; do
  read -re -p $'\033[1muser> \033[0m' user_input || break

  if [ -z "$user_input" ]; then
    continue
  fi

  case "$user_input" in
    /quit|/exit)
      echo "Goodbye!"
      exit 0
      ;;
    /help)
      ui_help
      ;;
    /tools)
      echo "Available tools:"
      tools_list | while read -r name; do
        echo "  - $name"
      done
      ;;
    /clear)
      history_clear
      context_clear
      ui_success "History cleared"
      ;;
    /model)
      echo "Current model: $DEFAULT_MODEL"
      read -ep "New model: " new_model
      if [ -n "$new_model" ]; then
        DEFAULT_MODEL="$new_model"
        ui_success "Model switched to: $DEFAULT_MODEL"
      fi
      ;;
    /context)
      if [ -f "$CONTEXT_FILE" ]; then
        context_summary
      else
        ui_info "No active loop context"
      fi
      ;;
    /memories)
      local_list=$(memory_list)
      if [ -n "$local_list" ]; then
        echo "$local_list"
      else
        ui_info "No memories stored yet"
      fi
      ;;
    /forget\ *)
      mid="${user_input#/forget }"
      if [ -n "$mid" ] && [ "$mid" -eq "$mid" ] 2>/dev/null; then
        memory_delete "$mid"
        ui_success "Memory #$mid deleted"
      else
        ui_error "Usage: /forget <id>"
      fi
      ;;
    /skip)
      if [ "$LOOP_MODE" = true ]; then
        loop_skip
        ui_info "Will skip current step"
      else
        ui_info "/skip only works in loop mode"
      fi
      ;;
    /stop)
      if [ "$LOOP_MODE" = true ]; then
        loop_stop
        ui_info "Will stop after current step"
      else
        ui_info "/stop only works in loop mode"
      fi
      ;;
    /debug)
      if [ "$SHELLBOT_DEBUG" = "true" ]; then
        SHELLBOT_DEBUG=false
        ui_info "Debug mode: OFF"
      else
        SHELLBOT_DEBUG=true
        ui_info "Debug mode: ON"
      fi
      ;;
    /loop\ *)
      goal="${user_input#/loop }"
      LOOP_MODE=true
      LAST_USER_MSG="$goal"
      loop_run "$goal" || ui_error "Loop run failed"
      LOOP_MODE=false
      ;;
    --loop|/loop)
      read -ep "Goal: " goal
      if [ -n "$goal" ]; then
        LOOP_MODE=true
        LAST_USER_MSG="$goal"
        loop_run "$goal" || ui_error "Loop run failed"
        LOOP_MODE=false
      fi
      ;;
    /*)
      ui_error "Unknown command: $user_input. Type /help for available commands."
      ;;
    *)
      LAST_USER_MSG="$user_input"
      react_run "$user_input" || ui_error "ReAct run failed"
      ;;
  esac
done

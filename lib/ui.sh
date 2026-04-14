#!/usr/bin/env bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

SHELLBOT_DEBUG="${SHELLBOT_DEBUG:-false}"

_has_rich() { python3 -m rich.markdown -h &>/dev/null; }
_has_gum()  { command -v gum &>/dev/null; }

ui_thought()     { echo -e "${CYAN}💭 Thought: $1${NC}"; }
ui_action()      { echo -e "${YELLOW}🔧 Action: $1 | Input: $2${NC}"; }
ui_observation() { echo -e "${GREEN}📋 Observation: $1${NC}"; }

ui_final() {
  local text="$1"
  echo ""
  python3 -c "
from rich.markdown import Markdown
from rich.console import Console
from rich.theme import Theme
import sys
text = sys.stdin.read()
if text.strip():
    theme = Theme({'markdown.code': 'cyan', 'markdown.code_block': 'cyan'})
    Console(theme=theme).print(Markdown(text))
" <<< "$text" 2>/dev/null || echo -e "${BOLD}${GREEN}$text${NC}"
  echo ""
}

ui_goal()        { echo -e "\n${BOLD}${BLUE}🎯 Goal: $1${NC}"; }
ui_plan_step()   {
  local step="$1"
  local rationale="${2:-}"
  if [ -n "$rationale" ]; then
    echo -e "${CYAN}📋 Plan: $step${DIM} — $rationale${NC}"
  else
    echo -e "${CYAN}📋 Plan: $step${NC}"
  fi
}
ui_warning()     { echo -e "${RED}⚠️  $1${NC}"; }
ui_info()        { echo -e "${DIM}$1${NC}"; }
ui_error()       { echo -e "${RED}✖ $1${NC}" >&2; }
ui_success()     { echo -e "${GREEN}✔ $1${NC}"; }

ui_loop_header() {
  echo -e "\n${BOLD}═══ Loop Step $1/$2 ═══${NC}"
}

ui_iteration() {
  echo -e "${DIM}── ReAct Step $1/$2 ──${DIM}"
}

SHELLBOT_SPIN_PID=""

ui_thinking() {
  if _has_gum; then
    gum spin --spinner dot --title "Thinking..." &>/dev/null &
    SHELLBOT_SPIN_PID=$!
  else
    echo -ne "${DIM}⏳ Thinking...${NC}\r"
  fi
}

ui_done_thinking() {
  if [ -n "$SHELLBOT_SPIN_PID" ]; then
    kill "$SHELLBOT_SPIN_PID" 2>/dev/null
    wait "$SHELLBOT_SPIN_PID" 2>/dev/null
    SHELLBOT_SPIN_PID=""
  fi
  echo -ne "\033[2K"
}

ui_loop_done() {
  echo -e "\n${BOLD}${GREEN}✅ Goal achieved${NC}"
}

ui_loop_timeout() {
  echo -e "\n${BOLD}${YELLOW}⏰ Loop timeout — outputting partial results${NC}"
}

ui_prompt() {
  echo -ne "${BOLD}user> ${NC}"
}

ui_debug() {
  if [ "$SHELLBOT_DEBUG" = "true" ]; then
    echo -e "${DIM}[DEBUG] $1${NC}" >&2
  fi
}

ui_welcome() {
  echo -e "${BOLD}${CYAN}"
  echo "  ___ _                _   "
  echo " / __| |_  ___  __ _ __| |_ "
  echo " \\__ \\ ' \\/ _ \\/ _\` / _|  _|"
  echo " |___/_||_\\___/\\__,_\\__|\\__|"
  echo -e "${NC}"
  echo -e "  ${DIM}Ops Agent • Function Calling + Loop • Pure Shell${NC}"
  echo -e "  ${DIM}Model: ${DEFAULT_MODEL}${NC}"
  echo -e "  ${DIM}Type /help for commands, /quit to exit${NC}"
  echo ""
}

ui_help() {
  echo -e "${BOLD}Commands:${NC}"
  echo "  /tools    List available tools"
  echo "  /clear    Clear conversation history"
  echo "  /model    Switch LLM model"
  echo "  /memories List stored memories"
  echo "  /forget <id> Delete a memory"
  echo "  /context Show loop context (loop mode)"
  echo "  /skip     Skip current step (loop mode)"
  echo "  /stop     Stop loop execution (loop mode)"
  echo "  /loop     Start a goal-oriented loop"
  echo "  /debug    Toggle debug mode"
  echo "  /help     Show this help"
  echo "  /quit     Exit ShellBot"
}

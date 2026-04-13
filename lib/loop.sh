#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/ui.sh"
source "$(dirname "${BASH_SOURCE[0]}")/react.sh"
source "$(dirname "${BASH_SOURCE[0]}")/context.sh"
source "$(dirname "${BASH_SOURCE[0]}")/planner.sh"
source "$(dirname "${BASH_SOURCE[0]}")/reflector.sh"

LOOP_SKIP_REQUESTED=false
LOOP_STOP_REQUESTED=false

loop_skip() {
  LOOP_SKIP_REQUESTED=true
}

loop_stop() {
  LOOP_STOP_REQUESTED=true
}

loop_run() {
  local goal="$1"

  context_init "$goal"
  ui_goal "$goal"

  local iteration=0
  while [ $iteration -lt $LOOP_MAX_ITERATIONS ]; do
    if [ "$LOOP_STOP_REQUESTED" = true ]; then
      ui_info "Loop stopped by user"
      break
    fi

    iteration=$((iteration + 1))
    ui_loop_header "$iteration" "$LOOP_MAX_ITERATIONS"
    LOOP_SKIP_REQUESTED=false

    local sub_goal
    sub_goal=$(planner_next_subgoal)
    if [ $? -ne 0 ]; then
      ui_error "Planner failed, stopping loop"
      break
    fi

    if [ "$sub_goal" = "DONE" ]; then
      ui_loop_done
      local final_summary
      final_summary=$(planner_summarize)
      ui_final "$final_summary"
      history_append "assistant" "$final_summary"
      return 0
    fi

    ui_subgoal "$sub_goal"

    if [ "$LOOP_SKIP_REQUESTED" = true ]; then
      context_record "$sub_goal" "Skipped by user" "skipped"
      ui_info "Sub-goal skipped"
      continue
    fi

    local result
    result=$(react_run "$sub_goal" "$(context_summary)")
    local react_exit=$?

    if [ $react_exit -eq 2 ]; then
      context_record "$sub_goal" "$result" "timeout"
    elif [ $react_exit -eq 0 ]; then
      context_record "$sub_goal" "$result" "done"
    else
      context_record "$sub_goal" "$result" "error"
    fi

    if [ "$LOOP_STOP_REQUESTED" = true ]; then
      ui_info "Loop stopped by user after current sub-goal"
      break
    fi

    local state
    state=$(planner_evaluate)

    case "$state" in
      DONE)
        ui_loop_done
        local final_summary
        final_summary=$(planner_summarize)
        ui_final "$final_summary"
        history_append "assistant" "$final_summary"
        return 0
        ;;
      REVISE)
        ui_revise
        reflector_analyze
        ;;
      CONTINUE|*)
        continue
        ;;
    esac
  done

  ui_loop_timeout
  local partial
  partial=$(context_summary)
  ui_final "Partial results:\n$partial"
  return 2
}

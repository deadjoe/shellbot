# ShellBot — 纯 Shell ReAct Loop Agent 规格说明书

> 定位：面向系统运维工程师的 AI Agent 助手  
> 技术栈：Bash + macOS CLI 工具 + API（零框架）  
> 版本：v0.1  
> 日期：2026-04-13

---

## 1. 项目概述

### 1.1 定位

ShellBot 是一个运行在 macOS 终端中的 AI Agent，面向系统运维工程师，具备以下核心能力：

- **本地系统操作**：执行 shell 命令、读写文件、搜索文件、检查服务状态
- **互联网搜索**：通用搜索（Tavily）、网页阅读（JINA Reader）
- **Red Hat KB 查询**：自动登录 SSO，搜索并阅读 access.redhat.com 知识库文章
- **自主推理与规划**：ReAct 推理 + Loop 自主任务循环

### 1.2 设计原则

| 原则 | 说明 |
|------|------|
| Bash 为主语言 | 所有流程控制、逻辑判断用 Bash 实现 |
| CLI 工具组合 | curl (HTTP)、jq (JSON)、python3 (HTML解析/计算) 为工具层 |
| 零 Agent 框架 | 不使用 pydanticAI、langchain 等 AI/Agent 框架 |
| 可审计 | 所有 Agent 思考过程、工具调用、结果对用户可见 |
| 安全优先 | 危险 shell 命令需确认；凭据不落地明文 |

### 1.3 运行模式

| 模式 | 启动方式 | 行为 |
|------|----------|------|
| 单轮 ReAct | `shellbot` | 一问一答，单次 ReAct 循环 |
| Loop Agent | `shellbot --loop` 或交互中 `/loop <goal>` | 接受复杂任务，自主规划+执行多轮 |

---

## 2. 架构设计

### 2.1 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                      用户 (终端交互)                         │
│                         ↕                                    │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                  shellbot.sh (入口)                   │   │
│  │    解析参数 → 选择模式(单轮/loop) → 启动主循环        │   │
│  └─────────────────────┬────────────────────────────────┘   │
│                        │                                     │
│  ┌─────────────────────▼────────────────────────────────┐   │
│  │             Outer Loop (loop.sh)                     │   │
│  │  ┌──────────────────────────────────────────────┐   │   │
│  │  │ 1. planner_next_subgoal → 生成下一子目标       │   │   │
│  │  │    - 返回 "DONE" → 任务完成                     │   │   │
│  │  │ 2. react_run → 执行内循环                      │   │   │
│  │  │ 3. context_record → 记录结果                   │   │   │
│  │  │ 4. planner_evaluate → 评估状态                  │   │   │
│  │  │    - DONE → 输出最终结果                        │   │   │
│  │  │    - CONTINUE → 继续                           │   │   │
│  │  │    - REVISE → reflector 反思，调整策略          │   │   │
│  │  │ 5. 支持 /skip 跳过子目标、/stop 停止循环        │   │   │
│  │  └──────────────────────────────────────────────┘   │   │
│  └─────────────────────┬────────────────────────────────┘   │
│                        │                                     │
│  ┌─────────────────────▼────────────────────────────────┐   │
│  │             Inner Loop (react.sh)                    │   │
│  │  构建 Prompt → 调用 LLM → 解析响应                    │   │
│  │    ├─ Thought → 继续思考                              │   │
│  │    ├─ Action + Action Input → 调用工具 → Observation │   │
│  │    └─ Final Answer → 返回结果                         │   │
│  └─────────────────────┬────────────────────────────────┘   │
│                        │                                     │
│  ┌─────────────────────▼────────────────────────────────┐   │
│  │              工具层 (tools.sh + tools/)              │   │
│  │  ┌──────────┬──────────┬──────────┬──────────────┐   │   │
│  │  │ 本地操作  │ 互联网   │ RH KB    │  计算       │   │   │
│  │  │ run_shell│search_web│search_rhkb│ calc        │   │   │
│  │  │ read_file│read_webpg│read_rhkb │             │   │   │
│  │  │ write_fl │          │          │             │   │   │
│  │  │ list_file│          │          │             │   │   │
│  │  │ search_fl│          │          │             │   │   │
│  │  └──────────┴──────────┴──────────┴──────────────┘   │   │
│  └─────────────────────┬────────────────────────────────┘   │
│                        │                                     │
│  ┌─────────────────────▼────────────────────────────────┐   │
│  │              基础设施层                               │   │
│  │  api.sh (OpenRouter) │ history.sh │ context.sh       │   │
│  │  config.sh            │ ui.sh      │ security.sh    │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 文件结构

```
shellbot/
├── shellbot.sh              # 主入口，参数解析，模式选择，REPL 循环
├── config.sh                # 全局配置 (API keys, model, limits, .env 加载)
├── lib/
│   ├── api.sh               # OpenRouter API 调用 (含重试、流式)
│   ├── react.sh             # ReAct 解析器 (内循环，多行结构化解析)
│   ├── loop.sh              # Loop Agent 控制器 (外循环，含 /skip /stop)
│   ├── planner.sh           # 任务分解 + 子目标生成 + 状态评估 + 汇总
│   ├── reflector.sh         # 失败反思 + 策略调整
│   ├── tools.sh             # 工具注册表 (字符串匹配) + 调度执行
│   ├── history.sh           # 对话历史管理 (JSON Lines，tail 优化)
│   ├── context.sh           # Loop 模式全局任务上下文
│   ├── ui.sh                # 终端 UI (颜色/格式化/多种显示函数)
│   └── security.sh          # 安全控制 (auto 确认模式)
├── tools/
│   ├── run_shell.sh         # 执行 shell 命令 (bash -c)
│   ├── read_file.sh         # 读取文件 (含存在性检查)
│   ├── write_file.sh        # 写入文件 (printf + JSON 验证)
│   ├── list_files.sh        # 列出目录
│   ├── search_files.sh      # 文件内容搜索 (rg/grep 自动检测)
│   ├── search_web.sh        # Tavily 搜索
│   ├── read_webpage.sh      # JINA Reader
│   ├── rhkb_auth.sh         # RH SSO 认证 (直接构造 SSO URL)
│   ├── search_rhkb.sh       # Red Hat KB 搜索 (hydra API)
│   ├── read_rhkb.sh         # Red Hat KB 文章阅读 (hydra API + HTML 双策略)
│   └── calc.sh              # 安全数学计算 (受限 eval)
├── prompts/
│   ├── system.sh            # System prompt 模板
│   ├── react_format.sh      # ReAct 输出格式说明
│   └── tools_desc.sh        # 工具描述文本 (含 search_files，注入 prompt)
└── data/
    └── .gitignore            # 忽略历史文件和 cookie jar
```

---

## 3. 核心模块详细设计

### 3.1 配置管理 (config.sh)

```bash
SHELLBOT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ===== API =====
OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"
OPENROUTER_BASE_URL="${OPENROUTER_BASE_URL:-https://openrouter.ai/api/v1}"
DEFAULT_MODEL="${DEFAULT_MODEL:-deepseek/deepseek-chat-v3-0324}"

# ===== Tavily =====
TAVILY_API_KEY="${TAVILY_API_KEY:-}"

# ===== JINA Reader =====
JINA_API_KEY="${JINA_API_KEY:-}"

# ===== Red Hat SSO =====
RH_USERNAME="${RH_USERNAME:-}"
RH_PASSWORD="${RH_PASSWORD:-}"
RH_COOKIE_JAR="${RH_COOKIE_JAR:-$HOME/.shellbot/rh_cookies.jar}"
RH_SSO_BASE="https://sso.redhat.com/auth/realms/redhat-external"
RH_PORTAL_BASE="https://access.redhat.com"

# ===== Loop Control =====
REACT_MAX_ITERATIONS="${REACT_MAX_ITERATIONS:-8}"
LOOP_MAX_ITERATIONS="${LOOP_MAX_ITERATIONS:-10}"
API_TIMEOUT="${API_TIMEOUT:-120}"
TOOL_TIMEOUT="${TOOL_TIMEOUT:-60}"
API_MAX_RETRIES="${API_MAX_RETRIES:-3}"

# ===== Security =====
SHELL_CONFIRM="${SHELL_CONFIRM:-auto}"
SHELL_DANGEROUS_PATTERNS="rm -rf |rm -f /|mkfs|dd if=|> /dev/sd|shutdown|reboot|init 0|init 6|:(){:|:&};:|chmod -R 777 /|chown -R|passwd|userdel|groupdel"

# ===== Streaming =====
SHELLBOT_STREAM="${SHELLBOT_STREAM:-true}"

# ===== Data =====
SHELLBOT_DATA_DIR="${SHELLBOT_DATA_DIR:-$HOME/.shellbot}"
HISTORY_FILE="$SHELLBOT_DATA_DIR/history.json"
CONTEXT_FILE="$SHELLBOT_DATA_DIR/context.json"
```

**凭据加载优先级**：环境变量 → `.env` 文件（始终覆盖）→ macOS Keychain（仅在变量为空时补充）

```bash
load_env() {
  local env_file="${1:-$SHELLBOT_DATA_DIR/.env}"
  if [ -f "$env_file" ]; then
    while IFS='=' read -r key value; do
      [[ "$key" =~ ^#.*$ ]] && continue
      [[ -z "$key" ]] && continue
      value="${value%\"}" value="${value#\"}"
      value="${value%\'}" value="${value#\'}"
      export "$key=$value"
    done < "$env_file"
  fi
}

load_keychain() {
  local key label
  for label in openrouter tavily jina rh; do
    key=$(security find-generic-password -s "shellbot-$label" -w 2>/dev/null) || continue
    case "$label" in
      openrouter) [ -z "$OPENROUTER_API_KEY" ] && OPENROUTER_API_KEY="$key" ;;
      tavily)     [ -z "$TAVILY_API_KEY" ]     && TAVILY_API_KEY="$key" ;;
      jina)       [ -z "$JINA_API_KEY" ]       && JINA_API_KEY="$key" ;;
      rh)         [ -z "$RH_PASSWORD" ]        && RH_PASSWORD="$key" ;;
    esac
  done
}

config_init() {
  mkdir -p "$SHELLBOT_DATA_DIR"
  load_env
  load_keychain
  export OPENROUTER_API_KEY TAVILY_API_KEY JINA_API_KEY RH_USERNAME RH_PASSWORD
}
```

### 3.2 API 调用 (lib/api.sh)

调用 OpenRouter 的 OpenAI-compatible 接口，支持重试（指数退避）和流式输出。

**非流式调用**：

```bash
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

    # 429 限流或网络错误，指数退避重试
    if [ "$http_code" = "429" ] || [ "$http_code" = "000" ]; then
      sleep "$delay"
      delay=$((delay * 2))
      continue
    fi

    # 其他错误，也重试
    sleep "$delay"
    delay=$((delay * 2))
  done

  echo "ERROR: API call failed after $API_MAX_RETRIES retries" >&2
  return 1
}
```

**流式调用**（`api_chat_stream`）：

- 发送 `stream: true` 请求，解析 SSE 事件
- `delta.reasoning` 以 dim 样式实时显示到 stderr（推理模型如 deepseek-r1）
- `delta.content` 正常样式实时显示到 stderr，同时累积到返回值
- reasoning → content 切换时自动换行 + 重置颜色
- **只有 `content` 被累积返回**（不含 reasoning），避免 ReAct 解析被推理文本污染
- 回退：如 rich/gum 不可用，自动降级到纯 ANSI

> 默认 `SHELLBOT_STREAM=true` 时 `react_run` 调用 `api_chat_stream`；设为 `false` 则调用 `api_chat`。

### 3.3 ReAct 引擎 (lib/react.sh)

**响应解析**（多行结构化解析，避免分隔符冲突）：

```bash
react_parse() {
  local response="$1"

  # 优先检测 Final Answer
  local final_answer
  final_answer=$(echo "$response" | awk '/^[Ff]inal [Aa]nswer:/ {sub(/^[Ff]inal [Aa]nswer:[[:space:]]*/, ""); print; exit}')

  if [ -n "$final_answer" ]; then
    echo "FINAL"
    echo "$final_answer"
    return 0
  fi

  # 逐行解析 Thought/Action/Action Input
  local thought="" action="" action_input=""
  local in_thought=false in_action=false in_action_input=false

  while IFS= read -r line; do
    if [[ "$line" =~ ^[Tt]hought:[[:space:]]*(.*) ]]; then
      thought="${BASH_REMATCH[1]}"
      in_thought=true; in_action=false; in_action_input=false
    elif [[ "$line" =~ ^[Aa]ction\ [Ii]nput:[[:space:]]*(.*) ]]; then
      action_input="${BASH_REMATCH[1]}"
      in_thought=false; in_action=false; in_action_input=true
    elif [[ "$line" =~ ^[Aa]ction:[[:space:]]*(.*) ]]; then
      local captured="${BASH_REMATCH[1]}"
      # 处理 LLM 把 Action 和 Action Input 输出在同一行的情况
      if [[ "$captured" =~ ^(.*)[Aa]ction\ [Ii]nput:[[:space:]]*(.*) ]]; then
        action="${BASH_REMATCH[1]}"
        action="$(echo "$action" | sed 's/[[:space:]]*$//')"
        action_input="${BASH_REMATCH[2]}"
      else
        action="$captured"
        action="$(echo "$action" | sed 's/[[:space:]]*$//')"
      fi
      in_thought=false; in_action=false; in_action_input=true
    elif [ "$in_action_input" = true ] && [[ "$line" =~ ^[[:space:]]+(.*) ]]; then
      # 多行 Action Input 续行
      action_input="$action_input ${BASH_REMATCH[1]}"
    fi
  done <<< "$response"

  action_input="$(echo "$action_input" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  if [ -z "$action" ]; then
    # LLM 未遵循格式，将整个响应作为 Final Answer
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
```

**构建消息**：

```bash
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
```

**ReAct 主循环**：

```bash
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

    # 流式/非流式分派
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
        # 非流式模式才显示 Thought（流式已在 stderr 实时输出）
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
        local thought action action_input
        thought=$(echo "$parsed" | sed -n '2p')
        action=$(echo "$parsed" | sed -n '3p')
        action_input=$(echo "$parsed" | sed -n '4p')

        # 非流式模式才显示 Thought/Action（流式已在 stderr 实时输出）
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
```

### 3.4 Loop Agent 控制器 (lib/loop.sh)

```bash
LOOP_SKIP_REQUESTED=false
LOOP_STOP_REQUESTED=false

loop_skip() { LOOP_SKIP_REQUESTED=true; }
loop_stop() { LOOP_STOP_REQUESTED=true; }

loop_run() {
  local goal="$1"

  context_init "$goal"
  ui_goal "$goal"

  local iteration=0
  while [ $iteration -lt $LOOP_MAX_ITERATIONS ]; do
    # 检查用户是否请求停止
    if [ "$LOOP_STOP_REQUESTED" = true ]; then
      ui_info "Loop stopped by user"
      break
    fi

    iteration=$((iteration + 1))
    ui_loop_header "$iteration" "$LOOP_MAX_ITERATIONS"
    LOOP_SKIP_REQUESTED=false

    # 1. 生成下一子目标
    local sub_goal
    sub_goal=$(planner_next_subgoal)
    if [ $? -ne 0 ]; then
      ui_error "Planner failed, stopping loop"
      break
    fi

    # Planner 返回 DONE → 任务完成
    if [ "$sub_goal" = "DONE" ]; then
      ui_loop_done
      local final_summary
      final_summary=$(planner_summarize)
      ui_final "$final_summary"
      history_append "assistant" "$final_summary"
      return 0
    fi

    ui_subgoal "$sub_goal"

    # 检查用户是否请求跳过
    if [ "$LOOP_SKIP_REQUESTED" = true ]; then
      context_record "$sub_goal" "Skipped by user" "skipped"
      ui_info "Sub-goal skipped"
      continue
    fi

    # 2. 执行内循环 ReAct
    local result
    result=$(react_run "$sub_goal" "$(context_summary)")
    local react_exit=$?

    # 3. 记录结果（含状态：done/timeout/error）
    if [ $react_exit -eq 2 ]; then
      context_record "$sub_goal" "$result" "timeout"
    elif [ $react_exit -eq 0 ]; then
      context_record "$sub_goal" "$result" "done"
    else
      context_record "$sub_goal" "$result" "error"
    fi

    # 再次检查停止请求
    if [ "$LOOP_STOP_REQUESTED" = true ]; then
      ui_info "Loop stopped by user after current sub-goal"
      break
    fi

    # 4. 评估整体状态
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
```

### 3.5 规划器 (lib/planner.sh)

Planner 通过 LLM 实现三个功能：

**生成子目标**：

```
You are a task planner for a system operations agent. Given the overall goal 
and completed sub-goals, determine the NEXT sub-goal to work on.

{context_summary}

Output ONLY the next sub-goal as a single line of text. If the overall goal 
is fully achieved, output exactly: DONE
```

**评估状态**：

```
You are a task evaluator for a system operations agent. Given the overall goal 
and all results so far, determine if the task is complete.

{context_summary}

Output ONLY ONE of these single words:
- DONE (if the goal is fully achieved)
- CONTINUE (if more work is needed)
- REVISE (if the approach is failing and needs adjustment)
```

**汇总结果**（`planner_summarize`）：

```
You are a summarizer for a system operations agent. Given the completed task 
results, provide a clear, structured final summary for the user.

{context_summary}

Provide a concise summary of findings, recommendations, and any action items. 
Use markdown formatting.
```

### 3.6 反思器 (lib/reflector.sh)

当状态为 REVISE 时触发：

```
You are a reflection engine for a system operations agent. The following 
approach did not achieve the desired result:

Failed sub-goal: {last_sub_goal}
Result: {last_result}

{context_summary}

Analyze WHY this approach failed and suggest a different approach.
Output TWO lines:
Line 1: the reason for failure (starting with "Reason: ")
Line 2: the revised approach (starting with "Revised: ")
```

反思结果通过 `context_record_reflection` 写入上下文的 `reflections` 数组。

### 3.7 任务上下文 (lib/context.sh)

上下文以 JSON 文件存储，由 jq 维护：

```json
{
  "goal": "用户原始目标",
  "sub_goals": [
    {
      "id": 1,
      "desc": "搜索 RH KB 关于 NFS 问题",
      "status": "done",
      "result": "找到 3 篇相关 KB 文章..."
    }
  ],
  "reflections": [
    {
      "iteration": 3,
      "failed_sub_goal": "直接 mount 测试",
      "reason": "权限不足，需要 sudo",
      "revised_approach": "先检查配置文件，再建议用户用 sudo"
    }
  ],
  "iteration": 4
}
```

**上下文摘要函数**：

```bash
context_summary() {
  if [ ! -f "$CONTEXT_FILE" ]; then
    echo ""
    return
  fi
  jq -r '
    "Goal: \(.goal)\n" +
    "Sub-goals:\n" +
    (.sub_goals | map("  [\(.status)] \(.desc): \(.result // "pending")") | join("\n")) +
    (if (.reflections | length) > 0 then
      "\nReflections:\n" +
      (.reflections | map("  - \(.reason) -> \(.revised_approach)") | join("\n"))
    else "" end)
  ' "$CONTEXT_FILE" 2>/dev/null
}
```

### 3.8 对话历史 (lib/history.sh)

```bash
# 历史记录格式 (JSON Lines，每行一条消息)
# {"role":"user","content":"...","timestamp":1713001234}

history_init() {
  mkdir -p "$(dirname "$HISTORY_FILE")"
  [ -f "$HISTORY_FILE" ] || > "$HISTORY_FILE"
}

history_append() {
  local role="$1"
  local content="$2"
  jq -n --arg role "$role" --arg content "$content" \
    --argjson ts "$(date +%s)" \
    '{role: $role, content: $content, timestamp: $ts}' \
    >> "$HISTORY_FILE"
}

history_get_messages() {
  # 先 tail 截断再 jq 聚合，避免大文件全量读取
  local limit="${1:-20}"
  tail -n "$limit" "$HISTORY_FILE" | jq -s 'map({role: .role, content: .content})'
}

history_get_messages_trimmed() {
  local max_chars="${1:-30000}"
  local messages
  messages=$(history_get_messages 50)

  local total_chars
  total_chars=$(echo "$messages" | jq '[.[].content | length] | add // 0')

  if [ "$total_chars" -gt "$max_chars" ]; then
    echo "$messages" | jq 'if length > 10 then .[-10:] else . end'
  else
    echo "$messages"
  fi
}

history_clear() {
  > "$HISTORY_FILE"
}

history_count() {
  wc -l < "$HISTORY_FILE" | tr -d ' '
}
```

### 3.9 工具系统 (lib/tools.sh)

**工具注册表**（字符串匹配，兼容 macOS bash 3.2）：

```bash
TOOL_NAMES="calc list_files read_file read_rhkb read_webpage run_shell search_files search_rhkb search_web write_file"

tools_list() {
  echo "$TOOL_NAMES" | tr ' ' '\n' | sort
}

_tool_get_script() {
  local name="$1"
  echo "$SHELLBOT_HOME/tools/${name}.sh"
}
```

**工具描述生成** (注入 LLM prompt)：

```bash
prompt_tools_desc() {
  cat <<'PROMPT'
Available tools:

- run_shell: Execute a shell command on the local system. Input: the shell command as a string.
- read_file: Read the content of a file. Input: file path string.
- write_file: Write content to a file. Input: JSON string {"path": "/path/to/file", "content": "file content here"}.
- list_files: List files in a directory with details. Input: directory path string (default: current directory).
- search_files: Search for a text pattern in files under current directory. Uses ripgrep (rg) if available, falls back to grep. Input: search pattern string.
- search_web: Search the internet for information. Input: search query string.
- read_webpage: Read a webpage and convert to clean markdown. Input: URL string.
- search_rhkb: Search Red Hat Knowledgebase for solutions. Input: search query string.
- read_rhkb: Read the full content of a Red Hat KB article. Input: the KB article URL string.
- calc: Perform a mathematical calculation. Input: mathematical expression string.
PROMPT
}
```

**工具调度执行**：

```bash
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
  result=$(timeout "$TOOL_TIMEOUT" bash "$script" "$tool_input" 2>&1)
  local exit_code=$?

  if [ $exit_code -eq 124 ]; then
    echo "Error: Tool execution timed out (${TOOL_TIMEOUT}s)"
    return 1
  fi

  echo "$result"
  return $exit_code
}
```

### 3.10 安全控制 (lib/security.sh)

```bash
security_check() {
  local tool_name="$1"
  local tool_input="$2"

  if [ "$tool_name" = "run_shell" ]; then
    # 危险命令检测 → 始终需确认
    if echo "$tool_input" | grep -qE "$SHELL_DANGEROUS_PATTERNS"; then
      ui_warning "Dangerous command detected: $tool_input"
      read -p "Allow execution? [y/N] " confirm
      if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        return 1
      fi
      return 0
    fi

    # auto 模式：非危险命令自动执行；true 模式：所有命令需确认
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
```

**`SHELL_CONFIRM` 模式**：

| 值 | 行为 |
|-----|------|
| `auto` | 危险命令需确认，普通命令自动执行 |
| `true` | 所有 shell 命令需确认 |
| `false` | 所有命令自动执行（不推荐） |

### 3.11 终端 UI (lib/ui.sh)

```bash
# 颜色定义
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

ui_thought()      { echo -e "${CYAN}💭 Thought: $1${NC}"; }
ui_action()       { echo -e "${YELLOW}🔧 Action: $1 | Input: $2${NC}"; }
ui_observation()  { echo -e "${GREEN}📋 Observation: $1${NC}"; }

# Final Answer 用 rich 渲染 markdown（代码高亮、表格），回退到纯 ANSI
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

ui_goal()         { echo -e "\n${BOLD}${BLUE}🎯 Goal: $1${NC}"; }
ui_subgoal()      { echo -e "${BLUE}  → Sub-goal: $1${NC}"; }
ui_warning()      { echo -e "${RED}⚠️  $1${NC}"; }
ui_info()         { echo -e "${DIM}$1${NC}"; }
ui_error()        { echo -e "${RED}✖ $1${NC}" >&2; }
ui_success()      { echo -e "${GREEN}✔ $1${NC}"; }

# Thinking 动画：有 gum 时用 spinner，回退到 ⏳ 静态
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

ui_loop_header()  { echo -e "\n${BOLD}═══ Loop Iteration $1/$2 ═══${NC}"; }
ui_iteration()    { echo -e "${DIM}── ReAct Step $1/$2 ──${NC}"; }
ui_loop_done()    { echo -e "\n${BOLD}${GREEN}📊 State: DONE ✓${NC}"; }
ui_loop_timeout() { echo -e "\n${BOLD}${YELLOW}📊 State: Loop timeout — outputting partial results${NC}"; }
ui_revise()       { echo -e "${BOLD}${YELLOW}🔄 REVISE — adjusting approach${NC}"; }
ui_prompt()       { echo -ne "${BOLD}user> ${NC}"; }
ui_debug()        { [ "$SHELLBOT_DEBUG" = "true" ] && echo -e "${DIM}[DEBUG] $1${NC}" >&2; }

ui_welcome() {
  echo -e "${BOLD}${CYAN}"
  echo "  ___ _                _   "
  echo " / __| |_  ___  __ _ __| |_ "
  echo " \\__ \\ ' \\/ _ \\/ _\` / _|  _|"
  echo " |___/_||_\\___/\\__,_\\__|\\__|"
  echo -e "${NC}"
  echo -e "  ${DIM}Ops Agent • ReAct + Loop • Pure Shell${NC}"
  echo -e "  ${DIM}Model: ${DEFAULT_MODEL}${NC}"
  echo -e "  ${DIM}Type /help for commands, /quit to exit${NC}"
  echo ""
}

ui_help() {
  echo -e "${BOLD}Commands:${NC}"
  echo "  /tools    List available tools"
  echo "  /clear    Clear conversation history"
  echo "  /model    Switch LLM model"
  echo "  /context  Show loop context (loop mode)"
  echo "  /skip     Skip current sub-goal (loop mode)"
  echo "  /stop     Stop loop execution (loop mode)"
  echo "  /debug    Toggle debug mode"
  echo "  /help     Show this help"
  echo "  /quit     Exit ShellBot"
}
```

---

## 4. 工具详细设计

### 4.1 本地操作工具

#### run_shell.sh

```bash
#!/usr/bin/env bash
bash -c "$1"
```

> 使用 `bash -c` 在子进程执行，避免 `eval` 的安全隐患。由 `security.sh` 做前置安全检查。

#### read_file.sh

```bash
#!/usr/bin/env bash
if [ ! -f "$1" ]; then
  echo "Error: File not found: $1"
  exit 1
fi
cat "$1" 2>&1 | head -500
```

#### write_file.sh

```bash
#!/usr/bin/env bash
path=$(echo "$1" | jq -r '.path // empty' 2>/dev/null)
content=$(echo "$1" | jq -r '.content // empty' 2>/dev/null)

if [ -z "$path" ] || [ -z "$content" ]; then
  echo "Error: Invalid input. Expected JSON: {\"path\": \"...\", \"content\": \"...\"}"
  exit 1
fi

mkdir -p "$(dirname "$path")"
printf '%s' "$content" > "$path"
echo "File written: $path"
```

> 使用 `printf '%s'` 而非 `echo`，避免丢失多行内容和特殊字符。

#### list_files.sh

```bash
#!/usr/bin/env bash
ls -la "${1:-.}" 2>&1
```

#### search_files.sh

```bash
#!/usr/bin/env bash
_search_bin=""
if command -v rg >/dev/null 2>&1; then
  _search_bin="rg"
else
  _search_bin="grep"
fi

if [ "$_search_bin" = "rg" ]; then
  rg --max-count=50 --max-filesize=1M --no-heading --line-number --color=never "$1" 2>&1 | head -100
else
  grep -rn --max-count=50 --color=never "$1" . 2>&1 | head -100
fi
```

> 自动检测 ripgrep (rg) 或回退到 grep，兼容不同环境。

### 4.2 互联网工具

#### search_web.sh (Tavily)

```bash
#!/usr/bin/env bash
curl -sS --max-time 30 "https://api.tavily.com/search" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg query "$1" \
    --arg key "$TAVILY_API_KEY" \
    '{api_key: $key, query: $query, max_results: 5, include_answer: true}')" \
  | jq -r '
    if .answer then "Answer: \(.answer)\n" else "" end +
    (.results // [] | map(
      "[\(.title)](\(.url))\n\(.content)\n"
    ) | join("\n"))
  '
```

#### read_webpage.sh (JINA Reader)

```bash
#!/usr/bin/env bash
curl -sS --max-time 30 \
  "https://r.jina.ai/$1" \
  -H "Authorization: Bearer $JINA_API_KEY" \
  -H "Accept: text/markdown" \
  | head -1000
```

### 4.3 Red Hat KB 工具

#### SSO 登录流程

经实际探测，access.redhat.com 首页不重定向到 SSO，需直接构造 SSO URL：

```
1. 构造 SSO 登录 URL:
   https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/auth
     ?client_id=customer-portal
     &redirect_uri=https%3A%2F%2Faccess.redhat.com%2F
     &response_type=code

2. GET SSO URL (带 -L 跟随重定向)
   → 获取登录页面 HTML，包含 rh-password-verification-form
   → cookie jar 中记录 AUTH_SESSION_ID 等

3. 用 python3 HTMLParser 解析密码表单 action URL
   → 包含动态参数: session_code, execution, tab_id 等

4. POST 用户名密码到 form action URL
   → 返回 302 + Location header
   → 手动跟随重定向获取 portal session cookie

5. 验证认证：访问任意 KB 页面，检查 HTTP 状态码
   → 200/403/404 = 认证成功
   → 302/000 = cookie 过期，需重新认证
```

#### rhkb_auth.sh

位于 `tools/rhkb_auth.sh`（不是 `lib/`），被 `search_rhkb.sh` 和 `read_rhkb.sh` 通过 `SHELLBOT_HOME` 绝对路径引用。

```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"
source "$SHELLBOT_HOME/lib/ui.sh"

RH_COOKIE_JAR="${RH_COOKIE_JAR:-$HOME/.shellbot/rh_cookies.jar}"

rhkb_auth() {
  if [ -z "$RH_USERNAME" ] || [ -z "$RH_PASSWORD" ]; then
    echo "Error: RH_USERNAME and RH_PASSWORD must be configured" >&2
    return 1
  fi

  mkdir -p "$(dirname "$RH_COOKIE_JAR")"
  ui_info "Authenticating to Red Hat SSO..."

  rm -f "$RH_COOKIE_JAR"

  # 直接构造 SSO URL（而非从 portal 首页获取重定向）
  local sso_login_url="https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/auth?client_id=customer-portal&redirect_uri=https%3A%2F%2Faccess.redhat.com%2F&response_type=code"

  curl -sS -c "$RH_COOKIE_JAR" --max-time 15 \
    -o /tmp/shellbot_rh_login.html \
    -L "$sso_login_url" 2>/dev/null

  # 解析密码表单 action URL（python3 HTMLParser）
  local form_action
  form_action=$(python3 -c "..." 2>/dev/null)

  # POST 用户名密码（不带 -L，手动跟随重定向）
  curl -sS -b "$RH_COOKIE_JAR" -c "$RH_COOKIE_JAR" \
    --max-time 30 -i -X POST "$form_action" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "username=$RH_USERNAME" \
    --data-urlencode "password=$RH_PASSWORD" \
    > /tmp/shellbot_rh_post.txt 2>/dev/null

  # 手动跟随 302 重定向
  local redirect_url
  redirect_url=$(grep -i "^location:" /tmp/shellbot_rh_post.txt | head -1 | tr -d '\r' | awk '{print $2}')
  curl -sS -b "$RH_COOKIE_JAR" -c "$RH_COOKIE_JAR" \
    --max-time 15 -o /tmp/shellbot_rh_landing.html \
    -L "$redirect_url" 2>/dev/null

  # 验证认证（访问 KB 页面而非 customer_profile API）
  local test_status
  test_status=$(curl -sS -b "$RH_COOKIE_JAR" -o /dev/null -w "%{http_code}" \
    --max-time 10 "https://access.redhat.com/solutions/2188281" 2>/dev/null)

  if [ "$test_status" = "200" ] || [ "$test_status" = "403" ] || [ "$test_status" = "404" ]; then
    ui_success "Red Hat SSO authenticated"
    return 0
  else
    echo "Error: SSO authentication verification failed (HTTP $test_status)" >&2
    return 1
  fi
}

rhkb_ensure_auth() {
  if [ ! -f "$RH_COOKIE_JAR" ] || [ ! -s "$RH_COOKIE_JAR" ]; then
    rhkb_auth
    return $?
  fi

  # 检测 cookie 有效性（访问 KB 页面，非 customer_profile API）
  local test_status
  test_status=$(curl -sS -b "$RH_COOKIE_JAR" -o /dev/null -w "%{http_code}" \
    --max-time 10 "https://access.redhat.com/solutions/2188281" 2>/dev/null)

  if [ "$test_status" = "302" ] || [ "$test_status" = "000" ]; then
    rhkb_auth
    return $?
  fi

  return 0
}
```

#### search_rhkb.sh

使用 hydra REST API（而非 spec 初稿猜测的 `/search/jcr:api/kcs`）：

```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"
source "$SHELLBOT_HOME/tools/rhkb_auth.sh"

query="$1"

if ! rhkb_ensure_auth; then
  echo "Error: Red Hat SSO authentication failed."
  exit 1
fi

encoded_query=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$query" 2>/dev/null)

search_result=$(curl -sS -b "$RH_COOKIE_JAR" \
  --max-time 30 \
  -H "Accept: application/json" \
  "https://access.redhat.com/hydra/rest/search/kcs?q=${encoded_query}&p=1&size=5" 2>/dev/null)

if [ -z "$search_result" ]; then
  echo "Error: Empty response from RH KB search"
  exit 1
fi

echo "$search_result" | jq -r '
  .response.docs[:5] | map(
    "[\(.allTitle // "Untitled")](\(.view_uri // ""))\n\(.publishedAbstract // .abstract // .brief_description // "")\n"
  ) | join("\n")
' 2>/dev/null
```

> URL 编码使用 `sys.argv[1]` 而非字符串插值，避免特殊字符注入。

#### read_rhkb.sh

双策略：优先从 hydra API 获取结构化数据，回退到 HTML 解析。

**策略 1 — hydra API**：

- 从 URL 提取 solution ID
- 用 `hydra/rest/search/kcs?q=id:{solution_id}` 查询
- 提取 Title、Issue、Environment、Resolution、Root Cause 等字段
- Resolution 若标记为 `subscriber_only`，显示提示信息

**策略 2 — HTML 解析**：

- 当 hydra API 无法获取完整内容时回退
- 用 python3 HTMLParser 解析 HTML 中的 `field_kcs_*` CSS 类
- 限制输出 8000 字符

### 4.4 计算工具

#### calc.sh

```bash
#!/usr/bin/env bash
python3 -c "
import sys, ast
try:
    expr = sys.argv[1]
    result = eval(expr, {'__builtins__': {}}, {
        'abs': abs, 'round': round, 'min': min, 'max': max,
        'pow': pow, 'sum': sum, 'int': int, 'float': float,
        'len': len, 'sorted': sorted, 'range': range,
    })
    print(result)
except Exception as e:
    print(f'Error: {e}')
" "$1"
```

> 使用受限 `__builtins__` + 白名单函数，防止代码注入。

---

## 5. 交互设计

### 5.1 启动与命令

```bash
# 单轮 ReAct 模式
shellbot

# Loop Agent 模式
shellbot --loop
shellbot -l

# 指定模型
shellbot --model anthropic/claude-sonnet-4
shellbot -m anthropic/claude-sonnet-4

# 调试模式
shellbot --debug
shellbot -d

# 非交互模式 (管道输入)
echo "检查当前系统负载" | shellbot --no-interactive
```

### 5.2 交互命令

| 命令 | 功能 |
|------|------|
| `/tools` | 列出可用工具 |
| `/clear` | 清空对话历史和 loop 上下文 |
| `/model` | 交互式切换 LLM 模型 |
| `/context` | 查看当前 Loop 上下文 (仅 loop 模式) |
| `/skip` | 跳过当前子目标 (仅 loop 模式) |
| `/stop` | 停止 Loop 执行 (仅 loop 模式) |
| `/debug` | 切换调试模式 (显示 API 请求/响应) |
| `/loop <goal>` | 在交互模式中启动 Loop 任务 |
| `/help` | 显示帮助 |
| `/quit` 或 `/exit` | 退出 |

### 5.3 输入处理

- 使用 `read -re` 启用 readline 支持，解决中文多字节字符退格问题
- 未以 `/` 开头的输入默认走 `react_run`
- `/loop <goal>` 可在交互模式中直接启动 loop，无需重启

### 5.4 输出示例

**单轮模式**：

```
user> RHEL 9 上怎么查看 firewalld 当前开放的端口？

── ReAct Step 1/8 ──
⏳ Thinking...
💭 Thought: 用户问的是 RHEL 9 firewalld 端口查看，我先执行命令获取当前状态
🔧 Action: run_shell | Input: firewall-cmd --list-ports 2>/dev/null || echo "firewalld not active"
📋 Observation: Observation: 80/tcp 443/tcp 22/tcp

── ReAct Step 2/8 ──
⏳ Thinking...

✅ Final Answer: 当前 firewalld 开放的端口为: 80/tcp, 443/tcp, 22/tcp。
   你也可以用 `firewall-cmd --list-all` 查看完整规则。
```

**Loop 模式**：

```
user> /loop 帮我全面检查这台 RHEL 9 服务器的安全配置，包括防火墙、SSH、SELinux

🎯 Goal: 全面检查 RHEL 9 服务器安全配置

═══ Loop Iteration 1/10 ═══
  → Sub-goal: 检查防火墙配置
  💭 Thought: 先查看 firewalld 状态和规则
  🔧 Action: run_shell | Input: firewall-cmd --state && firewall-cmd --list-all
  📋 Observation: running / services: ssh dhcpv6-client / ports: 80/tcp
  ✅ Sub-goal done: 防火墙运行中，开放了 ssh 和 80 端口

═══ Loop Iteration 2/10 ═══
  → Sub-goal: 检查 SSH 配置
  🔧 Action: run_shell | Input: grep -E 'PermitRootLogin|PasswordAuthentication|Port' /etc/ssh/sshd_config
  📋 Observation: PermitRootLogin yes / PasswordAuthentication yes / Port 22
  ✅ Sub-goal done: SSH 存在安全隐患

═══ Loop Iteration 3/10 ═══
  → Sub-goal: 检查 SELinux 状态
  🔧 Action: run_shell | Input: sestatus
  📋 Observation: SELinux status: enabled / Current mode: enforcing
  ✅ Sub-goal done: SELinux 配置正确

═══ Loop Iteration 4/10 ═══
  Planner: DONE

📊 State: DONE ✓

═══ 最终报告 ═══
1. 防火墙: ✅ 正常运行，建议限制 80 端口仅必要 IP
2. SSH: ⚠️  PermitRootLogin 和 PasswordAuthentication 均为 yes，
   建议改为 no 并启用密钥认证
3. SELinux: ✅ enforcing 模式，配置正确
```

---

## 6. 依赖与安装

### 6.1 必需依赖 (macOS 自带)

| 工具 | 用途 |
|------|------|
| bash | 主语言 (3.2+，不使用关联数组) |
| curl | API 调用 + 网页请求 |
| python3 | HTML 解析辅助、安全计算 |

### 6.2 需安装依赖

```bash
brew install jq          # JSON 解析 (核心依赖)
brew install coreutils   # timeout 命令 (GNU)
```

### 6.3 可选依赖

| 工具 | 用途 | 安装 |
|------|------|------|
| rich (Python) | Final Answer markdown 渲染（代码高亮、表格） | `pip3 install rich` |
| gum | Thinking 动画 spinner | `brew install gum` |
| rg (ripgrep) | 更快的文件搜索 | `brew install ripgrep` |

### 6.4 初始化

```bash
# 首次使用
mkdir -p ~/.shellbot
cp .env.example ~/.shellbot/.env
# 编辑 .env 填入 API keys

# 或使用 macOS Keychain
security add-generic-password -s "shellbot-openrouter" -a "$USER" -w "sk-xxx"
security add-generic-password -s "shellbot-tavily" -a "$USER" -w "tvly-xxx"
security add-generic-password -s "shellbot-jina" -a "$USER" -w "jina-xxx"
security add-generic-password -s "shellbot-rh" -a "$USER" -w "rh-password"
```

---

## 7. 错误处理

| 场景 | 处理 |
|------|------|
| API 调用失败 | 重试 `API_MAX_RETRIES` 次（指数退避），429/网络错误自动重试，仍失败则返回错误给 Agent 作为 Observation |
| 工具执行超时 | `timeout` 杀死进程（exit code 124），返回超时错误 |
| LLM 格式错误 | 回退：将整个响应当 Final Answer |
| RH SSO 登录失败 | 提示用户检查凭据 |
| Cookie 过期 | `rhkb_ensure_auth` 自动重新认证（检测 302/000 状态码） |
| 对话历史过长 | 自动截断保留最近 10 条消息 |
| Loop 超限 | 停止执行，输出已完成的部分结果 |
| Planner 调用失败 | 停止 loop，输出已获取的部分结果 |
| ReAct 内循环超限 | 返回 exit code 2，loop 记录 timeout 状态并继续 |

---

## 8. 已知限制与风险

| 项目 | 说明 | 缓解 |
|------|------|------|
| RH SSO 稳定性 | Keycloak 登录流程可能随 RH 更新变化 | 解析逻辑集中在 rhkb_auth.sh，易于更新 |
| RH SSO MFA | 如账号启用了 MFA，纯 curl 无法处理 | 首版不支持 MFA 账号，文档说明 |
| RH KB Resolution | hydra API 中标记为 `subscriber_only`，纯 curl 无法获取完整内容 | 显示提示信息，引导用户访问网页 |
| LLM 输出格式 | LLM 可能不严格遵循 ReAct 格式，或把 Action 和 Action Input 输出在同一行 | 多行结构化解析 + 同行合并 + 格式回退 |
| 流式 reasoning 显示 | 部分模型（如 qwen）reasoning 字段导致流式输出换行粘连 | reasoning 用 `printf '%s'` 逐字输出（不加额外换行）；只有 content 累积返回 |
| Token 消耗 | Loop 模式消耗较大 | 设置 max_iterations + 上下文截断 |
| shell 注入 | Agent 生成的 shell 命令可能有危险 | 危险模式检测 + auto/true 确认模式 |
| macOS bash 3.2 | 不支持 `declare -A` 关联数组 | 使用字符串匹配 + 函数分派 |
| macOS grep | 不支持 `-P` (PCRE) | 使用 bash regex + awk |
| `set -euo pipefail` | 在交互式程序中致命，子命令非零退出会终止整个脚本 | shellbot.sh 不使用，改为 `|| ui_error` 捕获错误 |
| 终端渲染 | 纯 ANSI 无法渲染 markdown 表格、代码高亮 | `ui_final` 使用 rich（回退到纯 ANSI）；gum 提供 spinner 动画 |

---

## 9. 审查记录 (Self-Review)

### 9.1 审查中发现的修正（已同步到正文）

| # | 严重度 | 问题 | 修正 | 正文对应 |
|---|--------|------|------|----------|
| 1 | **严重** | `grep -oP` (PCRE) 在 macOS 不可用 | 全部替换为 bash regex + awk | §3.3, §3.5, §3.6 |
| 2 | **严重** | macOS 无 `timeout` 命令 | 需 `brew install coreutils` | §6.2 |
| 3 | **严重** | `react_parse` 用 `\|` 分隔符，Action Input 含 `\|` 时解析错误 | 改用多行结构化输出（ACTION/thought/action/input 分行） | §3.3 |
| 4 | **高** | `api_chat` 中 `$?` 不是 HTTP status code | 改用 `-w "%{http_code}"` 分离 HTTP 状态码与 curl 退出码 | §3.2 |
| 5 | **高** | `calc.sh` `eval('$1')` 代码注入 | 改用受限 `__builtins__` + 白名单函数 | §4.4 |
| 6 | **高** | `run_shell.sh` 用 `exec eval` | 改为 `bash -c "$1"` | §4.1 |
| 7 | **高** | RH SSO 登录流程不完整 | 直接构造 SSO URL，手动跟随 302 重定向 | §4.3 |
| 8 | **中** | `curl -L` 跳过中间 cookie 捕获 | POST 后手动解析 Location header 跟随重定向 | §4.3 |
| 9 | **中** | URL 编码 `$query` 未转义 | 改用 `sys.argv[1]` | §4.3 |
| 10 | **中** | `history_get_messages` 全量读取 | 改用 `tail -n` 先截断 | §3.8 |
| 11 | **中** | `write_file.sh` 用 `echo` 丢失多行内容 | 改用 `printf '%s'` | §4.1 |
| 12 | **中** | `context_summary` jq 转义问题 | 调整引号策略 | §3.7 |
| 13 | **中** | `search_rhkb.sh` API 判断逻辑有误 | 改用 hydra REST API，移除 HTML 回退 | §4.3 |
| 14 | **低** | `rhkb_auth.sh` 路径依赖 PWD | 改用 `SHELLBOT_HOME` 绝对路径，移至 tools/ | §4.3 |
| 15 | **低** | "纯 Shell" 原则与 python3 依赖矛盾 | 修正为 "Bash 为主语言，CLI 工具组合" | §1.2 |
| 16 | **低** | `SHELL_CONFIRM=true` 全部确认体验差 | 新增 `auto` 模式（默认值），危险命令确认，普通自动 | §3.10 |

### 9.2 运行时发现并修正的问题

| # | 问题 | 修正 |
|---|------|------|
| 1 | `.env` 加载 `if [ -z "${!key}" ]` 只在变量为空时赋值，默认值覆盖 .env 配置 | 改为 `export "$key=$value"` 始终覆盖 |
| 2 | `set -euo pipefail` 在交互式程序中致命 | 从 shellbot.sh 移除，改为 `\|\| ui_error` |
| 3 | `read -r` 不用 readline，中文退格按字节删 UTF-8 | 改为 `read -re` 启用 readline |
| 4 | qwen 模型流式输出 reasoning 字段导致换行粘连 | reasoning 只做显示（`printf '%s'`），`content_accumulated` 只累积 content，避免污染 ReAct 解析 |
| 5 | LLM 把 Action 和 Action Input 输出同一行 | react_parse 添加同行合并处理 |
| 6 | RH KB search 用 `/search/jcr:api/kcs` 不可用 | 改用 `/hydra/rest/search/kcs` |
| 7 | `customer_profile` API 不适合检测 cookie 有效性 | 改用访问 KB 页面检测 |

### 9.3 设计原则修正

原 spec 1.2 节"纯 Shell"原则与实际依赖存在矛盾，已修正为：

| 原则 | 说明 |
|------|------|
| Bash 为主语言 | 所有流程控制、逻辑判断用 Bash 实现 |
| CLI 工具组合 | curl (HTTP)、jq (JSON)、python3 (HTML解析/计算) 为工具层 |
| 零 Agent 框架 | 不使用 pydanticAI、langchain 等 AI/Agent 框架 |
| 可审计 | 所有 Agent 思考过程、工具调用、结果对用户可见 |
| 安全优先 | 危险 shell 命令需确认；凭据不落地明文 |

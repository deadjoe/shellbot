# ShellBot — 纯 Shell Function Calling Loop Agent 规格说明书

> 定位：面向系统运维工程师的 AI Agent 助手  
> 技术栈：Bash + macOS CLI 工具 + API（零框架）  
> 版本：v0.2  
> 日期：2026-04-15

---

## 1. 项目概述

### 1.1 定位

ShellBot 是一个运行在 macOS 终端中的 AI Agent，面向系统运维工程师，具备以下核心能力：

- **本地系统操作**：执行 shell 命令、读写文件、搜索文件、检查服务状态
- **互联网搜索**：通用搜索（Tavily）、网页阅读（JINA Reader）
- **Red Hat KB 查询**：自动登录 SSO，搜索并阅读 access.redhat.com 知识库文章
- **自主推理与规划**：Function Calling + Loop 单对话流 + plan_step 工具
- **长期记忆**：SQLite3 + FTS5 全文检索，跨会话记忆存取

### 1.2 设计原则

| 原则 | 说明 |
|------|------|
| Bash 为主语言 | 所有流程控制、逻辑判断用 Bash 实现 |
| CLI 工具组合 | curl (HTTP)、jq (JSON)、python3 (HTML解析/计算)、sqlite3 (记忆存储) 为工具层 |
| 零 Agent 框架 | 不使用 pydanticAI、langchain 等 AI/Agent 框架 |
| 可审计 | 所有 Agent 思考过程、工具调用、结果对用户可见 |
| 安全优先 | 危险 shell 命令需确认；凭据不落地明文 |

### 1.3 运行模式

| 模式 | 启动方式 | 行为 |
|------|----------|------|
| 单轮 FC | `shellbot` | 一问一答，单次 Function Calling 循环 |
| Loop Agent | `shellbot --loop` 或交互中 `/loop <goal>` | 接受复杂任务，Function Calling 单对话流自主执行 |

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
│  │         Loop Agent (loop.sh) — 单对话流               │   │
│  │  ┌──────────────────────────────────────────────┐   │   │
│  │  │ 1. build_loop_messages() 构建初始消息          │   │   │
│  │  │    - system prompt + goal                      │   │   │
│  │  │    - memory_prefetch 注入相关记忆              │   │   │
│  │  │ 2. 每轮：调用 LLM with tools                   │   │   │
│  │  │ 3. 模型返回 tool_calls → 逐个执行工具           │   │   │
│  │  │    - plan_step: 记录到 context，不实际执行     │   │   │
│  │  │    - 其他工具: 调度执行，结果追加为 tool msg    │   │   │
│  │  │ 4. 工具结果 → 追加到 messages → 继续下一轮     │   │   │
│  │  │ 5. 模型返回纯 content → Final Answer → 结束    │   │   │
│  │  │ 6. 空响应 → nudge retry (最多2次)              │   │   │
│  │  │ 7. 支持 /skip /stop 用户控制                   │   │   │
│  │  └──────────────────────────────────────────────┘   │   │
│  └─────────────────────┬────────────────────────────────┘   │
│                        │                                     │
│  ┌─────────────────────▼────────────────────────────────┐   │
│  │      工具层 (tools.sh + tools_schema.sh + tools/)     │   │
│  │  ┌──────────┬──────────┬──────────┬──────────────┐   │   │
│  │  │ 本地操作  │ 互联网   │ RH KB    │ 记忆/规划    │   │   │
│  │  │ run_shell│search_web│search_rhkb│plan_step    │   │   │
│  │  │ read_file│read_webpg│read_rhkb │save_memory  │   │   │
│  │  │ write_fl │          │          │search_memory│   │   │
│  │  │ list_file│          │          │calc         │   │   │
│  │  │ search_fl│          │          │             │   │   │
│  │  └──────────┴──────────┴──────────┴──────────────┘   │   │
│  │  tools_schema.sh: 从 @tool/@param 注释自动生成        │   │
│  │  OpenAI Function Calling JSON Schema                  │   │
│  └─────────────────────┬────────────────────────────────┘   │
│                        │                                     │
│  ┌─────────────────────▼────────────────────────────────┐   │
│  │              基础设施层                               │   │
│  │  api.sh (OpenRouter+FC) │ history.sh │ context.sh     │   │
│  │  memory.sh (SQLite3)   │ compressor.sh │ config.sh   │   │
│  │  security.sh            │ ui.sh      │                │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 文件结构

```
shellbot/
├── shellbot.sh              # 主入口，参数解析，模式选择，REPL 循环
├── config.sh                # 全局配置 (API keys, model, limits, .env 加载)
├── lib/
│   ├── api.sh               # OpenRouter API 调用 (含重试、流式、Function Calling)
│   ├── react.sh             # 单轮 FC 引擎 (单轮模式使用，Function Calling 循环)
│   ├── loop.sh              # Loop Agent 控制器 (单对话流 + Function Calling)
│   ├── tools.sh             # 工具注册表 + 调度执行 + 参数解析
│   ├── tools_schema.sh      # 自动生成 OpenAI Function Calling JSON Schema
│   ├── history.sh           # 对话历史管理 (JSON Lines, tail 优化, 压缩)
│   ├── context.sh           # Loop 模式全局任务上下文 (steps 记录)
│   ├── memory.sh            # 长期记忆 (SQLite3 + FTS5 全文检索)
│   ├── compressor.sh        # 对话历史压缩 (LLM 摘要)
│   ├── ui.sh                # 终端 UI (颜色/格式化/多种显示函数)
│   └── security.sh          # 安全控制 (auto 确认模式)
├── tools/
│   ├── plan_step.sh         # 规划步骤声明 (虚拟工具，loop.sh 特殊处理)
│   ├── run_shell.sh         # 执行 shell 命令 (bash -c)
│   ├── read_file.sh         # 读取文件 (含存在性检查)
│   ├── write_file.sh        # 写入文件 (printf + JSON 验证)
│   ├── list_files.sh        # 列出目录
│   ├── search_files.sh      # 文件内容搜索 (rg/grep 自动检测)
│   ├── search_web.sh        # Tavily 搜索
│   ├── read_webpage.sh      # JINA Reader
│   ├── save_memory.sh       # 保存到长期记忆
│   ├── search_memory.sh     # 搜索长期记忆
│   ├── rhkb_auth.sh         # RH SSO 认证 (直接构造 SSO URL)
│   ├── search_rhkb.sh       # Red Hat KB 搜索 (hydra API)
│   ├── read_rhkb.sh         # Red Hat KB 文章阅读 (hydra API + HTML 双策略)
│   └── calc.sh              # 安全数学计算 (受限 eval)
├── prompts/
│   ├── system.sh            # System prompt 模板 (单轮模式)
│   └── loop_system.sh       # Loop 模式 System prompt (含 plan_step 引导)
└── data/
    └── .gitignore            # 忽略历史文件、cookie jar 和 memories.db
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

# ===== Memory =====
MEMORY_DB="$SHELLBOT_DATA_DIR/memories.db"

# ===== Context Compression =====
HISTORY_COMPRESS_THRESHOLD="${HISTORY_COMPRESS_THRESHOLD:-30000}"
HISTORY_COMPRESS_KEEP="${HISTORY_COMPRESS_KEEP:-10}"
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

调用 OpenRouter 的 OpenAI-compatible 接口，支持重试（指数退避）、流式输出和 Function Calling。

**非流式调用（含 Function Calling）**：

```bash
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
      -H "Authorization: Bearer $OPENR...KEY" \
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
```

> 与旧版 `api_chat()` 的关键区别：返回完整 API 响应 JSON（含 `choices[0].message.tool_calls`），而非仅提取 `content`。支持 `tools` 参数传入 Function Calling schema。

**流式调用（含 Function Calling + tool_calls 累积）**：

```bash
api_chat_stream_with_tools()
```

核心特性：

- 发送 `stream: true` 请求，解析 SSE 事件
- `delta.reasoning` 以 dim 样式实时显示到 stderr（推理模型如 deepseek-r1）
- `delta.content` 正常样式实时显示到 stderr，同时累积到 `content_accumulated`
- **tool_calls 累积**：按 `delta.tool_calls[0].index` 分组，逐 chunk 拼接 `function.name` 和 `function.arguments`，最终组装为完整 `tool_calls` 数组
- reasoning → content 切换时自动换行 + 重置颜色
- **只有 `content` 被累积返回**（不含 reasoning），避免解析被推理文本污染
- **Midstream error 检测**：SSE 中出现 `.error` 字段时（如 MiniMax 返回 "chat content is empty"），自动 fallback 到 `api_chat_with_tools` 非流式调用
- **空结果检测**：如果流式返回既无 `content` 也无 `tool_calls`，自动 fallback 到非流式调用，并将 SSE 数据保存到 `/tmp/shellbot_last_sse_debug.txt` 供调试
- 返回统一格式：`{content: "...", tool_calls: [...]}`，loop.sh 据此判断模型响应类型

**简单调用（用于压缩摘要）**：

```bash
api_chat_simple() {
  local messages="$1"
  local model="${2:-$DEFAULT_MODEL}"

  local response
  response=$(curl -sS --max-time "$API_TIMEOUT" \
    "$OPENROUTER_BASE_URL/chat/completions" \
    -H "Authorization: Bearer $OPENR...KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg model "$model" \
      --argjson messages "$messages" \
      '{model: $model, messages: $messages, temperature: 0.1, max_tokens: 1024}')" 2>/dev/null)

  echo "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null
}
```

> `api_chat_simple` 无 tools、低 temperature (0.1)、小 max_tokens (1024)，专用于 compressor 和 memory_extract 的 LLM 摘要调用。

> 默认 `SHELLBOT_STREAM=true` 时 `loop_run` 调用 `api_chat_stream_with_tools`；设为 `false` 则调用 `api_chat_with_tools`。

### 3.3 单轮 FC 引擎 (lib/react.sh)

单轮模式使用 Function Calling 循环，与 Loop 模式（§3.4）架构相同，只是 `max_iterations` 更少且无 `plan_step` 工具。代码中保留 `react_run` 函数名仅为向后兼容，实际已无 ReAct 文本解析逻辑。

**构建消息**：


```bash
build_react_messages() {
  local user_msg="$1"
  local context="${2:-}"

  local system_prompt
  system_prompt="$(prompt_system)"

  # Inject relevant memories
  local mem_context
  mem_context=$(memory_prefetch "$user_msg")
  if [ -n "$mem_context" ]; then
    system_prompt="$system_prompt

$mem_context"
  fi

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

**FC 主循环**：

```bash
react_run() {
  local user_msg="$1"
  local context="${2:-}"
  local messages
  messages=$(build_react_messages "$user_msg" "$context")

  local tools_schema
  tools_schema=$(tools_get_schema)

  local iteration=0
  while [ $iteration -lt $REACT_MAX_ITERATIONS ]; do
    iteration=$((iteration + 1))
    history_compress
    ui_iteration "$iteration" "$REACT_MAX_ITERATIONS"
    ui_thinking

    local response api_exit
    if [ "$SHELLBOT_STREAM" = "true" ]; then
      response=$(api_chat_stream_with_tools "$messages" "$tools_schema")
      api_exit=$?
      ui_done_thinking
    else
      response=$(api_chat_with_tools "$messages" "$tools_schema")
      api_exit=$?
      ui_done_thinking
    fi

    if [ $api_exit -ne 0 ]; then
      echo "ERROR: LLM call failed"
      return 1
    fi

    local content tool_calls
    if [ "$SHELLBOT_STREAM" = "true" ]; then
      content=$(echo "$response" | jq -r '.content // empty')
      tool_calls=$(echo "$response" | jq '.tool_calls // empty')
    else
      content=$(echo "$response" | jq -r '.choices[0].message.content // empty')
      tool_calls=$(echo "$response" | jq '.choices[0].message.tool_calls // empty')
    fi

    local has_tool_calls=false
    if [ -n "$tool_calls" ] && [ "$tool_calls" != "null" ] && [ "$tool_calls" != "[]" ]; then
      has_tool_calls=true
    fi

    if [ "$has_tool_calls" = true ]; then
      local assistant_msg
      if [ "$SHELLBOT_STREAM" = "true" ]; then
        assistant_msg=$(echo "$tool_calls" | jq \
          --arg content "$content" \
          '{role: "assistant", content: ($content // null), tool_calls: .}')
      else
        assistant_msg=$(echo "$response" | jq '.choices[0].message')
      fi
      messages=$(echo "$messages" | jq --argjson msg "$assistant_msg" '. + [$msg]')

      local tc_count=$(echo "$tool_calls" | jq 'length')
      local tc_idx=0
      while [ $tc_idx -lt $tc_count ]; do
        local tc_id tc_name tc_args
        tc_id=$(echo "$tool_calls" | jq -r ".[$tc_idx].id")
        tc_name=$(echo "$tool_calls" | jq -r ".[$tc_idx].function.name")
        tc_args=$(echo "$tool_calls" | jq -r ".[$tc_idx].function.arguments")

        ui_action "$tc_name" "$tc_args"

        local tool_input obs
        tool_input=$(parse_tool_input "$tc_name" "$tc_args")
        obs=$(tool_execute "$tc_name" "$tool_input" 2>&1)
        [ $? -ne 0 ] && [ -z "$obs" ] && obs="Error: Tool '$tc_name' failed"

        ui_observation "$obs"
        messages=$(echo "$messages" | jq \
          --arg tc_id "$tc_id" --arg obs "$obs" \
          '. + [{role: "tool", tool_call_id: $tc_id, content: $obs}]')

        tc_idx=$((tc_idx + 1))
      done

    elif [ -n "$content" ]; then
      ui_final "$content"
      history_append "user" "$user_msg"
      history_append "assistant" "$content"
      return 0
    else
      ui_warning "Empty response from LLM"
      return 1
    fi
  done

  ui_warning "Reached max FC iterations ($REACT_MAX_ITERATIONS)"
  return 2
}
```

> **与 Loop 模式的关系**：`react_run` 和 `loop_run` 的 FC 循环逻辑高度相似，主要差异：
> - `react_run` 无 `plan_step` 工具、无 `context_record`、无 nudge retry
> - `react_run` 使用 `REACT_MAX_ITERATIONS`（默认 8），`loop_run` 使用 `LOOP_MAX_ITERATIONS`（默认 10）
> - `react_run` 不剥离非标准字段（单轮对话无需担心历史污染）

### 3.4 Loop Agent 控制器 (lib/loop.sh)

Loop Agent 采用**单对话流 + Function Calling** 架构，取代旧版 planner + ReAct 文本解析双循环设计。规划能力通过 `plan_step` 工具实现，而非独立规划器模块。

**构建初始消息**：

```bash
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
```

> `memory_prefetch` 使用 FTS5 全文检索，从长期记忆中找出与 goal 最相关的 3 条记忆，注入系统提示。

**Loop 主循环**：

```bash
LOOP_SKIP_REQUESTED=false
LOOP_STOP_REQUESTED=false

loop_skip() { LOOP_SKIP_REQUESTED=true; }
loop_stop() { LOOP_STOP_REQUESTED=true; }

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
    _empty_response_retries=0

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
          '{role: "assistant", content: (if $content == "" then null else $content end), tool_calls: .}')
      else
        # Strip non-standard fields (reasoning, refusal, etc.)
        assistant_msg=$(echo "$response" | jq '.choices[0].message | {role, content, tool_calls}')
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
      # Empty response — retry with nudge instead of giving up immediately
      local empty_retries=${_empty_response_retries:-0}
      if [ $empty_retries -lt 2 ]; then
        _empty_response_retries=$((empty_retries + 1))
        ui_warning "Empty response from LLM (retry $((empty_retries + 1))/2)"
        messages=$(echo "$messages" | jq \
          --arg nudge "Please continue working on the goal. Respond with either a tool call or a final answer." \
          '. + [{role: "user", content: $nudge}]')
        continue
      fi
      ui_warning "Empty response from LLM after retries"
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
```

**关键设计点**：

| 特性 | 说明 |
|------|------|
| 单对话流 | 所有轮次共享同一个 `messages` 数组，LLM 自然看到完整上下文 |
| Function Calling | 模型通过 `tool_calls` 返回工具调用，而非解析文本格式 |
| plan_step 特殊处理 | `plan_step` 不作为普通工具执行，而是记录到 `context.json` 的 `steps` 数组，返回 "Step recorded" 提示模型继续行动 |
| 空响应 nudge retry | 追加 `{role: "user", content: "Please continue..."}` 消息重试最多 2 次 |
| 非标准字段剥离 | 构建历史消息时只保留 `{role, content, tool_calls}`，避免 MiniMax 等模型的非标准字段（reasoning, refusal）导致 0 token 问题 |
| history_compress | 每轮循环开始前检查历史长度，超阈值自动压缩 |

### 3.5 长期记忆 (lib/memory.sh)

基于 SQLite3 + FTS5 的跨会话记忆系统，支持自动提取和手动存取。

**数据库初始化**：

```bash
MEMORY_DB="$SHELLBOT_DATA_DIR/memories.db"

memory_init() {
  if [ ! -f "$MEMORY_DB" ]; then
    sqlite3 "$MEMORY_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS memories (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  content TEXT NOT NULL,
  category TEXT DEFAULT 'general',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
  content, category, content=memories, content_rowid=id
);
CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories BEGIN
  INSERT INTO memories_fts(rowid, content, category) VALUES (new.id, new.content, new.category);
END;
CREATE TRIGGER IF NOT EXISTS memories_ad AFTER DELETE ON memories BEGIN
  INSERT INTO memories_fts(memories_fts, rowid, content, category) VALUES ('delete', old.id, old.content, old.category);
END;
SQL
  fi
}
```

> 使用 FTS5 content table 模式：`memories` 表存储数据，`memories_fts` 虚拟表建索引。通过触发器自动同步 INSERT/DELETE。

**核心函数**：

| 函数 | 说明 |
|------|------|
| `memory_save <content> [category]` | 保存一条记忆，category 可选 (general/environment/preference/lesson) |
| `memory_search <query> [limit]` | FTS5 全文检索，查询词自动拆分为 OR 组合，按 rank 排序 |
| `memory_list` | 列出最近 20 条记忆（含 id, category, content 摘要, created_at） |
| `memory_delete <id>` | 按 ID 删除记忆（id 数字校验防 SQL 注入） |
| `memory_prefetch <query>` | 搜索与 query 相关的 3 条记忆，返回格式化文本用于注入系统提示 |
| `memory_extract <conversation>` | 用 LLM 从对话中自动提取值得记忆的事实，调用 `api_chat_simple` |

**SQL 注入防护**：`_sql_escape()` 将单引号替换为双单引号；`memory_delete` 校验 id 为纯数字。

**记忆工具**：

| 工具脚本 | 说明 |
|----------|------|
| `tools/save_memory.sh` | LLM 可调用 `save_memory` 工具主动保存重要信息 |
| `tools/search_memory.sh` | LLM 可调用 `search_memory` 工具检索历史记忆 |

### 3.6 上下文压缩 (lib/compressor.sh + lib/history.sh)

当对话历史过长时，自动压缩早期消息为摘要，保留最近消息。

**触发机制**：

```bash
# config.sh
HISTORY_COMPRESS_THRESHOLD="${HISTORY_COMPRESS_THRESHOLD:-30000}"  # 字符数阈值
HISTORY_COMPRESS_KEEP="${HISTORY_COMPRESS_KEEP:-10}"               # 保留最近 N 条

# history.sh 中 history_compress() 在 loop_run 每轮开始前调用
history_compress() {
  local keep="${1:-$HISTORY_COMPRESS_KEEP}"
  local threshold="${2:-$HISTORY_COMPRESS_THRESHOLD}"

  local total
  total=$(history_total_chars)

  if [ "$total" -lt "$threshold" ]; then
    return 0  # No compression needed
  fi

  # ... 分割、摘要、重建
}
```

**压缩流程**：

1. `history_total_chars()` 计算当前历史总字符数
2. 超过 `HISTORY_COMPRESS_THRESHOLD`（默认 30000 字符）时触发
3. 将消息分为早期和最近两部分（保留最近 `HISTORY_COMPRESS_KEEP` = 10 条）
4. `compress_summarize()` 调用 `api_chat_simple` 对早期消息生成 LLM 摘要
5. 重建历史文件：`[{role: "system", content: "[Summary] ..."}]` + 最近消息

**compressor.sh**：

```bash
compress_summarize() {
  local messages="$1"

  local compress_prompt='Summarize the conversation above. Preserve:
- Key findings and discoveries
- Completed steps and their results
- User preferences and constraints
- Unresolved issues or errors
- Important context for continuing the task

Be concise. Output only the summary.'

  local request_messages
  request_messages=$(jq -n --argjson msgs "$messages" --arg prompt "$compress_prompt" \
    '$msgs + [{role: "user", content: $prompt}]')

  api_chat_simple "$request_messages"
}
```

> `compress_summarize` 通过 `api_chat_simple` 调用 LLM，低 temperature (0.1) 确保摘要稳定，max_tokens (1024) 控制摘要长度。

### 3.7 任务上下文 (lib/context.sh)

上下文以 JSON 文件存储，由 jq 维护。Loop 模式下记录规划步骤：

```json
{
  "goal": "用户原始目标",
  "steps": [
    {
      "id": 1,
      "step": "检查防火墙配置",
      "rationale": "先确认防火墙是否正常运行"
    },
    {
      "id": 2,
      "step": "检查 SSH 配置",
      "rationale": "SSH 是常见攻击面"
    }
  ],
  "iteration": 2
}
```

> 与旧版不同，steps 只记录 `plan_step` 工具调用的步骤声明（step + rationale），不再有 status/result/reflections 字段。实际执行结果由 LLM 在对话流中自然维护。

**上下文函数**：

```bash
context_init() {
  local goal="$1"
  jq -n --arg goal "$goal" \
    '{goal: $goal, steps: [], iteration: 0}' \
    > "$CONTEXT_FILE"
}

context_record_step() {
  local step="$1"
  local rationale="${2:-}"

  local current
  current=$(cat "$CONTEXT_FILE" 2>/dev/null || echo '{}')
  local next_id
  next_id=$(echo "$current" | jq '.steps | length + 1')

  echo "$current" | jq \
    --arg step "$step" \
    --arg rationale "$rationale" \
    --argjson id "$next_id" \
    --argjson iter "$(($(echo "$current" | jq '.iteration') + 1))" \
    '.steps += [{id: $id, step: $step, rationale: $rationale}] |
     .iteration = $iter' \
    > "$CONTEXT_FILE"
}

context_summary() {
  if [ ! -f "$CONTEXT_FILE" ]; then
    echo ""
    return
  fi
  jq -r '
    "Goal: \(.goal)\n" +
    "Steps:\n" +
    (.steps | map("  [\(.id)] \(.step)\(if .rationale then " — \(.rationale)" else "" end)") | join("\n"))
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

history_total_chars() {
  if [ ! -f "$HISTORY_FILE" ] || [ ! -s "$HISTORY_FILE" ]; then
    echo 0
    return
  fi
  tail -n 100 "$HISTORY_FILE" | jq -s '[.[].content | length] | add // 0'
}

# Compress history: summarize early messages, keep recent ones
# Called by loop_run at each iteration start
history_compress() {
  local keep="${1:-$HISTORY_COMPRESS_KEEP}"
  local threshold="${2:-$HISTORY_COMPRESS_THRESHOLD}"

  local total
  total=$(history_total_chars)

  if [ "$total" -lt "$threshold" ]; then
    return 0  # No compression needed
  fi

  # Load compressor lazily (avoids circular source)
  source "$SHELLBOT_HOME/lib/compressor.sh"
  source "$SHELLBOT_HOME/lib/ui.sh"

  ui_info "Compressing conversation history (${total} chars)..."

  local all_messages
  all_messages=$(history_get_messages 1000)
  local total_count
  total_count=$(echo "$all_messages" | jq 'length')

  if [ "$total_count" -le "$keep" ]; then
    return 0
  fi

  # Split: early messages for summarization, keep recent ones
  local early_messages
  early_messages=$(echo "$all_messages" | jq --argjson keep "$keep" '.[:-($keep)]')
  local recent_messages
  recent_messages=$(echo "$all_messages" | jq --argjson keep "$keep" '.[-($keep):]')

  # Summarize early messages via LLM
  local summary
  summary=$(compress_summarize "$early_messages")

  if [ -z "$summary" ]; then
    ui_warning "Compression failed: could not generate summary"
    return 1
  fi

  # Rebuild history file: summary + recent messages
  > "$HISTORY_FILE"
  jq -nc --arg content "[Summary of earlier conversation] $summary" \
    --argjson ts "$(date +%s)" \
    '{role: "system", content: $content, timestamp: $ts}' >> "$HISTORY_FILE"
  echo "$recent_messages" | jq -c '.[]' | while IFS= read -r msg; do
    echo "$msg" >> "$HISTORY_FILE"
  done

  ui_success "History compressed: $total_count messages → summary + $keep recent"
  return 0
}
```

### 3.9 工具系统 (lib/tools.sh + lib/tools_schema.sh)

**工具注册表**（字符串匹配，兼容 macOS bash 3.2）：

```bash
TOOL_NAMES="calc list_files plan_step read_file read_rhkb read_webpage run_shell save_memory search_files search_memory search_rhkb search_web write_file"

tools_list() {
  echo "$TOOL_NAMES" | tr ' ' '\n' | sort
}

_tool_get_script() {
  local name="$1"
  echo "$SHELLBOT_HOME/tools/${name}.sh"
}
```

> `plan_step`、`save_memory`、`search_memory` 为新增工具。`rhkb_auth` 标记为 internal，不在 TOOL_NAMES 中暴露给 LLM。

**参数解析**（Function Calling 模式需要）：

```bash
# Parse tool arguments into the format expected by tool scripts
# Multi-param tools get raw JSON; single-param tools get the extracted value
parse_tool_input() {
  local tool_name="$1"
  local args_json="$2"

  case "$tool_name" in
    write_file|save_memory|search_memory)
      # These tools expect raw JSON and parse it internally
      echo "$args_json"
      ;;
    *)
      # Single-param tools: extract the first (and usually only) param value
      local first_val
      first_val=$(echo "$args_json" | jq -r 'to_entries[0].value // .' 2>/dev/null)
      if [ -n "$first_val" ] && [ "$first_val" != "null" ]; then
        echo "$first_val"
      else
        echo "$args_json"
      fi
      ;;
  esac
}
```

> Function Calling 返回 JSON 参数（如 `{"command": "ls -la"}`），需要解析提取。单参数工具取第一个值，多参数工具（write_file, save_memory）传原始 JSON。

**工具 Schema 自动生成** (lib/tools_schema.sh)：

```bash
# Generate OpenAI tools JSON schema from tool script @tool/@param comments
tools_get_schema() {
  local items=""

  for tool_name in $TOOL_NAMES; do
    local script="$SHELLBOT_HOME/tools/${tool_name}.sh"
    [ ! -f "$script" ] && continue

    # Parse @tool description
    local desc=""
    desc=$(grep -m1 '^# @tool ' "$script" | sed 's/^# @tool //')
    [ -z "$desc" ] && continue
    # Skip internal tools
    echo "$desc" | grep -qi "internal" && continue

    # Parse @param lines
    local properties="{}"
    local required="[]"

    while IFS= read -r line; do
      # Format: # @param name:type[(required)] description
      local pname pdesc
      pname=$(echo "$line" | sed 's/^# @param //' | cut -d: -f1)
      pdesc=$(echo "$line" | sed 's/^# @param [^ ]* //' | sed 's/(required) //; s/(optional) //')

      properties=$(echo "$properties" | jq \
        --arg name "$pname" \
        --arg desc "$pdesc" \
        '. + {($name): {type: "string", description: $desc}}')

      if echo "$line" | grep -q '(required)'; then
        required=$(echo "$required" | jq --arg name "$pname" '. + [$name]')
      fi
    done < <(grep '^# @param ' "$script")

    # Build tool item
    local item
    item=$(jq -n \
      --arg name "$tool_name" \
      --arg desc "$desc" \
      --argjson props "$properties" \
      --argjson reqs "$required" \
      '{
        type: "function",
        function: {
          name: $name,
          description: $desc,
          parameters: {
            type: "object",
            properties: $props,
            required: $reqs
          }
        }
      }')

    if [ -z "$items" ]; then
      items=$(echo "$item" | jq -s '.')
    else
      items=$(echo "$items" | jq --argjson item "$item" '. + [$item]')
    fi
  done

  if [ -z "$items" ]; then
    echo "[]"
  else
    echo "$items"
  fi
}
```

> 每个工具脚本头部使用 `# @tool` 和 `# @param` 注释声明元数据，`tools_get_schema` 自动扫描生成 OpenAI Function Calling JSON Schema。例如 `run_shell.sh` 的注释：
> ```
> # @tool Execute a shell command on the local system
> # @param command:string(required) The shell command to execute
> ```

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
  result=$(_run_with_timeout "$TOOL_TIMEOUT" bash "$script" "$tool_input" 2>&1)
  local exit_code=$?

  if [ $exit_code -eq 124 ]; then
    echo "Error: Tool execution timed out (${TOOL_TIMEOUT}s)"
    return 1
  fi

  echo "$result"
  return $exit_code
}
```

> 使用 `_run_with_timeout` 跨平台超时包装（优先 GNU `timeout`，回退 `gtimeout`，最终纯 bash 后台进程方案）。

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
ui_iteration()    { echo -e "${DIM}── Step $1/$2 ──${NC}"; }
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
# 单轮 FC 模式
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

── Step 1/8 ──
⏳ Thinking...
💭 Thought: 用户问的是 RHEL 9 firewalld 端口查看，我先执行命令获取当前状态
🔧 Action: run_shell | Input: firewall-cmd --list-ports 2>/dev/null || echo "firewalld not active"
📋 Observation: Observation: 80/tcp 443/tcp 22/tcp

── Step 2/8 ──
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
brew install sqlite3     # 长期记忆存储 + FTS5 全文检索
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
| API 调用失败 | 重试 `API_MAX_RETRIES` 次（指数退避），429/网络错误自动重试，仍失败则返回错误给 Agent |
| 工具执行超时 | `_run_with_timeout` 杀死进程（exit code 124），返回超时错误 |
| LLM 返回空响应 | nudge retry 最多 2 次，追加 user 消息鼓励模型响应 |
| 流式 midstream error | 自动 fallback 到 `api_chat_with_tools` 非流式调用 |
| 流式空结果 | 自动 fallback 到非流式调用，SSE 数据保存到 `/tmp/shellbot_last_sse_debug.txt` |
| 非标准字段 | 构建历史消息时只保留 `{role, content, tool_calls}`，避免 MiniMax 等模型非标准字段问题 |
| RH SSO 登录失败 | 提示用户检查凭据 |
| Cookie 过期 | `rhkb_ensure_auth` 自动重新认证（检测 302/000 状态码） |
| 对话历史过长 | 自动压缩：超过 30000 字符触发 LLM 摘要，保留最近 10 条消息 |
| Loop 超限 | 停止执行，输出已完成的部分结果 |
| 压缩摘要失败 | 保留原始历史，显示警告 |

---

## 8. 已知限制与风险

| 项目 | 说明 | 缓解 |
|------|------|------|
| RH SSO 稳定性 | Keycloak 登录流程可能随 RH 更新变化 | 解析逻辑集中在 rhkb_auth.sh，易于更新 |
| RH SSO MFA | 如账号启用了 MFA，纯 curl 无法处理 | 首版不支持 MFA 账号，文档说明 |
| RH KB Resolution | hydra API 中标记为 `subscriber_only`，纯 curl 无法获取完整内容 | 显示提示信息，引导用户访问网页 |
| Token 消耗 | Loop 模式消耗较大 | 设置 max_iterations + 上下文压缩 |
| shell 注入 | Agent 生成的 shell 命令可能有危险 | 危险模式检测 + auto/true 确认模式 |
| macOS bash 3.2 | 不支持 `declare -A` 关联数组 | 使用字符串匹配 + 函数分派 |
| macOS grep | 不支持 `-P` (PCRE) | 使用 bash regex + awk |
| `set -euo pipefail` | 在交互式程序中致命，子命令非零退出会终止整个脚本 | shellbot.sh 不使用，改为 `|| ui_error` 捕获错误 |
| 终端渲染 | 纯 ANSI 无法渲染 markdown 表格、代码高亮 | `ui_final` 使用 rich（回退到纯 ANSI）；gum 提供 spinner 动画 |
| 记忆提取质量 | LLM 自动提取记忆可能包含噪声 | memory_extract 跳过短对话 (<200字)，过滤纯序号/符号行 |
| FTS5 分词 | SQLite FTS5 默认 tokenizer 不支持中文分词 | 使用 OR 组合查询词作为近似匹配 |
| 压缩信息丢失 | 早期对话压缩为摘要后细节可能丢失 | 保留最近 10 条消息，摘要保留关键发现 |

---

## 9. 审查记录 (Self-Review)

### 9.1 审查中发现的修正（已同步到正文）

| # | 严重度 | 问题 | 修正 | 正文对应 |
|---|--------|------|------|----------|
| 1 | **严重** | `grep -oP` (PCRE) 在 macOS 不可用 | 全部替换为 bash regex + awk | §3.3, §3.5, §3.6 |
| 2 | **严重** | macOS 无 `timeout` 命令 | 需 `brew install coreutils` | §6.2 |
| 3 | **严重** | `react_parse` 用 `\|` 分隔符，Action Input 含 `\|` 时解析错误 | 已移除 `react_parse`，改用 Function Calling，无需文本解析 | §3.3 |
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
| 4 | qwen 模型流式输出 reasoning 字段导致换行粘连 | reasoning 只做显示（`printf '%s'`），`content_accumulated` 只累积 content |
| 5 | LLM 把 Action 和 Action Input 输出同一行 | 已改用 Function Calling，不再有文本格式问题 |
| 6 | RH KB search 用 `/search/jcr:api/kcs` 不可用 | 改用 `/hydra/rest/search/kcs` |
| 7 | `customer_profile` API 不适合检测 cookie 有效性 | 改用访问 KB 页面检测 |

### 9.3 v0.2 架构变更记录

v0.2 将 Loop Agent 从 planner + ReAct 文本解析双循环架构重构为 Function Calling 单对话流架构：

| # | 变更 | 说明 |
|---|------|------|
| 1 | 移除 planner.sh | 规划能力通过 `plan_step` 工具实现，不再需要独立规划器 |
| 2 | 移除 reflector.sh | 模型在单对话流中自然进行失败分析和策略调整 |
| 3 | 新增 Function Calling | `api_chat_with_tools` / `api_chat_stream_with_tools` 取代旧版 `api_chat` / `api_chat_stream` |
| 4 | 新增 tools_schema.sh | 从 `@tool` / `@param` 注释自动生成 OpenAI Function Calling JSON Schema |
| 5 | 新增 memory.sh | SQLite3 + FTS5 长期记忆，支持跨会话存取 |
| 6 | 新增 compressor.sh | 对话历史自动压缩，超 30000 字符触发 LLM 摘要 |
| 7 | 新增 plan_step 工具 | Loop 中特殊处理，记录步骤到 context 而非实际执行 |
| 8 | 新增 save_memory / search_memory 工具 | LLM 可主动存取长期记忆 |
| 9 | 移除 prompts/react_format.sh | Function Calling 不需要 ReAct 格式说明（已移除文本解析） |
| 10 | 移除 prompts/tools_desc.sh | 工具描述通过 Function Calling schema 传递，不再注入 prompt |
| 11 | 新增 prompts/loop_system.sh | Loop 模式系统提示，含 plan_step 引导 |
| 12 | context 结构简化 | `steps` 取代 `sub_goals` + `reflections`，不再有 status/result |
| 13 | 空响应 nudge retry | 追加 user 消息重试最多 2 次 |
| 14 | 非标准字段剥离 | 历史消息只保留 `{role, content, tool_calls}` |
| 15 | 流式 midstream error 处理 | 自动 fallback 到非流式调用 |
| 16 | 跨平台 timeout | `_run_with_timeout` 替代 GNU `timeout` |

### 9.4 设计原则修正

原 spec 1.2 节"纯 Shell"原则与实际依赖存在矛盾，已修正为：

| 原则 | 说明 |
|------|------|
| Bash 为主语言 | 所有流程控制、逻辑判断用 Bash 实现 |
| CLI 工具组合 | curl (HTTP)、jq (JSON)、python3 (HTML解析/计算)、sqlite3 (记忆存储) 为工具层 |
| 零 Agent 框架 | 不使用 pydanticAI、langchain 等 AI/Agent 框架 |
| 可审计 | 所有 Agent 思考过程、工具调用、结果对用户可见 |
| 安全优先 | 危险 shell 命令需确认；凭据不落地明文 |

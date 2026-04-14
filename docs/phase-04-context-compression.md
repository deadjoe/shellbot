# Phase 04: 上下文压缩

> 目标：用摘要压缩替代粗暴截断，在对话变长时保留关键信息而不是直接丢弃

## 问题

当前对话历史管理是 `tail -n` 截断——超过长度直接丢掉老消息。这意味着 Agent 会"失忆"：忘记前面做过什么、发现了什么、用户说了什么。

## 方案

当对话历史接近 token 上限时，用 LLM 对早期消息做摘要压缩，保留关键信息：

- **压缩触发**：消息总字符数超过阈值（默认 30000 字符）
- **压缩策略**：保留最近 N 条消息不动，对更早的消息做摘要
- **摘要存储**：摘要作为一条特殊 system 消息插入对话历史
- **摘要内容**：关键发现、已完成的步骤、用户偏好、未解决的问题

## 实现计划

### 1. 修改 `lib/history.sh`

新增压缩相关函数：

```bash
# 计算消息总字符数
history_total_chars() {
  if [ ! -f "$HISTORY_FILE" ] || [ ! -s "$HISTORY_FILE" ]; then
    echo 0
    return
  fi
  tail -n 100 "$HISTORY_FILE" | jq -s '[.[].content | length] | add // 0'
}

# 压缩历史：保留最近 N 条，其余做摘要
history_compress() {
  local keep="${1:-10}"
  local threshold="${2:-30000}"
  
  local total
  total=$(history_total_chars)
  
  if [ "$total" -lt "$threshold" ]; then
    return 0  # 不需要压缩
  fi
  
  ui_info "Compressing conversation history..."
  
  # 读取所有消息
  local all_messages
  all_messages=$(history_get_messages 1000)
  local total_count
  total_count=$(echo "$all_messages" | jq 'length')
  
  if [ "$total_count" -le "$keep" ]; then
    return 0  # 消息数不多，不需要压缩
  fi
  
  # 分割：早期消息做摘要，保留最近 N 条
  local early_messages
  early_messages=$(echo "$all_messages" | jq --argjson keep "$keep" '.[:-($keep)]')
  
  local recent_messages  
  recent_messages=$(echo "$all_messages" | jq --argjson keep "$keep" '.[-($keep):]')
  
  # 用 LLM 做摘要
  local summary
  summary=$(compress_summarize "$early_messages")
  
  if [ -z "$summary" ]; then
    return 1
  fi
  
  # 重建历史文件：摘要 + 最近消息
  > "$HISTORY_FILE"
  
  # 写入摘要作为 system 消息
  jq -n --arg content "[Summary of earlier conversation] $summary" \
    '{role: "system", content: $content, timestamp: (now | floor)}' >> "$HISTORY_FILE"
  
  # 写入最近消息
  echo "$recent_messages" | jq -c '.[]' >> "$HISTORY_FILE"
  
  ui_success "History compressed: $total_count messages → summary + $keep recent"
  return 0
}
```

### 2. 新增 `lib/compressor.sh`

摘要生成函数：

```bash
compress_summarize() {
  local messages="$1"
  
  # 构造压缩 prompt
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
  
  # 用当前模型做摘要（低 temperature）
  api_chat_compact "$request_messages"
}
```

### 3. 修改 `lib/api.sh`

新增 `api_chat_compact()`：简化版 API 调用，用于压缩摘要

```bash
api_chat_compact() {
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
  
  echo "$response" | jq -r '.choices[0].message.content // empty'
}
```

### 4. 修改 `lib/react.sh`

在 `react_run()` 循环中，每次迭代前检查是否需要压缩：

```bash
react_run() {
  ...
  while [ $iteration -lt $REACT_MAX_ITERATIONS ]; do
    # 检查并压缩历史
    history_compress
    ...
  done
}
```

### 5. 修改 `lib/loop.sh`

在 `loop_run()` 每次迭代前也检查压缩：

```bash
loop_run() {
  ...
  while [ $iteration -lt $LOOP_MAX_ITERATIONS ]; do
    history_compress
    ...
  done
}
```

### 6. 修改 `config.sh`

新增配置项：

```bash
HISTORY_COMPRESS_THRESHOLD="${HISTORY_COMPRESS_THRESHOLD:-30000}"
HISTORY_COMPRESS_KEEP="${HISTORY_COMPRESS_KEEP:-10}"
```

## 配置项

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `HISTORY_COMPRESS_THRESHOLD` | 30000 | 触发压缩的字符数阈值 |
| `HISTORY_COMPRESS_KEEP` | 10 | 压缩时保留最近 N 条消息 |

## 测试

```bash
# 制造长对话触发压缩
bash shellbot.sh --no-interactive <<'EOF'
Tell me about the following topics one by one: 1) What is the current date, 2) List files in /tmp, 3) Read /etc/hosts, 4) Calculate 100*200, 5) List files in /var, 6) What is the hostname, 7) Read /etc/resolv.conf, 8) Calculate 999/3, 9) List files in ~/github, 10) What is the uptime
EOF

# 交互模式测试
bash shellbot.sh
# 连续提问多个问题，观察是否触发压缩
# /clear 后查看历史文件
```

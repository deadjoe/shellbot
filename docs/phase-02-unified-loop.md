# Phase 02: 统一 Planner-Executor 对话流

> 目标：消除 Planner 和 Executor 的割裂，让 Planner 在同一个对话流中看到执行细节，做出更合理的决策

## 问题

当前 Loop 模式中，每次 Planner 调用是独立的 LLM 请求，只看到 `context_summary` 摘要：

```
Planner LLM call → "检查防火墙"  (只看到摘要)
  React LLM calls → 执行过程... (Planner 看不到)
Planner LLM call → "检查 SSH"   (还是只看到摘要)
```

导致：
- Planner 不知道 Executor 遇到了什么具体细节
- 每次规划是无状态的，没有连续思考
- context_summary 丢信息，Planner 可能做出不合理决策

## 方案

把 Loop 模式改为**单对话流**——Planner 和 Executor 共享同一个 messages 数组：

```
system prompt + 任务目标 → LLM → tool_calls(规划) → tool result → LLM → tool_calls(执行) → tool result → LLM → ...
```

### 核心变化

Planner 不再是独立的 LLM 调用，而是**通过 system prompt 引导 LLM 在同一个对话流中既规划又执行**。

### 实现方式

引入一个特殊的 `plan_step` 工具：

```json
{
  "name": "plan_step",
  "description": "Declare the next step you will take toward the overall goal. Use this before taking action.",
  "parameters": {
    "type": "object",
    "properties": {
      "step": { "type": "string", "description": "Description of the next step" },
      "rationale": { "type": "string", "description": "Why this step is needed" }
    },
    "required": ["step"]
  }
}
```

Loop 对话流：

1. LLM 调用 `plan_step`（声明下一步做什么）
2. 系统返回确认 "Step recorded. Proceed with your plan."
3. LLM 调用实际工具（run_shell, read_file 等）
4. 工具结果返回，LLM 决定下一步
5. 重复直到 LLM 直接回复 Final Answer（不再调用任何工具）

### 好处

- Planner 看到完整执行历史，决策更准
- 只需一个对话流，减少 API 调用次数
- 不需要 `planner.sh`、`reflector.sh`、`context.sh` 的复杂编排
- LLM 自己决定"要不要调整方向"（内在反思）

## 实现计划

### 1. 修改 `lib/loop.sh`

重写 `loop_run()`：

```bash
loop_run() {
  local goal="$1"
  
  # 构建包含目标 + plan_step 工具的 messages
  local messages
  messages=$(build_loop_messages "$goal")
  
  local iteration=0
  while [ $iteration -lt $LOOP_MAX_ITERATIONS ]; do
    iteration=$((iteration + 1))
    ui_loop_header "$iteration" "$LOOP_MAX_ITERATIONS"
    
    # 调用 LLM（带 tools）
    local response
    response=$(api_chat_with_tools "$messages")
    
    # 解析响应
    if has_tool_calls "$response"; then
      # 处理工具调用（plan_step 或其他工具）
      process_tool_calls "$response" "$messages"
    else
      # Final Answer
      local answer=$(extract_content "$response")
      ui_final "$answer"
      history_append "assistant" "$answer"
      return 0
    fi
  done
  
  ui_loop_timeout
  return 2
}
```

### 2. 修改 `lib/tools.sh`

- 将 `plan_step` 加入工具列表
- `plan_step` 的执行：记录到 context 并返回确认

### 3. 修改 `lib/tools_schema.sh`

- `plan_step` 工具加入 schema

### 4. 修改 `lib/context.sh`

- 简化：只记录 plan steps，不再管理复杂的 sub_goals/reflections 结构
- 新增 `context_record_step()` 记录步骤

### 5. 简化/移除模块

- `lib/planner.sh`：**移除**（规划能力由 LLM 在对话流中自然完成）
- `lib/reflector.sh`：**移除**（反思由 LLM 在对话流中自然完成，看到失败结果后自己调整）
- `prompts/react_format.sh`：已移除（Phase 01）

### 6. 新增 Loop System Prompt

`prompts/loop_system.sh`：

```
You are an autonomous system operations agent. You have a goal to achieve.

Before taking each action, use the plan_step tool to declare what you will do and why.
Then use the appropriate tool to execute.

If a step fails, analyze why and try a different approach.
When the goal is fully achieved, provide a final summary as your response (without calling any tools).

Goal: {goal}
```

### 7. 修改 `lib/ui.sh`

- 新增 `ui_plan_step()` 显示规划步骤
- 移除 `ui_subgoal()`（由 `ui_plan_step()` 替代）

## 保留的功能

- `/skip` 和 `/stop` 仍然支持（检查标志位）
- 上下文文件仍然记录进度
- 安全检查不受影响

## 测试

```bash
# Loop 模式测试
echo "List all running services and check if sshd is running" | bash shellbot.sh --loop --no-interactive
echo "Check disk usage and identify the largest directories" | bash shellbot.sh --loop --no-interactive

# 交互模式测试
bash shellbot.sh --loop
# /loop 检查系统资源使用情况
# 观察 plan_step → tool call → result 的流畅度
```

# Phase 01: Function Calling（替代文本 ReAct 解析）

> 目标：用 OpenAI Function Calling API 替代文本 ReAct 格式解析，从根本上解决 LLM 输出格式不可控的问题

## 问题

当前 ReAct 引擎让 LLM 输出纯文本格式：

```
Thought: 我需要检查防火墙
Action: run_shell
Action Input: firewall-cmd --list-all
```

然后用正则逐行解析。LLM 不守规矩时（格式变形、同行输出、缺失字段），解析频繁失败。

## 方案

改用 OpenAI Function Calling / Tool Use API：

1. 在 API 请求中声明 `tools` 参数（JSON Schema 格式），描述每个工具的名称、描述、参数
2. LLM 返回结构化的 `tool_calls`，API 层保证格式正确
3. 工具执行结果以 `tool` role 消息回传

### API 请求变化

**Before（文本 ReAct）：**
```json
{
  "model": "...",
  "messages": [...],
  "temperature": 0.3
}
```

**After（Function Calling）：**
```json
{
  "model": "...",
  "messages": [...],
  "temperature": 0.3,
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "run_shell",
        "description": "Execute a shell command on the local system",
        "parameters": {
          "type": "object",
          "properties": {
            "command": { "type": "string", "description": "The shell command to execute" }
          },
          "required": ["command"]
        }
      }
    }
  ]
}
```

### LLM 响应变化

**Before（纯文本 content）：**
```json
{"choices": [{"message": {"role": "assistant", "content": "Thought: ...\nAction: run_shell\nAction Input: ls"}}]}
```

**After（结构化 tool_calls）：**
```json
{"choices": [{"message": {"role": "assistant", "content": null, "tool_calls": [{"id": "call_abc", "type": "function", "function": {"name": "run_shell", "arguments": "{\"command\": \"ls\"}"}}]}}]}
```

### 消息流变化

```
user → assistant (tool_calls) → tool (result) → assistant (tool_calls or content) → ...
```

当 `message.content` 非空且无 `tool_calls` 时，视为 Final Answer。

## 实现计划

### 1. 新增 `lib/tools_schema.sh`

- 函数 `tools_get_schema()`：生成 OpenAI tools JSON 数组
- 从 tools/ 目录自动发现工具，每个工具文件头注释声明参数 schema
- 兼容方式：工具文件头部用特殊注释声明参数，如：

```bash
# @tool Execute a shell command on the local system
# @param command:string(required) The shell command to execute
```

### 2. 修改 `lib/api.sh`

- `api_chat()` 和 `api_chat_stream()`：接受可选 `tools` 参数
- 请求体包含 `tools` 字段
- 解析响应时同时处理 `content` 和 `tool_calls`

### 3. 修改 `lib/react.sh`

- `build_react_messages()`：移除 ReAct 格式 prompt，改用 system prompt + tools schema
- `react_run()`：
  - 不再调用 `react_parse()`
  - 直接检查 `tool_calls` 字段
  - 有 `tool_calls` → 执行工具，结果作为 `tool` role 消息追加
  - 无 `tool_calls` 且有 `content` → Final Answer
  - 追加 `tool` 消息时需携带 `tool_call_id`
- 移除 `react_parse()` 函数

### 4. 修改 `prompts/`

- `system.sh`：简化，移除 ReAct 格式说明，保留角色和约束
- `react_format.sh`：移除（不再需要格式指导）
- `tools_desc.sh`：移除（工具描述由 tools schema 自动生成）

### 5. 修改 `lib/tools.sh`

- 新增 `tools_get_schema()`：生成 tools JSON
- 保留 `tools_list()` 和 `tool_execute()`

### 6. 修改 `lib/loop.sh`

- `react_run()` 接口不变，内部实现已改，loop 无需大改

### 7. 工具文件头部注释

每个 tools/*.sh 文件头部加注释声明参数 schema，示例：

```bash
# @tool Execute a shell command on the local system
# @param command:string(required) The shell command to execute
```

## 不变的部分

- `config.sh`：不变
- `lib/security.sh`：不变
- `lib/ui.sh`：不变（Thought 显示改为读取 `content` 部分）
- `lib/history.sh`：新增 `tool` role 消息支持
- `lib/context.sh`：不变
- `lib/planner.sh`：不变（planner 不用 tools）
- `lib/reflector.sh`：不变
- 工具脚本文件：不变（只加头部注释）

## 测试

```bash
# 非交互模式测试
echo "What files are in /tmp?" | bash shellbot.sh --no-interactive
echo "Calculate 123 * 456" | bash shellbot.sh --no-interactive
echo "Read the file /etc/hosts" | bash shellbot.sh --no-interactive

# 交互模式测试
bash shellbot.sh
# 输入简单问题，验证工具调用正常
# 输入不需要工具的问题，验证直接回答正常
```

## 回退策略

如果模型不支持 Function Calling（极少数情况），回退到纯 content 输出当作 Final Answer。

# 更新日志

ShellBot 所有重要变更均记录在此文件中。

## [0.2.0] - 2026-04-15

### 新增

- **Function Calling**（Phase 01）：用 OpenAI 兼容的 Function Calling API 替代了基于文本的 ReAct 解析（`Thought/Action/Observation` 正则）。工具 schema 从 `tools/*.sh` 中的 `@tool`/`@param` 注解自动生成。(`44d20a0`)
- **统一循环**（Phase 02）：将独立的 Planner + Executor 合并为单一对话流。`plan_step` 工具让模型在行动前声明下一步——通过提示工程实现的软规划约束，而非独立模块。(`13a910e`)
- **跨会话记忆**（Phase 03）：SQLite3 + FTS5 持久化记忆。`memory_save`/`memory_search` 工具用于 LLM 驱动的存储与检索。`memory_prefetch` 将相关记忆注入系统提示。`memory_extract` 自动从对话中提取事实。(`b582eae`)
- **上下文压缩**（Phase 04）：对话历史超过 30000 字符时自动压缩。早期消息由 LLM 摘要，保留最近 N 条消息。摘要以系统消息形式插入。(`0b672d6`)
- **流式回退**：`api_chat_stream_with_tools` 检测 SSE 流中错误和空结果，自动回退到非流式 API 调用并转换格式。(`cf88f16`)
- **空响应重试**：LLM 返回空响应时，追加用户提示消息并最多重试 2 次。(`cf88f16`)
- **FTS5 搜索白名单**：`memory_search` 仅允许字母数字和中日韩字符进入 FTS5 MATCH 查询，每个词项用双引号包裹。(`6f59899`)

### 变更

- **术语清理**：移除所有面向用户的 "ReAct" 命名。UI 显示 "Step N/M" 而非 "ReAct Step N/M"。错误消息显示 "FC run failed" 而非 "ReAct run failed"。(`6f59899`)
- **SPEC.md §3.3**：从旧的 `react_parse()` 文本解析代码重写为实际的 Function Calling 实现。(`f188766`, `6f59899`)
- **非标准字段剥离**：循环历史中的助手消息现在剥离 `reasoning`、`refusal`、`reasoning_details` 字段——仅保留 `{role, content, tool_calls}`。防止 MiniMax 在后续请求中生成 0 token。(`cf88f16`)
- **SQL 转义加固**：`_sql_escape` 现在处理空字节、换行符、反斜杠和单引号，使用 `tr`+`sed`（兼容 bash 3.2）。(`6f59899`)
- **`content: null` 保留**：构建助手消息时，空内容设为 `null`（而非 `""`），符合 OpenAI 规范——MiniMax 需要 `null` 才能生成 token。(`cf88f16`)

### 移除

- **`react_parse()`**：基于文本的 ReAct 响应解析器（Thought/Action/Action Input 正则）不再存在。Function Calling 替代了所有文本解析。(`44d20a0`)
- **`prompts/react_format.sh`**：ReAct 格式指令已移除——Function Calling schema 传达工具接口。(`44d20a0`)
- **`prompts/tools_desc.sh`**：工具描述不再注入提示文本——通过 `tools` API 参数传递。(`44d20a0`)
- **`planner.sh` / `reflector.sh`**：独立的规划和反思模块已移除。规划现在是统一对话流中的 `plan_step` 工具调用。(`13a910e`)

### 修复

- **MiniMax 0 token 循环中断**：消息历史中存在非标准字段（`reasoning`、`refusal`）时，MiniMax 返回 `completion_tokens: 0` 导致循环在 1 次迭代后中断。已通过剥离这些字段修复。(`cf88f16`)
- **MiniMax 流式中途错误**：MiniMax 间歇性在流式传输中返回 `"chat content is empty"`，导致空结果。已通过自动回退到非流式模式修复。(`cf88f16`)
- **SQL 注入风险**：`_sql_escape` 之前仅处理单引号。LLM 输出中包含反斜杠、换行符或空字节的内容可能破坏 SQL。已通过全面转义修复。(`6f59899`)

---

## [0.1.0] - 2026-04-13

### 新增

- ShellBot 初始实现——面向系统运维工程师的纯 Shell AI Agent
- ReAct 推理循环，基于文本的 Thought/Action/Observation 解析
- 工具：`run_shell`、`read_file`、`write_file`、`list_files`、`search_files`、`search_web`、`read_webpage`、`search_rhkb`、`read_rhkb`、`calc`
- Loop Agent 模式，独立的 Planner + Reflector 模块
- OpenRouter API 集成，支持流式传输
- macOS 钥匙串凭据支持
- Red Hat KB SSO 认证与文章访问
- 交互式 REPL，支持斜杠命令（`/tools`、`/loop`、`/skip`、`/stop`、`/model`、`/clear`、`/debug`、`/quit`）

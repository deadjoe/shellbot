# Phase 05: 并行工具调用（Spec Only）

> 状态：仅规划，暂不实现

## 问题

当前每步只能调用一个工具。现实任务经常需要并行操作："同时检查多台服务器的负载"。OpenAI Function Calling API 本身支持一次返回多个 `tool_calls`。

## 为什么暂不实现

1. Shell 中并行执行（fork/wait）增加代码复杂度，与"简洁教学"目标冲突
2. 需要处理部分成功/部分失败、输出拼接、超时管理等问题
3. 教学优先级低——学生理解串行工具调用后，并行是自然延伸

## 规划方案（未来实现时参考）

### API 层面

LLM 可能一次返回多个 tool_calls：

```json
{
  "tool_calls": [
    {"id": "call_1", "function": {"name": "run_shell", "arguments": "{\"command\": \"uptime\"}"}},
    {"id": "call_2", "function": {"name": "run_shell", "arguments": "{\"command\": \"df -h\"}"}}
  ]
}
```

### Shell 并行执行

```bash
# 为每个 tool_call fork 子进程
for call in $tool_calls; do
  (tool_execute "$name" "$input" > "/tmp/shellbot_result_$call_id" 2>&1) &
  pids+=($!)
done

# 等待所有子进程
for pid in "${pids[@]}"; do
  wait "$pid"
done
```

### 结果回传

每个工具结果作为独立的 `tool` role 消息，携带对应的 `tool_call_id`。

### 超时管理

并行工具的总超时 = 单工具超时（不是 N × 单工具超时）。

## 教学讨论点

- 什么时候需要并行？什么时候串行更安全？
- 并行的副作用：资源竞争、输出顺序不确定
- 部分失败策略：全部回滚 vs 继续执行 vs 询问用户

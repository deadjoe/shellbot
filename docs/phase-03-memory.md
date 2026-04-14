# Phase 03: 跨会话记忆

> 目标：Agent 能记住之前的交互经验，跨会话积累知识，而不是每次从零开始

## 问题

当前每次启动 ShellBot 都是白纸一张。上次发现的环境特征、踩过的坑、用户偏好，全部丢失。一个没有记忆的 Agent，本质上每次都是新 Agent。

## 方案

用 **SQLite3 + FTS5**（macOS 自带）实现轻量记忆存储：

- 存储层：SQLite3 数据库，一张 `memories` 表 + FTS5 虚拟表
- 检索层：FTS5 全文检索召回候选，让 LLM 判断相关性
- 触发层：对话结束时自动提取值得记住的信息

### 为什么用 SQLite3 + FTS5

- macOS 自带，零安装
- FTS5 全文检索对记忆召回完全够用
- 学生能直接 `sqlite3 ~/.shellbot/memories.db "SELECT ..."` 查看数据
- 和项目"shell + CLI 工具"风格一致

## 实现计划

### 1. 新增 `lib/memory.sh`

```bash
MEMORY_DB="$SHELLBOT_DATA_DIR/memories.db"

# 初始化数据库
memory_init() {
  if [ ! -f "$MEMORY_DB" ]; then
    sqlite3 "$MEMORY_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS memories (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  content TEXT NOT NULL,
  category TEXT DEFAULT 'general',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(content, category, content=memories, content_rowid=id);
CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories BEGIN
  INSERT INTO memories_fts(rowid, content, category) VALUES (new.id, new.content, new.category);
END;
SQL
  fi
}

# 保存一条记忆
memory_save() {
  local content="$1"
  local category="${2:-general}"
  sqlite3 "$MEMORY_DB" "INSERT INTO memories (content, category) VALUES ($(sqlite3_quote "$content"), '$category');"
}

# 搜索记忆（FTS5 全文检索）
memory_search() {
  local query="$1"
  local limit="${2:-5}"
  sqlite3 "$MEMORY_DB" "SELECT content FROM memories_fts WHERE memories_fts MATCH '$(sqlite3_escape "$query")' ORDER BY rank LIMIT $limit;"
}

# 列出所有记忆
memory_list() {
  sqlite3 "$MEMORY_DB" "SELECT id, category, content FROM memories ORDER BY id DESC;"
}

# 删除记忆
memory_delete() {
  local id="$1"
  sqlite3 "$MEMORY_DB" "DELETE FROM memories WHERE id = $id;"
}
```

### 2. 新增记忆工具

在 `tools/` 中新增 `save_memory.sh` 和 `search_memory.sh`：

**save_memory.sh**：
```bash
# @tool Save important information to long-term memory for future sessions
# @param content:string(required) The information to remember
# @param category:string Category: general, environment, preference, lesson (default: general)
```

**search_memory.sh**：
```bash
# @tool Search your long-term memory for relevant information
# @param query:string(required) Search query
```

### 3. 修改 System Prompt

在 system prompt 中加入记忆上下文：

```bash
# 启动时预取相关记忆
memory_prefetch() {
  local query="$1"
  local results
  results=$(memory_search "$query" 3)
  if [ -n "$results" ]; then
    echo "Relevant memories from past sessions:"
    echo "$results"
    echo ""
  fi
}
```

注入到 system prompt 末尾，让 LLM 在本轮对话中知道过去的经验。

### 4. 自动记忆提取

对话结束时（交互模式退出 / 非交互模式完成），用 LLM 提取值得记住的信息：

```bash
memory_extract() {
  local conversation="$1"
  
  local prompt="Review the conversation and extract facts worth remembering for future sessions. 
Focus on: environment details, user preferences, discovered solutions, errors encountered.
Output each fact as a separate line. If nothing is worth remembering, output nothing."

  local result
  result=$(echo "$conversation" | api_chat_simple "$prompt")
  
  if [ -n "$result" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      memory_save "$line" "auto"
    done <<< "$result"
  fi
}
```

### 5. 修改 `shellbot.sh`

- 启动时调用 `memory_init`
- 退出时调用 `memory_extract`
- 新增 `/memories` 命令查看记忆
- 新增 `/forget <id>` 命令删除记忆

### 6. 修改 `lib/tools_schema.sh`

- 新增 `save_memory` 和 `search_memory` 的工具 schema

## 辅助函数

```bash
# SQLite3 字符串转义
sqlite3_escape() {
  local s="$1"
  s="${s//\'/\'\'}"
  echo "$s"
}
```

## 数据流

```
用户提问
  → memory_search(提问关键词) → 注入 system prompt
  → LLM 推理（知道过去的经验）
  → LLM 可能调用 save_memory（主动保存重要发现）
  → 对话结束
  → memory_extract()（自动提取）
```

## 测试

```bash
# 第一轮：让它发现并记住信息
echo "What is the OS version on this machine?" | bash shellbot.sh --no-interactive

# 第二轮：验证记忆
echo "What OS did I ask about last time?" | bash shellbot.sh --no-interactive

# 查看记忆数据库
sqlite3 ~/.shellbot/memories.db "SELECT * FROM memories;"

# 交互模式测试
bash shellbot.sh
# /memories  -- 查看所有记忆
# 主动让它记住一些东西
```

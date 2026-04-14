#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"

MEMORY_DB="$SHELLBOT_DATA_DIR/memories.db"

# Initialize memory database (SQLite3 + FTS5)
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

# Escape single quotes for SQL
_sql_escape() {
  local s="$1"
  s="${s//\'/\'\'}"
  echo "$s"
}

# Save a memory
memory_save() {
  local content="$1"
  local category="${2:-general}"
  sqlite3 "$MEMORY_DB" \
    "INSERT INTO memories (content, category) VALUES ('$(_sql_escape "$content")', '$(_sql_escape "$category")');"
}

# Search memories (FTS5 full-text search)
memory_search() {
  local query="$1"
  local limit="${2:-5}"
  # FTS5 MATCH: escape special chars, use simple term matching
  local safe_query
  safe_query=$(echo "$query" | sed "s/['\"*(){}]//g" | awk '{for(i=1;i<=NF;i++) printf "%s OR ", $i; print ""}' | sed 's/ OR $//')
  [ -z "$safe_query" ] && safe_query="$query"
  sqlite3 "$MEMORY_DB" \
    "SELECT content FROM memories_fts WHERE memories_fts MATCH '$(_sql_escape "$safe_query")' ORDER BY rank LIMIT $limit;" 2>/dev/null
}

# List all memories
memory_list() {
  sqlite3 -column -header "$MEMORY_DB" \
    "SELECT id, category, substr(content, 1, 80) AS content, created_at FROM memories ORDER BY id DESC LIMIT 20;" 2>/dev/null
}

# Delete a memory by ID
memory_delete() {
  local id="$1"
  sqlite3 "$MEMORY_DB" "DELETE FROM memories WHERE id = $id;" 2>/dev/null
}

# Prefetch relevant memories for a query
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

# Auto-extract memorable facts from conversation using LLM
memory_extract() {
  local conversation="$1"

  # Skip if conversation is too short
  local conv_len=${#conversation}
  if [ "$conv_len" -lt 200 ]; then
    return 0
  fi

  local prompt="Review the conversation below and extract facts worth remembering for future sessions.
Focus on: environment details, user preferences, discovered solutions, errors encountered, system configuration.
Output each fact as a separate line. If nothing is worth remembering, output nothing.

CONVERSATION:
${conversation:0:4000}"

  local result
  result=$(api_chat_simple "$(jq -n --arg prompt "$prompt" '[{role: "user", content: $prompt}]')")

  if [ -n "$result" ]; then
    local count=0
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      # Skip lines that are just filler
      [[ "$line" =~ ^[0-9]+\.$ ]] && continue
      [[ "$line" =~ ^[-*•]+$ ]] && continue
      memory_save "$line" "auto"
      count=$((count + 1))
    done <<< "$result"
    [ $count -gt 0 ] && ui_debug "Auto-saved $count memory items"
  fi
}

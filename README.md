# ShellBot

Pure-shell AI Agent for system ops engineers. Function Calling + unified Loop execution. Zero framework dependencies.

## What It Does

- **Local ops**: run shell commands, read/write/search files
- **Web search**: Tavily search + JINA Reader for web pages
- **Red Hat KB**: auto SSO login, search & read access.redhat.com articles
- **Autonomous planning**: Loop multi-turn with Function Calling + plan steps
- **Cross-session memory**: SQLite3 + FTS5 persistent memory (save/search)
- **Context compression**: LLM-based summarization when context exceeds limits

## Architecture

```
shellbot.sh (entry)
  → loop.sh (unified Loop: Function Calling + single conversation stream)
    → tools.sh (dispatch) + tools_schema.sh (OpenAI schema generation)
    → memory.sh (SQLite3 + FTS5) + compressor.sh (LLM summarization)
    → history.sh + context.sh + security.sh + ui.sh
```

No separate planner/reflector — Loop mode uses a single conversation stream with Function Calling throughout.

## Dependencies

### CLI Tools (required)

| Tool | Purpose | Install |
|------|---------|---------|
| bash 3.2+ | Runtime | macOS built-in |
| curl | HTTP requests | macOS built-in |
| python3 | HTML parsing, math eval | macOS built-in |
| jq | JSON parsing | `brew install jq` |
| sqlite3 | Persistent memory (FTS5) | macOS built-in |
| timeout (GNU) | Tool execution timeout | `brew install coreutils` |

```bash
brew install jq coreutils
```

### CLI Tools (optional)

| Tool | Purpose | Install |
|------|---------|---------|
| rich (Python) | Markdown rendering for final answers (code highlight, tables) | `pip3 install rich` |
| gum | Spinner animation during LLM thinking | `brew install gum` |
| ripgrep (rg) | Faster file content search (falls back to grep) | `brew install ripgrep` |

```bash
pip3 install rich
brew install gum ripgrep
```

### API Keys (required)

| Service | Variable | Purpose | Get |
|---------|----------|---------|-----|
| OpenRouter | `OPENROUTER_API_KEY` | LLM backend (required) | [openrouter.ai/keys](https://openrouter.ai/keys) |
| Tavily | `TAVILY_API_KEY` | Web search | [app.tavily.com](https://app.tavily.com) |
| Jina | `JINA_API_KEY` | URL→markdown conversion | [jina.ai/api](https://jina.ai/api) |
| Red Hat | `RH_USERNAME` / `RH_PASSWORD` | RH KB access | Your Red Hat account |

OpenRouter is mandatory. Tavily/Jina/Red Hat are only needed if you use the corresponding tools.

## Quick Start

```bash
# 1. Install required CLI tools
brew install jq coreutils

# 2. Configure API keys
mkdir -p ~/.shellbot
cp .env.example ~/.shellbot/.env
# Edit ~/.shellbot/.env with your API keys

# Or use macOS Keychain instead of .env:
security add-generic-password -s "shellbot-openrouter" -a "$USER" -w "sk-xxx"

# 3. Run
bash shellbot.sh              # interactive ReAct mode
bash shellbot.sh --loop       # interactive Loop mode
echo "query" | bash shellbot.sh --no-interactive  # pipe mode
```

## Configuration

| Variable | Source | Purpose |
|----------|--------|---------|
| `OPENROUTER_API_KEY` | .env / Keychain | LLM backend |
| `TAVILY_API_KEY` | .env / Keychain | Web search |
| `JINA_API_KEY` | .env / Keychain | Web page reader |
| `RH_USERNAME` / `RH_PASSWORD` | .env / Keychain | Red Hat SSO |
| `DEFAULT_MODEL` | .env | Default: `deepseek/deepseek-chat-v3-0324` |
| `SHELLBOT_STREAM` | .env | `true`/`false`, default: `true` |
| `SHELL_CONFIRM` | .env | `auto`/`true`/`false`, default: `auto` |

Credential priority: env var → `.env` file → macOS Keychain.

## Interactive Commands

| Command | Description |
|---------|-------------|
| `/tools` | List available tools |
| `/loop <goal>` | Start loop task |
| `/skip` | Skip current sub-goal (loop) |
| `/stop` | Stop loop (loop) |
| `/model` | Switch LLM model |
| `/clear` | Clear history |
| `/debug` | Toggle debug |
| `/quit` | Exit |

## Tools

| Tool | Description |
|------|-------------|
| `run_shell` | Execute shell command |
| `read_file` | Read file content |
| `write_file` | Write file (JSON input) |
| `list_files` | List directory |
| `search_files` | Search file contents (rg/grep) |
| `search_web` | Tavily internet search |
| `read_webpage` | JINA Reader URL→markdown |
| `search_rhkb` | Search Red Hat KB |
| `read_rhkb` | Read Red Hat KB article |
| `calc` | Safe math evaluation |
| `plan_step` | Declare current planning step (Loop) |
| `save_memory` | Save fact to persistent memory |
| `search_memory` | Search persistent memory (FTS5) |

## Memory & Compression

### Cross-session Memory (SQLite3 + FTS5)

- `memory.sh` stores facts in a local SQLite database with full-text search
- `save_memory` / `search_memory` tools let the agent persist & recall information
- DB location: `~/.shellbot/memory.db`

### Context Compression

- `compressor.sh` triggers when conversation exceeds the configured token limit
- Uses a lightweight LLM call to summarize older history into a compact summary
- Compression runs automatically inside `history.sh` — transparent to the agent loop

## License

MIT

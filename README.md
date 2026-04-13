# ShellBot

Pure-shell AI Agent for system ops engineers. ReAct reasoning + Loop autonomous task execution. Zero framework dependencies.

## What It Does

- **Local ops**: run shell commands, read/write/search files
- **Web search**: Tavily search + JINA Reader for web pages
- **Red Hat KB**: auto SSO login, search & read access.redhat.com articles
- **Autonomous planning**: ReAct single-turn or Loop multi-turn with planner/reflector

## Architecture

```
shellbot.sh (entry) → loop.sh (outer) → react.sh (inner) → tools/
```

## Quick Start

```bash
# Install dependencies
brew install jq coreutils
pip3 install rich    # optional: markdown rendering for final answers
brew install gum     # optional: spinner animation
brew install ripgrep # optional: faster file search

# Configure
mkdir -p ~/.shellbot
cp .env.example ~/.shellbot/.env
# Edit ~/.shellbot/.env with your API keys

# Run
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

## License

MIT

# Changelog

All notable changes to ShellBot are documented in this file.

## [0.2.0] - 2026-04-15

### Added

- **Function Calling** (Phase 01): Replaced text-based ReAct parsing (`Thought/Action/Observation` regex) with OpenAI-compatible Function Calling API. Tool schemas auto-generated from `@tool`/`@param` annotations in `tools/*.sh`. (`44d20a0`)
- **Unified Loop** (Phase 02): Merged separate Planner + Executor into a single conversation stream. The `plan_step` tool lets the model declare its next step before acting — a soft planning constraint via prompt engineering, not a separate module. (`13a910e`)
- **Cross-session Memory** (Phase 03): SQLite3 + FTS5 persistent memory. `memory_save`/`memory_search` tools for LLM-driven storage and retrieval. `memory_prefetch` injects relevant memories into system prompt. `memory_extract` auto-extracts facts from conversations. (`b582eae`)
- **Context Compression** (Phase 04): Automatic conversation history compression when exceeding 30000 characters. Early messages summarized by LLM, recent N messages preserved. Summary inserted as a system message. (`0b672d6`)
- **Stream fallback**: `api_chat_stream_with_tools` detects midstream SSE errors and empty stream results, automatically falling back to non-streaming API call with format conversion. (`cf88f16`)
- **Empty response nudge retry**: On empty LLM response, appends a user nudge message and retries up to 2 times before giving up. (`cf88f16`)
- **FTS5 search whitelist**: `memory_search` now only allows alphanumeric + CJK characters in FTS5 MATCH queries, each term double-quoted. (`6f59899`)

### Changed

- **Terminology**: Removed all "ReAct" naming from user-facing text and documentation. UI shows "Step N/M" instead of "ReAct Step N/M". Error messages say "FC run failed" instead of "ReAct run failed". (`6f59899`)
- **SPEC.md §3.3**: Rewritten from old `react_parse()` text-parsing code to actual Function Calling implementation. (`f188766`, `6f59899`)
- **Non-standard field stripping**: Assistant messages in loop history now strip `reasoning`, `refusal`, `reasoning_details` fields — only `{role, content, tool_calls}` preserved. Prevents MiniMax 0-token generation on subsequent requests. (`cf88f16`)
- **SQL escaping hardened**: `_sql_escape` now handles null bytes, newlines, backslashes, and single quotes using `tr`+`sed` (bash 3.2 compatible). (`6f59899`)
- **`content: null` preservation**: When constructing assistant messages, empty content is set to `null` (not `""`) per OpenAI spec — MiniMax requires `null` to generate tokens. (`cf88f16`)

### Removed

- **`react_parse()`**: Text-based ReAct response parser (Thought/Action/Action Input regex) no longer exists. Function Calling replaces all text parsing. (`44d20a0`)
- **`prompts/react_format.sh`**: ReAct format instructions removed — Function Calling schema conveys tool interface. (`44d20a0`)
- **`prompts/tools_desc.sh`**: Tool descriptions no longer injected into prompt text — delivered via `tools` API parameter. (`44d20a0`)
- **`planner.sh` / `reflector.sh`**: Separate planning and reflection modules removed. Planning is now a `plan_step` tool call within the unified conversation stream. (`13a910e`)

### Fixed

- **MiniMax 0-token loop halt**: Loop halted after 1 iteration because MiniMax returned `completion_tokens: 0` when non-standard fields (`reasoning`, `refusal`) were present in message history. Fixed by stripping these fields. (`cf88f16`)
- **MiniMax stream midstream error**: MiniMax intermittently returns `"chat content is empty"` during streaming, causing empty results. Fixed with auto-fallback to non-streaming. (`cf88f16`)
- **SQL injection risk**: `_sql_escape` previously only handled single quotes. Content from LLM output with backslashes, newlines, or null bytes could break SQL. Fixed with comprehensive escaping. (`6f59899`)

---

## [0.1.0] - 2026-04-13

### Added

- Initial implementation of ShellBot — pure-shell AI Agent for system ops engineers
- ReAct reasoning loop with text-based Thought/Action/Observation parsing
- Tools: `run_shell`, `read_file`, `write_file`, `list_files`, `search_files`, `search_web`, `read_webpage`, `search_rhkb`, `read_rhkb`, `calc`
- Loop Agent mode with separate Planner + Reflector modules
- OpenRouter API integration with streaming support
- macOS Keychain credential support
- Red Hat KB SSO authentication and article access
- Interactive REPL with slash commands (`/tools`, `/loop`, `/skip`, `/stop`, `/model`, `/clear`, `/debug`, `/quit`)

#!/usr/bin/env bash

prompt_tools_desc() {
  cat <<'PROMPT'
Available tools:

- run_shell: Execute a shell command on the local system. Input: the shell command as a string.
- read_file: Read the content of a file. Input: file path string.
- write_file: Write content to a file. Input: JSON string {"path": "/path/to/file", "content": "file content here"}.
- list_files: List files in a directory with details. Input: directory path string (default: current directory).
- search_files: Search for a text pattern in files under current directory. Uses ripgrep (rg) if available, falls back to grep. Input: search pattern string.
- search_web: Search the internet for information. Input: search query string.
- read_webpage: Read a webpage and convert to clean markdown. Input: URL string.
- search_rhkb: Search Red Hat Knowledgebase for solutions. Input: search query string.
- read_rhkb: Read the full content of a Red Hat KB article. Input: the KB article URL string.
- calc: Perform a mathematical calculation. Input: mathematical expression string.
PROMPT
}

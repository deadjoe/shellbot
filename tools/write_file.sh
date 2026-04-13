#!/usr/bin/env bash
path=$(echo "$1" | jq -r '.path // empty' 2>/dev/null)
content=$(echo "$1" | jq -r '.content // empty' 2>/dev/null)

if [ -z "$path" ] || [ -z "$content" ]; then
  echo "Error: Invalid input. Expected JSON: {\"path\": \"...\", \"content\": \"...\"}"
  exit 1
fi

mkdir -p "$(dirname "$path")"
printf '%s' "$content" > "$path"
echo "File written: $path"

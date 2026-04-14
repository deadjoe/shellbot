#!/usr/bin/env bash

# @tool Save important information to long-term memory for future sessions
# @param content:string(required) The information to remember
# @param category:string Category: general, environment, preference, lesson (default: general)

source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"
source "$SHELLBOT_HOME/lib/memory.sh"

content=$(echo "$1" | jq -r '.content // empty' 2>/dev/null)
category=$(echo "$1" | jq -r '.category // "general"' 2>/dev/null)

if [ -z "$content" ]; then
  echo "Error: content parameter is required"
  exit 1
fi

memory_save "$content" "$category"
echo "Saved to memory (category: $category)"

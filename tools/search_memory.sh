#!/usr/bin/env bash

# @tool Search your long-term memory for relevant information
# @param query:string(required) Search query

source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"
source "$SHELLBOT_HOME/lib/memory.sh"

query=$(echo "$1" | jq -r '.query // empty' 2>/dev/null)
if [ -z "$query" ]; then
  query="$1"
fi

if [ -z "$query" ]; then
  echo "Error: query parameter is required"
  exit 1
fi

found=$(memory_search "$query" 5)
if [ -n "$found" ]; then
  echo "$found"
else
  echo "No matching memories found."
fi

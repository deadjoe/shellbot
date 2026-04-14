#!/usr/bin/env bash
# @tool Read the content of a file
# @param path:string(required) The file path to read
if [ ! -f "$1" ]; then
  echo "Error: File not found: $1"
  exit 1
fi
cat "$1" 2>&1 | head -500

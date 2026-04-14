#!/usr/bin/env bash
# @tool Read a webpage and convert to clean markdown using JINA Reader
# @param url:string(required) The URL to read
source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"

if [ -z "$JINA_API_KEY" ]; then
  echo "Error: JINA_API_KEY not configured"
  exit 1
fi

curl -sS --max-time 30 \
  "https://r.jina.ai/$1" \
  -H "Authorization: Bearer $JINA_API_KEY" \
  -H "Accept: text/markdown" \
  | head -1000

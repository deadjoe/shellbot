#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"

if [ -z "$TAVILY_API_KEY" ]; then
  echo "Error: TAVILY_API_KEY not configured"
  exit 1
fi

curl -sS --max-time 30 "https://api.tavily.com/search" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg query "$1" \
    --arg key "$TAVILY_API_KEY" \
    '{api_key: $key, query: $query, max_results: 5, include_answer: true}')" \
  | jq -r '
    if .answer then "Quick Answer: \(.answer)\n" else "" end +
    (.results // [] | map(
      "[\(.title)](\(.url))\n\(.content)\n"
    ) | join("\n"))
  ' 2>/dev/null

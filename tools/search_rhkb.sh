#!/usr/bin/env bash
# @tool Search Red Hat Knowledgebase for solutions
# @param query:string(required) The search query
source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"
source "$SHELLBOT_HOME/tools/rhkb_auth.sh"

query="$1"

if ! rhkb_ensure_auth; then
  echo "Error: Red Hat SSO authentication failed. Check RH_USERNAME and RH_PASSWORD."
  exit 1
fi

encoded_query=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$query" 2>/dev/null)

search_result=$(curl -sS -b "$RH_COOKIE_JAR" \
  --max-time 30 \
  -H "Accept: application/json" \
  "https://access.redhat.com/hydra/rest/search/kcs?q=${encoded_query}&p=1&size=5" 2>/dev/null)

if [ -z "$search_result" ]; then
  echo "Error: Empty response from RH KB search"
  exit 1
fi

echo "$search_result" | jq -r '
  .response.docs[:5] | map(
    "[\(.allTitle // "Untitled")](\(.view_uri // ""))\n\(.publishedAbstract // .abstract // .brief_description // "")\n"
  ) | join("\n")
' 2>/dev/null

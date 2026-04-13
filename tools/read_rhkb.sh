#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"
source "$SHELLBOT_HOME/tools/rhkb_auth.sh"

article_url="$1"

if [ -z "$article_url" ]; then
  echo "Error: No article URL provided"
  exit 1
fi

if ! rhkb_ensure_auth; then
  echo "Error: Red Hat SSO authentication failed"
  exit 1
fi

solution_id=$(echo "$article_url" | sed -n 's|.*/solutions/\([0-9]*\).*|\1|p')

if [ -n "$solution_id" ]; then
  search_result=$(curl -sS -b "$RH_COOKIE_JAR" \
    --max-time 30 \
    -H "Accept: application/json" \
    "https://access.redhat.com/hydra/rest/search/kcs?q=id:${solution_id}&p=1&size=1" 2>/dev/null)

  doc_count=$(echo "$search_result" | jq '.response.docs | length' 2>/dev/null)

  if [ "$doc_count" -gt 0 ]; then
    echo "$search_result" | jq -r '
      .response.docs[0] |
      "Title: " + (.allTitle // "N/A") + "\n" +
      "URL: " + (.view_uri // "N/A") + "\n" +
      "Kind: " + (.documentKind // "N/A") + "\n" +
      "Created: " + (.createdDate // "N/A") + "\n" +
      "Modified: " + (.lastModifiedDate // "N/A") + "\n\n" +
      "--- Issue ---\n" + (.field_kcs_issue_txt // .publishedAbstract // .abstract // .brief_description // "N/A") + "\n\n" +
      "--- Environment ---\n" + (.solution_environment // "See article page") + "\n\n" +
      "--- Resolution ---\n" + (if .solution_resolution == "subscriber_only" then "[Subscriber-only content - visit the article page for full resolution]" else (.solution_resolution // "See article page") end) + "\n\n" +
      "--- Root Cause ---\n" + (if .solution_rootcause == "subscriber_only" then "[Subscriber-only content]" else (.solution_rootcause // "N/A") end)
    ' 2>/dev/null
    exit 0
  fi
fi

echo "Fetching article HTML..."
html_content=$(curl -sS -b "$RH_COOKIE_JAR" \
  --max-time 30 \
  "$article_url" 2>/dev/null)

echo "$html_content" | python3 << 'PYEOF'
from html.parser import HTMLParser
import sys

class ArticleParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_content = False
        self.skip = False
        self.output = []
        self.current_section = ""
    def handle_starttag(self, tag, attrs):
        d = dict(attrs)
        cls = d.get("class", "")
        if "field_kcs" in cls:
            self.in_content = True
            self.current_section = cls.replace("field_kcs_", "").replace("_txt", "").upper()
            self.output.append(f"\n## {self.current_section}\n")
        if tag in ("script", "style", "nav", "header", "footer", "noscript"):
            self.skip = True
        if self.in_content and not self.skip:
            if tag in ("pre", "code"):
                self.output.append("\n```\n")
            elif tag in ("h1", "h2", "h3", "h4"):
                level = int(tag[1])
                self.output.append("\n" + "#" * level + " ")
            elif tag == "li":
                self.output.append("\n- ")
            elif tag == "br":
                self.output.append("\n")
    def handle_endtag(self, tag):
        if tag in ("script", "style", "nav", "header", "footer", "noscript"):
            self.skip = False
        if self.in_content and not self.skip:
            if tag in ("pre", "code"):
                self.output.append("\n```\n")
            elif tag == "section":
                self.in_content = False
                self.current_section = ""
            elif tag in ("p", "h1", "h2", "h3", "h4", "li", "div"):
                self.output.append("\n")
    def handle_data(self, data):
        if self.skip or not self.in_content:
            return
        text = data.strip()
        if text:
            self.output.append(text + " ")

p = ArticleParser()
p.feed(sys.stdin.read())
result = "".join(p.output).strip()
print(result[:8000])
PYEOF

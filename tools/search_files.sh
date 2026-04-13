#!/usr/bin/env bash

_search_bin=""
if command -v rg >/dev/null 2>&1; then
  _search_bin="rg"
else
  _search_bin="grep"
fi

if [ "$_search_bin" = "rg" ]; then
  rg --max-count=50 --max-filesize=1M --no-heading --line-number --color=never "$1" 2>&1 | head -100
else
  grep -rn --max-count=50 --color=never "$1" . 2>&1 | head -100
fi

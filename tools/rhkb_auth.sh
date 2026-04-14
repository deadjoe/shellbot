#!/usr/bin/env bash
# @tool Authenticate with Red Hat SSO (internal, not exposed to LLM)
source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"
source "$SHELLBOT_HOME/lib/ui.sh"

RH_COOKIE_JAR="${RH_COOKIE_JAR:-$HOME/.shellbot/rh_cookies.jar}"

rhkb_auth() {
  if [ -z "$RH_USERNAME" ] || [ -z "$RH_PASSWORD" ]; then
    echo "Error: RH_USERNAME and RH_PASSWORD must be configured" >&2
    return 1
  fi

  mkdir -p "$(dirname "$RH_COOKIE_JAR")"
  ui_info "Authenticating to Red Hat SSO..."

  rm -f "$RH_COOKIE_JAR"

  local sso_login_url="https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/auth?client_id=customer-portal&redirect_uri=https%3A%2F%2Faccess.redhat.com%2F&response_type=code"

  curl -sS -c "$RH_COOKIE_JAR" --max-time 15 \
    -o /tmp/shellbot_rh_login.html \
    -L "$sso_login_url" 2>/dev/null

  if [ ! -f /tmp/shellbot_rh_login.html ] || [ ! -s /tmp/shellbot_rh_login.html ]; then
    echo "Error: Failed to fetch SSO login page" >&2
    return 1
  fi

  local form_count
  form_count=$(grep -c "rh-password-verification-form" /tmp/shellbot_rh_login.html 2>/dev/null || echo "0")
  if [ "$form_count" -eq 0 ]; then
    echo "Error: SSO login form not found in response" >&2
    return 1
  fi

  local form_action
  form_action=$(python3 -c "
from html.parser import HTMLParser
class P(HTMLParser):
    def __init__(self):
        super().__init__()
        self.result = ''
    def handle_starttag(self, tag, attrs):
        d = dict(attrs)
        if tag == 'form' and d.get('id') == 'rh-password-verification-form':
            self.result = d.get('action', '')
p = P()
p.feed(open('/tmp/shellbot_rh_login.html').read())
print(p.result)
" 2>/dev/null)

  if [ -z "$form_action" ]; then
    echo "Error: Failed to parse SSO login form action URL" >&2
    return 1
  fi

  ui_debug "Form action: $form_action"

  local post_status
  post_status=$(curl -sS -b "$RH_COOKIE_JAR" -c "$RH_COOKIE_JAR" \
    --max-time 30 \
    -i \
    -X POST "$form_action" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "username=$RH_USERNAME" \
    --data-urlencode "password=$RH_PASSWORD" 2>/dev/null > /tmp/shellbot_rh_post.txt; echo $?)

  local redirect_url
  redirect_url=$(grep -i "^location:" /tmp/shellbot_rh_post.txt | head -1 | tr -d '\r' | awk '{print $2}')

  if [ -n "$redirect_url" ]; then
    ui_debug "Following redirect: $redirect_url"
    curl -sS -b "$RH_COOKIE_JAR" -c "$RH_COOKIE_JAR" \
      --max-time 15 \
      -o /tmp/shellbot_rh_landing.html \
      -L "$redirect_url" 2>/dev/null
  fi

  local test_status
  test_status=$(curl -sS -b "$RH_COOKIE_JAR" -o /dev/null -w "%{http_code}" \
    --max-time 10 \
    "https://access.redhat.com/solutions/2188281" 2>/dev/null)

  if [ "$test_status" = "200" ] || [ "$test_status" = "403" ] || [ "$test_status" = "404" ]; then
    ui_success "Red Hat SSO authenticated"
    return 0
  else
    echo "Error: SSO authentication verification failed (HTTP $test_status)" >&2
    return 1
  fi
}

rhkb_ensure_auth() {
  if [ ! -f "$RH_COOKIE_JAR" ] || [ ! -s "$RH_COOKIE_JAR" ]; then
    rhkb_auth
    return $?
  fi

  local test_status
  test_status=$(curl -sS -b "$RH_COOKIE_JAR" -o /dev/null -w "%{http_code}" \
    --max-time 10 \
    "https://access.redhat.com/solutions/2188281" 2>/dev/null)

  if [ "$test_status" = "302" ] || [ "$test_status" = "000" ]; then
    rhkb_auth
    return $?
  fi

  return 0
}

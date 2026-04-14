#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"

# Generate OpenAI tools JSON schema from tool script @tool/@param comments
tools_get_schema() {
  local items=""

  for tool_name in $TOOL_NAMES; do
    local script="$SHELLBOT_HOME/tools/${tool_name}.sh"
    [ ! -f "$script" ] && continue

    # Skip internal tools (like rhkb_auth)
    local desc=""
    desc=$(grep -m1 '^# @tool ' "$script" | sed 's/^# @tool //')
    [ -z "$desc" ] && continue
    # Skip tools marked as internal
    echo "$desc" | grep -qi "internal" && continue

    # Parse @param lines
    local properties="{}"
    local required="[]"

    while IFS= read -r line; do
      local pname pdesc
      # Format: # @param name:type[(required)] description
      pname=$(echo "$line" | sed 's/^# @param //' | cut -d: -f1)
      pdesc=$(echo "$line" | sed 's/^# @param [^ ]* //' | sed 's/(required) //; s/(optional) //')

      # Add property
      properties=$(echo "$properties" | jq \
        --arg name "$pname" \
        --arg desc "$pdesc" \
        '. + {($name): {type: "string", description: $desc}}')

      # Check if required
      if echo "$line" | grep -q '(required)'; then
        required=$(echo "$required" | jq --arg name "$pname" '. + [$name]')
      fi
    done < <(grep '^# @param ' "$script")

    # Build tool item
    local item
    item=$(jq -n \
      --arg name "$tool_name" \
      --arg desc "$desc" \
      --argjson props "$properties" \
      --argjson reqs "$required" \
      '{
        type: "function",
        function: {
          name: $name,
          description: $desc,
          parameters: {
            type: "object",
            properties: $props,
            required: $reqs
          }
        }
      }')

    if [ -z "$items" ]; then
      items=$(echo "$item" | jq -s '.')
    else
      items=$(echo "$items" | jq --argjson item "$item" '. + [$item]')
    fi
  done

  if [ -z "$items" ]; then
    echo "[]"
  else
    echo "$items"
  fi
}

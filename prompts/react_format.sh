#!/usr/bin/env bash

prompt_react_format() {
  cat <<'PROMPT'
You MUST strictly follow this format in every response:

Thought: analyze the situation and decide what to do
Action: tool_name
Action Input: the input for the tool

When you have gathered enough information to answer, use:
Thought: I now have enough information to provide the final answer
Final Answer: your complete answer to the user

RULES:
- Always start with "Thought:" before any action
- Use exactly ONE action per response turn
- After each action, you will receive an Observation with the result
- Continue the Thought→Action→Observation cycle until you can provide a Final Answer
- Never skip the Thought step
- Never invent Observations — wait for the actual tool result
- If a tool fails, analyze why and try a different approach
- Action Input must be a single line (use JSON for structured inputs like write_file)
PROMPT
}

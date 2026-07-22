#!/usr/bin/env bash
# Emit AGENTS.md as SessionStart additionalContext, so the rules apply in every repo.
set -euo pipefail

rules="${CLAUDE_PLUGIN_ROOT:-}/AGENTS.md"
[ -f "$rules" ] || exit 0

emit_with_jq() {
    jq -Rs '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}' "$1"
}

emit_with_python() {
    python3 -c 'import json, sys; print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": open(sys.argv[1]).read()}}))' "$1"
}

main() {
    if command -v jq >/dev/null 2>&1; then
        emit_with_jq "$rules"
    elif command -v python3 >/dev/null 2>&1; then
        emit_with_python "$rules"
    else
        exit 0
    fi
}

main

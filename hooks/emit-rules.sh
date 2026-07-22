#!/usr/bin/env bash
# Emit AGENTS.md as SessionStart additionalContext, so the rules apply in every repo.
set -euo pipefail

# Claude Code sets CLAUDE_PLUGIN_ROOT. Codex sets PLUGIN_ROOT and CLAUDE_PLUGIN_ROOT. Fall back to
# the directory of this script, because an empty variable would otherwise read /AGENTS.md.
plugin_root() {
    local root=${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:-}}
    if [ -n "$root" ]; then
        printf '%s' "$root"
        return
    fi
    (cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
}

emit_with_jq() {
    jq -Rs '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}' "$1"
}

emit_with_python() {
    python3 -c 'import json, sys
with open(sys.argv[1]) as handle:
    rules = handle.read()
output = {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": rules}}
print(json.dumps(output))' "$1"
}

# A session must always start, so every failure warns and exits 0. A silent exit would make a
# broken install look the same as a working one.
main() {
    local rules
    rules="$(plugin_root)/AGENTS.md"

    if [ ! -f "$rules" ]; then
        printf 'codelore: no rules file at %s. The rules were not loaded.\n' "$rules" >&2
        exit 0
    fi

    if command -v jq >/dev/null 2>&1; then
        emit_with_jq "$rules"
    elif command -v python3 >/dev/null 2>&1; then
        emit_with_python "$rules"
    else
        printf 'codelore: jq and python3 are both absent. The rules were not loaded.\n' >&2
        exit 0
    fi
}

main

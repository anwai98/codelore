#!/usr/bin/env bash
# Enforce the rules that must not be overridden by the instructions of a repository.
# Package installs are denied. Commits and pushes are escalated to the user.
#
# The check reads the text of the command. It stops a violation by mistake. It is not a security
# boundary. A command that builds its name at run time, as in "P=pip; $P install x", is not seen.
set -uo pipefail

json_field() {
    local input=$1 field=$2
    if command -v jq >/dev/null 2>&1; then
        jq -r --arg f "$field" 'getpath($f | split(".")) // empty' <<<"$input"
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c 'import json, sys
value = json.loads(sys.stdin.read())
for key in sys.argv[1].split("."):
    value = value.get(key) if isinstance(value, dict) else None
    if value is None:
        break
print(value if value else "")' "$field" <<<"$input"
    fi
}

emit() {
    local decision=$1 reason=$2
    if command -v jq >/dev/null 2>&1; then
        jq -n --arg d "$decision" --arg r "$reason" \
            '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
    else
        # The decision and the reason are fixed text of this script, so they need no escape.
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' \
            "$decision" "$reason"
    fi
    exit 0
}

# A shell invoker holds its command in quotes. Remove the quotes to see the command.
normalize() {
    local command=$1
    if grep -qE '(^|[[:space:]])(bash|sh|zsh|dash)[[:space:]]+-c([[:space:]]|$)' <<<"$command"; then
        command=${command//\'/}
        command=${command//\"/}
    fi
    printf '%s' "$command"
}

check_segment() {
    local segment=$1

    # A help request or a dry run installs nothing.
    if grep -qE '(^|[[:space:]])(--help|--dry-run)([[:space:]]|$)' <<<"$segment"; then
        return 0
    fi

    if grep -qE '(^|[[:space:]])(pip[0-9.]*|python[0-9.]*[[:space:]]+-m[[:space:]]+pip|uv[[:space:]]+pip)[[:space:]]+install\b' <<<"$segment"; then
        emit deny "The environment is managed by the user. Do not install packages with pip. Ask the user to install it."
    fi

    if grep -qE '(^|[[:space:]])(micromamba|mamba|conda)[[:space:]]+install\b' <<<"$segment"; then
        emit deny "The environment is managed by the user. Do not install packages with conda or micromamba. Ask the user to install it."
    fi

    # A global option of git can carry a value, as in "git -C <path> commit".
    if grep -qE '(^|[[:space:]])git([[:space:]]+(-[Cc][[:space:]]+[^[:space:]]+|--[a-z-]+=[^[:space:]]+|-[^[:space:]]+))*[[:space:]]+(commit|push)\b' <<<"$segment"; then
        emit ask "The user must give explicit permission before a commit or a push."
    fi
}

main() {
    local input tool command segment

    input=$(cat)
    tool=$(json_field "$input" "tool_name")
    [ "$tool" = "Bash" ] || exit 0

    command=$(json_field "$input" "tool_input.command")
    [ -n "$command" ] || exit 0

    # Each part of a compound command is checked alone, so one part cannot hide another part.
    while IFS= read -r segment; do
        [ -n "$segment" ] || continue
        check_segment "$segment"
    done < <(sed -E 's/(\|\||&&|[;|&])/\n/g' <<<"$(normalize "$command")")

    exit 0
}

main

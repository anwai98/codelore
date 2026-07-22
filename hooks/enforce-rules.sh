#!/usr/bin/env bash
# Enforce the rules that must not be overridden by repository instructions.
set -uo pipefail

TOKEN_TYPES=()
TOKEN_VALUES=()
DECISION=allow
REASON=
SUBCOMMAND=
SUBCOMMAND_INDEX=-1

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
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s",'\
'"permissionDecisionReason":"%s"}}\n' \
            "$decision" "$reason"
    fi
    exit 0
}

set_decision() {
    local decision=$1 reason=$2
    if [ "$decision" = "deny" ] || [ "$DECISION" = "allow" ]; then
        DECISION=$decision
        REASON=$reason
    fi
}

append_token() {
    TOKEN_TYPES+=("$1")
    TOKEN_VALUES+=("$2")
}

tokenize() {
    local input=$1 length i char next state token have_token
    TOKEN_TYPES=()
    TOKEN_VALUES=()
    length=${#input}
    state=plain
    token=
    have_token=0

    for ((i = 0; i < length; i++)); do
        char=${input:i:1}
        if [ "$state" = "single" ]; then
            if [ "$char" = "'" ]; then
                state=plain
            else
                token+=$char
            fi
            continue
        fi
        if [ "$state" = "double" ]; then
            if [ "$char" = '"' ]; then
                state=plain
            elif [ "$char" = "\\" ] && [ $((i + 1)) -lt "$length" ]; then
                i=$((i + 1))
                token+=${input:i:1}
            else
                token+=$char
            fi
            continue
        fi

        case "$char" in
            "'")
                state=single
                have_token=1
                ;;
            '"')
                state=double
                have_token=1
                ;;
            "\\")
                have_token=1
                if [ $((i + 1)) -lt "$length" ]; then
                    i=$((i + 1))
                    token+=${input:i:1}
                fi
                ;;
            ' '|$'\t'|$'\r')
                if [ "$have_token" -eq 1 ]; then
                    append_token word "$token"
                    token=
                    have_token=0
                fi
                ;;
            ';'|'('|')'|$'\n')
                if [ "$have_token" -eq 1 ]; then
                    append_token word "$token"
                    token=
                    have_token=0
                fi
                append_token separator "$char"
                ;;
            '|'|'&')
                if [ "$have_token" -eq 1 ]; then
                    append_token word "$token"
                    token=
                    have_token=0
                fi
                next=
                if [ $((i + 1)) -lt "$length" ]; then
                    next=${input:i+1:1}
                fi
                if [ "$next" = "$char" ]; then
                    append_token separator "$char$next"
                    i=$((i + 1))
                else
                    append_token separator "$char"
                fi
                ;;
            *)
                token+=$char
                have_token=1
                ;;
        esac
    done

    if [ "$have_token" -eq 1 ]; then
        append_token word "$token"
    fi
}

contains_word() {
    local needle=$1 word
    shift
    for word in "$@"; do
        [ "$word" = "$needle" ] && return 0
    done
    return 1
}

is_safe_preview() {
    contains_word --help "$@" || contains_word --dry-run "$@"
}

inspect_python() {
    local args=("$@") count i
    count=${#args[@]}
    for ((i = 0; i + 2 < count; i++)); do
        if [ "${args[$i]}" = "-m" ] && [ "${args[$((i + 1))]}" = "pip" ]; then
            find_subcommand pip "${args[@]:$((i + 2))}"
            if [ "$SUBCOMMAND" = "install" ]; then
                set_decision deny "The environment is managed by the user. Do not install packages with pip."
            fi
        fi
    done
}

option_takes_value() {
    local kind=$1 option=$2
    case "$kind:$option" in
        git:-C|git:-c|git:--exec-path|git:--git-dir|git:--work-tree|git:--namespace|git:--config-env|git:--attr-source)
            return 0
            ;;
        pip:--python|pip:--proxy|pip:--retries|pip:--timeout|pip:--exists-action|pip:--trusted-host)
            return 0
            ;;
        pip:--cert|pip:--client-cert|pip:--cache-dir|pip:--log|pip:--use-feature|pip:--use-deprecated)
            return 0
            ;;
        conda:-n|conda:--name|conda:-p|conda:--prefix|conda:-r|conda:--root-prefix|conda:--rc-file|conda:--log-level)
            return 0
            ;;
        uv:--directory|uv:--project|uv:--config-file|uv:--color|uv:--python|uv:--python-preference)
            return 0
            ;;
    esac
    return 1
}

find_subcommand() {
    local kind=$1 args i count word
    shift
    args=("$@")
    count=${#args[@]}
    SUBCOMMAND=
    SUBCOMMAND_INDEX=-1

    for ((i = 0; i < count; i++)); do
        word=${args[$i]}
        if [ "$word" = "--" ]; then
            i=$((i + 1))
            if [ "$i" -lt "$count" ]; then
                SUBCOMMAND=${args[$i]}
                SUBCOMMAND_INDEX=$i
            fi
            return
        fi
        if [[ "$word" = -* ]]; then
            option_takes_value "$kind" "$word" && i=$((i + 1))
            continue
        fi
        SUBCOMMAND=$word
        SUBCOMMAND_INDEX=$i
        return
    done
}

inspect_shell_invoker() {
    local args=("$@") count i option
    count=${#args[@]}
    for ((i = 0; i < count; i++)); do
        option=${args[$i]}
        if [[ "$option" = -c || "$option" =~ ^-[^-]*c[^-]*$ ]]; then
            i=$((i + 1))
            while [ "$i" -lt "$count" ] && [ "${args[$i]}" = "--" ]; do
                i=$((i + 1))
            done
            [ "$i" -lt "$count" ] && inspect_command "${args[$i]}"
            return
        fi
    done
}

inspect_simple_command() {
    local words=("$@") count i j word executable args option
    count=${#words[@]}
    i=0

    while [ "$i" -lt "$count" ]; do
        word=${words[$i]}
        executable=${word##*/}
        case "$word" in
            [A-Za-z_][A-Za-z0-9_]*=*)
                i=$((i + 1))
                continue
                ;;
        esac
        case "$executable" in
            '!'|'{'|'}'|if|then|elif|else|while|until|do|done)
                i=$((i + 1))
                continue
                ;;
            command|builtin|exec|nohup|time)
                i=$((i + 1))
                while [ "$i" -lt "$count" ] && [[ "${words[$i]}" = -* ]]; do
                    i=$((i + 1))
                done
                continue
                ;;
            env)
                i=$((i + 1))
                while [ "$i" -lt "$count" ]; do
                    option=${words[$i]}
                    if [[ "$option" = -u || "$option" = --unset || "$option" = -C || "$option" = --chdir || \
                        "$option" = -S || "$option" = --split-string ]]; then
                        i=$((i + 2))
                    elif [[ "$option" = -* || "$option" = [A-Za-z_][A-Za-z0-9_]*=* ]]; then
                        i=$((i + 1))
                    else
                        break
                    fi
                done
                continue
                ;;
            sudo)
                i=$((i + 1))
                while [ "$i" -lt "$count" ] && [[ "${words[$i]}" = -* ]]; do
                    option=${words[$i]}
                    i=$((i + 1))
                    case "$option" in
                        -u|--user|-g|--group|-h|--host|-p|--prompt|-C|--close-from|-T|--command-timeout)
                            i=$((i + 1))
                            ;;
                        -R|--chroot|-D|--chdir)
                            i=$((i + 1))
                            ;;
                    esac
                done
                continue
                ;;
        esac
        break
    done

    [ "$i" -lt "$count" ] || return
    executable=${words[$i]##*/}
    args=()
    for ((j = i + 1; j < count; j++)); do
        args+=("${words[$j]}")
    done

    case "$executable" in
        bash|sh|zsh|dash)
            inspect_shell_invoker "${args[@]}"
            ;;
        pip|pip[0-9]|pip[0-9].[0-9]*)
            find_subcommand pip "${args[@]}"
            if ! is_safe_preview "${args[@]}" && [ "$SUBCOMMAND" = "install" ]; then
                set_decision deny "The environment is managed by the user. Do not install packages with pip."
            fi
            ;;
        python|python[0-9]|python[0-9].[0-9]*)
            if ! is_safe_preview "${args[@]}"; then
                inspect_python "${args[@]}"
            fi
            ;;
        uv)
            find_subcommand uv "${args[@]}"
            if ! is_safe_preview "${args[@]}" && [ "$SUBCOMMAND" = "pip" ]; then
                find_subcommand pip "${args[@]:$((SUBCOMMAND_INDEX + 1))}"
                if [ "$SUBCOMMAND" = "install" ]; then
                    set_decision deny "The environment is managed by the user. Do not install packages with pip."
                fi
            fi
            ;;
        micromamba|mamba|conda)
            find_subcommand conda "${args[@]}"
            if ! is_safe_preview "${args[@]}" && [ "$SUBCOMMAND" = "install" ]; then
                set_decision deny \
                    "The environment is managed by the user. Do not install packages with conda or micromamba."
            fi
            ;;
        git)
            find_subcommand git "${args[@]}"
            if ! is_safe_preview "${args[@]}" && [[ "$SUBCOMMAND" = commit || "$SUBCOMMAND" = push ]]; then
                set_decision ask "The user must give explicit permission before a commit or a push."
            fi
            ;;
    esac
}

inspect_command() {
    local command=$1 token_types token_values segment i
    tokenize "$command"
    token_types=("${TOKEN_TYPES[@]}")
    token_values=("${TOKEN_VALUES[@]}")
    segment=()

    for ((i = 0; i < ${#token_types[@]}; i++)); do
        if [ "${token_types[$i]}" = "separator" ]; then
            [ "${#segment[@]}" -eq 0 ] || inspect_simple_command "${segment[@]}"
            segment=()
        else
            segment+=("${token_values[$i]}")
        fi
    done
    [ "${#segment[@]}" -eq 0 ] || inspect_simple_command "${segment[@]}"
}

main() {
    local input tool command
    input=$(cat)
    tool=$(json_field "$input" "tool_name")
    [ "$tool" = "Bash" ] || exit 0

    command=$(json_field "$input" "tool_input.command")
    [ -n "$command" ] || exit 0
    inspect_command "$command"

    case "$DECISION" in
        deny|ask)
            emit "$DECISION" "$REASON"
            ;;
    esac
}

main

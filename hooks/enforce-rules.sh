#!/usr/bin/env bash
# Enforce the rules that must not be overridden by repository instructions.
set -uo pipefail

TOKEN_TYPES=()
TOKEN_VALUES=()
HEREDOC_DELIMITERS=()
HEREDOC_STRIP_TABS=()
DECISION=allow
REASON=
IS_CODEX=0
STRIPPED_COMMAND=
REDIRECTION_WIDTH=0
SUBCOMMAND=
SUBCOMMAND_INDEX=-1
PYTHON_MODULE=
PYTHON_MODULE_INDEX=-1
PYTHON_SAFE_PREVIEW=0

PIP_REASON="The environment is managed by the user. Do not install packages with pip."
CONDA_REASON="The environment is managed by the user. Do not install packages with conda or micromamba."
UV_REASON="The environment is managed by the user. Do not install packages with uv."

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

collect_heredocs() {
    local line=$1 length i j char next state delimiter strip_tabs boundary
    length=${#line}
    state=plain
    boundary=1

    for ((i = 0; i < length; i++)); do
        char=${line:i:1}
        if [ "$state" = "single" ]; then
            [ "$char" = "'" ] && state=plain
            continue
        fi
        if [ "$state" = "double" ]; then
            if [ "$char" = '"' ]; then
                state=plain
            elif [ "$char" = "\\" ]; then
                i=$((i + 1))
            fi
            continue
        fi

        case "$char" in
            "'")
                state=single
                boundary=0
                ;;
            '"')
                state=double
                boundary=0
                ;;
            "\\")
                boundary=0
                i=$((i + 1))
                ;;
            '#')
                [ "$boundary" -eq 1 ] && return
                boundary=0
                ;;
            ' '|$'\t')
                boundary=1
                ;;
            ';'|'|'|'&'|'('|')')
                boundary=1
                ;;
            '<')
                next=
                [ $((i + 1)) -lt "$length" ] && next=${line:i+1:1}
                if { [ "$i" -gt 0 ] && [ "${line:i-1:1}" = "<" ]; } || [ "$next" != "<" ] || \
                    { [ $((i + 2)) -lt "$length" ] && [ "${line:i+2:1}" = "<" ]; }; then
                    boundary=1
                    continue
                fi

                j=$((i + 2))
                strip_tabs=0
                if [ "$j" -lt "$length" ] && [ "${line:j:1}" = "-" ]; then
                    strip_tabs=1
                    j=$((j + 1))
                fi
                while [ "$j" -lt "$length" ] && [[ "${line:j:1}" = ' ' || "${line:j:1}" = $'\t' ]]; do
                    j=$((j + 1))
                done

                delimiter=
                state=plain
                while [ "$j" -lt "$length" ]; do
                    char=${line:j:1}
                    if [ "$state" = "single" ]; then
                        if [ "$char" = "'" ]; then
                            state=plain
                        else
                            delimiter+=$char
                        fi
                    elif [ "$state" = "double" ]; then
                        if [ "$char" = '"' ]; then
                            state=plain
                        elif [ "$char" = "\\" ] && [ $((j + 1)) -lt "$length" ]; then
                            j=$((j + 1))
                            delimiter+=${line:j:1}
                        else
                            delimiter+=$char
                        fi
                    else
                        case "$char" in
                            "'")
                                state=single
                                ;;
                            '"')
                                state=double
                                ;;
                            "\\")
                                if [ $((j + 1)) -lt "$length" ]; then
                                    j=$((j + 1))
                                    delimiter+=${line:j:1}
                                fi
                                ;;
                            ' '|$'\t'|';'|'|'|'&'|'('|')'|'<'|'>')
                                break
                                ;;
                            *)
                                delimiter+=$char
                                ;;
                        esac
                    fi
                    j=$((j + 1))
                done
                if [ -n "$delimiter" ]; then
                    HEREDOC_DELIMITERS+=("$delimiter")
                    HEREDOC_STRIP_TABS+=("$strip_tabs")
                fi
                state=plain
                boundary=1
                i=$((j - 1))
                ;;
            *)
                boundary=0
                ;;
        esac
    done
}

strip_heredoc_bodies() {
    local remaining=$1 line has_newline compare delimiter strip_tabs
    STRIPPED_COMMAND=
    HEREDOC_DELIMITERS=()
    HEREDOC_STRIP_TABS=()

    while :; do
        if [[ "$remaining" = *$'\n'* ]]; then
            line=${remaining%%$'\n'*}
            remaining=${remaining#*$'\n'}
            has_newline=1
        else
            line=$remaining
            remaining=
            has_newline=0
        fi

        if [ "${#HEREDOC_DELIMITERS[@]}" -gt 0 ]; then
            delimiter=${HEREDOC_DELIMITERS[0]}
            strip_tabs=${HEREDOC_STRIP_TABS[0]}
            compare=$line
            if [ "$strip_tabs" -eq 1 ]; then
                while [[ "$compare" = $'\t'* ]]; do
                    compare=${compare#$'\t'}
                done
            fi
            if [ "$compare" = "$delimiter" ]; then
                HEREDOC_DELIMITERS=("${HEREDOC_DELIMITERS[@]:1}")
                HEREDOC_STRIP_TABS=("${HEREDOC_STRIP_TABS[@]:1}")
            fi
        else
            STRIPPED_COMMAND+=$line
            collect_heredocs "$line"
            [ "$has_newline" -eq 0 ] || STRIPPED_COMMAND+=$'\n'
        fi

        [ "$has_newline" -eq 1 ] || break
    done
}

tokenize() {
    local input=$1 length i char next state token have_token output_redirection fd_redirection
    TOKEN_TYPES=()
    TOKEN_VALUES=()
    length=${#input}
    state=plain
    token=
    have_token=0
    output_redirection='^[0-9]*>$'
    fd_redirection='^[0-9]*[<>]$'

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
            '|')
                if [[ "$token" =~ $output_redirection ]]; then
                    token+=$char
                    have_token=1
                    continue
                fi
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
            '&')
                next=
                [ $((i + 1)) -lt "$length" ] && next=${input:i+1:1}
                if [[ "$token" =~ $fd_redirection ]] || { [ -z "$token" ] && [ "$next" = ">" ]; }; then
                    token+=$char
                    have_token=1
                    continue
                fi
                if [ "$have_token" -eq 1 ]; then
                    append_token word "$token"
                    token=
                    have_token=0
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

is_assignment() {
    [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*(\+)?= ]]
}

is_redirection() {
    local pattern='^[0-9]*(&>>|&>|<<<|<<-?|>>|<>|>\||>&|<&|>|<)(.*)$'
    REDIRECTION_WIDTH=0
    if [[ "$1" =~ $pattern ]]; then
        REDIRECTION_WIDTH=1
        [ -n "${BASH_REMATCH[2]}" ] || REDIRECTION_WIDTH=2
        return 0
    fi
    return 1
}

# A preview flag counts only when it sits in an option position. In `git commit -m --help` the
# flag is the commit message, so the command is a real commit and not a request for help.
# The arguments are the words after the executable. The kind is that of the executable.
is_safe_preview() {
    local kind=$1 args count i word scope
    shift
    args=("$@")
    count=${#args[@]}
    scope=$kind

    for ((i = 0; i < count; i++)); do
        word=${args[$i]}
        [ "$word" = "--" ] && return 1
        case "$word" in
            --help|--dry-run)
                return 0
                ;;
        esac
        if [[ "$word" = -* ]]; then
            option_takes_value "$scope" "$word" && i=$((i + 1))
            continue
        fi
        # The first bare word is the subcommand. Its own options govern the rest of the line.
        [ "$scope" = "$kind" ] && scope=$kind-$word
    done
    return 1
}

# Find the module of `python -m`. Python attaches the name or takes the next word, and it allows a
# bundle of short options. All of `-m pip`, `-mpip`, and `-um pip` name the module pip.
# The result is the module and the index of its first argument.
find_python_module() {
    local args=("$@") count i j word length letter rest
    count=${#args[@]}
    PYTHON_MODULE=
    PYTHON_MODULE_INDEX=-1
    PYTHON_SAFE_PREVIEW=0

    for ((i = 0; i < count; i++)); do
        word=${args[$i]}
        [[ "$word" = -?* ]] || return
        if [[ "$word" = --help || "$word" = --dry-run ]]; then
            PYTHON_SAFE_PREVIEW=1
            return
        fi
        [[ "$word" = --* ]] && continue
        length=${#word}
        for ((j = 1; j < length; j++)); do
            letter=${word:j:1}
            rest=${word:j+1}
            case "$letter" in
                m)
                    if [ -n "$rest" ]; then
                        PYTHON_MODULE=$rest
                        PYTHON_MODULE_INDEX=$((i + 1))
                    elif [ $((i + 1)) -lt "$count" ]; then
                        PYTHON_MODULE=${args[$((i + 1))]}
                        PYTHON_MODULE_INDEX=$((i + 2))
                    fi
                    return
                    ;;
                c)
                    return
                    ;;
                W|X|Q)
                    [ -n "$rest" ] || i=$((i + 1))
                    break
                    ;;
            esac
        done
    done
}

inspect_python() {
    local pip_args
    find_python_module "$@"
    [ "$PYTHON_SAFE_PREVIEW" -eq 0 ] || return
    [ "$PYTHON_MODULE" = "pip" ] || return
    [ "$PYTHON_MODULE_INDEX" -lt "$#" ] || return
    pip_args=("${@:$((PYTHON_MODULE_INDEX + 1))}")
    find_subcommand pip "${pip_args[@]}"
    if ! is_safe_preview pip "${pip_args[@]}" && [ "$SUBCOMMAND" = "install" ]; then
        set_decision deny "$PIP_REASON"
    fi
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
        conda:--cwd)
            return 0
            ;;
        uv:--directory|uv:--project|uv:--config-file|uv:--color|uv:--python|uv:--python-preference)
            return 0
            ;;
        uv:--with|uv:--with-requirements|uv:--extra|uv:--env-file)
            return 0
            ;;
        git-commit:-m|git-commit:--message|git-commit:-F|git-commit:--file|git-commit:--author)
            return 0
            ;;
        git-commit:--date|git-commit:-c|git-commit:--reedit-message|git-commit:-C|git-commit:--reuse-message)
            return 0
            ;;
        git-commit:--fixup|git-commit:--squash|git-commit:-t|git-commit:--template|git-commit:--trailer)
            return 0
            ;;
        git-push:--repo|git-push:-o|git-push:--push-option|git-push:--receive-pack|git-push:--exec)
            return 0
            ;;
        git-push:--recurse-submodules)
            return 0
            ;;
        pip-install:-r|pip-install:--requirement|pip-install:-c|pip-install:--constraint|pip-install:-t)
            return 0
            ;;
        pip-install:--target|pip-install:-i|pip-install:--index-url|pip-install:--extra-index-url)
            return 0
            ;;
        pip-install:-f|pip-install:--find-links|pip-install:--prefix|pip-install:--root|pip-install:--src)
            return 0
            ;;
        conda-install:-n|conda-install:--name|conda-install:-p|conda-install:--prefix|conda-install:-c)
            return 0
            ;;
        conda-install:--channel|conda-install:--file)
            return 0
            ;;
        conda-create:-n|conda-create:--name|conda-create:-p|conda-create:--prefix|conda-create:-c)
            return 0
            ;;
        conda-create:--channel|conda-create:--file|conda-create:-f)
            return 0
            ;;
        conda-update:-n|conda-update:--name|conda-update:-p|conda-update:--prefix|conda-update:-c)
            return 0
            ;;
        conda-update:--channel|conda-update:--file)
            return 0
            ;;
        conda-upgrade:-n|conda-upgrade:--name|conda-upgrade:-p|conda-upgrade:--prefix|conda-upgrade:-c)
            return 0
            ;;
        conda-upgrade:--channel|conda-upgrade:--file)
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

# Inspect the command that a runner executes, as in `micromamba run -n super pip install x`.
# The arguments are the words after the `run` subcommand.
inspect_runner() {
    local kind=$1 args prefix index
    shift
    [ "$#" -gt 0 ] || return
    args=("$@")
    find_subcommand "$kind" "${args[@]}"
    index=$SUBCOMMAND_INDEX
    [ "$index" -ge 0 ] || return
    if [ "$index" -gt 0 ]; then
        prefix=("${args[@]:0:$index}")
        is_safe_preview "$kind" "${prefix[@]}" && return
    fi
    inspect_simple_command "${args[@]:$index}"
}

# The uv subcommands that change the environment of the user.
inspect_uv() {
    local args=("$@") nested count index
    count=${#args[@]}
    find_subcommand uv "${args[@]}"
    index=$SUBCOMMAND_INDEX
    if [ "$index" -gt 0 ]; then
        nested=("${args[@]:0:$index}")
        is_safe_preview uv "${nested[@]}" && return
    fi

    case "$SUBCOMMAND" in
        add|sync)
            if ! is_safe_preview uv "${args[@]}"; then
                set_decision deny "$UV_REASON"
            fi
            return
            ;;
    esac

    [ "$index" -ge 0 ] && [ $((index + 1)) -lt "$count" ] || return

    case "$SUBCOMMAND" in
        pip)
            nested=("${args[@]:$((index + 1))}")
            find_subcommand pip "${nested[@]}"
            if ! is_safe_preview pip "${nested[@]}"; then
                case "$SUBCOMMAND" in
                    install|sync)
                        set_decision deny "$PIP_REASON"
                        ;;
                esac
            fi
            ;;
        tool)
            nested=("${args[@]:$((index + 1))}")
            find_subcommand uv "${nested[@]}"
            if ! is_safe_preview uv "${nested[@]}" && [ "$SUBCOMMAND" = "install" ]; then
                set_decision deny "$UV_REASON"
            fi
            ;;
        run)
            inspect_runner uv "${args[@]:$((index + 1))}"
            ;;
    esac
}

# The conda and micromamba subcommands that change the environment of the user.
inspect_conda() {
    local args=("$@") nested count index
    count=${#args[@]}
    find_subcommand conda "${args[@]}"
    index=$SUBCOMMAND_INDEX
    if [ "$index" -gt 0 ]; then
        nested=("${args[@]:0:$index}")
        is_safe_preview conda "${nested[@]}" && return
    fi

    case "$SUBCOMMAND" in
        install|create|update|upgrade)
            if ! is_safe_preview conda "${args[@]}"; then
                set_decision deny "$CONDA_REASON"
            fi
            return
            ;;
    esac

    [ "$index" -ge 0 ] && [ $((index + 1)) -lt "$count" ] || return

    case "$SUBCOMMAND" in
        env)
            nested=("${args[@]:$((index + 1))}")
            find_subcommand conda "${nested[@]}"
            if ! is_safe_preview conda "${nested[@]}"; then
                case "$SUBCOMMAND" in
                    create|update)
                        set_decision deny "$CONDA_REASON"
                        ;;
                esac
            fi
            ;;
        run)
            inspect_runner conda "${args[@]:$((index + 1))}"
            ;;
    esac
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
        if is_assignment "$word"; then
            i=$((i + 1))
            continue
        fi
        if is_redirection "$word"; then
            i=$((i + REDIRECTION_WIDTH))
            continue
        fi
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
                    elif [[ "$option" = -* ]] || is_assignment "$option"; then
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

    # An executable with no argument cannot break a rule. The check also keeps the branches below
    # from expanding an empty array, which aborts bash 3.2 under `set -u`. macOS ships bash 3.2.
    [ "${#args[@]}" -gt 0 ] || return

    case "$executable" in
        bash|sh|zsh|dash)
            inspect_shell_invoker "${args[@]}"
            ;;
        pip|pip[0-9]|pip[0-9].[0-9]*)
            find_subcommand pip "${args[@]}"
            if ! is_safe_preview pip "${args[@]}" && [ "$SUBCOMMAND" = "install" ]; then
                set_decision deny "$PIP_REASON"
            fi
            ;;
        python|python[0-9]|python[0-9].[0-9]*)
            inspect_python "${args[@]}"
            ;;
        uv)
            inspect_uv "${args[@]}"
            ;;
        micromamba|mamba|conda)
            inspect_conda "${args[@]}"
            ;;
        git)
            find_subcommand git "${args[@]}"
            if ! is_safe_preview git "${args[@]}" && [[ "$SUBCOMMAND" = commit || "$SUBCOMMAND" = push ]]; then
                if [ "$IS_CODEX" -eq 0 ]; then
                    set_decision ask "The user must give explicit permission before a commit or a push."
                fi
            fi
            ;;
    esac
}

inspect_command() {
    local command=$1 token_types token_values segment i
    strip_heredoc_bodies "$command"
    tokenize "$STRIPPED_COMMAND"
    [ "${#TOKEN_TYPES[@]}" -gt 0 ] || return
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
    local input tool command model
    input=$(cat)
    tool=$(json_field "$input" "tool_name")
    [ "$tool" = "Bash" ] || exit 0
    model=$(json_field "$input" "model")
    [ -z "$model" ] || IS_CODEX=1

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

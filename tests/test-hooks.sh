#!/usr/bin/env bash
# Test the hook scripts. Run from anywhere: tests/test-hooks.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

report() {
    local status=$1 name=$2 detail=${3:-}
    if [ "$status" = "pass" ]; then
        PASS=$((PASS + 1))
        printf 'ok   %s\n' "$name"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL %s\n     %s\n' "$name" "$detail"
    fi
}

decision_for() {
    local command=$1 input output
    input=$(jq -n --arg c "$command" '{tool_name: "Bash", tool_input: {command: $c}}')
    output=$(printf '%s' "$input" | "$ROOT/hooks/enforce-rules.sh")
    if [ -z "$output" ]; then
        echo "allow"
    else
        jq -r '.hookSpecificOutput.permissionDecision' <<<"$output"
    fi
}

expect_decision() {
    local command=$1 expected=$2 actual
    actual=$(decision_for "$command")
    if [ "$actual" = "$expected" ]; then
        report pass "[$expected] $command"
    else
        report fail "[$expected] $command" "got '$actual'"
    fi
}

test_denied_installs() {
    expect_decision "pip install torch" deny
    expect_decision "pip3 install torch" deny
    expect_decision "python -m pip install -e ." deny
    expect_decision "uv pip install ruff" deny
    expect_decision "micromamba install -n super numpy" deny
    expect_decision "mamba install numpy" deny
    expect_decision "conda install scipy" deny
    expect_decision "cd /tmp && pip install foo" deny
    expect_decision "/usr/bin/pip install torch" deny
    expect_decision "pip --isolated install torch" deny
    expect_decision "micromamba -n super install numpy" deny
}

test_attached_python_module_is_inspected() {
    expect_decision "python -mpip install torch" deny
    expect_decision "python3 -mpip install torch" deny
    expect_decision "python -um pip install torch" deny
    expect_decision "python -umpip install torch" deny
    expect_decision "python -u -m pip install -e ." deny
    expect_decision "python -W ignore -m pip install torch" deny
    expect_decision "python -X faulthandler -m pip install torch" deny
    expect_decision "python -Wignore -mpip install torch" deny
    expect_decision "python -mpip download install" allow
    expect_decision "python -c 'import pip' -m pip install torch" allow
    expect_decision "python train.py -m pip install torch" allow
}

test_every_install_verb_is_denied() {
    expect_decision "uv add torch" deny
    expect_decision "uv sync" deny
    expect_decision "uv tool install ruff" deny
    expect_decision "uv pip sync requirements.txt" deny
    expect_decision "conda create -n x numpy" deny
    expect_decision "conda env create -f env.yaml" deny
    expect_decision "conda env update -f env.yaml" deny
    expect_decision "micromamba create -n x numpy" deny
    expect_decision "conda update numpy" deny
    expect_decision "mamba upgrade -n super scipy" deny
    expect_decision "uv lock" allow
    expect_decision "conda env list" allow
    expect_decision "conda list" allow
}

# A bare executable expands an empty array, which aborts bash 3.2 under `set -u`.
test_bare_executables_are_handled() {
    expect_decision "pip" allow
    expect_decision "python" allow
    expect_decision "uv" allow
    expect_decision "conda" allow
    expect_decision "micromamba" allow
    expect_decision "git" allow
    expect_decision "bash" allow
    expect_decision "uv pip" allow
    expect_decision "micromamba run" allow
    expect_decision "conda env" allow
    expect_decision "uv tool" allow
    expect_decision "python -m" allow
    expect_decision "   " allow
}

test_escalated_git() {
    expect_decision "git commit -m 'x'" ask
    expect_decision "git push origin main" ask
    expect_decision "git -C /tmp commit -m y" ask
    expect_decision "git -c user.name=x commit" ask
    expect_decision "git --git-dir=/a/.git push" ask
    expect_decision "/usr/bin/git push origin main" ask
    expect_decision "git --git-dir /a/.git push" ask
}

test_preview_flags_only_count_as_options() {
    expect_decision "git commit -m --help" ask
    expect_decision "git commit -m --dry-run" ask
    expect_decision "git commit --message --help" ask
    expect_decision "git commit -F --help" ask
    expect_decision "git commit -m x --author --help" ask
    expect_decision "git -C /tmp commit -m --help" ask
    expect_decision "git push --repo --dry-run" ask
    expect_decision "git commit -m 'add a --dry-run flag'" ask
    expect_decision "pip install -r --help" deny
    expect_decision "conda install -n --help numpy" deny
    expect_decision "git commit --help" allow
    expect_decision "git commit --help -m x" allow
    expect_decision "git push --dry-run origin main" allow
    expect_decision "git push origin main --dry-run" allow
    expect_decision "pip install --help" allow
    expect_decision "pip install torch --dry-run" allow
}

test_compound_commands_cannot_hide_a_violation() {
    expect_decision "du -h && pip install torch" deny
    expect_decision "ls -h; pip install torch" deny
    expect_decision "make --dry-run && pip install torch" deny
    expect_decision "sort -h data.txt && git push origin main" ask
    expect_decision "echo done | grep -h done && conda install numpy" deny
    expect_decision "git commit -m x && pip install torch" deny
    expect_decision "git push origin main; conda install numpy" deny
}

test_runner_commands_are_inspected() {
    expect_decision "micromamba run -n super pip install torch" deny
    expect_decision "micromamba run -n super python -m pip install -e ." deny
    expect_decision "conda run -n super pip install torch" deny
    expect_decision "mamba run -p /opt/env pip install torch" deny
    expect_decision "conda run -n super --cwd /tmp pip install torch" deny
    expect_decision "uv run pip install torch" deny
    expect_decision "uv run --with numpy pip install torch" deny
    expect_decision "micromamba run -n super bash -c 'pip install torch'" deny
    expect_decision "micromamba run -n super git push origin main" ask
    expect_decision "micromamba run -n super python train.py" allow
    expect_decision "micromamba run -n super flake8 --max-line-length=120 ." allow
}

test_shell_invoker_is_inspected() {
    expect_decision "bash -c 'pip install torch'" deny
    expect_decision "sh -c \"micromamba install numpy\"" deny
    expect_decision "bash -c 'git push origin main'" ask
    expect_decision "/bin/bash -c 'pip install torch'" deny
    expect_decision "bash -lc 'pip install torch'" deny
}

# A stub PATH that holds every tool of the hook except jq, so the python3 branch runs.
test_enforcement_survives_without_jq() {
    local stub binary decision

    if [ -z "$(type -P python3)" ]; then
        report pass "enforcement without jq (skipped: no python3)"
        return
    fi

    stub=$(mktemp -d)
    for binary in python3 grep sed cat bash; do
        ln -s "$(type -P "$binary")" "$stub/$binary"
    done

    decision=$(jq -n '{tool_name: "Bash", tool_input: {command: "pip install torch"}}' \
        | env -i PATH="$stub" "$stub/bash" "$ROOT/hooks/enforce-rules.sh" \
        | jq -r '.hookSpecificOutput.permissionDecision // empty')
    rm -rf "$stub"

    if [ "$decision" = "deny" ]; then
        report pass "enforcement still denies when jq is absent"
    else
        report fail "enforcement still denies when jq is absent" "got '$decision'"
    fi
}

test_allowed() {
    expect_decision "pip list" allow
    expect_decision "pip install --help" allow
    expect_decision "git status" allow
    expect_decision "git diff" allow
    expect_decision "git log --oneline" allow
    expect_decision "git log --grep commit" allow
    expect_decision "echo 'pip install' > notes.txt" allow
    expect_decision "printf '%s' 'git commit && pip install torch'" allow
    expect_decision "echo git commit" allow
    expect_decision "echo pip install torch" allow
    expect_decision "pip download install" allow
    expect_decision "python train.py" allow
    expect_decision "micromamba run -n super python train.py" allow
}

test_non_bash_tool_is_ignored() {
    local output
    output=$(jq -n '{tool_name: "Read", tool_input: {file_path: "/x"}}' | "$ROOT/hooks/enforce-rules.sh")
    if [ -z "$output" ]; then
        report pass "[allow] non-Bash tool produces no decision"
    else
        report fail "[allow] non-Bash tool produces no decision" "got '$output'"
    fi
}

test_rules_payload_is_valid_json() {
    local event
    event=$(CLAUDE_PLUGIN_ROOT="$ROOT" "$ROOT/hooks/emit-rules.sh" | jq -r '.hookSpecificOutput.hookEventName')
    if [ "$event" = "SessionStart" ]; then
        report pass "emit-rules emits a SessionStart payload"
    else
        report fail "emit-rules emits a SessionStart payload" "got '$event'"
    fi
}

test_rules_payload_matches_agents_md() {
    if CLAUDE_PLUGIN_ROOT="$ROOT" "$ROOT/hooks/emit-rules.sh" \
        | jq -j '.hookSpecificOutput.additionalContext' | cmp -s - "$ROOT/AGENTS.md"; then
        report pass "emit-rules payload is byte-identical to AGENTS.md"
    else
        report fail "emit-rules payload is byte-identical to AGENTS.md" "content differs"
    fi
}

test_emission_survives_without_jq() {
    local stub event
    if [ -z "$(type -P python3)" ]; then
        report pass "emission without jq (skipped: no python3)"
        return
    fi

    stub=$(mktemp -d)
    for binary in python3 bash; do
        ln -s "$(type -P "$binary")" "$stub/$binary"
    done
    event=$(env -i PATH="$stub" CLAUDE_PLUGIN_ROOT="$ROOT" "$stub/bash" "$ROOT/hooks/emit-rules.sh" \
        | jq -r '.hookSpecificOutput.hookEventName // empty')
    rm -rf "$stub"

    if [ "$event" = "SessionStart" ]; then
        report pass "emit-rules still works when jq is absent"
    else
        report fail "emit-rules still works when jq is absent" "got '$event'"
    fi
}

# The plugin root must never come from an empty variable, or the hook reads /AGENTS.md.
test_rules_root_falls_back_to_the_script_location() {
    local event
    event=$(env -u CLAUDE_PLUGIN_ROOT -u PLUGIN_ROOT "$ROOT/hooks/emit-rules.sh" \
        | jq -r '.hookSpecificOutput.hookEventName // empty')
    if [ "$event" = "SessionStart" ]; then
        report pass "emit-rules finds the rules without either plugin root variable"
    else
        report fail "emit-rules finds the rules without either plugin root variable" "got '$event'"
    fi
}

test_rules_root_accepts_the_codex_variable() {
    local event
    event=$(env -u CLAUDE_PLUGIN_ROOT PLUGIN_ROOT="$ROOT" "$ROOT/hooks/emit-rules.sh" \
        | jq -r '.hookSpecificOutput.hookEventName // empty')
    if [ "$event" = "SessionStart" ]; then
        report pass "emit-rules accepts PLUGIN_ROOT, the Codex variable"
    else
        report fail "emit-rules accepts PLUGIN_ROOT, the Codex variable" "got '$event'"
    fi
}

test_rules_missing_file_warns_and_exits_zero() {
    local empty output status warning
    empty=$(mktemp -d)
    output=$(CLAUDE_PLUGIN_ROOT="$empty" "$ROOT/hooks/emit-rules.sh" 2>"$empty/stderr")
    status=$?
    warning=$(cat "$empty/stderr")
    rm -rf "$empty"

    if [ -z "$output" ] && [ "$status" -eq 0 ] && [ -n "$warning" ]; then
        report pass "emit-rules warns and exits 0 when the rules file is absent"
    else
        report fail "emit-rules warns and exits 0 when the rules file is absent" \
            "status '$status', stdout '$output', stderr '$warning'"
    fi
}

frontmatter_of() {
    awk 'NR==1 && $0=="---" {inside=1; next} inside && $0=="---" {exit} inside {print}' "$1"
}

test_every_skill_is_well_formed() {
    local skill dir block name description found=0

    for skill in "$ROOT"/skills/*/SKILL.md; do
        [ -e "$skill" ] || break
        found=$((found + 1))
        dir=$(basename "$(dirname "$skill")")
        block=$(frontmatter_of "$skill")

        if [ -z "$block" ]; then
            report fail "$dir: SKILL.md has frontmatter" "no --- block at the top of the file"
            continue
        fi

        name=$(sed -n 's/^name:[[:space:]]*//p' <<<"$block" | head -1)
        description=$(sed -n 's/^description:[[:space:]]*//p' <<<"$block" | head -1)

        if [ "$name" = "$dir" ]; then
            report pass "$dir: frontmatter name matches the directory"
        else
            report fail "$dir: frontmatter name matches the directory" "name is '$name'"
        fi

        if [ -n "$description" ]; then
            report pass "$dir: frontmatter has a description"
        else
            report fail "$dir: frontmatter has a description" "the description is empty or missing"
        fi
    done

    if [ "$found" -gt 0 ]; then
        report pass "the skills directory holds at least one skill"
    else
        report fail "the skills directory holds at least one skill" "no SKILL.md was found"
    fi
}

test_claude_md_only_imports_agents_md() {
    if grep -qx '@AGENTS.md' "$ROOT/CLAUDE.md"; then
        report pass "CLAUDE.md imports AGENTS.md"
    else
        report fail "CLAUDE.md imports AGENTS.md" "the @AGENTS.md import is missing"
    fi
}

test_manifests_are_valid_json() {
    local manifest
    for manifest in \
        "$ROOT/.agents/plugins/marketplace.json" \
        "$ROOT/.claude-plugin/marketplace.json" \
        "$ROOT/.claude-plugin/plugin.json" \
        "$ROOT/.codex-plugin/plugin.json" \
        "$ROOT/hooks/hooks.json"; do
        if jq -e . "$manifest" >/dev/null; then
            report pass "${manifest#"$ROOT"/} is valid JSON"
        else
            report fail "${manifest#"$ROOT"/} is valid JSON" "jq rejected the file"
        fi
    done
}

test_plugin_manifests_agree() {
    local claude_manifest=$ROOT/.claude-plugin/plugin.json
    local codex_manifest=$ROOT/.codex-plugin/plugin.json
    if jq -e -s '.[0].name == .[1].name and .[0].version == .[1].version' \
        "$claude_manifest" "$codex_manifest" >/dev/null; then
        report pass "Claude Code and Codex use the same plugin name and version"
    else
        report fail "Claude Code and Codex use the same plugin name and version" "the manifests differ"
    fi

    if jq -e '.skills == "./skills/"' "$codex_manifest" >/dev/null; then
        report pass "the Codex manifest loads the shared skills directory"
    else
        report fail "the Codex manifest loads the shared skills directory" "the skills path is not ./skills/"
    fi
}

test_marketplaces_point_to_the_plugin_root() {
    local claude_marketplace=$ROOT/.claude-plugin/marketplace.json
    local codex_marketplace=$ROOT/.agents/plugins/marketplace.json
    if jq -e '.plugins | length == 1 and .[0].name == "codelore" and .[0].source == "./"' \
        "$claude_marketplace" >/dev/null; then
        report pass "the Claude Code marketplace points to the plugin root"
    else
        report fail "the Claude Code marketplace points to the plugin root" "the codelore source is not ./"
    fi

    if jq -e '.plugins | length == 1 and .[0].name == "codelore" and .[0].source.path == "./"' \
        "$codex_marketplace" >/dev/null; then
        report pass "the Codex marketplace points to the plugin root"
    else
        report fail "the Codex marketplace points to the plugin root" "the codelore source path is not ./"
    fi
}

main() {
    command -v jq >/dev/null 2>&1 || { echo "jq is required to run these tests."; exit 1; }

    test_denied_installs
    test_attached_python_module_is_inspected
    test_every_install_verb_is_denied
    test_bare_executables_are_handled
    test_escalated_git
    test_preview_flags_only_count_as_options
    test_compound_commands_cannot_hide_a_violation
    test_runner_commands_are_inspected
    test_shell_invoker_is_inspected
    test_enforcement_survives_without_jq
    test_allowed
    test_non_bash_tool_is_ignored
    test_rules_payload_is_valid_json
    test_rules_payload_matches_agents_md
    test_emission_survives_without_jq
    test_rules_root_falls_back_to_the_script_location
    test_rules_root_accepts_the_codex_variable
    test_rules_missing_file_warns_and_exits_zero
    test_every_skill_is_well_formed
    test_claude_md_only_imports_agents_md
    test_manifests_are_valid_json
    test_plugin_manifests_agree
    test_marketplaces_point_to_the_plugin_root

    printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
    [ "$FAIL" -eq 0 ]
}

main

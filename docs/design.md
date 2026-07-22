# Design

This file gives the reason for the structure of the repository. Read it before you change the
layout or the hooks.

## The problem

The rules and the skill were global before. `CLAUDE.md` was in the home directory, and the skill was
in `~/.claude/skills/`. Both applied to every repository, but only on one machine. A second machine
needed a manual copy.

The goal is one repository that gives the rules and the skills to Claude Code and to Codex, on any
machine, with the smallest possible setup for each machine.

## The files

| File | Role |
| :--- | :--- |
| `AGENTS.md` | The rules. This is the single source of truth. Codex reads it directly. |
| `CLAUDE.md` | Imports `AGENTS.md` with `@AGENTS.md`, then adds the rules for work in this repository. |
| `hooks/emit-rules.sh` | Sends `AGENTS.md` into the context of every session. |
| `hooks/enforce-rules.sh` | Blocks the commands that must not run. |
| `skills/` | The skills. Claude Code finds them because the repository is a plugin. |

`AGENTS.md` is the portable payload. The hook sends it to every repository on the machine. A rule
that applies only to this repository must go into `CLAUDE.md`, below the import. If you put such a
rule into `AGENTS.md`, it goes to all other repositories, where it has no meaning.

## Why a plugin

Claude Code installs a plugin one time for each machine. The plugin then applies in every
repository. This removes the manual copy.

A plugin cannot supply a `CLAUDE.md`. It can supply a `SessionStart` hook. The hook returns the
rules as `additionalContext`, and Claude Code puts this text into the context window. This is the
only way for a plugin to give always-on rules.

The repository root is the plugin, and the repository is also its own marketplace. Because of this,
`${CLAUDE_PLUGIN_ROOT}` is the repository root, and the hook finds `AGENTS.md` at an exact path.
The repository holds one plugin. If it must hold more than one plugin later, each plugin moves into
`plugins/<name>/`, and the `source` in `marketplace.json` changes.

## Why a PreToolUse hook

Instructions are context, not configuration. Claude Code does not enforce them. If the instructions
of a repository disagree with the rules, the result is not certain.

The order of the files does not solve this. Claude Code loads the file of the repository after the
global file, and Codex does the same. The file that is closer to the working directory comes later,
and later text has more weight. This is the opposite of what we want.

Two things reduce the risk:

1. `AGENTS.md` starts with a statement that the rules govern. This is an explicit instruction, and
   it is stronger than the position of the text. It works for Claude Code and for Codex.
2. `hooks/enforce-rules.sh` is a `PreToolUse` hook. It returns `deny` or `ask`. This is a real
   block. No instruction of a repository can remove it. Codex has no equal mechanism.

The hook blocks the installation of packages, and it escalates a commit and a push to the user.

The hook reads the text of the command, so it has limits. It splits a compound command at `;`, `&&`,
`||`, and `|`, and it tests each part alone. It also removes the quotes of a shell invoker, so it
sees the command inside `bash -c "..."`. It cannot see a command that is built at run time, as in
`P=pip; $P install x`. Treat the hook as a guard against a violation by mistake, not as a security
boundary.

If `jq` is absent, the hook uses `python3`. If both are absent, the hook allows the command, because
it cannot read the input.

The hook does not check that Python runs in the `super` environment. After `micromamba activate
super`, a bare `python` command is correct, and the hook cannot see the state of the shell. The
check gave a wrong result too often, so this rule stays a soft rule in `AGENTS.md`.

## Codex

Codex has no plugin system. It reads `AGENTS.md` from fixed paths, so it needs a link:

```
ln -s ~/codelore/AGENTS.md ~/.codex/AGENTS.md
```

Codex does not support an import. For this reason `AGENTS.md` holds the full text, and `CLAUDE.md`
only imports it. Do not turn this around.

## Cost

Each skill adds about 150 tokens to every session. The `description` in the frontmatter causes this
cost, because Claude Code must always know when to start the skill. Keep the description short, but
keep the words that start the skill. Look at the cost again when the plugin has more than about six
skills:

```
claude plugin details codelore
```

## Tests

`tests/test-hooks.sh` tests the decisions of both hooks, the format of the payload, and the
structure of each skill. The CI runs the same script. Run it after each change to a hook.

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
| `AGENTS.md` | The rules. This is the single source of truth for both agents. |
| `CLAUDE.md` | Imports `AGENTS.md` with `@AGENTS.md`, then adds the rules for work in this repository. |
| `hooks/emit-rules.sh` | Sends `AGENTS.md` into the context of every session. |
| `hooks/enforce-rules.sh` | Blocks the commands that must not run. |
| `skills/` | The skills. Both agents find them through their plugins. |
| `.claude-plugin/` | The Claude Code plugin and marketplace manifests. |
| `.codex-plugin/` | The Codex plugin manifest. |
| `.agents/plugins/` | The Codex marketplace manifest. |

`AGENTS.md` is the portable payload. The hook sends it to every repository on the machine. A rule
that applies only to this repository must go into `CLAUDE.md`, below the import. If you put such a
rule into `AGENTS.md`, it goes to all other repositories, where it has no meaning.

## Why plugins

Claude Code and Codex install a plugin one time for each machine. The plugin then applies in every
repository. This removes the manual copy and gives both agents the same skills and hooks.

The agents use different manifest formats. Claude Code reads `.claude-plugin/plugin.json` and
`.claude-plugin/marketplace.json`. Codex reads `.codex-plugin/plugin.json` and
`.agents/plugins/marketplace.json`. Both plugins use the shared `skills/` and `hooks/` directories.
Both manifests pin the plugin version. Bump the versions together for each release, because both
agents cache installed plugins by version. The tests check that the versions stay equal.

A plugin cannot supply a `CLAUDE.md`. It can supply a `SessionStart` hook. The hook returns the
rules as `additionalContext`, and Claude Code puts this text into the context window. This is the
only way for a plugin to give always-on rules.

The repository root is the plugin, and the repository is also its own marketplace. Both agents set
`${CLAUDE_PLUGIN_ROOT}` for plugin hooks, so the hook finds `AGENTS.md` at an exact path. Codex
sets `PLUGIN_ROOT` and also `CLAUDE_PLUGIN_ROOT` for compatibility. `hooks/emit-rules.sh` reads
either variable, and it falls back to its own location, because an empty variable would make it
read `/AGENTS.md`. If it finds no rules file, it writes a warning and exits 0. The session must
always start, but a broken install must not look the same as a working one. The
repository holds one plugin. If it must hold more than one plugin later, each plugin moves into
`plugins/<name>/`, and each marketplace source changes.

## Why a PreToolUse hook

Instructions are context, not configuration. The agents do not enforce them. If the instructions of
a repository disagree with the rules, the result is not certain.

The order of the files does not solve this. Claude Code loads the file of the repository after the
global file, and Codex does the same. The file that is closer to the working directory comes later,
and later text has more weight. This is the opposite of what we want.

Two things reduce the risk:

1. `AGENTS.md` starts with a statement that the rules govern. This makes the intended precedence
   explicit, but it is still an instruction and not a mechanical guarantee.
2. `hooks/enforce-rules.sh` is a `PreToolUse` hook. It returns `deny` for forbidden installs in
   both agents. For a commit or a push, it returns `ask` in Claude Code. Codex does not support
   `ask` from this hook, so the hook leaves Git approval to Codex's native sandbox and approval
   flow.

The hook blocks the installation of packages in both agents. It escalates a commit and a push to
the user in Claude Code. In Codex, the native sandbox protects `.git` and network access, so these
commands enter the normal approval flow. Bypassing the Codex sandbox also bypasses this approval;
the rule in `AGENTS.md` remains an instruction in that mode. The hook blocks every install verb it
knows, not only `install`: `pip install`, `python -m pip install`,
`uv add`, `uv sync`, `uv pip install`, `uv tool install`, and the `conda` and `micromamba` verbs
`install`, `create`, `update`, `upgrade`, and `env create`/`env update`. It reads `python -m pip`
in the attached form `-mpip` and inside a bundle of short options such as `-um pip`. Rules that the
hook does not cover remain instructions. A conflicting repository rule can still make their result
less certain.

The hook reads the text of the command, so it has limits. It tokenizes simple shell commands,
respects quoted text, ignores heredoc bodies, checks each part of a compound command, and skips
assignment and redirection prefixes before finding the executable. It inspects commands inside
shell invokers such as `bash -lc "..."` and inside runners such as
`micromamba run -n super ...`. It lists the options that take a value for each runner, so it can
find the nested command. An unknown option that takes a value shifts this position and hides the
nested command. Preview flags are checked after resolving a nested command. A `--help` or a
`--dry-run` counts only in an option position, so `git commit -m --help` stays a real commit. The
hook cannot see a command that is built at run time, as in
`P=pip; $P install x`. It also does not parse command substitutions or commands hidden behind other
programs. Treat the hook as a guard against a violation by mistake, not as a security boundary.

If `jq` is absent, the hook uses `python3`. If both are absent, the hook allows the command, because
it cannot read the input.

The hook does not check that Python runs in the `super` environment. After `micromamba activate
super`, a bare `python` command is correct, and the hook cannot see the state of the shell. The
check gave a wrong result too often, so this rule stays a soft rule in `AGENTS.md`.

## Codex

Codex reads the plugin from `.codex-plugin/plugin.json`. Its marketplace file is
`.agents/plugins/marketplace.json`. Install both from this repository:

```
codex plugin marketplace add anwai98/codelore
codex plugin add codelore@codelore
```

Codex does not support the `@AGENTS.md` import. The SessionStart hook gives it the global rules when
the plugin is active. Codex also reads the root `AGENTS.md` when it works in this repository. For
these reasons, `AGENTS.md` holds the full text, and `CLAUDE.md` only imports it. Do not turn this
around.

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

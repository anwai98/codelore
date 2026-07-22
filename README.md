# codelore

Shared rules and skills for coding agents. One repository, used by Claude Code and Codex.

`AGENTS.md` is the single source of truth for the rules. `CLAUDE.md` only imports it. Add new rules
to `AGENTS.md`, not to `CLAUDE.md`.

## Contents

- `AGENTS.md`: the rules for git, the environment, testing, code quality, and code style.
- `skills/simple-technical-english/`: a skill that writes all prose in Simplified Technical English.
- `hooks/`: a `SessionStart` hook. It puts the rules into the context of every session.

## Claude Code

The repository is a plugin and its own marketplace. Install it one time on each device:

```
/plugin marketplace add anwai98/codelore
/plugin install codelore@codelore
/reload-plugins
```

This gives you the skill and the rules in every repository on the device.

To check the install, run `/context` in a different repository. The rules must be present, and the
skill must show as `/codelore:simple-technical-english`.

## Codex

Codex has no plugin system. It reads `AGENTS.md` from fixed paths. Link this file into the Codex
home directory one time on each device:

```
ln -s ~/codelore/AGENTS.md ~/.codex/AGENTS.md
```

Codex also reads an `AGENTS.md` in the root of each repository. A repository file is added to the
global file, and the repository file has the higher priority.

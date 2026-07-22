# codelore

Shared rules and skills for coding agents. One repository, used by Claude Code and Codex.

`AGENTS.md` is the single source of truth for the rules. `CLAUDE.md` only imports it. Add new rules
to `AGENTS.md`, not to `CLAUDE.md`.

## Contents

- `AGENTS.md`: the rules for git, the environment, testing, code quality, and code style.
- `skills/simple-technical-english/`: a skill that writes all prose in Simplified Technical English.
- `hooks/`: hooks that load the rules and guard commands that need approval or must not run.
- `.claude-plugin/`: the Claude Code plugin and marketplace manifests.
- `.codex-plugin/` and `.agents/`: the Codex plugin and marketplace manifests.

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

The repository is also a Codex plugin and its own marketplace. Install it one time on each device:

```
codex plugin marketplace add anwai98/codelore
codex plugin add codelore@codelore
```

Start a new Codex session after the install. Open `/hooks`, review the Codelore hook definitions,
and trust them. Codex skips plugin hooks until you complete this review.

This gives you the skill, the rules, and the command guard in every repository on the device. Use
`codex plugin list` to check the install. Use `/skills` and `/hooks` in a new session to check the
loaded components.

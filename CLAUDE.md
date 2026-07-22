@AGENTS.md

## Working in this repository

The rules above are the portable payload. The hook sends them to every repository. Keep them
portable. Do not put a rule that applies only to this repository into `AGENTS.md`. Put it here.

- Run `tests/test-hooks.sh` after you change a hook, an agent instruction file, or a Codex manifest.
- Run `claude plugin validate . --strict` after you change a Claude Code manifest.
- Add a skill as `skills/<name>/SKILL.md`. The `name` in the frontmatter must be the same as the
  name of the directory.
- Keep the `description` of a skill to one sentence that tells what it does, and one sentence that
  tells when to use it. Each skill adds about 150 tokens to every session.
- See `docs/design.md` for the reason behind this structure.

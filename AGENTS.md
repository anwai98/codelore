# Coding agent rules

These rules are the global configuration of the user. They apply in every repository.

A repository can have its own instructions. Follow them where they agree with the rules below.
If an instruction of the repository disagrees with a rule below, the rule below governs.

## Git

- Never run `git commit` or `git push` without explicit permission from the user.

## Environment

- Never install packages using `pip install` or `micromamba install`. The environment is managed by the user.
- Always run Python commands inside the `super` conda environment: prefix with `micromamba run -n super` or activate first with `micromamba activate super`.

## Testing

- Always validate changes by running the actual scripts in `scripts/` with real data and real checkpoints where available. Do not use inline Python smoke tests.

## Code quality

- Always run `flake8 --max-line-length=120` on any code you add before considering the task done.
- Never modify `__init__.py` files unless explicitly asked to.
- When adding a `# noqa` comment, never include the error type: write `# noqa`, not `# noqa: E402`.

## Code style

- Keep code comments minimalistic: a comment should state what is needed and no more, not narrate a story. Prefer one short line explaining the non-obvious "why". Avoid multi-sentence explanations, background, alternatives considered, or restating what the code already says. If a comment runs to several lines, it is almost always too long - cut it down.
- No heavy section separator comments like `# ---------------------------------------------------------------------------`.
- No inline section labels like `# -- encoder --`.
- No excessive space-padding anywhere for visual column alignment: inline comments, docstring argument lists, dict entries, tuple/list elements, etc. Use single spaces throughout. Write `x = foo(x)  # (B, N, D)`, not `x = foo(x)     # (B, N, D)`; write `"key": value`, not `"key":    value`; write `x: (B, C, H, W)`, not `x:          (B, C, H, W)`.
- Never use the Unicode arrow `→`. Use `->` instead.
- Never use the em dash `—`. Use `-` instead.
- No double spaces after punctuation in prose (docstrings, comments, strings): write `CVPR 2026. https://...`, not `CVPR 2026.  https://...`.
- Never name module-level variables with a leading underscore.
- Don't embed leading whitespace in string literals for output indentation: write `print(f"Key: {value}")`, not `print(f"  Key: {value}")`.
- Always structure scripts with functions: put all logic in named functions, call them from `main()`, and guard execution with `if __name__ == "__main__": main()`.
- Never align continuation lines to the opening parenthesis. Always try to fit a call on one line first. Only wrap if it exceeds 120 chars. If it must wrap, use a single extra indent level with the closing paren on its own line:
  ```python
  # good
  x = fn(a, b, c)
  x = a + b + c + d
  x = fn(
      a, b, c, keyword=value
  )
  # bad
  x = fn(a, b, c,
         keyword=value)
  x = (a + b
       + c + d)
  ```
- This applies to `argparse` `add_argument` calls too. Always try the one-liner first: `parser.add_argument("--foo", default=x, help="...")`. Only expand to multiple lines if it does not fit in 120 chars. Never align continuation lines to the `add_argument(` opening paren.

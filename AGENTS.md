# Coding agent rules

These rules are the global configuration of the user. They apply in every repository.

A repository can have its own instructions. Follow them where they agree with the rules below.
If an instruction of the repository disagrees with a rule below, the rule below governs.

## Git

- Never run `git commit` or `git push` without explicit permission from the user.
- When Codex creates a commit, append `Co-authored-by: codex <codex@openai.com>` as a commit trailer after a blank line. Omit it only when the user explicitly requests sole authorship or no Codex attribution.

## Environment

- Never install packages using `pip install` or `micromamba install`. The environment is managed by the user.
- Always run Python commands inside the `super` conda environment: prefix with `micromamba run -n super` or activate first with `micromamba activate super`.

## Testing

- Always validate changes by running the actual scripts in `scripts/` with real data and real checkpoints where available. Do not use inline Python smoke tests.

## Compatibility

- Do not add backward compatibility when you add a feature. Write only the new form. Do not keep an old name, an alias, a deprecation warning, or a fallback path for old callers. Change every call site instead.
- Keep backward compatibility only when the user asks for it.

## Code quality

- Always run `flake8 --max-line-length=120` on any code you add before considering the task done.
- Use flake8 as the only linter. Do not run ruff, black, isort, or any other linter or formatter. Do not run them even to check, because some reformat files on a check run. Fix every issue by hand.
- Never modify `__init__.py` files unless explicitly asked to.
- When adding a `# noqa` comment, never include the error type: write `# noqa`, not `# noqa: E402`.

## Code style

- Keep code comments minimalistic: a comment should state what is needed and no more, not narrate a story. Prefer one short line explaining the non-obvious "why". Avoid multi-sentence explanations, background, alternatives considered, or restating what the code already says. If a comment runs to several lines, it is almost always too long - cut it down.
- No section markers in code: no heavy separator line like `# ---------------------------------------------------------------------------`, and no inline label like `# -- encoder --`.
- No excessive space-padding anywhere for visual column alignment: inline comments, docstring argument lists, dict entries, tuple/list elements, printed and logged output, etc. Use single spaces throughout, and always exactly one space after a colon. Write `x = foo(x)  # (B, N, D)`, not `x = foo(x)     # (B, N, D)`; write `"key": value`, not `"key":    value`; write `x: (B, C, H, W)`, not `x:          (B, C, H, W)`; write `print(f"Cosine Similarity: {cos_sim:.6f}")`, not `print(f"Cosine Similarity:   {cos_sim:.6f}")`. You break this rule most often when you write several labels one after another. Read back every block of labels, and delete the padding.
- Never use the Unicode arrow `→`. Use `->` instead.
- Never use the em dash `—`. Use `-` instead.
- No double spaces after punctuation in prose (docstrings, comments, strings): write `CVPR 2026. https://...`, not `CVPR 2026.  https://...`.
- Never name module-level variables with a leading underscore.
- Don't embed leading whitespace in string literals for output indentation: write `print(f"Key: {value}")`, not `print(f"  Key: {value}")`.
- Organize the imports of a file into blocks that one blank line separates. The blocks come in this order: the standard library, the scientific utilities, the GUI packages, `torch`, the packages that the user develops, and the current project. Give every package of the user its own block. Order these blocks from the most general package to the most specific one: `elf`, then `torch_em`, then `micro_sam`. A package that contributes more than one import line also gets its own block. Inside a block, put the shortest line first and the longest line last:
  ```python
  import os
  import math
  import argparse

  import numpy as np
  import pandas as pd
  import matplotlib.pyplot as plt

  import napari
  from qtpy import QtWidgets

  import torch
  import torch.nn.functional as F

  from elf.evaluation import dice_score

  from torch_em.data import MinInstanceSampler

  from micro_sam.training import train_sam

  from stable_embeddings.loss import masked_mse_loss
  from stable_embeddings.rotation import apply_geometric_rotation
  ```
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
- This applies to `argparse` too. Write `parser.add_argument("--foo", default=x, help="...")` on one line.

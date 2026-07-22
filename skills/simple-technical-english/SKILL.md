---
name: simple-technical-english
description: Write all prose in Simplified Technical English (ASD-STE100), adapted for code. Use whenever you write or edit code comments, docstrings, type/argument descriptions, error and log messages, CLI help text, README and documentation files, commit messages, PR descriptions, or any other explanatory text. Also use when asked to "simplify the wording", "clean up the docstrings", "make the comments clearer", or to review text for clarity.
---

# Simplified Technical English for code

Write every piece of prose so that a reader with limited English can understand it on the
first reading. The standard is ASD-STE100 (Simplified Technical English): 53 writing rules
and a restricted vocabulary, made for aircraft maintenance manuals. The rules below are
that standard, adapted to code.

Apply this to: docstrings, inline comments, error and warning messages, log messages,
CLI `help=` strings, tooltips, README and docs, commit messages, PR descriptions.

Do not apply this to: identifiers, API names, citations, quoted output, or text the user
supplies verbatim.

## The rules

### 1. Keep sentences short

- Instructions and procedures: 20 words maximum per sentence.
- Descriptive text: 25 words maximum per sentence.
- One idea per sentence. One instruction per sentence.

If a sentence needs a comma to hold two thoughts together, make it two sentences.

### 2. Keep paragraphs short

- One topic per paragraph. Six sentences maximum.
- A docstring starts with one summary sentence, then a blank line, then the details.
- Use a vertical list when you describe more than two items, conditions, or steps.

### 3. Use simple verb forms only

Allowed: infinitive, imperative, simple present, simple past, simple future, and the past
participle as an adjective.

Not allowed: progressive forms, perfect tenses, and stacked modals.

```
bad:  The embeddings are being computed, and will have been cached once this returns.
good: This function computes the embeddings. It caches them before it returns.

bad:  We might be able to reuse the decoder here.
good: You can reuse the decoder here.
```

An `-ing` word is allowed only as a technical noun or a noun modifier, for example
"tiling strategy" or "training data".

### 4. Use the active voice

- Instructions are always active and imperative: "Call `initialize()` before you segment."
- Descriptions are active by default. Use the passive only when the actor is unknown or
  does not matter.

```
bad:  The state is reset by the widget when a new image is selected.
good: The widget resets the state when the user selects a new image.
```

### 5. Do not leave out words

Short does not mean clipped. Keep articles, `that`, and relative pronouns. A comment is a
short complete sentence, not a telegram.

```
bad:  # cache empty, recompute
good: # The cache is empty, so we recompute the embeddings.

bad:  Returns dict maps id to mask.
good: Returns a dictionary that maps each object id to its mask.
```

### 6. Limit noun clusters to three words

Break a longer cluster with a preposition or a relative clause.

```
bad:  instance segmentation decoder checkpoint path
good: the path to the checkpoint of the instance segmentation decoder
```

### 7. One word, one meaning, one part of speech

- Do not use a noun as a verb. Write "Send a request to the server", not "Request the server".
- Do not give one word two meanings in the same codebase. If `mask` is the prompt, do not
  also call the output `mask`.
- Use the same term for the same thing every time. Do not use synonyms for variety.
  Pick "tile" or "block", then keep it.

### 8. Prefer the short, plain word

`use` not `utilize`. `start` not `initiate`. `about` not `approximately`. `to` not `in order to`.
See `references/word-choice.md` for the substitution table.

### 9. Write warnings and conditions first

Put the condition or the danger before the action, so the reader never acts too early.

```
bad:  Delete the cache after you make sure that no worker still reads it.
good: Make sure that no worker still reads the cache. Then delete the cache.
```

### 10. No idioms, no metaphors, no humor

Remove "under the hood", "out of the box", "magic", "kill the process", "a bit hacky",
"gotcha", "on the fly", "for free". State the mechanism instead.

```
bad:  # This is where the magic happens.
good: # This loop merges the masks of the overlapping tiles.
```

### 11. Define an abbreviation once

Write the full term the first time, with the abbreviation in parentheses: "automatic mask
generator (AMG)". Standard domain abbreviations such as SAM, GPU, or API need no expansion.

### 12. Be direct about requirements

Avoid `shall`, `should`, `may`, and `it is recommended`. Write "You must pass a decoder",
or "You can pass a decoder", or "Do not pass a decoder".

## Docstrings

Follow the docstring convention of the repository. Apply the rules above inside it.

```python
def segment_volume(volume, predictor, tile_shape=None):
    """Segment all objects in a 3D volume.

    The function segments each slice, then it merges the objects across the slices.
    You must precompute the image embeddings before you call this function.

    Args:
        volume: The input volume with the shape (Z, Y, X).
        predictor: The SAM predictor.
        tile_shape: The shape of the tiles. Use tiles if the slices are larger than 2048 pixels.

    Returns:
        The segmentation with the same shape as the input volume.
    """
```

Argument descriptions are noun phrases or short sentences. Start each one with "The",
not with the argument name.

## Comments

The house rule stays: a comment states what is needed and no more. Simplified Technical
English governs *how* you write the comment, not how much you write. A one line comment is
still the target, and it is now a readable one.

```
bad:  # Handle the weird case where the prompt might've been added already.
good: # Skip the prompt if this frame already has it.
```

## Error and log messages

- One sentence for the problem. One sentence for the fix.
- Name the actual value that failed.
- No blame, no exclamation marks.

```
bad:  raise ValueError("Invalid input!!! Something went wrong with the tile shape.")
good: raise ValueError(f"The tile shape {tile_shape} must have 2 entries. Pass a tuple of 2 integers.")
```

## Checklist before you finish

1. Is any sentence longer than 25 words?
2. Does any sentence contain two instructions?
3. Is there a progressive or perfect verb form?
4. Is there a passive sentence with a known actor?
5. Is there a noun cluster of four or more words?
6. Is one thing named in two ways?
7. Is there an idiom, a metaphor, or a joke?
8. Is there a long word where a short word works?

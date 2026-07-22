# Word choice

ASD-STE100 restricts the writer to about 900 approved words, each with one meaning and one
part of speech. That dictionary is built for aircraft maintenance, so it does not contain
the words this codebase needs. Use this rule instead:

> Technical terms are free. Everything around them uses the shortest common English word,
> and that word keeps one meaning across the whole project.

A technical term is a name for a thing in the domain or in the code: tensor, embedding,
tile, decoder, checkpoint, layer, widget, prompt. Keep those. Simplify the rest.

## Substitutions

| Do not write | Write |
| --- | --- |
| utilize, leverage, employ | use |
| initiate, commence | start |
| terminate, cease | stop, end |
| perform, execute, conduct | do, run |
| facilitate, enable (as prose) | let, allow |
| attempt | try |
| obtain, acquire, retrieve | get |
| provide, supply | give, pass |
| require | need |
| additional, supplementary | more, extra |
| approximately | about |
| sufficient | enough |
| prior to | before |
| subsequent to, following | after |
| in order to | to |
| due to the fact that, owing to | because |
| in the event that | if |
| in the case of | for |
| with respect to, with regard to | for, about |
| a number of, a variety of | some, several |
| the majority of | most |
| at this point in time | now |
| currently, presently | now (or delete it) |
| it is possible to | you can |
| it is necessary to | you must |
| it should be noted that | (delete it) |
| please note that | (delete it) |
| basically, essentially, simply, just | (delete it) |
| ensure | make sure that |
| verify | check |
| modify, alter | change |
| determine | find, decide |
| implement | write, add, build |
| functionality | function, feature |
| methodology | method |
| specify, designate | set, name |
| initialize (in prose) | set up |
| commence, proceed to | (delete it, use the verb) |
| in conjunction with | with |
| as well as | and |
| however (mid sentence) | but (or a new sentence) |
| thus, hence, therefore | so |
| e.g. | for example |
| i.e. | that is |
| etc. | (name the items, or write "and more") |
| via | with, through |

## Constructions to remove

| Do not write | Write |
| --- | --- |
| is being computed | is computed |
| has been cached | is cached, was cached |
| will have finished | finishes |
| might be able to | can |
| would need to be | needs |
| there is a check that | the code checks |
| this is done in order to | this does X so that |
| the reason is because | the reason is that |

## Idioms to remove

under the hood, out of the box, on the fly, for free, kill the process, a bit hacky,
gotcha, edge case magic, plumbing, glue code, boils down to, in a nutshell, at the end of
the day, take care of, deal with, play nicely with, breaks things, is a no-op (write "does
nothing").

## Words with two meanings

Give each of these one meaning per project, and write it down in the project glossary or
in `CLAUDE.md`:

- **mask**: the prompt, or the output? Pick one. Use `mask prompt` and `segmentation` for the other.
- **model**: the network, or the checkpoint? Use `checkpoint` for the file.
- **state**: the annotator singleton, or a state dictionary? Use `state dict` for the second.
- **image**: one 2D plane, or the full input? Use `slice`, `frame`, and `volume`.
- **run**: the verb, or one execution? Use `run` as the verb only.
- **set**: the verb, or the collection? Use `set` as the verb only.

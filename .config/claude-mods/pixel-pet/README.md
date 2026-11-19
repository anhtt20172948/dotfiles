# pixel-pet

A Claude Code mod in the local `dotfiles-mods` marketplace
([marketplace.json](../.claude-plugin/marketplace.json)). Install,
reload and test steps shared by every mod are in the
[dotfiles README](../../../README.md#claude-code-mods).

pixel-pet draws a chibi Saiyan above the prompt, with its name, what it is
doing, its form and power level, and the session's turn, tool and error counts
beside it. Two pixel rows share one text row (`▀`/`▄` with a foreground and a
background colour). The sprites are hand-drawn originals for personal use.

It draws the largest fighter the band has room for, and the band grows with
the terminal (a 40-row terminal gives it 14 rows):

| Band rows | The fighter |
| --- | --- |
| 10 or more, with 60 columns for it and its text | 24x20 pixels: shaded hair, a two-tone outfit, and a face for each mood (brows, eyes with a glint, mouth, blush, tears) |
| 6 or more | 16x12 pixels |
| 4 or 5 | its 16x8 head alone |
| fewer than 4 | none: it gives way |

The model in use picks the fighter and its effort level picks the form:

| Effort | Opus: Goku | Sonnet: Vegeta | Haiku or any other: kid Gohan |
| --- | --- | --- | --- |
| low | base form (black hair, no aura) | base form | base form |
| medium | Super Saiyan (gold hair, pale gold aura) | Super Saiyan | Super Saiyan |
| high | Super Saiyan 2 (aura with lightning sparks) | Super Saiyan 2 | Super Saiyan 2 |
| xhigh | Super Saiyan 3 (long hair) | Majin (the M mark) | Ultimate (white aura) |
| max | Ultra Instinct (silver) | Ultra Ego (purple) | Beast (silver, red eyes) |

A model that takes no effort stays in base form. Every model request of the main
conversation names its model and effort, so the fighter follows `/model`,
`/effort` and `/config` as they change: `/model <name>` and `/effort <level>`
show at once, a picker's choice or a `/config` change by the next request.
Before the session's first request the effort is read from the `effortLevel`
setting, so a `--effort` flag shows once the first prompt is sent.

| When | The fighter |
| --- | --- |
| idle | walks back and forth and blinks, a calm aura around the body |
| a turn or a tool runs | powers up, fists clenched, brows down and shouting, aura flaring, `running Bash...` |
| a turn ends | a thumbs up with a grin and a blush, `done!`, for 4 seconds |
| a tool fails or a turn is interrupted | knocked back with eyes squeezed shut and a tear, hair back to base for a moment, `Bash failed…` |
| idle for 3 minutes | meditates, eyes closed, `zZz` |

Vegeta scowls even at rest, and Super Saiyan 3 has no brows.

The power level grows with every finished turn and tool call, drops with every
error, and is multiplied by the form.

`/pet` hides or shows it. In `/config` (type `pet`), Pet name sets the name
shown (empty, the default, shows the fighter's own) and Character picks Goku,
Vegeta or Gohan whatever the model (`auto`, the default, follows the model).
Prompts and tools never wait on its updates. It gives way while a survey holds
the band, and under `NO_COLOR` it is drawn as a silhouette with its eyes cut out
and no aura. Its colours are picked to land near the 256-colour cube, so a
session in tmux, which Claude Code draws in 256 colours, looks nearly the same
as a truecolor terminal.

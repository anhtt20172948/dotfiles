# pixel-pet

A Claude Code mod in the local `dotfiles-mods` marketplace
([marketplace.json](../.claude-plugin/marketplace.json)). Install,
reload and test steps shared by every mod are in the
[dotfiles README](../../../README.md#claude-code-mods).

pixel-pet draws a chibi Saiyan above the prompt, with its name, what it is
doing, its form and power level, and the session's turn, tool and error counts
beside it. The sprites are hand-drawn originals for personal use.

Each text cell holds six pixels, two across and three down, drawn with one
sextant glyph (`🬀`-`🬻`, Unicode 13's Symbols for Legacy Computing) in a
foreground and a background colour: three times the pixels half blocks
(`▀`/`▄`, two a cell) fit in the same cells. A cell shows two colours at
most, so the faces are drawn to the cell grid: eyes, brows, mouths, blush and
tears never share a cell with a third colour, and the aura fills a cell beside
the fighter in one colour or not at all. Elsewhere a cell that mixes more keeps
the two colours that lose the least, an eye before the skin around it.

It draws the largest fighter the band has room for, and the band grows with
the terminal (a 40-row terminal gives it 14 rows):

| Band rows | The fighter (sextants; half blocks) |
| --- | --- |
| 10 or more, with 60 columns for it and its text | 24x10 cells, 48x30 pixels; 24x20: shaded hair, a two-tone outfit, and a face for each mood (brows, eyes with a glint, mouth, blush, tears) |
| 6 or more | 16x6 cells, 32x18 pixels; 16x12 |
| 4 or 5 | its head alone in 16x4 cells, 32x12 pixels; 16x8 |
| fewer than 4 | none: it gives way |

kitty draws the sextants itself, whatever its font, as it does box drawing and
blocks; another terminal needs a font that has them (`fc-list ':charset=1fb00'
family` lists the installed ones). Where they show as boxes or blanks, set
Render to `halfblock` in `/config` for the half-block fighter.

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
| a turn ends | fires its signature beam (below), then a thumbs up with a grin and a blush, `done!`, for 4 seconds |
| a tool fails or a turn is interrupted | knocked back with eyes squeezed shut and a tear, hair back to base for a moment, `Bash failed…` |
| idle for 3 minutes | meditates, eyes closed, `zZz` |

Vegeta scowls even at rest, and Super Saiyan 3 has no brows.

When a turn ends the fighter pushes both palms forward and fires its
signature beam, shouting it a syllable at a time:

| Fighter | Beam | Shout |
| --- | --- | --- |
| Goku | Kamehameha, blue | `Ka... me... ha... me... HA!!` |
| Vegeta | Final Flash, yellow | `Final... FLASH!!` |
| Gohan | Masenko, gold | `Ma... sen... KO!!` |

A ball of energy grows in its palms for a second, then the beam shoots right
and pushes the name, the shout and the counts along with it; after a moment
it cools, draws back and the text slides home, about 2.7 seconds in all (3.4 for a milestone). A
turn that lifts the power level past a milestone it had not reached (9,000,
then 100,000, 1,000,000 and every power of ten on) fires a thicker, longer
beam with a bigger ball, and `It's over 9000!!!` (or the milestone it
crossed) in place of the counts. A prompt or a tool call ends the beam at
once, and nothing waits on it.

The beam never takes the 36 columns kept for the text: it reaches at most 40
columns beside the large fighter and 24 beside the small one, shorter as the
band narrows. In a band with no room to spare only the ball glows in the
palms, and the head alone shouts without a beam. It is drawn as the fighter is, in sextants
or half blocks, and under `NO_COLOR` as plain glyphs.

The power level grows with every finished turn and tool call, drops with every
error, and is multiplied by the form.

`/pet` hides or shows it. In `/config` (type `pet`), Pet name sets the name
shown (empty, the default, shows the fighter's own), Character picks Goku,
Vegeta or Gohan whatever the model (`auto`, the default, follows the model),
Render draws it in sextants (the default) or half blocks, and Attacks
turns the beam off (on by default) for the plain thumbs up.
Prompts and tools never wait on its updates. It gives way while a survey holds
the band, and under `NO_COLOR` it is drawn as a silhouette with its eyes cut out
and no aura. Its colours are picked to land near the 256-colour cube, so a
session in tmux, which Claude Code draws in 256 colours, looks nearly the same
as a truecolor terminal.

# pixel-pet

A Claude Code mod in the local `dotfiles-mods` marketplace
([marketplace.json](../.claude-plugin/marketplace.json)). Install,
reload and test steps shared by every mod are in the
[dotfiles README](../../../README.md#claude-code-mods).

pixel-pet draws a pixel-art cat, four rows tall, above the
prompt, with its name, what it is doing and the session's turn, tool and error
counts beside it. Two pixel rows share one text row (`▀`/`▄` with a foreground
and a background colour).

| When | The cat |
| --- | --- |
| idle | walks back and forth and blinks |
| a turn or a tool runs | paws tap, `đang chạy Bash...` |
| a turn ends | closed eyes and blush, `xong rồi! ♥`, for 4 seconds |
| a tool fails or a turn is interrupted | a tear, `Bash lỗi rồi…` |
| idle for 3 minutes | sleeps, `zZz` |

`/pet` hides or shows it. Its name is the Pet name row of `/config` (type `pet`),
`Mochi` by default. Prompts and tools never wait on its updates. It gives way
while a survey holds the band or the band has fewer than four rows, and under
`NO_COLOR` it is drawn as a silhouette with its eyes cut out.

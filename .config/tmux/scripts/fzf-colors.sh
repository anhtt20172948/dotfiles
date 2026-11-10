#!/usr/bin/env bash
# fzf-colors.sh - the one fzf --color spec every picker under
# .config/tmux/scripts uses. Sourced, never executed; bash 3.2 clean.
#
# It names ANSI slots 0-15 and -1 (terminal default), never hex, so the pickers
# follow the terminal palette (kitty, and through it DMS), and bg:-1 lets kitty's
# opacity show through. The leading `16` makes the 16-colour scheme the base, so
# elements left unnamed (gutter, scrollbar, separator...) use terminal colours
# too instead of fzf's fixed 256-colour `dark` scheme.
#
# Slot contract (README "Colour consistency", enforced by
# tests/palette_consistency_test.sh): cyan (6) = DMS primary, the accent, so
# pointer/spinner/prompt/label; brightblack (8) is a surface and border tone,
# never text, so it fills the selected row (bg+) and draws the border; black (0)
# equals the background in DMS's palette, so it is never a selection surface;
# magenta (5) is a dark container tone in DMS's palette, so it is never text.
# Text: red (1) = match highlight, blue (4) = header, white (7) = info line,
# green (2) = multi-select marker.
#
# .config/fzf/fzfrc carries the same spec for shell fzf; the palette test keeps
# the two identical.

# shellcheck disable=SC2034 # used by the scripts that source this file
PICKER_FZF_COLORS='16,bg:-1,bg+:8,fg:-1,fg+:-1,hl:1,hl+:1,header:4,info:7,pointer:6,spinner:6,marker:2,prompt:6,label:6,border:8'

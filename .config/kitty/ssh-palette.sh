#!/bin/sh
set -eu

config=${XDG_CONFIG_HOME:-$HOME/.config}/kitty
for name in dank-theme.conf current-theme.conf; do
    palette=$config/$name
    if [ -f "$palette" ] && [ -r "$palette" ]; then
        # Quote the source for kitty's shlex parser; resolve directory/file links.
        quoted=$(printf '%s' "$palette" | sed 's/\\/\\\\/g; s/"/\\"/g')
        printf 'copy --symlink-strategy=resolve --dest=.config/kitty/remote-palette.conf "%s"\n' "$quoted"
        exit 0
    fi
done
printf 'kitty ssh: no readable palette in %s\n' "$config" >&2
exit 1

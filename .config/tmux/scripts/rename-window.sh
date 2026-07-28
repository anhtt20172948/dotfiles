#!/usr/bin/env bash
cur="${1:-$(tmux display-message -p "#W")}"

printf "󰆍 Rename '%s' to: " "$cur"
input=""
while IFS= read -r -s -n 1 ch; do
    case "$ch" in
        $'\e')
            exit 0
            ;;
        $'\n'|$'\r'|'')
            echo
            break
            ;;
        $'\177'|$'\b')
            input="${input%?}"
            printf "\b \b"
            ;;
        $'\004')
            exit 0
            ;;
        *)
            input="$input$ch"
            printf "%s" "$ch"
            ;;
    esac
done

[ -n "$input" ] && tmux rename-window -- "$input"

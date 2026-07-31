#!/usr/bin/env bash
cur="${1:-$(tmux display-message -p "#W")}"

printf "󰆍 Rename '%s' to: " "$cur"
input=""
while IFS= read -r -s -n 1 ch; do
    case "$ch" in
        $'\e')
            # Escape sequence: could be a bare Esc (cancel) or the start of an
            # arrow/function key (\e[A etc). Drain the rest of the sequence with
            # a zero timeout — without this, any arrow key aborted the rename.
            rest=""
            while IFS= read -r -s -n 1 -t 0.01 more; do
                rest+="$more"
            done
            [[ -z "$rest" ]] && { echo; exit 0; }   # bare Esc → cancel
            ;;                                       # otherwise ignore the key
        $'\n'|$'\r'|'')
            echo
            break
            ;;
        $'\177'|$'\b')
            # Only emit the erase sequence when there is something to erase,
            # otherwise repeated backspace chewed through the prompt text.
            if [[ -n "$input" ]]; then
                input="${input%?}"
                printf "\b \b"
            fi
            ;;
        $'\004')
            echo
            exit 0
            ;;
        *)
            input="$input$ch"
            printf "%s" "$ch"
            ;;
    esac
done

[ -n "$input" ] && tmux rename-window -- "$input"

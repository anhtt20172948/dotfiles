# dotfiles

## Installation

To install the dotfiles using `stow`, follow these steps:

1. Clone the repository to your home directory:
    ```bash
    git clone https://github.com/yourusername/dotfiles.git ~/dotfiles
    ```

2. Navigate to the dotfiles directory:
    ```bash
    cd ~/dotfiles
    ```

3. Use `stow` to create symlinks for the desired configuration files
   ``` bash
   stow --adopt .
   ```

## Remote helper scripts

`.local/bin/show` and `.local/bin/download` search a list of SSH hosts in
parallel for a given path, then open it or copy it down. They live in
`.local/bin` so `stow` puts them on `$PATH`.

```bash
show     /home/user/project/report.pdf          # sshfs-mount + xdg-open
download /home/user/project/data.csv            # rsync into ./data.csv
download /home/user/project/dir ./local-dir     # explicit destination
```

Both read their host list from `.config/remote-hosts` (one host per line, `#`
comments allowed). Host names must be resolvable by ssh — normally a `Host`
entry in `~/.ssh/config`. Every enabled host costs one parallel ssh probe per
lookup, so keep the list to what you actually use.

If a path exists on several hosts, both scripts prompt for a choice. Piping
works too: `echo 1 | download /path`.

`show` mounts the remote root under `/tmp/mnt_show_<host>` and schedules an
unmount 10 minutes later. To unmount early:

```bash
fusermount3 -u /tmp/mnt_show_<host>
```

Unmount failures are appended to `${TMPDIR:-/tmp}/show-unmount.log`.

## Other scripts

- `install_linux_x86_64.sh` — fetch pinned release binaries into `~/.local/bin`
- `install_zsh.sh` — build ncurses + zsh from source into `~/.local`
- `install_neovim.sh` — build Neovim from source (run with `bash`, or `chmod +x`)
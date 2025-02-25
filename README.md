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
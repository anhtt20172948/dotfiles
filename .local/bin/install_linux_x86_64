#!/usr/bin/env bash
set -euo pipefail

# Versions / tags and derived filenames
LAZYGIT_VER="0.48.0"
LAZYGIT_TAG="v${LAZYGIT_VER}"
LAZYGIT_ASSET="lazygit_${LAZYGIT_VER}_Linux_x86_64.tar.gz"

RIPGREP_VER="14.1.1"
RIPGREP_ASSET="ripgrep-${RIPGREP_VER}-x86_64-unknown-linux-musl.tar.gz"
RIPGREP_DIR="ripgrep-${RIPGREP_VER}-x86_64-unknown-linux-musl"

FD_VER="10.3.0"
FD_TAG="v${FD_VER}"
FD_ASSET="fd-${FD_TAG}-x86_64-unknown-linux-musl.tar.gz"
FD_DIR="fd-${FD_TAG}-x86_64-unknown-linux-musl"

YAZI_TAG="nightly"
YAZI_ASSET="yazi-x86_64-unknown-linux-musl.zip"
YAZI_DIR="yazi-x86_64-unknown-linux-musl"

FZF_VERSION="0.67.0"
FZF_TAG="v${FZF_VERSION}"
FZF_ASSET="fzf-${FZF_VERSION}-linux_amd64.tar.gz"


mkdir -p ~/.local/bin
cd ~/.local/bin

# Lazy git
wget "https://github.com/jesseduffield/lazygit/releases/download/${LAZYGIT_TAG}/${LAZYGIT_ASSET}"
tar -xvf "${LAZYGIT_ASSET}"
rm -f "${LAZYGIT_ASSET}"

# Ripgrep
wget "https://github.com/BurntSushi/ripgrep/releases/download/${RIPGREP_VER}/${RIPGREP_ASSET}"
tar -xvzf "${RIPGREP_ASSET}"
ln -s "${RIPGREP_DIR}/rg" .
rm -f "${RIPGREP_ASSET}"

# FD
wget "https://github.com/sharkdp/fd/releases/download/${FD_TAG}/${FD_ASSET}"
tar -xvf "${FD_ASSET}"
cp "${FD_DIR}/fd" .
rm -rf "${FD_DIR}" "${FD_ASSET}"

# yazi
wget "https://github.com/sxyazi/yazi/releases/download/${YAZI_TAG}/${YAZI_ASSET}"
unzip "${YAZI_ASSET}"
mv "${YAZI_DIR}/ya" .
mv "${YAZI_DIR}/yazi" .
rm -rf "${YAZI_DIR}" "${YAZI_ASSET}"

# fzf
wget https://github.com/junegunn/fzf/releases/download/${FZF_TAG}/${FZF_ASSET}
tar -xvzf ${FZF_ASSET}
rm -f ${FZF_ASSET}

# eza
EZA_VER="0.23.4"
EZA_TAG="v${EZA_VER}"
EZA_ASSET="eza_x86_64-unknown-linux-musl.tar.gz"
EZA_DIR="eza-${EZA_VER}-x86_64-unknown-linux-musl"
wget https://github.com/eza-community/eza/releases/download/${EZA_TAG}/${EZA_ASSET}
tar -xvzf ${EZA_ASSET}
rm -rf ${EZA_DIR} ${EZA_ASSET}

# intstall btop
BTOP_VER="1.4.5"
BTOP_TAG="v${BTOP_VER}"
BTOP_ASSET="btop-x86_64-linux-musl.tbz"
BTOP_DIR="btop"
wget https://github.com/aristocratos/btop/releases/download/${BTOP_TAG}/${BTOP_ASSET}
tar -xvf ${BTOP_ASSET}
mv ${BTOP_DIR} btop_install
rm -f ${BTOP_ASSET}
ln -s btop_install/bin/btop .

# Install zoxide
ZOXIDE_VER="0.9.8"
ZOXIDE_ASSET="zoxide-$ZOXIDE_VER-x86_64-unknown-linux-musl.tar.gz"
ZOXIDE_DIR="zoxide-$ZOXIDE_VER-x86_64-unknown-linux-musl"
ZOXIDE_TAG="v$ZOXIDE_VER"
wget https://github.com/ajeetdsouza/zoxide/releases/download/${ZOXIDE_TAG}/${ZOXIDE_ASSET}
tar -xvf ${ZOXIDE_ASSET}
rm -rf ${ZOXIDE_DIR} ${ZOXIDE_ASSET}

# install atuin
ATUIN_VER="18.10.0"
ATUIN_TAG="v${ATUIN_VER}"
ATUIN_ASSET="atuin-x86_64-unknown-linux-musl.tar.gz"
ATUIN_DIR="atuin-x86_64-unknown-linux-musl"
wget https://github.com/atuinsh/atuin/releases/download/${ATUIN_TAG}/${ATUIN_ASSET}
tar -xvf ${ATUIN_ASSET}
mv ${ATUIN_DIR}/atuin .
rm -f ${ATUIN_ASSET}
rm -rf ${ATUIN_DIR}
./atuin import auto

# install neovim
NVIM_VER="0.11.5"
NVIM_TAG="v${NVIM_VER}"
wget https://github.com/neovim/neovim-releases/releases/download/${NVIM_TAG}/nvim-linux-x86_64.tar.gz -O nvim-linux64.tar.gz
tar -xvzf nvim-linux64.tar.gz
ln -s nvim-linux-x86_64/bin/nvim nvim
rm -f nvim-linux64.tar.gz

# install sesh
SESH_VER="2.19.0"
SESH_TAG="v${SESH_VER}"
wget https://github.com/joshmedeski/sesh/releases/download/$SESH_TAG/sesh_Linux_x86_64.tar.gz
tar -xvzf sesh_Linux_x86_64.tar.gz
rm -f sesh_Linux_x86_64.tar.gz

# install gum
GUM_VER="0.17.0"
GUM_TAG="v${GUM_VER}"
GUM_ASSET="gum_${GUM_VER}_Linux_x86_64.tar.gz"
GUM_DIR="gum_${GUM_VER}_Linux_x86_64"
wget https://github.com/charmbracelet/gum/releases/download/$GUM_TAG/$GUM_ASSET
tar -xvzf gum_${GUM_VER}_Linux_x86_64.tar.gz
rm -f gum_${GUM_VER}_Linux_x86_64.tar.gz
ln -s $GUM_DIR/gum .

cat >> ~/.bashrc << 'EOF'
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}
eval "$(zoxide init --cmd cd bash)"
alias vi="nvim"

# eza
alias ls="eza --grid --color=always --long --git --icons --all --no-permissions --no-user --no-time --no-filesize"
alias lla="eza --color=always --long --git --icons --all --octal-permissions"
EOF

echo "export PATH=$HOME/.local/bin:$PATH" >> ~/.bashrc
source ~/.bashrc   

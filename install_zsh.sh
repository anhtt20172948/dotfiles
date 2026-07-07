et -e

# Tự động dọn dẹp nếu script bị lỗi giữa chừng
trap 'echo "Có lỗi xảy ra. Đang dọn dẹp..."; rm -rf ncurses-6.5* zsh*;' ERR

# Tạo cấu trúc thư mục .local tiêu chuẩn
mkdir -p "$HOME/.local/bin" "$HOME/.local/include" "$HOME/.local/lib" "$HOME/.local/lib/pkgconfig"

# Thiết lập các cờ môi trường tối ưu cho .local
export CXXFLAGS="-fPIC" 
export CFLAGS="-fPIC" 
export CPPFLAGS="-I${HOME}/.local/include" 
export LDFLAGS="-L${HOME}/.local/lib"
export PKG_CONFIG_PATH="$HOME/.local/lib/pkgconfig:$PKG_CONFIG_PATH"
export PATH="$HOME/.local/bin:$PATH"

# Số core CPU để tăng tốc biên dịch
NUM_CORES=$(nproc 2>/dev/null || echo 2)

# ==========================================
# 1. CÀI ĐẶT NCURSES (Có thêm hỗ trợ pkg-config)
# ==========================================
echo "--- Đang tải và cài đặt ncurses vào ~/.local ---"
wget -q --show-progress https://ftp.gnu.org/pub/gnu/ncurses/ncurses-6.5.tar.gz
tar -xzvf ncurses-6.5.tar.gz
cd ncurses-6.5

./configure --prefix="$HOME/.local" \
	            --enable-shared \
		                --with-shared \
				            --enable-pc-files \
					                --with-pkg-config-libdir="$HOME/.local/lib/pkgconfig" \
							            --enable-widec # Bật hỗ trợ ký tự UTF-8 ký tự đặc biệt

make -j"$NUM_CORES"
make install

# Tạo bản symlink từ libncursesw (wide) sang libncurses tiêu chuẩn để Zsh dễ nhận diện
cd "$HOME/.local/lib"
ln -sf libncursesw.so libncurses.so
ln -sf libncursesw.a libncurses.a

cd - && cd .. && rm -rf ncurses-6.5.tar.gz ncurses-6.5

# ==========================================
# 2. CÀI ĐẶT ZSH (Bổ sung cờ định vị thư viện chuyên sâu)
# ==========================================
echo "--- Đang tải và cài đặt zsh vào ~/.local ---"
wget -q --show-progress -O zsh.tar.xz https://sourceforge.net/projects/zsh/files/latest/download
mkdir -p zsh_src
tar -xJf zsh.tar.xz -C zsh_src --strip-components 1
cd zsh_src

# Chỉ định tường minh đường dẫn ncurses thông qua các cờ mở rộng
./configure --prefix="$HOME/.local" \
	            --enable-multibyte \
		                --with-term-lib="ncurses" \
				            CPPFLAGS="-I${HOME}/.local/include -I${HOME}/.local/include/ncursesw -I${HOME}/.local/include/ncurses" \
					                LDFLAGS="-L${HOME}/.local/lib"

make -j"$NUM_CORES"
make install
cd .. && rm -rf zsh.tar.xz zsh_src

# ==========================================
# 3. CẤU HÌNH KHỞI ĐỘNG (BASH TO ZSH)
# ==========================================
echo "--- Cấu hình chuyển đổi Shell tự động ---"

if ! grep -q "exec ~/.local/bin/zsh" ~/.bash_profile 2>/dev/null; then
	    cat << 'EOF' >> ~/.bash_profile

# Tự động nạp thư mục .local/bin vào PATH nếu chưa có
if [ -d "$HOME/.local/bin" ] ; then
    PATH="$HOME/.local/bin:$PATH"
fi

# Tự động chuyển sang ZSH cài ở .local
if [ -f ~/.local/bin/zsh ]; then
    export SHELL=$HOME/.local/bin/zsh
    exec $HOME/.local/bin/zsh -l
fi
EOF
    echo "Đã thêm cấu hình Zsh vào ~/.bash_profile"
else
	    echo "Cấu hình Zsh đã tồn tại trong ~/.bash_profile từ trước."
fi

echo "--- HOÀN THÀNH ---"
echo "Hãy chạy lệnh: source ~/.bash_profile"

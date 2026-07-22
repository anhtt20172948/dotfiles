#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# Configuration & Helper Functions
###############################################################################

REPO_URL="https://github.com/neovim/neovim.git"
PREFIX="${HOME}/.local"
SRC_DIR="${HOME}/src"
BUILD_DIR="${SRC_DIR}/neovim"
NVIM_BIN="${PREFIX}/bin/nvim"
JOBS=$(nproc)

# Hàm kiểm tra version Neovim hiện tại trên máy
# Hàm kiểm tra version Neovim hiện tại trên máy
get_installed_version() {
    local timeline_bin=""
    
    if command -v "$NVIM_BIN" >/dev/null 2>&1; then
        timeline_bin="$NVIM_BIN"
    elif command -v nvim >/dev/null 2>&1; then
        timeline_bin="$(command -v nvim)"
    else
        echo "Chưa cài đặt"
        return
    fi
    
    # Lấy dòng đầu tiên chứa thông tin version
    "$timeline_bin" --version | head -n 1
}

# Hàm lấy danh sách Tag chính thức từ Git Remote
get_remote_tags() {
    local limit="${1:-10}"
    git ls-remote --tags --refs "${REPO_URL}" \
        | awk -F'/' '{print $3}' \
        | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
        | sort -V -r \
        | head -n "${limit}"
}

# Hàm hiển thị Trợ giúp
usage() {
    echo "Sử dụng:"
    echo "  $0                  : Hiển thị version hiện tại & menu chọn phiên bản để cài"
    echo "  $0 [NVIM_VERSION]   : Cài đặt trực tiếp phiên bản chỉ định (VD: v0.10.0, stable, master)"
    echo "  $0 -h | --help      : Xem hướng dẫn này"
    exit 0
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
fi

###############################################################################
# Interactive Version Selection (Chọn Version trước)
###############################################################################

# Lấy thông tin bản hiện tại
CURRENT_NVIM=$(get_installed_version)

NVIM_VERSION="${1:-}"

# Nếu người dùng KHÔNG truyền tham số, bật menu tương tác
if [ -z "${NVIM_VERSION}" ]; then
    echo "=========================================="
    echo "📌 Version hiện tại trên máy: ${CURRENT_NVIM}"
    echo "=========================================="
    echo "==> Đang tải danh sách phiên bản mới nhất từ GitHub..."
    echo
    
    # Lấy 10 tag mới nhất vào array
    mapfile -t TAGS < <(get_remote_tags 10)
    
    # Thêm các nhánh phổ biến vào menu
    OPTIONS=("${TAGS[@]}" "stable" "master" "Nhập phiên bản khác...")

    echo "=========================================="
    echo "    CHỌN PHIÊN BẢN NEOVIM Muốn CÀI ĐẶT    "
    echo "=========================================="
    
    for i in "${!OPTIONS[@]}"; do
        printf "  [%2d] %s\n" "$((i+1))" "${OPTIONS[$i]}"
    done
    echo "=========================================="

    # Vòng lặp yêu cầu người dùng chọn số hợp lệ
    while true; do
        read -rp "Nhập lựa chọn của bạn [1-${#OPTIONS[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#OPTIONS[@]}" ]; then
            SELECTED_OPTION="${OPTIONS[$((choice-1))]}"
            break
        else
            echo "❌ Lựa chọn không hợp lệ. Vui lòng thử lại!"
        fi
    done

    # Xử lý nếu người dùng chọn nhập thủ công
    if [ "${SELECTED_OPTION}" == "Nhập phiên bản khác..." ]; then
        read -rp "Nhập Git Version/Tag/Branch bạn muốn (VD: v0.9.5): " NVIM_VERSION
    else
        NVIM_VERSION="${SELECTED_OPTION}"
    fi
fi

echo
echo "📌 Phiên bản hiện tại : ${CURRENT_NVIM}"
echo "🎯 Phiên bản sẽ cài   : ${NVIM_VERSION}"
read -rp "Xác nhận bắt đầu Clone và Cài đặt? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "❌ Đã hủy quá trình cài đặt."
    exit 0
fi

###############################################################################
# Clone & Checkout
###############################################################################

mkdir -p "${SRC_DIR}"

if [ ! -d "${BUILD_DIR}" ]; then
    echo "==> Đang clone Neovim repository..."
    git clone "${REPO_URL}" "${BUILD_DIR}"
fi

cd "${BUILD_DIR}"

echo "==> Đang cập nhật tags từ Git..."
git fetch --tags --quiet

# Kiểm tra xem Version có tồn tại trong Git không
if ! git rev-parse --verify --quiet "${NVIM_VERSION}^{commit}" >/dev/null; then
    echo "❌ LỖI: Version/Tag/Branch '${NVIM_VERSION}' KHÔNG tồn tại trên Git!"
    exit 1
fi

echo "==> Đang chuyển sang version: ${NVIM_VERSION}"
git checkout "${NVIM_VERSION}"

###############################################################################
# Environment
###############################################################################

mkdir -p "${PREFIX}"

export PATH="${PREFIX}/bin:${PATH}"
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/share/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="${PREFIX}/lib:${LD_LIBRARY_PATH:-}"
export CMAKE_PREFIX_PATH="${PREFIX}:${CMAKE_PREFIX_PATH:-}"

###############################################################################
# Clean & Build Dependencies
###############################################################################

echo "==> Đang dọn dẹp các bản build cũ..."
make distclean || true
rm -rf .deps build

echo "==> Đang biên dịch dependencies..."
make deps \
    CMAKE_BUILD_TYPE=Release \
    CMAKE_INSTALL_PREFIX="${PREFIX}" \
    DEPS_CMAKE_FLAGS="-DCMAKE_INSTALL_PREFIX=${PREFIX}" \
    -j${JOBS}

###############################################################################
# Build & Install Neovim
###############################################################################

echo "==> Đang biên dịch Neovim..."
make \
    CMAKE_BUILD_TYPE=Release \
    CMAKE_INSTALL_PREFIX="${PREFIX}" \
    DEPS_CMAKE_FLAGS="-DCMAKE_INSTALL_PREFIX=${PREFIX}" \
    -j${JOBS}

echo "==> Đang cài đặt vào ${PREFIX}..."
make install

###############################################################################
# Update PATH in Shell RC
###############################################################################

mkdir -p "${HOME}/.local/bin"

if ! grep -q '.local/bin' "${HOME}/.zshrc" 2>/dev/null; then
cat <<EOF >> "${HOME}/.zshrc"

export PATH="\$HOME/.local/bin:\$PATH"
export LD_LIBRARY_PATH="\$HOME/.local/lib:\$LD_LIBRARY_PATH"
export PKG_CONFIG_PATH="\$HOME/.local/lib/pkgconfig:\$PKG_CONFIG_PATH"

EOF
fi

###############################################################################
# Done
###############################################################################

echo
echo "✅ Hoàn tất cài đặt Neovim [${NVIM_VERSION}]:"
echo "--------------------------------------"
"${HOME}/.local/bin/nvim" --version | head -5
echo "--------------------------------------"

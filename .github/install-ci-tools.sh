#!/usr/bin/env bash
# Install pinned release binaries from .github/ci-tools.txt into BIN_DIR.
#
#   .github/install-ci-tools.sh BIN_DIR TOOL...
#
# Each download is checked against its sha256 before it is unpacked; BIN_DIR
# gets a symlink per tool (Neovim finds its runtime through the link).
# Runs under the stock macOS /bin/bash 3.2 as well as on Linux.
set -euo pipefail

[[ $# -ge 2 ]] || {
	echo "usage: $0 BIN_DIR TOOL..." >&2
	exit 2
}
BIN_DIR=$1
shift
MANIFEST="$(cd "$(dirname "$0")" && pwd)/ci-tools.txt"

case "$(uname -s)-$(uname -m)" in
Linux-x86_64) PLATFORM=linux-x64 ;;
Darwin-arm64) PLATFORM=macos-arm64 ;;
*)
	echo "unsupported platform: $(uname -s)-$(uname -m)" >&2
	exit 1
	;;
esac

sha256_of() {
	if command -v sha256sum >/dev/null; then
		sha256sum "$1" | cut -d' ' -f1
	else
		shasum -a 256 "$1" | cut -d' ' -f1
	fi
}

# {tag} is the release tag, {version} the tag without its leading "v".
expand() {
	local s=$1 tag=$2
	s=${s//\{tag\}/$tag}
	printf '%s\n' "${s//\{version\}/${tag#v}}"
}

install_tool() {
	local want=$1 tool platform repo tag sha asset bin found=0
	while read -r tool platform repo tag sha asset bin; do
		[[ "$tool" == "$want" && "$platform" == "$PLATFORM" ]] || continue
		found=1
		break
	done < <(grep -v '^#' "$MANIFEST")
	if [[ $found -eq 0 ]]; then
		echo "$want: no $PLATFORM entry in $MANIFEST" >&2
		return 1
	fi
	asset=$(expand "$asset" "$tag")
	bin=$(expand "$bin" "$tag")

	local dir="$BIN_DIR/.pkg/$tool" file
	rm -rf "$dir"
	mkdir -p "$dir"
	file="$dir/$asset"
	curl -fsSL --retry 3 "https://github.com/$repo/releases/download/$tag/$asset" -o "$file"
	local got
	got=$(sha256_of "$file")
	if [[ "$got" != "$sha" ]]; then
		echo "$tool $tag: sha256 mismatch for $asset (got $got, want $sha)" >&2
		return 1
	fi
	case "$asset" in
	*.tar.gz | *.tar.xz) tar -xf "$file" -C "$dir" ;;
	*.zip) unzip -q "$file" -d "$dir" ;;
	*.gz) gunzip -c "$file" >"$dir/$bin" ;;
	# A bare executable (ttyd.x86_64): the bin column is its name.
	*.x86_64) mv "$file" "$dir/$bin" ;;
	*)
		echo "$tool: unknown archive type: $asset" >&2
		return 1
		;;
	esac
	rm -f "$file"
	chmod +x "$dir/$bin"
	ln -sf "$dir/$bin" "$BIN_DIR/$(basename "$bin")"
	echo "$tool $tag ($PLATFORM) -> $BIN_DIR/$(basename "$bin")"
}

mkdir -p "$BIN_DIR"
BIN_DIR=$(cd "$BIN_DIR" && pwd)
for t in "$@"; do
	install_tool "$t"
done

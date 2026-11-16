#!/bin/sh
# Executed inside the container, with the pinned header manifest on stdin.
set -eu
name=$1 tag=$2 major=$3 version=$4
executable=$(readlink -f "$HOME/.local/bin/$name" 2>/dev/null) || executable=''
case $name:$executable in
    clangd:"$HOME"/.local/opt/clangd-"$tag".*/clangd/data/bin/clangd) ;;
    clang-tidy:"$HOME"/.local/opt/clang-tidy-"$tag".*/bin/clang-tidy) ;;
    *) printf 'resource header audit skipped (unmanaged or different version)'; exit 0 ;;
esac
include=${executable%/bin/*}/lib/clang/$major/include
[ -d "$include" ] || { printf 'Missing resource directory: %s\n' "$include" >&2; exit 1; }

compiler_roots() {
    for compiler in c++ g++ cc gcc clang++ clang; do
        command -v "$compiler" >/dev/null 2>&1 || continue
        for option in -print-file-name=include -print-resource-dir; do
            root=$("$compiler" "$option" 2>/dev/null) || continue
            [ "$option" != -print-resource-dir ] || root=$root/include
            case $root in /*) ;; *) continue ;; esac
            [ ! -d "$root" ] || printf '%s\n' "$root"
        done
    done
}

copy_header() {
    source=$1 relative=$2
    destination=$include/$relative
    # Preserve upstream headers, including symlinks, rather than mixing versions.
    [ ! -e "$destination" ] && [ ! -L "$destination" ] || return 0
    mkdir -p "${destination%/*}"
    temporary=$(mktemp "${destination%/*}/.header.XXXXXXXX")
    trap 'rm -f "$temporary"' EXIT
    cp "$source" "$temporary"
    mv "$temporary" "$destination"
    trap - EXIT
}

supply_runtime_headers() {
    root=$1
    for relative in omp.h omp-tools.h ompt.h ompt-multiplex.h ompx.h \
                    openacc.h acc_prof.h ISO_Fortran_binding.h; do
        [ ! -f "$root/$relative" ] || copy_header "$root/$relative" "$relative"
    done
    for family in sanitizer xray fuzzer profile orc orc_rt; do
        [ -d "$root/$family" ] || continue
        files=$(find -L "$root/$family" -type f -print)
        while IFS= read -r source; do
            [ -n "$source" ] || continue
            copy_header "$source" "${source#"$root/"}"
        done <<EOF
$files
EOF
    done
}

# Only runtime API families are borrowed; GCC intrinsic/builtin headers stay hidden.
roots=$(compiler_roots)
while IFS= read -r root; do
    [ -z "$root" ] || supply_runtime_headers "$root"
done <<EOF
$roots
EOF

missing=''
while IFS= read -r relative || [ -n "$relative" ]; do
    case $relative in ''|'#'*) continue ;; esac
    if [ ! -f "$include/$relative" ]; then
        missing=${missing:+$missing, }$relative
    fi
done
if [ -n "$missing" ]; then
    printf 'missing resource headers (LLVM %s): %s' "$version" "$missing"
else
    printf 'resource headers complete (LLVM %s manifest)' "$version"
fi

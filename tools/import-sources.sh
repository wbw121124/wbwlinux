#!/usr/bin/env bash
# Download all LFS 13.0 source tarballs + patches into tools/x86_64/sources/
# for committing into the repository (so GitHub Actions jobs skip the slow
# linuxfromscratch.org downloads). Run on a machine with good connectivity:
#     bash tools/import-sources.sh
# The linux kernel tarball (147 MB, > GitHub 100 MB single-file limit) is NOT
# bundled; it is downloaded at build time from kernel.org instead.
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="tools/x86_64/sources"
mkdir -p "$DEST"
cd "$DEST"

EXCLUDE="linux-6.18.10.tar.xz"

download() {
    local url="$1" f="${1##*/}"
    [ "$f" = "$EXCLUDE" ] && return 0
    if [ -s "$f" ]; then
        echo "skip  $f"
        return 0
    fi
    echo "get   $f"
    curl -fsSL --retry 3 --connect-timeout 30 --max-time 600 -o "$f" "$url"
}

export -f download 2>/dev/null || true

# parallel downloads: GNU mirrors are fast in CN via tuna mirror
grep -v "$EXCLUDE" ../wget-list | xargs -P 8 -I{} bash -c 'download "$@"' _ {}

echo "==> verifying md5sums"
md5sum -c ../md5sums

echo "==> done: $(ls | wc -l) files, $(du -sh . | cut -f1)"

#!/usr/bin/env bash
# 01 - Host preparation: install host prerequisites, create directory layout,
#     download and verify all LFS source tarballs.

set -euo pipefail
# re-exec as root if needed (GitHub hosted runners are non-root users)
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E bash "$0" "$@"
fi

cd "$(dirname "$0")"
source env.sh
source common.sh

[ "$(id -u)" -eq 0 ] || die "must run as root"

log "==> host: $(uname -r) $(uname -m), $(nproc) cores, $(free -g | awk '/Mem:/{print $2}') GB RAM"

# --- host prerequisites -----------------------------------------------
if command -v apt-get >/dev/null 2>&1; then
    log "==> installing host prerequisites"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends \
        binutils bison gawk gcc g++ make patch python3 texinfo \
        wget xz-utils zstd xorriso mtools dosfstools cpio squashfs-tools \
        grub-common grub-pc-bin grub-efi-amd64-bin \
        gnupg curl ca-certificates
    apt-get clean
fi

for tool in gcc make bison gawk python3 wget xz zstd xorriso mksquashfs cpio; do
    command -v "$tool" >/dev/null 2>&1 || die "host tool '$tool' missing"
done
log "==> host prerequisites OK"

# --- directory layout (LFS 4.2) ---------------------------------------
mkdir -pv "$LFS_ROOT"
mkdir -pv "$SOURCES" "$LFS_ROOT"/{etc,var,usr,opt,tools}
chmod -v a+wt "$SOURCES"

# 64-bit layout symlinks
for i in bin lib sbin; do
    ln -sv usr/$i "$LFS_ROOT/$i"
done
[ -d "$LFS_ROOT/lib64" ] || ln -sv usr/lib "$LFS_ROOT/lib64"
ln -sv usr/bin "$LFS_ROOT/bin" 2>/dev/null || true

# --- download all sources (skip if already present, e.g. restored) ----
if [ -z "${SKIP_DOWNLOAD:-}" ] && [ ! -f "$SOURCES/.downloaded" ]; then
    log "==> downloading $(wc -l < tools/x86_64/wget-list) files"
    cd "$SOURCES"
    wget -q -nc --no-verbose --timeout=30 --tries=3 \
        --input-file="$SCRIPTS_DIR/../tools/x86_64/wget-list" \
        || warn "wget reported errors (will be caught by md5 check)"
    # retry loop for any missing/zero-length files
    for attempt in 1 2 3; do
        local_missing=0
        while IFS= read -r url; do
            fname="${url##*/}"
            [ -s "$fname" ] || { local_missing=$((local_missing + 1)); wget -q -nc --timeout=30 --tries=2 -O "$fname" "$url" || true; }
        done < "$SCRIPTS_DIR/../tools/x86_64/wget-list"
        [ "$local_missing" -eq 0 ] && break
        sleep 5
    done
    log "==> verifying md5sums"
    if ! ( cd "$SOURCES" && md5sum -c "$SCRIPTS_DIR/../tools/x86_64/md5sums" > md5.log ); then
        warn "md5 verification FAILED - see $SOURCES/md5.log"
        grep -v ': OK$' "$SOURCES/md5.log" || true
        exit 1
    fi
    touch "$SOURCES/.downloaded"
fi
log "==> sources ready: $(ls "$SOURCES" | wc -l) files"

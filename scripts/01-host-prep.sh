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
    # GitHub-hosted runners hit transient stalls on azure.archive.ubuntu.com
    # (apt-get update hangs on 'Ign:' / TCP half-open - saw 25+ min hangs).
    # The azure URL can live in sources.list, *.sources, or (Ubuntu 24.04)
    # the apt-mirrors.txt mirrorlist - nuke every reference, then bound
    # update with a timeout + retry so CI can never hang on package setup.
    log "==> removing azure.archive.ubuntu.com from apt sources (mirror stall workaround)"
    sed -i 's|azure\.archive\.ubuntu\.com|archive.ubuntu.com|g' \
        /etc/apt/sources.list /etc/apt/sources.list.d/*.sources /etc/apt/apt-mirrors.txt 2>/dev/null || true
    if grep -rsq "azure.archive.ubuntu.com" /etc/apt/sources.list /etc/apt/sources.list.d/ /etc/apt/apt-mirrors.txt 2>/dev/null; then
        log "WARN: azure.archive.ubuntu.com still present after sed, removing leftover source files"
        grep -rl "azure.archive.ubuntu.com" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null | xargs -r rm -f
    fi
    if ! timeout 600 apt-get update -y; then
        log "apt-get update failed (rc=$?), retrying once"
        timeout 600 apt-get update -y
    fi
    apt-get install -y --no-install-recommends \
        binutils bison gawk gcc g++ make patch python3 texinfo \
        wget xz-utils zstd xorriso mtools dosfstools cpio squashfs-tools \
        grub-common grub-pc-bin grub-efi-amd64-bin \
        gnupg curl ca-certificates ccache
    apt-get clean
fi

for tool in gcc make bison gawk python3 wget xz zstd xorriso mksquashfs cpio; do
    command -v "$tool" >/dev/null 2>&1 || die "host tool '$tool' missing"
done
log "==> host prerequisites OK"

# --- ccache wrapper links (host-side toolchain builds) --------------
# Invoked as gcc/g++/cc/c++ or as the cross $LFS_TGT-*; ccache finds the
# real compiler by searching PATH, skipping its own link dir.
# NOTE: only wrap names whose real binary actually exists. The cross
# $LFS_TGT-cc / $LFS_TGT-c++ are NEVER installed by gcc pass1, so a
# wrapper link here would shadow a nonexistent compiler: gcc pass2's
# configure then picks "$LFS_TGT-cc" as CC_FOR_TARGET and the libgcc
# sub-configure dies with "ccache: error: Could not find compiler".
mkdir -pv "$LFS_ROOT/ccache-wrap"
for t in gcc g++ cc c++ \
         x86_64-lfs-linux-gnu-gcc x86_64-lfs-linux-gnu-g++; do
    ln -sf "$(command -v ccache)" "$LFS_ROOT/ccache-wrap/$t"
done
log "==> ccache wrappers ready"

# --- directory layout (LFS 4.2) ---------------------------------------
mkdir -pv "$LFS_ROOT"
mkdir -pv "$SOURCES" "$LFS_ROOT"/{etc,var,usr,opt,tools}
chmod -v a+wt "$SOURCES"

# 64-bit layout symlinks
for i in bin lib sbin; do
    ln -sv usr/$i "$LFS_ROOT/$i"
done
mkdir -pv "$LFS_ROOT/lib64"
ln -sv usr/bin "$LFS_ROOT/bin" 2>/dev/null || true

# --- download all sources (skip if already present, e.g. restored) ----
# 95 of 96 files are bundled in tools/x86_64/sources (checked into git);
# only the linux kernel tarball (147 MB, over GitHub's 100 MB file limit)
# is downloaded here from kernel.org's CDN.
if [ -z "${SKIP_DOWNLOAD:-}" ] && [ ! -f "$SOURCES/.downloaded" ]; then
    log "==> copying bundled sources from repository"
    cp -v "$SCRIPTS_DIR"/../tools/x86_64/sources/* "$SOURCES/" 2>/dev/null || true

    if [ ! -s "$SOURCES/linux-$LFS_KERNEL_VER.tar.xz" ]; then
        log "==> downloading linux-$LFS_KERNEL_VER.tar.xz (147 MB, exceeds git limit)"
        wget -q --timeout=30 --tries=3 -O "$SOURCES/linux-$LFS_KERNEL_VER.tar.xz" \
            "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$LFS_KERNEL_VER.tar.xz" \
            || wget -q -O "$SOURCES/linux-$LFS_KERNEL_VER.tar.xz" \
                "https://www.kernel.org/pub/linux/kernel/v6.x/linux-$LFS_KERNEL_VER.tar.xz" \
            || true
    fi
    [ -s "$SOURCES/linux-$LFS_KERNEL_VER.tar.xz" ] || \
        die "kernel tarball download failed"

    log "==> verifying md5sums"
    if ! ( cd "$SOURCES" && md5sum -c "$SCRIPTS_DIR/../tools/x86_64/md5sums" > md5.log ); then
        warn "md5 verification FAILED - see $SOURCES/md5.log"
        grep -v ': OK$' "$SOURCES/md5.log" || true
        exit 1
    fi
    touch "$SOURCES/.downloaded"
fi
log "==> sources ready: $(ls "$SOURCES" | wc -l) files"

#!/usr/bin/env bash
# 02 - Toolchain: LFS ch5 (cross toolchain) + ch6 (temporary tools), run on
#     the HOST as root. Builds directly as root (no 'lfs' user) into
#     $LFS_ROOT/tools and $LFS_ROOT/usr, then sets up the chroot filesystems.

set -euo pipefail
cd "$(dirname "$0")"
source env.sh
source common.sh

[ "$(id -u)" -eq 0 ] || die "must run as root"

# --- ownership + chroot virtual filesystems (7.2 / 7.3) --------------
log "==> setting ownership"
chown -R root:root "$LFS_ROOT" || true
log "==> mounting virtual kernel file systems"
mount_kernfs

# --- environment for the host-side cross build (LFS 4.4 equivalent) ---
export PATH="$LFS_ROOT/tools/bin:$PATH"
export CONFIG_SITE="$LFS_ROOT/usr/share/config.site"
export LC_ALL=POSIX
export LFS="$LFS_ROOT"
export SOURCES="$LFS_ROOT/sources"

log "==> building cross toolchain (ch5) + temporary tools (ch6), -j$NPROC"
log "==> starting: $(date)"
source "$STAGES_DIR/10-host-stage.sh"
log "==> toolchain done: $(date)"

# save toolchain log marker for the workflow
touch "$LFS_ROOT/tools/.toolchain-complete"

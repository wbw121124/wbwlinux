#!/usr/bin/env bash
# 03 - Base system: enter the chroot and run ch7.5-7.13 (20-chroot-stage)
#     and the full ch8 basic system (30-ch8-stage).

set -euo pipefail
cd "$(dirname "$0")"
source env.sh
source common.sh

[ "$(id -u)" -eq 0 ] || die "must run as root"

# snapshot restore (job 2) may leave mounts from a previous run - clear them
umount_kernfs || true
mount_kernfs

# copy the build scripts into the chroot
CHROOT_BUILD="$LFS_ROOT/build"
mkdir -p "$CHROOT_BUILD/stages" "$LFS_ROOT/config"
cp -v env.sh common.sh "$CHROOT_BUILD/"
cp -v "$STAGES_DIR/20-chroot-stage.sh" "$STAGES_DIR/30-ch8-stage.sh" "$CHROOT_BUILD/stages/"
[ -d "$CONFIG_DIR" ] && cp -rv "$CONFIG_DIR"/. "$LFS_ROOT/config/" || true

CHROOT_CMD="
set -euo pipefail
export SOURCES=/sources
export SCRIPTS_DIR=/build
export STAGES_DIR=/build/stages
export CONFIG_DIR=/config
source /build/env.sh
source /build/common.sh
log '==> chroot: ch7.5-7.13 (temporary system cleanup)'
source /build/stages/20-chroot-stage.sh
log '==> chroot: ch8 basic system'
source /build/stages/30-ch8-stage.sh
log '==> chroot base system done'
"

log "==> entering chroot (long build, ~2.5-3.5h on 2 vCPUs)"
chroot "$LFS_ROOT" /usr/bin/env -i \
    HOME=/root TERM="$TERM" PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin \
    MAKEFLAGS="$MAKEFLAGS" \
    /bin/bash --login -c "$CHROOT_CMD"

# LFS 8.85 strip + 8.86 cleanup are inside 30-ch8-stage; done.
touch "$LFS_ROOT/usr/.base-system-complete"
log "==> base system complete"

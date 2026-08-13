#!/usr/bin/env bash
# 04 - System configuration: copy the chroot script in and run it.

set -euo pipefail
cd "$(dirname "$0")"
source env.sh
source common.sh

[ "$(id -u)" -eq 0 ] || die "must run as root"

umount_kernfs || true
mount_kernfs

mkdir -p "$LFS_ROOT/build/chroot"
cp -v env.sh common.sh "$LFS_ROOT/build/"
cp -v chroot/04-sysconfig.sh "$LFS_ROOT/build/chroot/"

chroot "$LFS_ROOT" /usr/bin/env -i \
    HOME=/root TERM="$TERM" PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin \
    MAKEFLAGS="$MAKEFLAGS" \
    /bin/bash --login /build/chroot/04-sysconfig.sh

touch "$LFS_ROOT/etc/.sysconfig-complete"
log "==> system configuration complete"

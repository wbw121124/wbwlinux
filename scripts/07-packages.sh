#!/usr/bin/env bash
# Host-side wrapper for chroot/07-packages.sh.
# Copies scripts into the chroot and runs the package build inside it.
set -euo pipefail
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E bash "$0" "$@"
fi

cd "$(dirname "$0")"
source env.sh
source common.sh

[ "$(id -u)" -eq 0 ] || die "must run as root"

umount_kernfs || true
mount_kernfs

mkdir -p "$LFS_ROOT/build/chroot"
cp -v env.sh common.sh "$LFS_ROOT/build/"
cp -v chroot/07-packages.sh chroot/arch-resolve-fcitx5.py \
      "$LFS_ROOT/build/chroot/"

chroot "$LFS_ROOT" /usr/bin/env -i \
    HOME=/root TERM="$TERM" PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin:/usr/local/bin \
    /bin/bash --login /build/chroot/07-packages.sh

log "==> packages build complete (host wrapper)"

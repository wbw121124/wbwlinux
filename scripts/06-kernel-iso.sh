#!/usr/bin/env bash
# 06 - Kernel + initramfs (in chroot), then assemble the live ISO on the
#     host: rootfs.squashfs, GRUB BIOS+UEFI image via grub-mkrescue.

set -euo pipefail
cd "$(dirname "$0")"
source env.sh
source common.sh

[ "$(id -u)" -eq 0 ] || die "must run as root"

umount_kernfs || true
mount_kernfs

# ---- kernel + initramfs inside the chroot ---------------------------
mkdir -p "$LFS_ROOT/build/chroot"
cp -v env.sh common.sh "$LFS_ROOT/build/"
cp -v chroot/06-kernel-initramfs.sh "$LFS_ROOT/build/chroot/"
cp -v "$CONFIG_DIR/kernel-live.fragment" "$LFS_ROOT/config/"

chroot "$LFS_ROOT" /usr/bin/env -i \
    HOME=/root TERM="$TERM" PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin \
    MAKEFLAGS="$MAKEFLAGS" \
    /bin/bash --login /build/chroot/06-kernel-initramfs.sh

# ---- snapshot the rootfs into a squashfs image ----------------------
umount_kernfs || true

ISO_ROOT="$SCRIPTS_DIR/../iso"
mkdir -p "$ISO_ROOT/boot/grub" "$ISO_ROOT/live"
log "==> packing rootfs.squashfs (xz, this takes a while)"
mksquashfs "$LFS_ROOT" "$ISO_ROOT/live/rootfs.squashfs" \
    -comp xz -noappend \
    -e sources build root/downloads proc sys dev run etc/ld.so.cache
ls -lh "$ISO_ROOT/live/rootfs.squashfs"

# ---- copy kernel + initramfs out ------------------------------------
cp -v "$LFS_ROOT/boot/vmlinuz-$LFS_KERNEL_VER-lfs-cn" "$ISO_ROOT/boot/vmlinuz-$LFS_KERNEL_VER-lfs-cn"
cp -v "$LFS_ROOT/boot/initramfs-lfs-cn.img" "$ISO_ROOT/boot/initramfs-lfs-cn.img"

# ---- GRUB config (BIOS + UEFI via grub-mkrescue) --------------------
cat > "$ISO_ROOT/boot/grub/grub.cfg" << EOF
set timeout=5
set default=0

insmod part_gpt
insmod part_msdos
insmod iso9660

menuentry "LFS-CN $LFS_VERSION (Live x86_64, 中文终端)" {
    linux /boot/vmlinuz-$LFS_KERNEL_VER-lfs-cn quiet vga=791
    initrd /boot/initramfs-lfs-cn.img
}

menuentry "LFS-CN $LFS_VERSION - Troubleshooting (console)" {
    linux /boot/vmlinuz-$LFS_KERNEL_VER-lfs-cn quiet vga=791 systemd.unit=emergency.target
    initrd /boot/initramfs-lfs-cn.img
}
EOF

log "==> building ISO with grub-mkrescue"
grub-mkrescue --output="$SCRIPTS_DIR/../lfs-cn-$LFS_VERSION-x86_64.iso" \
    --volid LFS_CN "$ISO_ROOT"

ls -lh "$SCRIPTS_DIR/../lfs-cn-$LFS_VERSION-x86_64.iso"
log "==> ISO complete"

#!/usr/bin/env bash
# 06 - Kernel + initramfs (in chroot), then assemble the live ISO on the
#     host: rootfs.squashfs, GRUB BIOS+UEFI image via grub-mkrescue.

set -euo pipefail
# re-exec as root if needed (GitHub hosted runners are non-root users)
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E bash "$0" "$@"
fi

cd "$(dirname "$0")"
source env.sh
source common.sh

# Re-resolve the selected kernel track for resumed builds and persist the
# exact release + checksum into the restored snapshot for the chroot.
mkdir -p "$LFS_ROOT/build"
bash "$SCRIPTS_DIR/resolve-kernel.sh" "$LFS_ROOT/build/kernel-version.env"
source "$LFS_ROOT/build/kernel-version.env"

[ "$(id -u)" -eq 0 ] || die "must run as root"

# Resume builds may restore a snapshot made before the kernel version bump.
# Ensure the exact requested tarball is present and matches kernel.org SHA-256.
KERNEL_TARBALL="$LFS_ROOT/sources/linux-$LFS_KERNEL_VER.tar.xz"
KERNEL_URL="$LFS_KERNEL_URL"
# Older snapshots may predate the installer dependencies.
[ -s "$LFS_ROOT/sources/dialog_1.3-20250116.orig.tar.gz" ] || wget -q --timeout=30 --tries=3 -O "$LFS_ROOT/sources/dialog_1.3-20250116.orig.tar.gz" "https://deb.debian.org/debian/pool/main/d/dialog/dialog_1.3-20250116.orig.tar.gz"
[ -s "$LFS_ROOT/sources/dosfstools-4.2.tar.gz" ] || wget -q --timeout=30 --tries=3 -O "$LFS_ROOT/sources/dosfstools-4.2.tar.gz" "https://github.com/dosfstools/dosfstools/releases/download/v4.2/dosfstools-4.2.tar.gz"
if [ ! -s "$KERNEL_TARBALL" ] || [ "$(sha256sum "$KERNEL_TARBALL" | awk '{print $1}')" != "$LFS_KERNEL_SHA256" ]; then
    rm -f "$KERNEL_TARBALL"
    log "==> downloading Linux $LFS_KERNEL_VER source for ISO/resume build"
    wget -q --timeout=30 --tries=3 -O "$KERNEL_TARBALL" "$KERNEL_URL" || \
        wget -q --timeout=30 --tries=3 -O "$KERNEL_TARBALL" "${LFS_KERNEL_URL/cdn.kernel.org/www.kernel.org}" || \
        die "kernel tarball download failed"
fi
printf '%s  %s\n' "$LFS_KERNEL_SHA256" "$KERNEL_TARBALL" | sha256sum -c - || die "Linux kernel SHA-256 verification failed"

printf 'd58d058105cdd976d21ec4dd069b57d3  %s\n' "$LFS_ROOT/sources/dialog_1.3-20250116.orig.tar.gz" | md5sum -c - || die "dialog source checksum failed"
printf '49c8e457327dc61efab5b115a27b087a  %s\n' "$LFS_ROOT/sources/dosfstools-4.2.tar.gz" | md5sum -c - || die "dosfstools source checksum failed"

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
# Stage the installer before packing the rootfs so it is present in the ISO.
install -Dm755 "$SCRIPTS_DIR/install-lfs-cn.sh" "$LFS_ROOT/usr/sbin/lfs-cn-installer"
log "==> packing rootfs.squashfs (xz, this takes a while)"
mksquashfs "$LFS_ROOT" "$ISO_ROOT/live/rootfs.squashfs" \
    -comp xz -noappend \
    -e sources build root/downloads proc sys dev run etc/ld.so.cache
ls -lh "$ISO_ROOT/live/rootfs.squashfs"

# ---- pack initramfs (cpio is not inside the chroot; do it on the host) ----
log "==> packing initramfs"
( cd "$LFS_ROOT/boot/initramfs-lfs-cn" && find . -print0 | cpio --null -ov --format=newc 2>/dev/null | gzip -9 > "$LFS_ROOT/boot/initramfs-lfs-cn.img" )
ls -lh "$LFS_ROOT/boot/initramfs-lfs-cn.img"

# ---- self-check the packed image: it must contain a working /bin/sh and /init ----
log "==> verifying packed initramfs"
INITRD_IMG="$LFS_ROOT/boot/initramfs-lfs-cn.img"
# cpio -it lists entries with a leading './' - normalize before matching
gzip -dc "$INITRD_IMG" | cpio -it 2>/dev/null | sed 's#^\./##' > /tmp/initramfs-list.txt || die "initramfs: cannot read back $INITRD_IMG"
for entry in "usr/bin/bash" "bin/sh" "init" "usr/bin/mount" "usr/sbin/switch_root" "usr/lib/libc.so.6" "lib64/ld-linux-x86-64.so.2"; do
    grep -qx "$entry" /tmp/initramfs-list.txt || die "initramfs: required entry '$entry' missing from packed image - build must fail, not ship a broken ISO"
done
log "initramfs: $(grep -c '^' /tmp/initramfs-list.txt) entries verified in packed image"

# ---- copy kernel + initramfs out ------------------------------------
cp -v "$LFS_ROOT/boot/vmlinuz-$LFS_KERNEL_VER-lfs-cn" "$ISO_ROOT/boot/vmlinuz-$LFS_KERNEL_VER-lfs-cn"
cp -v "$LFS_ROOT/boot/initramfs-lfs-cn.img" "$ISO_ROOT/boot/initramfs-lfs-cn.img"

# ---- GRUB config (BIOS + UEFI via grub-mkrescue) --------------------
# NOTE: menu titles are English on purpose - GRUB has no CJK glyphs in its
# default unicode.pf2, Chinese titles render as garbage in both BIOS (VGA)
# and UEFI consoles. Chinese UI lives in the system itself (fbterm).
# locale.* cmdline params (systemd.locale(7)) force PID1 + services +
# getty/login to English: the vconsole cannot draw CJK, so any localized
# boot/login output would be mojibake. zh_CN comes back inside fbterm.
cat > "$ISO_ROOT/boot/grub/grub.cfg" << EOF
set timeout=5
set default=0

insmod part_gpt
insmod part_msdos
insmod iso9660

menuentry "LFS-CN $LFS_VERSION (Live x86_64)" {
    linux /boot/vmlinuz-$LFS_KERNEL_VER-lfs-cn quiet vga=791 locale.LANG=C.UTF-8 locale.LC_MESSAGES=C.UTF-8
    initrd /boot/initramfs-lfs-cn.img
}

# persistence auto-detection can be skipped entirely with persist=off:
# nothing on disk is ever written, useful for untrusted hosts
menuentry "LFS-CN $LFS_VERSION (Live x86_64, volatile session)" {
    linux /boot/vmlinuz-$LFS_KERNEL_VER-lfs-cn quiet vga=791 persist=off locale.LANG=C.UTF-8 locale.LC_MESSAGES=C.UTF-8
    initrd /boot/initramfs-lfs-cn.img
}

menuentry "LFS-CN $LFS_VERSION - Troubleshooting (console)" {
    linux /boot/vmlinuz-$LFS_KERNEL_VER-lfs-cn quiet vga=791 systemd.unit=emergency.target locale.LANG=C.UTF-8 locale.LC_MESSAGES=C.UTF-8
    initrd /boot/initramfs-lfs-cn.img
}
EOF

log "==> building ISO with grub-mkrescue"
grub-mkrescue --output="$SCRIPTS_DIR/../lfs-cn-$LFS_VERSION-x86_64.iso" \
    --volid LFS_CN "$ISO_ROOT"

ls -lh "$SCRIPTS_DIR/../lfs-cn-$LFS_VERSION-x86_64.iso"
log "==> ISO complete"

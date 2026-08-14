#!/usr/bin/env bash
# Runs INSIDE the LFS chroot. Build the kernel with a fragment config,
# create an initramfs (minimal dynamic binaries + live init), and write
# a live-friendly /etc/fstab. ISO assembly happens on the host.
set -euo pipefail
export SOURCES=/sources
export SCRIPTS_DIR=/build
export STAGES_DIR=/build/stages
export CONFIG_DIR=/config
source /build/env.sh
source /build/common.sh

KERNEL_VER="$LFS_KERNEL_VER"

# ---------------------------------------------------------------------
# kernel
# ---------------------------------------------------------------------
cd /sources
log "==> extracting kernel linux-$KERNEL_VER"
rm -rf "linux-$KERNEL_VER"
tar xf "linux-$KERNEL_VER.tar.xz"
cd "linux-$KERNEL_VER"

log "==> configuring kernel (defconfig + live fragment)"
make mrproper
make defconfig
cat /config/kernel-live.fragment >> .config
make olddefconfig
grep -E 'CONFIG_(SQUASHFS|OVERLAY_FS|ISO9660|BLK_DEV_LOOP|FB_VESA|FB_EFI|FRAMEBUFFER_CONSOLE|DEVTMPFS|UNICODE|NLS_UTF8|NLS_ASCII|EXT4_FS|VFAT_FS|USB|AHCI|ATA|VIRTIO|NETDEVICES|E1000|PCNET|8139|VIRTIO_NET|XFS)=' .config | sort > /tmp/kernel-config-verified.txt
wc -l /tmp/kernel-config-verified.txt

log "==> building kernel (this takes a while)"
make -j"$NPROC" bzImage
make -j"$NPROC" modules

log "==> installing kernel"
make modules_install
cp -iv arch/x86/boot/bzImage "/boot/vmlinuz-$KERNEL_VER-lfs-cn"
cp -iv System.map "/boot/System.map-$KERNEL_VER"
cp -iv .config "/boot/config-$KERNEL_VER"

# switch_root will exec /sbin/init on the live root - make sure it exists
# (systemd ships its binary under /usr/lib/systemd/systemd)
if [ -e /usr/lib/systemd/systemd ] && [ ! -e /sbin/init ]; then
    ln -sfv ../usr/lib/systemd/systemd /sbin/init
fi
ls -l /sbin/init

# ---------------------------------------------------------------------
# live /etc/fstab (no fixed partitions in a live ISO)
# ---------------------------------------------------------------------
cat > /etc/fstab << 'EOF'
# Begin /etc/fstab (LFS-CN live)

tmpfs           /run            tmpfs   defaults                        0 0
devpts          /dev/pts        devpts  gid=5,mode=0620                 0 0
proc            /proc           proc    nosuid,noexec,nodev             0 0
sysfs           /sys            sysfs   nosuid,noexec,nodev             0 0
# End /etc/fstab
EOF

# ---------------------------------------------------------------------
# initramfs: minimal root with live init
# ---------------------------------------------------------------------
INITRAMFS_DIR=/boot/initramfs-lfs-cn
rm -rf "$INITRAMFS_DIR"
mkdir -p "$INITRAMFS_DIR"/{bin,sbin,usr/bin,usr/sbin,lib,lib64,proc,sys,dev,run,mnt,newroot,etc}

copy_deps() {
    local bin="$1"
    [ -e "$bin" ] || return 1
    cp -avL "$bin" "$INITRAMFS_DIR$bin" 2>/dev/null
    local missing=0
    local dl
    dl="$(ldd "$bin" 2>/dev/null | awk '{print $3}' | grep -v '^$')"
    dl="$dl $(ldd "$bin" 2>/dev/null | awk '/=> \/lib/{print $3}')"
    for so in $dl; do
        if [ -e "$INITRAMFS_DIR$so" ]; then continue; fi
        cp -avL "$so" "$INITRAMFS_DIR$so" 2>/dev/null || missing=1
        if [[ "$so" == *linux-gnu/ld-linux* || "$so" == *ld-linux* ]]; then
            cp -avL "$so" "$INITRAMFS_DIR/lib64/" 2>/dev/null || true
        fi
    done
    return 0
}

copy_deps /usr/bin/bash
copy_deps /usr/bin/mount
copy_deps /usr/bin/umount
copy_deps /usr/bin/switch_root
copy_deps /usr/bin/sleep
copy_deps /usr/bin/cat
copy_deps /usr/bin/mkdir
copy_deps /usr/bin/cp
copy_deps /usr/bin/grep
copy_deps /usr/bin/awk
copy_deps /usr/bin/sed
copy_deps /usr/bin/insmod
copy_deps /usr/bin/modprobe
copy_deps /usr/bin/blkid
copy_deps /usr/bin/mknod

# the dynamic linker must be in the expected location
cp -avL /lib64/ld-linux-x86-64.so.2 "$INITRAMFS_DIR/lib64/" 2>/dev/null || true

# init is #!/bin/sh -> make /bin/sh available (bash is copied as /usr/bin/bash)
ln -sfv /usr/bin/bash "$INITRAMFS_DIR/bin/sh"

cat > "$INITRAMFS_DIR/init" << 'EOF'
#!/bin/sh
export PATH=/sbin:/bin:/usr/sbin:/usr/bin

mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mkdir -p /dev/pts /dev/shm
mount -t devpts devpts /dev/pts

# wait for the ISO device to appear (poll with retries; USB/CD probing can lag)
iso_dev=""
attempt=0
while [ $attempt -lt 30 ]; do
    attempt=$((attempt+1))
    for dev in $(cat /proc/partitions | awk '{print $4}' | grep -E '^(sr|sd)[a-z0-9]+$'); do
        if mount -t iso9660 -r "/dev/$dev" /mnt 2>/dev/null; then
            if [ -f /mnt/live/rootfs.squashfs ]; then
                iso_dev="/dev/$dev"
                break
            fi
            umount /mnt 2>/dev/null
        fi
    done
    [ -n "$iso_dev" ] && break
    sleep 1
done

if [ -z "$iso_dev" ]; then
    echo "ERROR: cannot find the LFS-CN live medium" > /dev/console
    echo "No ISO with /live/rootfs.squashfs found" > /dev/console
    exec /bin/sh
fi

echo "live: ISO found on $iso_dev" > /dev/console

mkdir -p /run/rootfs
mount -t squashfs -o loop /mnt/live/rootfs.squashfs /run/rootfs

mkdir -p /run/overlay /run/upper /run/work
mount -t tmpfs tmpfs /run/overlay
mkdir -p /run/upper /run/work
mount -t overlay overlay -o lowerdir=/run/rootfs,upperdir=/run/upper,workdir=/run/work /newroot

mkdir -p /newroot/proc /newroot/sys /newroot/dev /newroot/run /newroot/mnt
mount -t proc proc /newroot/proc
mount -t sysfs sysfs /newroot/sys
mount -t devtmpfs devtmpfs /newroot/dev

echo "live: switching root" > /dev/console
exec switch_root /newroot /sbin/init
EOF
chmod +x "$INITRAMFS_DIR/init"

# NOTE: the initramfs image is packed on the HOST in 06-kernel-iso.sh
# (cpio is a BLFS package, not available inside this chroot)
log '==> kernel + initramfs tree done'

# free the kernel build tree (excluded from squashfs, but wastes runner disk)
cd /sources
rm -rf "linux-$KERNEL_VER"

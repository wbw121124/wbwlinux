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
grep -qx "CONFIG_NTFS_FS=y" .config || die "kernel config: native read-write NTFS driver (CONFIG_NTFS_FS) is not enabled"
grep -qx "CONFIG_NTFS3_FS=y" .config || die "kernel config: NTFS3 driver is not enabled"
grep -E 'CONFIG_(SQUASHFS|OVERLAY_FS|ISO9660|BLK_DEV_LOOP|FB_VESA|FB_EFI|FRAMEBUFFER_CONSOLE|DEVTMPFS|UNICODE|NLS_UTF8|NLS_ASCII|EXT4_FS|VFAT_FS|NTFS_FS|NTFS3_FS|USB|AHCI|ATA|VIRTIO|NETDEVICES|E1000|PCNET|8139|VIRTIO_NET|XFS)=' .config | sort > /tmp/kernel-config-verified.txt
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
#
# /var and /home are tmpfs on purpose as belt-and-suspenders. The primary
# fix (in the initramfs init) keeps the overlay upper alive on a dedicated
# /run/overlay tmpfs so the whole root stays writable via copy-up. These
# tmpfs mounts additionally guarantee /var and /home are writable even if
# the overlay upper were ever detached again. systemd regenerates
# machine-id/catalog on demand.

tmpfs           /run            tmpfs   defaults                        0 0
tmpfs           /var            tmpfs   defaults                        0 0
tmpfs           /home           tmpfs   defaults                        0 0
devpts          /dev/pts        devpts  gid=5,mode=0620                 0 0
proc            /proc           proc    nosuid,noexec,nodev             0 0
sysfs           /sys            sysfs   nosuid,noexec,nodev             0 0
# End /etc/fstab
EOF

# ---------------------------------------------------------------------
# ---------------------------------------------------------------------
# Disk-installer runtime: dialog, dosfstools, and UEFI GRUB.
# Source archives are fetched and checksum-verified by the host stage.
# ---------------------------------------------------------------------
cd /sources
if [ ! -x /usr/bin/dialog ]; then
    log "==> building dialog TUI"
    rm -rf dialog-1.3-20250116
    tar xf dialog_1.3-20250116.orig.tar.gz
    cd dialog-1.3-20250116
    ./configure --prefix=/usr --with-ncursesw
    make -j"$NPROC"
    make install
    cd /sources
    rm -rf dialog-1.3-20250116
fi
if [ ! -x /usr/bin/mkfs.fat ]; then
    log "==> building dosfstools"
    rm -rf dosfstools-4.2
    tar xf dosfstools-4.2.tar.gz
    cd dosfstools-4.2
    ./configure --prefix=/usr --enable-compat-symlinks
    make -j"$NPROC"
    make install
    cd /sources
    rm -rf dosfstools-4.2
fi
if [ ! -x /usr/sbin/grub-install ] && [ ! -x /usr/bin/grub-install ]; then
    log "==> building UEFI GRUB for the disk installer"
    rm -rf grub-2.14 grub-build-efi
    tar xf grub-2.14.tar.xz
    mkdir -p /sources/grub-build-efi
    cd /sources/grub-build-efi
    ../grub-2.14/configure --prefix=/usr --with-platform=efi --target=x86_64 --disable-werror
    make -j"$NPROC"
    make install
    cd /sources
    rm -rf grub-2.14 grub-build-efi
fi
command -v dialog >/dev/null 2>&1 || die "installer TUI dependency dialog was not installed"
command -v mkfs.fat >/dev/null 2>&1 || die "installer dependency dosfstools was not installed"
command -v grub-install >/dev/null 2>&1 || die "installer dependency UEFI GRUB was not installed"

# initramfs: minimal root with live init
# ---------------------------------------------------------------------
INITRAMFS_DIR=/boot/initramfs-lfs-cn
rm -rf "$INITRAMFS_DIR"
mkdir -p "$INITRAMFS_DIR"/{bin,sbin,usr/bin,usr/sbin,usr/lib,lib,lib64,proc,sys,dev,run,mnt,newroot,etc}

copy_deps() {
    # accept both "bash" and "/usr/bin/bash" call styles
    local name="${1##*/}" bin=""
    for p in /usr/bin /usr/sbin /bin /sbin; do
        [ -e "$p/$name" ] && { bin="$p/$name"; break; }
    done
    [ -n "$bin" ] || { log "WARN: $name not found in PATH, skipping"; return 0; }
    cp -avL "$bin" "$INITRAMFS_DIR$bin" || log "ERROR: failed to copy $bin"
    local missing=0
    local dl
    dl="$(ldd "$bin" 2>/dev/null | awk '{print $3}' | grep -v '^$')"
    dl="$dl $(ldd "$bin" 2>/dev/null | awk '/=> \/lib/{print $3}')"
    if [ -z "$dl" ]; then
        log "WARN: no dynamic deps detected for $bin (statically linked?)"
    fi
    for so in $dl; do
        if [ -e "$INITRAMFS_DIR$so" ]; then continue; fi
        if ! cp -avL "$so" "$INITRAMFS_DIR$so" 2>/dev/null; then
            missing=1
            log "WARN: failed to copy dep $so"
        fi
        if [[ "$so" == *linux-gnu/ld-linux* || "$so" == *ld-linux* ]]; then
            cp -avL "$so" "$INITRAMFS_DIR/lib64/" 2>/dev/null || true
        fi
    done
    return 0
}

copy_deps bash
copy_deps mount
copy_deps umount
copy_deps switch_root
copy_deps sleep
copy_deps cat
copy_deps mkdir
copy_deps cp
copy_deps grep
copy_deps awk
copy_deps sed
copy_deps sort
copy_deps insmod
copy_deps modprobe
copy_deps blkid
copy_deps mknod
copy_deps losetup

# the dynamic linker must be in the expected location
cp -avL /lib64/ld-linux-x86-64.so.2 "$INITRAMFS_DIR/lib64/" 2>/dev/null || true

# init is #!/bin/sh -> make /bin/sh available (bash is copied as /usr/bin/bash)
ln -sfv /usr/bin/bash "$INITRAMFS_DIR/bin/sh"

# ---- hard self-checks: a broken initramfs must fail the build, not ship ----
[ -x "$INITRAMFS_DIR/usr/bin/bash" ] || die "initramfs: /usr/bin/bash missing (copy_deps failed to find bash)"
[ -e "$INITRAMFS_DIR/bin/sh" ] || die "initramfs: bin/sh symlink missing"
for t in mount umount sleep cat mkdir cp grep awk sed sort mknod; do
    [ -e "$INITRAMFS_DIR/usr/bin/$t" ] || log "ERROR: initramfs missing required tool /usr/bin/$t"
done
for t in switch_root insmod modprobe blkid losetup; do
    [ -e "$INITRAMFS_DIR/usr/sbin/$t" ] || log "ERROR: initramfs missing required tool /usr/sbin/$t"
done
[ -e "$INITRAMFS_DIR/lib64/ld-linux-x86-64.so.2" ] || die "initramfs: dynamic loader missing"
[ -e "$INITRAMFS_DIR/usr/lib/libc.so.6" ] || die "initramfs: libc.so.6 missing (copy_deps dep copy target dir missing?)"
log "initramfs: $(find "$INITRAMFS_DIR" -type f | wc -l) regular files staged"

cat > "$INITRAMFS_DIR/init" << 'EOF'
#!/bin/sh
export PATH=/sbin:/bin:/usr/sbin:/usr/bin

mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mkdir -p /dev/pts /dev/shm
mount -t devpts devpts /dev/pts

# Installed systems pass lfs_root=UUID=<uuid>; live boots keep the ISO scan.
# blkid resolves UUIDs before a userspace udev daemon is available.
live_store=""
iso_dev=""
root_spec=""
for arg in $(cat /proc/cmdline); do
    case "$arg" in lfs_root=*) root_spec="${arg#lfs_root=}" ;; esac
done

if [ -n "$root_spec" ]; then
    attempt=0
    while [ $attempt -lt 30 ]; do
        attempt=$((attempt+1))
        case "$root_spec" in
            UUID=*) root_dev="$(blkid -U "${root_spec#UUID=}" 2>/dev/null)" ;;
            LABEL=*) root_dev="$(blkid -L "${root_spec#LABEL=}" 2>/dev/null)" ;;
            /dev/*) root_dev="$root_spec" ;;
            *) root_dev="" ;;
        esac
        if [ -n "$root_dev" ] && mount -t ext4 -o rw "$root_dev" /mnt 2>/dev/null; then
            if [ -f /mnt/live/rootfs.squashfs ]; then
                live_store=/mnt
                echo "live: installed payload found on $root_dev" > /dev/console
                break
            fi
            umount /mnt 2>/dev/null
        fi
        sleep 1
    done
    if [ -z "$live_store" ]; then
        echo "ERROR: lfs_root=$root_spec has no /live/rootfs.squashfs" > /dev/console
        exec /bin/sh
    fi
else
    attempt=0
    while [ $attempt -lt 30 ]; do
        attempt=$((attempt+1))
        for dev in $(cat /proc/partitions | awk '{print $4}' | grep -E '^(sr|sd)[a-z0-9]+
# ROOT CAUSE FIX: the overlay upper+work MUST live inside the dedicated
# /run/overlay tmpfs (not on the initramfs root). switch_root relocates the
# initramfs root and this fstab then stacks a fresh tmpfs on /run, but the
# /run/overlay tmpfs mount stays alive underneath; the overlay pins its
# upperdir dentry, so the whole merged root (/etc, /var, /home, ...) remains
# writable via overlay copy-up. Without this the writable upper was detached,
# dropping /etc and /var to the read-only squashfs lower, and
# systemd-timesyncd/logind/journal-catalog-update failed at STATE_DIRECTORY
# (ENOENT) plus hwdb-update/update-done failed writing /etc.
#
# ---- persistence (W4): reuse an upperdir across boots ------------------
# Unless persist=off is on the cmdline, probe partitions for either:
#   a) a filesystem whose root contains an upper/ directory (dedicated
#      persistence fs; label it LFS-CN-PERSIST for convenience), or
#   b) a file lfs-cn-persistence.img in its root - an ext4 image attached
#      via loop0 (works from FAT/exFAT sticks too).
# With no medium found the boot falls back to the stock volatile tmpfs.
PERSIST_UPPER=""
if ! grep -q 'persist=off' /proc/cmdline; then
    mkdir -p /run/persist
    for dev in $(cat /proc/partitions | awk '{print $4}' | grep -E '^(sd|vd|hd|nvme|mtd)[a-z0-9]*p?[0-9]+$' | sort -u); do
        if [ "/dev/$dev" = "$iso_dev" ]; then continue; fi
        if mount -t ext4 -o rw "/dev/$dev" /run/persist 2>/dev/null; then
            :
        elif mount -t vfat -o rw,umask=000 "/dev/$dev" /run/persist 2>/dev/null; then
            :
        else
            continue
        fi
        if [ -d /run/persist/upper ]; then
            mkdir -p /run/persist/work
            PERSIST_UPPER=/run/persist/upper
            PERSIST_WORK=/run/persist/work
            echo "live: persistent session on /dev/$dev" > /dev/console
            break
        fi
        if [ -f /run/persist/lfs-cn-persistence.img ]; then
            [ -e /dev/loop-control ] || mknod /dev/loop-control c 10 237 2>/dev/null
            [ -e /dev/loop0 ] || mknod /dev/loop0 b 7 0 2>/dev/null
            if losetup /dev/loop0 /run/persist/lfs-cn-persistence.img 2>/dev/null \
               && mount -t ext4 -o rw /dev/loop0 /run/persist 2>/dev/null; then
                mkdir -p /run/persist/upper /run/persist/work
                PERSIST_UPPER=/run/persist/upper
                PERSIST_WORK=/run/persist/work
                echo "live: persistent session via lfs-cn-persistence.img on /dev/$dev" > /dev/console
                break
            fi
        fi
        umount /run/persist 2>/dev/null
    done
fi

mkdir -p /run/overlay
if [ -n "$PERSIST_UPPER" ]; then
    # persistent store already mounted under /run; like the tmpfs case the
    # overlay pins its dentries so it survives switch_root + fstab's /run
    :
else
    mount -t tmpfs tmpfs /run/overlay
    mkdir -p /run/overlay/upper /run/overlay/work
    PERSIST_UPPER=/run/overlay/upper
    PERSIST_WORK=/run/overlay/work
    echo "live: volatile session (no persistence medium found)" > /dev/console
fi
mount -t overlay overlay -o lowerdir=/run/rootfs,upperdir=$PERSIST_UPPER,workdir=$PERSIST_WORK /newroot

mkdir -p /newroot/proc /newroot/sys /newroot/dev /newroot/run /newroot/mnt
mount -t proc proc /newroot/proc
mount -t sysfs sysfs /newroot/sys
mount -t devtmpfs devtmpfs /newroot/dev

# /var and /home are also covered by tmpfs as belt-and-suspenders so they
# stay writable even if the overlay upper were ever detached again.
mkdir -p /newroot/var /newroot/home
mount -t tmpfs tmpfs /newroot/var
mount -t tmpfs tmpfs /newroot/home

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
); do
            if mount -t iso9660 -r "/dev/$dev" /mnt 2>/dev/null; then
                if [ -f /mnt/live/rootfs.squashfs ]; then
                    iso_dev="/dev/$dev"
                    live_store=/mnt
                    break
                fi
                umount /mnt 2>/dev/null
            fi
        done
        [ -n "$live_store" ] && break
        sleep 1
    done
    if [ -z "$live_store" ]; then
        echo "ERROR: cannot find the LFS-CN live medium" > /dev/console
        echo "No ISO with /live/rootfs.squashfs found" > /dev/console
        exec /bin/sh
    fi
    echo "live: ISO found on $iso_dev" > /dev/console
fi

mkdir -p /run/rootfs
mount -t squashfs -o loop "$live_store/live/rootfs.squashfs" /run/rootfs

# ROOT CAUSE FIX: the overlay upper+work MUST live inside the dedicated
# /run/overlay tmpfs (not on the initramfs root). switch_root relocates the
# initramfs root and this fstab then stacks a fresh tmpfs on /run, but the
# /run/overlay tmpfs mount stays alive underneath; the overlay pins its
# upperdir dentry, so the whole merged root (/etc, /var, /home, ...) remains
# writable via overlay copy-up. Without this the writable upper was detached,
# dropping /etc and /var to the read-only squashfs lower, and
# systemd-timesyncd/logind/journal-catalog-update failed at STATE_DIRECTORY
# (ENOENT) plus hwdb-update/update-done failed writing /etc.
#
# ---- persistence (W4): reuse an upperdir across boots ------------------
# Unless persist=off is on the cmdline, probe partitions for either:
#   a) a filesystem whose root contains an upper/ directory (dedicated
#      persistence fs; label it LFS-CN-PERSIST for convenience), or
#   b) a file lfs-cn-persistence.img in its root - an ext4 image attached
#      via loop0 (works from FAT/exFAT sticks too).
# With no medium found the boot falls back to the stock volatile tmpfs.
PERSIST_UPPER=""
if ! grep -q 'persist=off' /proc/cmdline; then
    mkdir -p /run/persist
    for dev in $(cat /proc/partitions | awk '{print $4}' | grep -E '^(sd|vd|hd|nvme|mtd)[a-z0-9]*p?[0-9]+$' | sort -u); do
        if [ "/dev/$dev" = "$iso_dev" ]; then continue; fi
        if mount -t ext4 -o rw "/dev/$dev" /run/persist 2>/dev/null; then
            :
        elif mount -t vfat -o rw,umask=000 "/dev/$dev" /run/persist 2>/dev/null; then
            :
        else
            continue
        fi
        if [ -d /run/persist/upper ]; then
            mkdir -p /run/persist/work
            PERSIST_UPPER=/run/persist/upper
            PERSIST_WORK=/run/persist/work
            echo "live: persistent session on /dev/$dev" > /dev/console
            break
        fi
        if [ -f /run/persist/lfs-cn-persistence.img ]; then
            [ -e /dev/loop-control ] || mknod /dev/loop-control c 10 237 2>/dev/null
            [ -e /dev/loop0 ] || mknod /dev/loop0 b 7 0 2>/dev/null
            if losetup /dev/loop0 /run/persist/lfs-cn-persistence.img 2>/dev/null \
               && mount -t ext4 -o rw /dev/loop0 /run/persist 2>/dev/null; then
                mkdir -p /run/persist/upper /run/persist/work
                PERSIST_UPPER=/run/persist/upper
                PERSIST_WORK=/run/persist/work
                echo "live: persistent session via lfs-cn-persistence.img on /dev/$dev" > /dev/console
                break
            fi
        fi
        umount /run/persist 2>/dev/null
    done
fi

mkdir -p /run/overlay
if [ -n "$PERSIST_UPPER" ]; then
    # persistent store already mounted under /run; like the tmpfs case the
    # overlay pins its dentries so it survives switch_root + fstab's /run
    :
else
    mount -t tmpfs tmpfs /run/overlay
    mkdir -p /run/overlay/upper /run/overlay/work
    PERSIST_UPPER=/run/overlay/upper
    PERSIST_WORK=/run/overlay/work
    echo "live: volatile session (no persistence medium found)" > /dev/console
fi
mount -t overlay overlay -o lowerdir=/run/rootfs,upperdir=$PERSIST_UPPER,workdir=$PERSIST_WORK /newroot

mkdir -p /newroot/proc /newroot/sys /newroot/dev /newroot/run /newroot/mnt
mount -t proc proc /newroot/proc
mount -t sysfs sysfs /newroot/sys
mount -t devtmpfs devtmpfs /newroot/dev

# /var and /home are also covered by tmpfs as belt-and-suspenders so they
# stay writable even if the overlay upper were ever detached again.
mkdir -p /newroot/var /newroot/home
mount -t tmpfs tmpfs /newroot/var
mount -t tmpfs tmpfs /newroot/home

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

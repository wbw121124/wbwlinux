#!/usr/bin/env bash
# Install the LFS-CN Live ISO payload to a GPT disk (UEFI x86_64).
# Destructive partitioning is gated by a warning dialog AND typing ERASE.
set -Eeuo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
# fbterm may advertise a TERM without an ncurses entry; fall back safely.
if ! command -v infocmp >/dev/null 2>&1 || ! infocmp "${TERM:-linux}" >/dev/null 2>&1; then export TERM=linux; fi

APP=lfs-cn-installer
MNT=/mnt/lfs-cn-install
TMP=/run/lfs-cn-installer
DIALOG_BIN=

die() {
    local msg=$1
    if [[ -n "${DIALOG_BIN}" ]]; then
        "${DIALOG_BIN}" --title "LFS-CN 安装器" --msgbox "$msg" 10 72 || true
    else
        printf 'ERROR: %s\n' "$msg" >&2
    fi
    exit 1
}

for candidate in dialog whiptail; do
    if command -v "$candidate" >/dev/null 2>&1; then DIALOG_BIN=$candidate; break; fi
done
[[ -n "$DIALOG_BIN" ]] || { echo "需要 dialog 或 whiptail 才能启动 TUI。" >&2; exit 1; }
[[ $(id -u) -eq 0 ]] || die "请以 root 身份运行：sudo lfs-cn-installer"
[[ -d /sys/firmware/efi ]] || die "当前 Live 系统以传统 BIOS/CSM 模式启动。此安装器目前只支持 UEFI x86_64，请在固件中启用 UEFI 后重启。"

for tool in lsblk sfdisk blockdev udevadm mkfs.fat mkfs.ext4 blkid mount umount cp sync grub-install; do
    command -v "$tool" >/dev/null 2>&1 || die "缺少必要工具：$tool。此镜像可能不是包含安装器的新版 ISO。"
done

mkdir -p "$TMP" "$MNT"
cleanup() {
    set +e
    mountpoint -q "$TMP/rootfs" && umount "$TMP/rootfs"
    mountpoint -q "$MNT/boot/efi" && umount "$MNT/boot/efi"
    mountpoint -q "$MNT" && umount "$MNT"
    [[ -d "$TMP/iso" ]] && mountpoint -q "$TMP/iso" && umount "$TMP/iso"
}
trap cleanup EXIT

# Find the ISO9660 medium again: the initramfs' original /mnt mount does not
# survive switch_root as a dependable path.
ISO_DEV=
while read -r dev; do
    [[ -b "$dev" ]] || continue
    mkdir -p "$TMP/iso"
    if mount -t iso9660 -o ro "$dev" "$TMP/iso" 2>/dev/null; then
        if [[ -s "$TMP/iso/live/rootfs.squashfs" ]]; then ISO_DEV=$dev; break; fi
        umount "$TMP/iso"
    fi
done < <(blkid -t TYPE=iso9660 -o device 2>/dev/null | sort -u)
[[ -n "$ISO_DEV" ]] || die "无法找到 LFS-CN Live ISO（未发现包含 /live/rootfs.squashfs 的 ISO9660 介质）。"
ISO_PARENT=$(lsblk -no PKNAME "$ISO_DEV" 2>/dev/null | head -n1)
if [[ -n "$ISO_PARENT" ]]; then ISO_PARENT="/dev/$ISO_PARENT"; else ISO_PARENT="$ISO_DEV"; fi

# Offer only whole disks; never use the current live optical device.
mapfile -t DISKS < <(lsblk -dpno NAME,SIZE,MODEL,TYPE | awk '$4=="disk" {print $1 "|" $2 "|" $3}')
(("${#DISKS[@]}" > 0)) || die "没有发现可安装的整块磁盘。"
MENU=()
for entry in "${DISKS[@]}"; do
    IFS='|' read -r dev size model <<< "$entry"
    model=${model:-Unknown}
    MENU+=("$dev" "$size — $model")
done
TARGET=$("$DIALOG_BIN" --clear --title "LFS-CN 安装器" \
    --menu "选择目标磁盘。该磁盘上的所有分区和数据都将被删除。\n\nLive 介质：$ISO_DEV" 18 78 8 "${MENU[@]}" 3>&1 1>&2 2>&3) || exit 0
[[ -b "$TARGET" ]] || die "目标设备无效：$TARGET"
if [[ "$TARGET" == "$ISO_DEV" || "$TARGET" == "$ISO_PARENT" ]]; then
    die "所选目标磁盘承载当前 Live ISO（$ISO_DEV），拒绝擦除启动介质。"
fi

# If any child partition is mounted, stop instead of attempting to unmount
# unknown user filesystems behind their back.
if lsblk -nrpo MOUNTPOINTS "$TARGET" | grep -q '[^[:space:]]'; then
    die "$TARGET 或其分区当前已挂载。请先卸载这些分区，再重新运行安装器。"
fi

DISK_BYTES=$(lsblk -bndo SIZE "$TARGET")
(( DISK_BYTES >= 8 * 1024 * 1024 * 1024 )) || die "目标磁盘至少需要 8 GiB，当前磁盘不足以容纳 Live 系统。"
DETAIL=$(lsblk -dnpo NAME,SIZE,MODEL "$TARGET")
"$DIALOG_BIN" --title "第一次确认：将清空磁盘" --yesno \
    "即将对以下磁盘重新分区并格式化：\n\n$DETAIL\n\n操作会永久删除该磁盘上的全部数据。\n\n下一步还必须输入 ERASE 才会继续。" 14 76 || exit 0
TOKEN=$("$DIALOG_BIN" --title "第二次确认" --inputbox \
    "最后确认：输入大写 ERASE 以擦除 $TARGET。\n输入其他内容将取消操作。" 10 72 3>&1 1>&2 2>&3) || exit 0
[[ "$TOKEN" == ERASE ]] || die "确认字符串不匹配，未修改磁盘。"

# Build partition names correctly for /dev/sda vs /dev/nvme0n1 and mmcblk.
if [[ "$TARGET" =~ [0-9]$ ]]; then
    ESP="${TARGET}p1"; ROOT="${TARGET}p2"
else
    ESP="${TARGET}1"; ROOT="${TARGET}2"
fi

"$DIALOG_BIN" --title "正在安装" --infobox \
    "正在建立 GPT 分区表并格式化。请勿关闭电源。" 6 62
# Two partitions: 512 MiB EFI System Partition, then ext4 root payload store.
sfdisk --wipe always --wipe-partitions always "$TARGET" <<'PARTITIONS'
label: gpt
,512M,U
,,L
PARTITIONS
blockdev --rereadpt "$TARGET"
udevadm settle
for _ in $(seq 1 20); do
    [[ -b "$ESP" && -b "$ROOT" ]] && break
    sleep 1
done
[[ -b "$ESP" && -b "$ROOT" ]] || die "分区创建后未出现预期设备：$ESP / $ROOT"
mkfs.fat -F 32 -n LFS_EFI "$ESP"
mkfs.ext4 -F -L LFS-CN "$ROOT"

mount "$ROOT" "$MNT"
mkdir -p "$MNT/live" "$MNT/boot/efi" "$MNT/upper" "$MNT/work"
mount "$ESP" "$MNT/boot/efi"
cp -v "$TMP/iso/live/rootfs.squashfs" "$MNT/live/rootfs.squashfs"
# The kernel is in the squashfs root tree; initramfs is packed later into ISO /boot.
mkdir -p "$TMP/rootfs"
mount -t squashfs -o loop,ro "$MNT/live/rootfs.squashfs" "$TMP/rootfs"
KERNEL=$(find "$TMP/rootfs/boot" -maxdepth 1 -type f -name 'vmlinuz-*-lfs-cn' -print -quit)
[[ -n "$KERNEL" ]] || die "ISO 的 squashfs 中找不到 LFS-CN 内核。"
[[ -s "$TMP/iso/boot/initramfs-lfs-cn.img" ]] || die "ISO 的 boot 目录中找不到 initramfs-lfs-cn.img。"
cp -v "$KERNEL" "$MNT/boot/vmlinuz-lfs-cn"
# The initramfs image is packed after rootfs.squashfs, so take it from the ISO boot tree.
cp -v "$TMP/iso/boot/initramfs-lfs-cn.img" "$MNT/boot/initramfs-lfs-cn.img"
umount "$TMP/rootfs"
rmdir "$TMP/rootfs"

ROOT_UUID=$(blkid -s UUID -o value "$ROOT")
[[ -n "$ROOT_UUID" ]] || die "无法读取目标 root 分区 UUID。"
mkdir -p "$MNT/boot/grub"
cat > "$MNT/boot/grub/grub.cfg" <<GRUB
set default=0
set timeout=5
insmod part_gpt
insmod fat
insmod ext2
search --no-floppy --fs-uuid --set=root $ROOT_UUID

menuentry "LFS-CN (installed Live system, persistent)" {
    linux /boot/vmlinuz-lfs-cn lfs_root=UUID=$ROOT_UUID quiet locale.LANG=C.UTF-8 locale.LC_MESSAGES=C.UTF-8
    initrd /boot/initramfs-lfs-cn.img
}
GRUB

grub-install --target=x86_64-efi --efi-directory="$MNT/boot/efi" \
    --boot-directory="$MNT/boot" --bootloader-id=LFS-CN --removable --no-nvram --recheck
sync
"$DIALOG_BIN" --title "安装完成" --msgbox \
    "LFS-CN 已安装到 $TARGET。\n\nEFI 分区：$ESP\n系统/Live 数据分区：$ROOT\n\n现在可以关闭安装器、重启并从目标磁盘启动。请在固件中选择 UEFI 启动。" 12 72
exit 0

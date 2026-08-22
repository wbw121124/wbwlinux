#!/usr/bin/env bash
# 05 - Extras: download everything on the HOST (no network tools inside the
#     chroot), then build/install inside the chroot.

set -euo pipefail
# re-exec as root if needed (GitHub hosted runners are non-root users)
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E bash "$0" "$@"
fi

cd "$(dirname "$0")"
source env.sh
source common.sh

[ "$(id -u)" -eq 0 ] || die "must run as root"

DL="$LFS_ROOT/root/downloads"
mkdir -p "$DL"

log "==> downloading extras (host side)"
declare -A urls=(
  ["node-$NODE_VER-linux-x64.tar.xz"]="$NODE_URL/node-$NODE_VER-linux-x64.tar.xz"
  ["rust-$RUST_VER-x86_64-unknown-linux-gnu.tar.xz"]="$RUST_URL/rust-$RUST_VER-x86_64-unknown-linux-gnu.tar.xz"
  ["powershell-$PWSH_VER-linux-x64.tar.gz"]="$POWERSHELL_URL/v$PWSH_VER/powershell-$PWSH_VER-linux-x64.tar.gz"
  ["nvim-linux-x86_64.tar.gz"]="$NEOVIM_URL/stable/nvim-linux-x86_64.tar.gz"
  ["icu4c-$ICU_VER-sources.tgz"]="$ICU_URL/icu4c-$ICU_VER-sources.tgz"
  ["nano-$NANO_VER.tar.xz"]="https://www.nano-editor.org/dist/v8/nano-$NANO_VER.tar.xz"
  ["freetype-$FREETYPE_VER.tar.xz"]="https://downloads.sourceforge.net/freetype/freetype-$FREETYPE_VER.tar.xz"
  ["fontconfig-$FONTCONFIG_VER.tar.xz"]="https://gitlab.freedesktop.org/api/v4/projects/890/packages/generic/fontconfig/$FONTCONFIG_VER/fontconfig-$FONTCONFIG_VER.tar.xz"
  ["fbterm-1.7.tar.gz"]="https://deb.debian.org/debian/pool/main/f/fbterm/fbterm_1.7.orig.tar.gz"
  ["wqy-microhei-0.2.0-beta.tar.gz"]="https://downloads.sourceforge.net/project/wqy/wqy-microhei/0.2.0-beta/wqy-microhei-0.2.0-beta.tar.gz"
  ["libunwind-1.6.2.tar.gz"]="https://github.com/libunwind/libunwind/releases/download/v1.6.2/libunwind-1.6.2.tar.gz"
  ["libucimf-$UCIMF_VER.tar.gz"]="https://deb.debian.org/debian/pool/main/libu/libucimf/libucimf_${UCIMF_VER}.orig.tar.gz"
  ["ucimf-openvanilla-$OV_BRIDGE_VER.tar.gz"]="https://deb.debian.org/debian/pool/main/u/ucimf-openvanilla/ucimf-openvanilla_${OV_BRIDGE_VER}.orig.tar.gz"
  ["fbterm-ucimf-$FBTERM_UCIMF_VER.tar.gz"]="https://deb.debian.org/debian/pool/main/f/fbterm-ucimf/fbterm-ucimf_${FBTERM_UCIMF_VER}.orig.tar.gz"
  ["$OV_MODULES_TARBALL"]="https://codeload.github.com/pkg-ime/openvanilla-modules/tar.gz/$OV_MODULES_COMMIT"
  ["Fira_Code_v$FIRACODE_VER.zip"]="https://github.com/tonsky/FiraCode/releases/download/$FIRACODE_VER/Fira_Code_v$FIRACODE_VER.zip"
  ["manpages-zh_${MANPAGES_ZH_VER}_all.deb"]="https://deb.debian.org/debian/pool/main/m/manpages-zh/manpages-zh_${MANPAGES_ZH_VER}_all.deb"
)
declare -A mirrors=(
  ["node-$NODE_VER-linux-x64.tar.xz"]="https://registry.npmmirror.com/-/binary/node/$NODE_VER/node-$NODE_VER-linux-x64.tar.xz"
  ["fbterm-1.7.tar.gz"]="https://archive.ubuntu.com/ubuntu/pool/universe/f/fbterm/fbterm_1.7.orig.tar.gz"
)

download_with_retry() {
    local f="$1" u="$2" n
    for n in 1 2 3; do
        log "    attempt $n: $u"
        if curl -fSL --retry 1 -o "$DL/$f" "$u" && [ -s "$DL/$f" ]; then
            return 0
        fi
        rm -f "$DL/$f"
        sleep 3
    done
    return 1
}

for f in "${!urls[@]}"; do
    if [ ! -s "$DL/$f" ]; then
        log "==> downloading $f"
        if ! download_with_retry "$f" "${urls[$f]}" \
            && { [ -z "${mirrors[$f]:-}" ] || ! download_with_retry "$f" "${mirrors[$f]}"; }; then
            die "download failed after retries: $f"
        fi
    fi
done
log "==> extras downloaded: $(ls "$DL" | wc -l) files"

# ---- run the install inside the chroot ------------------------------
umount_kernfs || true
mount_kernfs

mkdir -p "$LFS_ROOT/build/chroot"
cp -v env.sh common.sh "$LFS_ROOT/build/"
cp -v chroot/05-extras.sh "$LFS_ROOT/build/chroot/"

chroot "$LFS_ROOT" /usr/bin/env -i \
    HOME=/root TERM="$TERM" PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin \
    MAKEFLAGS="$MAKEFLAGS" \
    /bin/bash --login /build/chroot/05-extras.sh

touch "$LFS_ROOT/opt/.extras-complete"
log "==> extras complete"

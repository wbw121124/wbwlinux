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
  ["nvim-$NVIM_VER.tar.gz"]="$NEOVIM_URL/v$NVIM_VER.tar.gz"
  ["cmake-$CMAKE_VER-linux-x86_64.tar.gz"]="https://github.com/Kitware/CMake/releases/download/v$CMAKE_VER/cmake-$CMAKE_VER-linux-x86_64.tar.gz"
  ["lua-$LUA_VER.tar.gz"]="https://www.lua.org/ftp/lua-$LUA_VER.tar.gz"
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
  # ninja has no source asset in its releases -> tag auto-archive
  ["ninja-$NINJA_VER.tar.gz"]="https://github.com/ninja-build/ninja/archive/refs/tags/v$NINJA_VER.tar.gz"
  ["meson-$MESON_VER.tar.gz"]="https://github.com/MesonBuild/meson/releases/download/$MESON_VER/meson-$MESON_VER.tar.gz"
  ["curl-$CURL_VER.tar.xz"]="https://curl.se/download/curl-$CURL_VER.tar.xz"
  ["libarchive-$LIBARCHIVE_VER.tar.xz"]="https://github.com/libarchive/libarchive/releases/download/v$LIBARCHIVE_VER/libarchive-$LIBARCHIVE_VER.tar.xz"
  ["pacman-$PACMAN_VER.tar.xz"]="https://gitlab.archlinux.org/pacman/pacman/-/releases/v$PACMAN_VER/downloads/pacman-$PACMAN_VER.tar.xz"
  # CLI tool bundle: fd/rg/bat official musl static binaries, htop Debian
  # prebuilt, wget GNU source (versions verified 2026-08-23).
  # KEYS MUST BE THE EXACT FILENAMES chroot/05-extras.sh opens - use the
  # upstream release asset names verbatim (root cause #26: saving under a
  # shortened key while the chroot script expected the asset name made tar
  # fail with ENOENT)
  ["fd-v$FD_VER-x86_64-unknown-linux-musl.tar.gz"]="https://github.com/sharkdp/fd/releases/download/v$FD_VER/fd-v$FD_VER-x86_64-unknown-linux-musl.tar.gz"
  ["ripgrep-$RIPGREP_VER-x86_64-unknown-linux-musl.tar.gz"]="https://github.com/BurntSushi/ripgrep/releases/download/$RIPGREP_VER/ripgrep-$RIPGREP_VER-x86_64-unknown-linux-musl.tar.gz"
  ["bat-v$BAT_VER-x86_64-unknown-linux-musl.tar.gz"]="https://github.com/sharkdp/bat/releases/download/v$BAT_VER/bat-v$BAT_VER-x86_64-unknown-linux-musl.tar.gz"
  ["htop-$HTOP_VER.tar.xz"]="https://github.com/htop-dev/htop/releases/download/$HTOP_VER/htop-$HTOP_VER.tar.xz"
  ["wget-$WGET_VER.tar.gz"]="https://ftp.gnu.org/gnu/wget/wget-$WGET_VER.tar.gz"
  ["sudo-$SUDO_VER.tar.gz"]="https://www.sudo.ws/dist/sudo-$SUDO_VER.tar.gz"
  ["git-$GIT_VER.tar.xz"]="https://mirrors.edge.kernel.org/pub/software/scm/git/git-$GIT_VER.tar.xz"
  # Firefox (prebuilt binary; packaged but not installed by default)
  ["firefox-$FIREFOX_VER.tar.xz"]="https://download-installer.cdn.mozilla.net/pub/firefox/releases/$FIREFOX_VER/linux-x86_64/en-US/firefox-$FIREFOX_VER.tar.xz"
  # NetworkManager (prebuilt from Arch core repo; pacman 7.1 needs it for Wi-Fi)
  ["networkmanager-$NM_VER-1-x86_64.pkg.tar.zst"]="https://geo.mirror.pkgbuild.com/extra/os/x86_64/networkmanager-$NM_VER-1-x86_64.pkg.tar.zst"
  # Rea-Dark XFCE theme (orchyn/XFCE, pinned to commit)
  ["orchyn-XFCE-main.tar.gz"]="https://codeload.github.com/orchyn/XFCE/tar.gz/$REA_COMMIT"
  # Yaru theme (Ubuntu 26.04 LTS, pinned to tag)
  ["yaru-${YARU_VER}.tar.gz"]="https://codeload.github.com/ubuntu/yaru/tar.gz/${YARU_COMMIT}"
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
cp -v chroot/05-extras.sh chroot/06-xorg-xfce.sh chroot/07-packages.sh \
      chroot/arch-resolve.py chroot/arch-resolve-fcitx5.py \
      chroot/ovimgeneric.patch chroot/zhuyin.cin \
      "$LFS_ROOT/build/chroot/"
cp -v chroot/zhuyin.cin "$LFS_ROOT/build/zhuyin.cin"

chroot "$LFS_ROOT" /usr/bin/env -i \
    HOME=/root TERM="$TERM" PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin:/usr/local/bin \
    MAKEFLAGS="$MAKEFLAGS" \
    /bin/bash --login /build/chroot/05-extras.sh

# X.Org + XFCE from the Arch binary repos (needs curl/zstd/python3 from
# the extras run just above); baked into the squashfs, startx -> XFCE
chroot "$LFS_ROOT" /usr/bin/env -i \
    HOME=/root TERM="$TERM" PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin:/usr/local/bin \
    /bin/bash --login /build/chroot/06-xorg-xfce.sh

touch "$LFS_ROOT/opt/.extras-complete"
log "==> extras complete"

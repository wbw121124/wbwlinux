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

# Pre-download sassc/libsass for the Yaru build (root cause #57): the
# config snapshot may predate these entries in the extras download map.
for pair in "libsass-$LIBSASS_VER|https://github.com/sass/libsass/archive/refs/tags/$LIBSASS_VER.tar.gz" \
            "sassc-$SASSC_VER|https://github.com/sass/sassc/archive/refs/tags/$SASSC_VER.tar.gz" \
            "astroterm-linux-x86_64|https://github.com/da-luce/astroterm/releases/download/$ASTROTERM_VER/astroterm-linux-x86_64" \
            "expat-$EXPAT_VER|https://github.com/libexpat/libexpat/releases/download/R_${EXPAT_VER//./_}/expat-$EXPAT_VER.tar.gz" \
            "typst-x86_64-unknown-linux-musl|https://github.com/typst/typst/releases/download/$TYPST_VER/typst-x86_64-unknown-linux-musl.tar.xz" \
            "tdf-$TDF_VER|https://codeload.github.com/itsjunetime/tdf/tar.gz/$TDF_VER" \
            "tmux-$TMUX_VER|https://github.com/tmux/tmux/releases/download/$TMUX_VER/tmux-$TMUX_VER.tar.gz" \
            "libevent-$LIBEVENT_VER|https://github.com/libevent/libevent/releases/download/release-$LIBEVENT_VER/libevent-$LIBEVENT_VER.tar.gz" \
            "go$GO_VER.linux-amd64.tar.gz|$GO_URL/go$GO_VER.linux-amd64.tar.gz"; do
    name="${pair%%|*}"; url="${pair#*|}"
    tgt="$LFS_ROOT/root/downloads/$name"
    if [ ! -f "$tgt" ]; then
        log "==> downloading $name"
        curl -fSL --retry 3 --max-time 240 -o "$tgt" "$url" \
            || warn "$name download failed - related package will be skipped"
    fi
done

umount_kernfs || true
mount_kernfs

mkdir -p "$LFS_ROOT/build/chroot"
cp -v env.sh common.sh "$LFS_ROOT/build/"
cp -v chroot/07-packages.sh chroot/arch-resolve-fcitx5.py \
      chroot/arch-resolve.py \
      "$LFS_ROOT/build/chroot/"

chroot "$LFS_ROOT" /usr/bin/env -i \
    HOME=/root TERM="$TERM" PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin:/usr/local/bin \
    /bin/bash --login /build/chroot/07-packages.sh

# Hard self-check: chroot writes /pkgrepo which is $LFS_ROOT/pkgrepo here.
[ -d "$LFS_ROOT/pkgrepo" ] || die "packages: $LFS_ROOT/pkgrepo missing after build (chroot wrote to a wrong path?)"
[ -n "$(ls -A "$LFS_ROOT/pkgrepo")" ] || die "packages: $LFS_ROOT/pkgrepo is empty (no packages produced)"
log "==> packages build complete (host wrapper); repo contents:"
ls -lh "$LFS_ROOT/pkgrepo/"

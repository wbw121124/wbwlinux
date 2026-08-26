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

# Pre-download VS Code tarball into $LFS_ROOT/root/downloads so the chroot
# can find it at /root/downloads/code-$VSCODE_VER-linux-x64.tar.gz.
mkdir -p "$LFS_ROOT/root/downloads"
VS_DL="$LFS_ROOT/root/downloads/code-$VSCODE_VER-linux-x64.tar.gz"
if [ ! -f "$VS_DL" ]; then
    log "==> downloading VS Code $VSCODE_VER"
    curl -fSL --retry 3 --max-time 300 \
        -o "$VS_DL" \
        "https://update.code.visualstudio.com/$VSCODE_VER/linux-x64/stable" \
        || warn "VS Code download failed — build_vscode will skip"
fi

# Pre-download sassc/libsass for the Yaru build (root cause #57): the
# config snapshot may predate these entries in the extras download map.
for pair in "libsass-$LIBSASS_VER|https://github.com/sass/libsass/archive/refs/tags/$LIBSASS_VER.tar.gz" \
            "sassc-$SASSC_VER|https://github.com/sass/sassc/archive/refs/tags/$SASSC_VER.tar.gz"; do
    name="${pair%%|*}"; url="${pair#*|}"
    tgt="$LFS_ROOT/root/downloads/$name.tar.gz"
    if [ ! -f "$tgt" ]; then
        log "==> downloading $name"
        curl -fSL --retry 3 --max-time 180 -o "$tgt" "$url" \
            || warn "$name download failed — Yaru build will fail to configure"
    fi
done

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

# Hard self-check: chroot writes /pkgrepo which is $LFS_ROOT/pkgrepo here.
[ -d "$LFS_ROOT/pkgrepo" ] || die "packages: $LFS_ROOT/pkgrepo missing after build (chroot wrote to a wrong path?)"
[ -n "$(ls -A "$LFS_ROOT/pkgrepo")" ] || die "packages: $LFS_ROOT/pkgrepo is empty (no packages produced)"
log "==> packages build complete (host wrapper); repo contents:"
ls -lh "$LFS_ROOT/pkgrepo/"

#!/usr/bin/env bash
# Runs INSIDE the LFS chroot, AFTER chroot/05-extras.sh (needs curl, zstd,
# python3). Imports the X.Org + XFCE stack from the Arch Linux BINARY
# repositories - no compilation - WITHOUT letting pacman touch the system:
#
#   1. download fresh {core,extra}.db repo indexes,
#   2. arch-resolve.py computes the dependency closure of a fixed seed
#      set, treating everything LFS already provides as satisfied, so
#      Arch's glibc/gcc-libs/coreutils are NEVER pulled (the guardrail
#      behind README's "Arch repos stay disabled"),
#   3. each package archive is extracted straight into / with GNU tar's
#      --skip-old-files: any path that already exists stays LFS-owned;
#      only genuinely new files land. New libs link against our glibc
#      fine (ELF symbol versioning is backward compatible).
#
# The result is baked into the squashfs: boot -> tty1 -> startx -> XFCE.
set -euo pipefail
export SOURCES=/sources
export SCRIPTS_DIR=/build
export STAGES_DIR=/build/stages
export CONFIG_DIR=/config
source /build/env.sh
source /build/common.sh

[ "$(uname -m)" = "x86_64" ] || die "arch-import: x86_64 only"
command -v curl >/dev/null || die "arch-import: curl missing (extras must run first)"
command -v python3 >/dev/null || die "arch-import: python3 missing"

WORK=/tmp/arch-import
rm -rf "$WORK"
mkdir -p "$WORK/db"

free_mb=$(df -Pm / | awk 'NR==2{print $4}')
log "==> arch-import: ${free_mb}MB free on /"
[ "$free_mb" -gt 3000 ] || die "arch-import: need >3000MB free, have ${free_mb}MB"

fetch() { # fetch <repo-relative-url> <outfile>
    local u="$1" o="$2" m
    for m in $ARCH_MIRRORS; do
        log "    try $m/$u"
        if curl -kfSL --retry 2 --max-time 900 -o "$o" "$m/$u" && [ -s "$o" ]; then
            return 0
        fi
        rm -f "$o"
    done
    return 1
}

log '==> downloading Arch repo databases'
for repo in core extra; do
    fetch "$repo/os/x86_64/$repo.db" "$WORK/db/$repo.db" \
        || die "arch-import: cannot download $repo.db from any mirror"
done

log '==> resolving dependency closure'
python3 "$SCRIPTS_DIR/chroot/arch-resolve.py" "$WORK/db" "$WORK" \
    > "$WORK/resolve.log" 2>&1 || { cat "$WORK/resolve.log"; die "arch-import: resolver failed"; }
cat "$WORK/summary.txt" || true
grep '^WARN' "$WORK/resolve.log" || true

total=$(wc -l < "$WORK/dl.txt")
[ "$total" -gt 50 ] || die "arch-import: suspiciously small closure ($total pkgs)"

log "==> downloading+extracting $total Arch binary packages (--skip-old-files)"
n=0
while read -r repo filename; do
    [ -n "$filename" ] || continue
    n=$((n + 1))
    if ! fetch "$repo/os/x86_64/$filename" "$WORK/pkg"; then
        die "arch-import: download failed: $repo/$filename"
    fi
    if ! tar --zstd -xf "$WORK/pkg" -C / --skip-old-files \
            --exclude=.PKGINFO --exclude=.MTREE \
            --exclude=.INSTALL --exclude=.BUILDINFO 2> "$WORK/tar.err"; then
        # hard errors other than "file already exists" are fatal
        grep -v -e 'Skipping' -e 'existing' "$WORK/tar.err" | grep . \
            && die "arch-import: extraction failed for $filename" || true
    fi
    rm -f "$WORK/pkg"
    [ $((n % 25)) -eq 0 ] && log "    $n/$total done"
done < "$WORK/dl.txt"
log "==> extracted $total packages"

# ---------------------------------------------------------------------
# refresh every cache the GUI stack depends on (binaries came from the
# extraction above, so ldconfig MUST come first)
# ---------------------------------------------------------------------
log '==> running post-install cache refreshes'
ldconfig
/usr/bin/glib-compile-schemas /usr/share/glib-2.0/schemas 2>/dev/null || warn "glib schemas compile failed"
if [ -x /usr/bin/gdk-pixbuf-query-loaders ]; then
    gdk-pixbuf-query-loaders --update-cache >/dev/null 2>&1 || warn "gdk-pixbuf loader cache failed"
fi
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q || true
if [ -d /usr/share/mime ]; then
    update-mime-database /usr/share/mime >/dev/null 2>&1 || true
fi
fc-cache -f >/dev/null 2>&1 || true
for d in /usr/share/icons/*/; do
    [ -d "$d" ] && gtk-update-icon-cache -qtf "$d" >/dev/null 2>&1 || true
done

# ---------------------------------------------------------------------
# session bootstrap: startx reads ~/.xinitrc
# ---------------------------------------------------------------------
cat > /root/.xinitrc << 'EOF'
# XFCE via startx; dbus-launch supplies the session bus when available
if command -v dbus-launch >/dev/null 2>&1; then
    exec dbus-launch --exit-with-session startxfce4
fi
exec startxfce4
EOF
chmod 755 /root/.xinitrc

# ---------------------------------------------------------------------
# hard self-check: a half-imported GUI stack must fail the build
# ---------------------------------------------------------------------
for f in /usr/bin/Xorg /usr/bin/startx /usr/bin/xinit \
         /usr/bin/startxfce4 /usr/bin/xfwm4 /usr/bin/xfce4-panel \
         /usr/lib/libX11.so.6 /usr/lib/libgtk-3.so.0; do
    [ -e "$f" ] || die "arch-import self-check: missing $f"
done

rm -rf "$WORK"
log '==> X.Org + XFCE imported (startx starts an XFCE session)'

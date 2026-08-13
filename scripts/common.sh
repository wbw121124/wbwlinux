# Common helpers for LFS-CN stage scripts. Source after env.sh.

log()   { echo "[$(date +%H:%M:%S)] $*"; }
die()   { log "ERROR: $*"; exit 1; }
warn()  { echo "[$(date +%H:%M:%S)] WARN: $*" >&2; }

# Strip ANSI color escapes from build logs (already plain on runners).
running_in_chroot() { [ "$(stat -c %d:%i / 2>/dev/null)" != "$(stat -c %d:%i /proc/1/root/. 2>/dev/null)" ]; }

# ---------------------------------------------------------------------------
# pkg_run '<extract-dir>' <<'CMD'
#   Run one LFS package build block. Executes the heredoc inside the package
#   build directory under /sources, extracting the tarball first and cleaning
#   up afterwards. Works both on the host (S=$LFS_ROOT/sources) and inside the
#   chroot (S=/sources).
# ---------------------------------------------------------------------------
pkg_run() {
    local dir="${1:-}"
    local body
    body="$(cat)"
    [ -n "$dir" ] || die "pkg_run requires an extract directory name"
    local tarball
    tarball="$(find "$SOURCES" -maxdepth 1 -name "$dir.tar.*" | head -1 || true)"
    [ -n "$tarball" ] || die "tarball for '$dir' not found in $SOURCES"
    log "==> build $dir"
    (
        cd "$SOURCES"
        rm -rf "$dir"
        tar xf "$tarball"
        cd "$dir"
        bash -c "$body"
    )
    local rc=$?
    rm -rf "$SOURCES/$dir"
    [ $rc -eq 0 ] || die "build of '$dir' failed (rc=$rc)"
}

# ---------------------------------------------------------------------------
# shell_run <<'CMD'
#   Run a bare command block (directory setup, config files, cleanup) from the
#   /sources directory (tzdata-style '../../foo' references resolve to it).
# ---------------------------------------------------------------------------
shell_run() {
    local body
    body="$(cat)"
    log "==> run: $(echo "$body" | head -1 | cut -c1-100)"
    ( cd "$SOURCES" && bash -c "$body" )
}

# ---------------------------------------------------------------------------
# chroot_wrap <<'CMD'
#   Execute the heredoc inside the LFS chroot.
# ---------------------------------------------------------------------------
chroot_wrap() {
    local body
    body="$(cat)"
    log "==> chroot: $(echo "$body" | head -1 | cut -c1-100)"
    chroot "$LFS_ROOT" /usr/bin/env -i \
        HOME=/root TERM="$TERM" PS1='(lfs) \u:\w\$ ' \
        PATH=/usr/bin:/usr/sbin \
        MAKEFLAGS="$MAKEFLAGS" \
        /bin/bash --login -c "$body"
}

# ---------------------------------------------------------------------------
# Snapshots: tar.zst of $LFS_ROOT, split into fixed-size parts for GitHub
# Actions artifact upload (free-plan single-file limits), streamed so no
# extra disk space is needed.
# ---------------------------------------------------------------------------
export ARTIFACTS_DIR="$(dirname "$SCRIPTS_DIR")/.artifacts"
export SNAP_PART_SIZE="${SNAP_PART_SIZE:-450M}"

snapshot() {
    local name="${1:?usage: snapshot <name>}"
    mkdir -p "$ARTIFACTS_DIR"
    rm -f "$ARTIFACTS_DIR/$name.tar.zst.part-"*
    log "==> snapshot $LFS_ROOT -> $ARTIFACTS_DIR/$name.tar.zst.part-* ($SNAP_PART_SIZE each)"
    tar --zstd -C / --exclude=proc --exclude=sys --exclude=dev --exclude=run \
        -cf - "${LFS_ROOT#/}" |
        split -b "$SNAP_PART_SIZE" -d -a 3 - "$ARTIFACTS_DIR/$name.tar.zst.part-"
    local total=0
    for p in "$ARTIFACTS_DIR/$name.tar.zst.part-"*; do
        total=$((total + $(stat -c %s "$p")))
    done
    log "==> snapshot done: $(ls "$ARTIFACTS_DIR/$name.tar.zst.part-"* | wc -l) parts, $(numfmt --to=iec-i $total)"
}

restore() {
    local name="${1:?usage: restore <name>}"
    local first="$ARTIFACTS_DIR/$name.tar.zst.part-000"
    [ -f "$first" ] || die "snapshot $name not found (expected $first)"
    log "==> restore $name (parts $(ls "$ARTIFACTS_DIR/$name.tar.zst.part-"* | wc -l)) -> /"
    mkdir -p "$LFS_ROOT"
    cat "$ARTIFACTS_DIR/$name.tar.zst.part-"* | tar --zstd -C / -xf -
    log "==> restore done"
}

# ---------------------------------------------------------------------------
# Mount/unmount the virtual filesystems for the chroot (7.3).
# ---------------------------------------------------------------------------
mount_kernfs() {
    mkdir -pv "$LFS_ROOT"/{dev,proc,sys,run}
    mount --bind /dev "$LFS_ROOT/dev"
    mount --bind /dev/pts "$LFS_ROOT/dev/pts"
    mount --bind /proc "$LFS_ROOT/proc"
    mount --bind /sys "$LFS_ROOT/sys"
    mount --bind /run "$LFS_ROOT/run"
    if [ -h "$LFS_ROOT/dev/shm" ]; then
        mkdir -pv "$LFS_ROOT/$(readlink "$LFS_ROOT/dev/shm")"
    else
        mount --bind /dev/shm "$LFS_ROOT/dev/shm"
    fi
}

umount_kernfs() {
    for d in dev/pts dev/shm dev run proc sys; do
        mountpoint -q "$LFS_ROOT/$d" && umount "$LFS_ROOT/$d" || true
    done
}

# ---------------------------------------------------------------------------
# CLI entry for the workflow: bash common.sh --snapshot <name>
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--snapshot" ] || [ "${1:-}" = "--restore" ]; then
    if [ "$(id -u)" -ne 0 ]; then
        exec sudo -E bash "$0" "$@"
    fi
    source "$(dirname "$0")/env.sh"
    if [ "${1:-}" = "--snapshot" ]; then
        snapshot "${2:?}"
    else
        restore "${2:?}"
    fi
fi

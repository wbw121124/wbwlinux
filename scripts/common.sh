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
    local rc=0
    (
        cd "$SOURCES"
        rm -rf "$dir"
        tar xf "$tarball"
        if [ ! -d "$dir" ]; then
            top="$(tar -tf "$tarball" 2>/dev/null | awk -F/ 'NF>1{print $1; exit}')"
            [ -n "$top" ] && [ -d "$top" ] && mv "$top" "$dir"
        fi
        cd "$dir"
        bash -e -c "$body"
    ) || rc=$?
    if [ $rc -ne 0 ]; then
        mkdir -p "$SOURCES/.diag"
        find "$SOURCES/$dir" -maxdepth 3 -name config.log 2>/dev/null | while read -r f; do
            rel=${f#"$SOURCES/$dir"/}
            cp -v "$f" "$SOURCES/.diag/$dir--${rel//\//__}.config.log" || true
            echo "===== config.log: $f ====="
            grep -n -B6 -A45 -m1 'cannot run C compiled programs' "$f" || true
            echo "===== end $f ====="
        done
        df -h "$SOURCES" || true
        mount | grep -E 'sources|/mnt/lfs' || true
        rm -rf "$SOURCES/$dir"
        die "build of '$dir' failed (rc=$rc); see $SOURCES/.diag/"
    fi
    rm -rf "$SOURCES/$dir"
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
    local rc=0
    ( cd "$SOURCES" && bash -e -c "$body" ) || rc=$?
    [ $rc -eq 0 ] || die "shell_run block failed (rc=$rc)"
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
        /bin/bash --login -e -c "$body"
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
    tar --zstd -C / \
        --exclude="${LFS_ROOT#/}/proc" \
        --exclude="${LFS_ROOT#/}/sys" \
        --exclude="${LFS_ROOT#/}/dev" \
        --exclude="${LFS_ROOT#/}/run" \
        --exclude="${LFS_ROOT#/}/ccache" \
        --exclude="${LFS_ROOT#/}/ccache-wrap" \
        -cf - "${LFS_ROOT#/}" |
        split -b "$SNAP_PART_SIZE" -d -a 3 - "$ARTIFACTS_DIR/$name.tar.zst.part-"
    local total=0
    local parts=0
    for p in "$ARTIFACTS_DIR/$name.tar.zst.part-"*; do
        [ -e "$p" ] || break
        parts=$((parts + 1))
        total=$((total + $(stat -c %s "$p")))
    done
    [ "$parts" -gt 0 ] || die "snapshot '$name' produced no parts (tar|split failed?)"
    log "==> snapshot done: $parts parts, $(numfmt --to=iec-i $total)"
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
    # SCRIPTS_DIR is only set by env.sh; the top-level export above ran too
    # early and produced a relative path. Re-resolve to an absolute path.
    export ARTIFACTS_DIR="$(dirname "$SCRIPTS_DIR")/.artifacts"
    if [ "${1:-}" = "--snapshot" ]; then
        snapshot "${2:?}"
    else
        restore "${2:?}"
    fi
fi

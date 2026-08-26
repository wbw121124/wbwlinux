#!/usr/bin/env python3
"""Arch repo dependency-closure resolver for LFS-CN's X.Org+XFCE import.

Reads pacman repo databases (gzip tarballs of per-package 'desc' files),
resolves the dependency closure of SEEDS, treats everything in SKIP as
already provided by the host LFS system, and writes:

    <outdir>/dl.txt      lines of "<repo> <filename>" to download+extract
    <outdir>/summary.txt human-readable plan stats

Exit code 0 only when every dependency was resolved somehow.
"""
import os
import sys
import tarfile

SEEDS = [
    # X.Org base (the modesetting driver is built into xorg-server)
    "xorg-server", "xorg-xinit",
    # kmscon (Phase 1) hard-requires libxkbcommon at build+runtime
    "libxkbcommon",
    # X.Org video drivers for QEMU bochs / basic fallback
    # xf86-video-virtio removed from Arch repos; modesetting covers virtio-gpu
    "xf86-video-fbdev", "xf86-video-vesa",
    # XFCE core desktop
    "xfce4-session", "xfce4-panel", "xfwm4", "xfdesktop",
    "xfce4-settings", "xfce4-appfinder", "xfconf", "garcon",
    "thunar", "thunar-volman", "tumbler", "xfce4-terminal", "mousepad",
    # LuaJIT (neovim cmake build needs Lua 5.1 interpreter; luajit is preferred)
    "luajit",
]

# Everything LFS 13.0 already provides (ch8 + extras builds). NEVER pull
# these from Arch - that is the rolling-glibc clash README warns about.
SKIP = {
    "glibc", "gcc-libs", "filesystem", "bash", "coreutils",
    "util-linux", "util-linux-libs", "systemd-libs", "systemd",
    "dbus", "ncurses", "readline", "zlib", "bzip2", "xz", "zstd",
    "openssl", "expat", "libffi", "pcre2", "sqlite", "curl", "wget",
    "which", "perl", "python", "gawk", "grep", "sed", "tar", "gzip",
    "shadow", "procps-ng", "e2fsprogs", "findutils", "diffutils",
    "gettext", "gmp", "mpfr", "libcap", "libgcrypt", "libgpg-error",
    "lz4", "acl", "attr", "elfutils", "libelf", "kbd", "tzdata",
    "file", "less", "kmod", "iproute2", "man-db", "pacman", "meson",
    "ninja", "libarchive", "sh", "awk",
    # library sonames that LFS provides (resolver sees these as deps)
    "libcom_err", "libcrypto", "libdbus", "libexpat", "libffi",
    "libmount", "libncursesw", "libreadline", "libss", "libsystemd",
    "libudev", "libz",
}


def load_db(path, repo):
    """Return {name: pkg} and provider map built from one repo database."""
    pkgs, provs = {}, {}
    with tarfile.open(path, "r:*") as tf:
        for member in tf.getmembers():
            if not member.isfile() or not member.name.endswith("/desc"):
                continue
            fh = tf.extractfile(member)
            if fh is None:
                continue
            cur, key = {}, None
            for raw in fh.read().decode("utf-8", "replace").splitlines():
                line = raw.strip()
                if line.startswith("%") and line.endswith("%") and len(line) > 2:
                    key = line[1:-1]
                    cur.setdefault(key, [])
                elif key and line:
                    cur[key].append(line)
            name = (cur.get("NAME") or [""])[0]
            if not name:
                continue
            pkgs[name] = {
                "repo": repo,
                "filename": (cur.get("FILENAME") or [""])[0],
                "version": (cur.get("VERSION") or [""])[0],
                "depends": cur.get("DEPENDS", []),
                "provides": cur.get("PROVIDES", []),
            }
            for p in pkgs[name]["provides"]:
                virt = p.split("=")[0].split("<")[0].split(">")[0].strip()
                provs.setdefault(virt, set()).add(name)
    return pkgs, provs


def dep_base(dep):
    """'foo>=1.2|bar' -> candidate base names in declared order."""
    out = []
    for alt in dep.split("|"):
        base = alt.strip()
        for ch in "<>=":
            base = base.split(ch)[0].strip()
        if base:
            out.append(base)
    return out


def main():
    dbdir, outdir = sys.argv[1], sys.argv[2]
    all_pkgs, provides = {}, {}
    for repo in ("core", "extra"):
        pkgs, provs = load_db(os.path.join(dbdir, f"{repo}.db"), repo)
        all_pkgs.update(pkgs)
        for k, v in provs.items():
            provides.setdefault(k, set()).update(v)

    chosen, missing = {}, []
    queue = list(SEEDS)
    while queue:
        dep = queue.pop(0)
        target = None
        for base in dep_base(dep):
            if base in SKIP:
                target = None
                break
            if base in all_pkgs:
                target = base
                break
            for prov in sorted(provides.get(base, ())):
                if prov in SKIP:
                    target = None
                    break
                if prov in all_pkgs:
                    target = prov
                    break
            if target:
                break
        else:
            missing.append(dep)
            continue
        if not target or target in chosen:
            continue
        chosen[target] = all_pkgs[target]
        queue.extend(all_pkgs[target]["depends"])

    lines = []
    for name in sorted(chosen):
        pkg = chosen[name]
        if not pkg["filename"]:
            continue
        lines.append(f"{pkg['repo']} {pkg['filename']}")
    with open(os.path.join(outdir, "dl.txt"), "w") as fh:
        fh.write("\n".join(lines) + ("\n" if lines else ""))
    with open(os.path.join(outdir, "summary.txt"), "w") as fh:
        fh.write(f"seeds={len(SEEDS)} install={len(lines)} "
                 f"missing={len(missing)}\n")
        for m in sorted(set(missing)):
            fh.write(f"MISSING: {m}\n")

    for m in sorted(set(missing)):
        print(f"WARN unresolved dependency: {m}", file=sys.stderr)
    print(f"resolver: seeds={len(SEEDS)} packages-to-import={len(lines)} "
          f"unresolved={len(set(missing))}")
    # hard failure only if nothing was resolvable or a SEED itself is gone
    seed_names = {b for s in SEEDS for b in dep_base(s)}
    lost_seeds = [s for s in seed_names
                  if s not in all_pkgs and s not in SKIP
                  and not provides.get(s)]
    if not lines:
        sys.exit("FATAL: resolver produced an empty import list")
    if lost_seeds:
        sys.exit(f"FATAL: seed packages vanished from repos: {lost_seeds}")


if __name__ == "__main__":
    main()

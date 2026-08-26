#!/usr/bin/env python3
"""Arch repo dependency-closure resolver for fcitx5 input method stack.

Same approach as arch-resolve.py but with fcitx5-specific seeds and SKIP set.
Reads pacman repo databases, resolves the dependency closure of SEEDS,
treats everything in SKIP as already provided by the host LFS system, and
writes:

    <outdir>/dl.txt      lines of "<repo> <filename>" to download+extract
    <outdir>/summary.txt human-readable plan stats

Exit code 0 only when every dependency was resolved somehow.
"""
import os
import sys
import tarfile

SEEDS = [
    "fcitx5",
    "fcitx5-gtk",
    "fcitx5-chinese-addons",
]

# Everything LFS 13.0 already provides (ch8 + extras + xorg-xfce imports).
# NEVER pull these from Arch.
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
    # library sonames that LFS provides
    "libcom_err", "libcrypto", "libdbus", "libexpat", "libffi",
    "libmount", "libncursesw", "libreadline", "libss", "libsystemd",
    "libudev", "libz",
    # X.Org / GTK / GLib already imported from Arch by 06-xorg-xfce.sh
    "libx11", "libxkbcommon", "libxkbcommon-x11", "libxcb",
    "libxinerama", "libxrandr", "libxext", "libxfixes", "libxi",
    "libxtst", "libxrender", "libxcomposite", "libxdamage",
    "gtk3", "gtk4", "glib2", "pango", "cairo", "harfbuzz", "fribidi",
    "gdk-pixbuf", "atk", "at-spi2-core", "at-spi2-atk",
    "hicolor-icon-theme", "adwaita-icon-theme",
    "shared-mime-info", "desktop-file-utils",
    "fontconfig", "freetype2", "libjpeg-turbo", "libpng", "libtiff",
    "libwebp", "librsvg", "libxml2", "libxslt",
    "icu",
    "wayland", "libinput", "libudev", "mtdev", "libwacom",
    "xorg-server", "xorg-xinit", "xfce4-session", "xfce4-panel",
    "xfwm4", "xfdesktop", "xfce4-settings", "xfce4-appfinder",
    "xfconf", "garcon", "thunar", "thunar-volman", "tumbler",
    "xfce4-terminal", "mousepad",
    # luajit (already built by extras)
    "luajit",
    # cmake / extra-cmake-modules (if already available)
    "cmake",
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


def skip_hit(base):
    """True when base (or its soname stem) is provided by LFS itself.

    Arch lists shared-library deps as 'libcrypto.so=3-64'; dep_base()
    yields 'libcrypto.so' while SKIP stores the plain name 'libcrypto'
    (root cause #58: 12 bogus MISSING warnings per run).
    """
    if base in SKIP:
        return True
    return base.endswith(".so") and base[:-3] in SKIP


def main():
    dbdir, outdir = sys.argv[1], sys.argv[2]
    # Optional third arg: comma-separated extra seeds (e.g. "nss,nspr" for VS Code deps)
    extra = sys.argv[3].split(",") if len(sys.argv) > 3 and sys.argv[3] else []
    all_pkgs, provides = {}, {}
    for repo in ("core", "extra"):
        db_path = os.path.join(dbdir, f"{repo}.db")
        if not os.path.exists(db_path):
            continue
        pkgs, provs = load_db(db_path, repo)
        all_pkgs.update(pkgs)
        for k, v in provs.items():
            provides.setdefault(k, set()).update(v)

    chosen, missing = {}, []
    queue = list(SEEDS) + extra
    while queue:
        dep = queue.pop(0)
        target = None
        for base in dep_base(dep):
            if skip_hit(base):
                target = None
                break
            if base in all_pkgs:
                target = base
                break
            for prov in sorted(provides.get(base, ())):
                if skip_hit(prov):
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
    print(f"fcitx5 resolver: seeds={len(SEEDS)} packages-to-import={len(lines)} "
          f"unresolved={len(set(missing))}")
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

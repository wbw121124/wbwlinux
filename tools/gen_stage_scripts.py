#!/usr/bin/env python3
"""Generate build stage scripts from the LFS 13.0 NOCHUNKS.html book.

Output:
  stages/10-host-stage.sh    ch5 (host) + ch6 (host) package blocks
  stages/20-chroot-stage.sh  ch7.5-7.13 (chroot) package blocks
  stages/30-ch8-stage.sh     ch8 basic system (chroot) package blocks
  stages/40-ch9-stage.sh     ch9 configuration (chroot) command blocks
"""
import html
import re
import sys
from pathlib import Path

PRE_RE = re.compile(r"<pre\s+class=\"userinput\">(.*?)</pre>", re.DOTALL | re.IGNORECASE)
KBD_RE = re.compile(r"<kbd\b[^>]*>(.*?)</kbd>", re.DOTALL | re.IGNORECASE)
TITLE_RE = re.compile(
    r"<h[23]\b[^>]*>\s*<a\b[^>]*id=\"([^\"]+)\"[^>]*>.*?</a>\s*([^<]+?)\s*</h[23]>",
    re.DOTALL,
)
DL_RE = re.compile(r"Download \(HTTP\):\s*<a\s+class=\"ulink\"\s+href=\"([^\"]+)\"", re.DOTALL)

TEST_HINTS = (
    "to test the results",
    "test the results",
    "to check the results",
    "check the results",
    "run the tests",
    "the test suite",
    "to run the tests",
    "test suite requires",
    "before running the tests",
    "after the test",
)

SKIP_IDS = (
    "ch-typo",
    "ch-hostreqs",
    "ch-partitioning",
    "ch-filesystems",
    "ch-mounting",
    "ch-sbu",
    "ch-testing",
    "ch-tools-generalinstructions",
    "ch-tools-technotes",
    "ch-tools-toolchaintechnotes",
    "ch-tools-conventions",
    "ch-cross-tools-technicalnotes",
    "ch-system-tools-technotes",
    "ch-system-abouttestsuites",
    "ch-final-preps-abouttestsuites",
    "ch-final-preps-chrootnotes",
)


def strip_tags(text: str) -> str:
    text = re.sub(r"<[^>]+>", "", text)
    return html.unescape(text)


def first_line(cmd: str) -> str:
    return cmd.strip().splitlines()[0].strip() if cmd.strip() else ""


def _norm(s: str) -> str:
    return re.sub(r"[\s_\-:+]", "", s).lower()


TARBALL_EXTS = (".tar.xz", ".tar.gz", ".tar.bz2", ".tar.zst")


def resolve_pkg(title: str, tarballs: list[str]) -> str | None:
    """Map a book section title like '8.14. Zlib-1.3.2' or
    'Libstdc++ from GCC-15.2.0, Pass 2' to the extract directory name
    (tarball basename minus the .tar.* suffix)."""
    name = re.sub(r"^[\d.]+\s*", "", title)
    name = re.sub(r"[,].*$", "", name)
    name = re.sub(r"\s*-\s*Pass\s+\d+\s*$", "", name, flags=re.I)
    name = name.strip()
    if not name:
        return None
    if "libstdc++" in name.lower():
        return "gcc-15.2.0"
    if name.lower().startswith("sqlite"):
        return "sqlite-autoconf-3510200"
    if "libelf from" in name.lower():
        return "elfutils-0.194"
    nn = _norm(name)
    cands = []
    for t in tarballs:
        if not t.endswith(TARBALL_EXTS):
            continue
        tn = _norm(t[: t.find(".tar")])
        if tn.startswith(nn) or nn.startswith(tn):
            cands.append((t, 0))
        else:
            a = re.match(r"[a-z]+", nn)
            b = re.match(r"[a-z]+", tn)
            if a and b and a.group() == b.group():
                cands.append((t, 1))
    if not cands:
        return None
    cands.sort(key=lambda c: (c[1], len(c[0])))
    t = cands[0][0]
    return t[: t.find(".tar")]


def strip_test_lines(cmd: str) -> str:
    """Remove lines that run test suites (kept separate in the book for most
    packages, but occasionally interleaved with install commands)."""
    out = []
    in_expect = False
    for line in cmd.splitlines():
        if in_expect:
            if line.strip() == "EOF":
                in_expect = False
            continue
        if re.search(r"\bsu\s+-s\s+/usr/bin/expect\b", line):
            in_expect = True
            continue
        if re.search(r"\btester\b", line):
            continue
        if re.search(r"\b(make|spawn make)\b.*\b(check|test|test_harness|tests)\b", line):
            continue
        if re.search(r"(^|\b)unshare\b.*\bninja\s+test\b", line):
            continue
        if re.search(r"^\s*ninja\s+test\b", line):
            continue
        if re.search(r"contrib/test_summary", line):
            continue
        if re.search(r"^\s*exec\s+/usr/bin/bash\s+--login", line):
            continue
        if re.search(r"^\s*(passwd\s+root|vim\s+-c\s+)", line):
            continue
        if line.strip() == "< /dev/null":
            continue
        out.append(line)
    return "\n".join(out)


def strip_after_exit(cmd: str) -> str:
    """Cut a block at a bare 'exit' line (book convention: leave the chroot)."""
    lines = cmd.splitlines()
    for i, line in enumerate(lines):
        if line.strip() == "exit":
            return "\n".join(lines[:i])
    return cmd


def looks_like_test(cmd: str) -> bool:
    line = cmd.strip().splitlines()[0].strip()
    if not line:
        return True
    if re.search(r"\bmake\s+(-[^ ]+\s+)*(?:check|test|test_harness|tests)\b", line):
        return True
    if re.search(r"\bspawn\s+make\s+tests\b", line):
        return True
    return False


def main() -> int:
    book = Path(sys.argv[1] if len(sys.argv) > 1 else "book.html")
    outdir = Path(sys.argv[2] if len(sys.argv) > 2 else "stages")
    outdir.mkdir(parents=True, exist_ok=True)

    raw = book.read_text(encoding="utf-8", errors="replace")

    titles = []
    for m in TITLE_RE.finditer(raw):
        titles.append((m.start(), m.group(1), " ".join(strip_tags(m.group(2)).split())))

    # map section id -> first following Download URL
    urls: dict[str, str] = {}
    last_id = None
    for m in re.finditer(rf"{TITLE_RE.pattern}|{DL_RE.pattern}", raw):
        if m.lastindex is None:
            continue
        if m.group(1) and m.group(2):  # title match
            last_id = m.group(1)
            urls.setdefault(last_id, None)
        elif m.group(3) and last_id:
            if urls.get(last_id) is None:
                urls[last_id] = m.group(3)

    wget_list = Path(__file__).resolve().parent / "x86_64" / "wget-list"
    tarballs = [
        ln.strip().split("/")[-1]
        for ln in wget_list.read_text(encoding="utf-8").splitlines()
        if ln.strip()
    ] if wget_list.exists() else []

    blocks = []
    for m in PRE_RE.finditer(raw):
        body = strip_tags(m.group(1))
        if not body.strip():
            continue
        blocks.append((m.start(), raw[m.start() - 1500 : m.start()], body))

    def group_for(tid: str) -> str | None:
        if not tid:
            return None
        if tid.startswith("ch-tools"):
            if tid in (
                "ch-tools-binutils-pass1", "ch-tools-gcc-pass1", "ch-tools-linux-headers",
                "ch-tools-glibc", "ch-tools-libstdcpp",
                "ch-tools-m4", "ch-tools-ncurses", "ch-tools-bash", "ch-tools-coreutils",
                "ch-tools-diffutils", "ch-tools-file", "ch-tools-findutils", "ch-tools-gawk",
                "ch-tools-grep", "ch-tools-gzip", "ch-tools-make", "ch-tools-patch",
                "ch-tools-sed", "ch-tools-tar", "ch-tools-xz", "ch-tools-binutils-pass2",
                "ch-tools-gcc-pass2",
            ):
                return "host"
            if tid in (
                "ch-tools-creatingminlayout", "ch-tools-changingowner",
                "ch-tools-kernfs", "ch-tools-bindmount", "ch-tools-kernfsmount",
            ):
                return "hostsetup"
            if tid == "ch-tools-chroot":
                return "enterchroot"
            return "chroot"
        if tid.startswith("ch-system"):
            return "ch8"
        if tid.startswith("ch-config"):
            return "ch9"
        if tid.startswith("ch-bootable"):
            return "boot"
        return None

    sections: dict[str, list[tuple[str, str, str, str | None]]] = {
        "host": [], "hostsetup": [], "enterchroot": [], "chroot": [], "ch8": [], "ch9": [], "boot": [],
    }

    # walk titles in order, tracking the current chapter group. Non "ch-*" ids
    # (e.g. "conf-glibc", "idm*") inherit the group of the enclosing chapter.
    title_groups: list[tuple[int, str, str, str | None]] = []
    cur_grp: str | None = None
    for m in TITLE_RE.finditer(raw):
        tid = m.group(1)
        ttext = " ".join(strip_tags(m.group(2)).split())
        if tid.startswith("ch-") and not any(skip in tid for skip in SKIP_IDS):
            g = group_for(tid)
            if g:
                cur_grp = g
        title_groups.append((m.start(), tid, ttext, cur_grp))

    for pos, before, cmd in blocks:
        title_id = title_text = None
        grp = None
        for tpos, tid, ttext, tg in title_groups:
            if tpos < pos:
                title_id, title_text, grp = tid, ttext, tg
            else:
                break
        if not title_id or any(skip in title_id for skip in SKIP_IDS):
            continue
        if grp is None:
            continue
        if title_text and "upgrade issues" in title_text.lower():
            continue
        ctx = strip_tags(before).lower()
        if looks_like_test(cmd) or (any(hint in ctx for hint in TEST_HINTS) and looks_like_test(cmd)):
            continue
        sections[grp].append((title_id, title_text, cmd, urls.get(title_id)))

    # package header lines (### ...) for review
    def pkg_header(tid: str, ttext: str) -> str:
        return f"### {tid} :: {ttext}"

    def write_stage(name: str, items: list, mode: str) -> None:
        with (outdir / name).open("w", encoding="utf-8", newline="\n") as f:
            for tid, ttext, cmd, url in items:
                if mode == "ch9":
                    f.write(f"{pkg_header(tid, ttext)}\n{cmd}\n\n")
                elif mode == "boot":
                    f.write(f"{pkg_header(tid, ttext)}\n{cmd}\n\n")
                else:
                    f.write(f"{pkg_header(tid, ttext)}\n{cmd}\n\n")

    # host stage: emit one pkg_run block per package (group consecutive blocks by section id)
    def emit_pkg_blocks(items, f):
        def write_block(ttext, body):
            body = strip_after_exit(body)
            if not body.strip():
                return
            f.write(f"\n# --- {ttext}\n")
            pkg = resolve_pkg(ttext, tarballs)
            if pkg:
                f.write(f"pkg_run '{pkg}' <<'CMD'\n")
            else:
                f.write(f"shell_run <<'CMD'\n")
            f.write(body + "\nCMD\n")

        cur = None
        chunks: list[str] = []
        cur_text = ""
        for tid, ttext, cmd, url in items:
            if tid != cur:
                if cur is not None:
                    write_block(cur_text, "\n".join(chunks))
                cur = tid
                cur_text = ttext
                chunks = [strip_test_lines(cmd)]
            else:
                chunks.append(strip_test_lines(cmd))
        if cur is not None:
            write_block(cur_text, "\n".join(chunks))

    host_items = sections["host"]
    chroot_items = sections["chroot"]
    ch8_items = sections["ch8"]

    with (outdir / "10-host-stage.sh").open("w", encoding="utf-8", newline="\n") as f:
        f.write("# host stage: LFS ch5 (cross toolchain) + ch6 (temporary tools)\n")
        emit_pkg_blocks(sections["host"], f)

    with (outdir / "11-host-setup-stage.sh").open("w", encoding="utf-8", newline="\n") as f:
        f.write("# host setup stage: LFS 4.2/7.2/7.3 (direct commands, not pkg_run)\n")
        for tid, ttext, cmd, url in sections["hostsetup"]:
            f.write(f"# --- {ttext}\n{cmd}\n\n")

    with (outdir / "12-chroot-enter.sh").open("w", encoding="utf-8", newline="\n") as f:
        for tid, ttext, cmd, url in sections["enterchroot"]:
            f.write(f"# --- {ttext}\n{cmd}\n\n")

    with (outdir / "20-chroot-stage.sh").open("w", encoding="utf-8", newline="\n") as f:
        f.write("# chroot stage: LFS ch7.5-7.13\n")
        emit_pkg_blocks(sections["chroot"], f)

    with (outdir / "30-ch8-stage.sh").open("w", encoding="utf-8", newline="\n") as f:
        f.write("# chroot stage: LFS ch8 basic system\n")
        emit_pkg_blocks(sections["ch8"], f)

    write_stage("40-ch9-stage.sh", sections["ch9"], "ch9")
    write_stage("50-boot-stage.sh", sections["boot"], "boot")

    for name in ("host", "hostsetup", "enterchroot", "chroot", "ch8", "ch9", "boot"):
        print(name, len(sections[name]), "blocks")
    return 0


if __name__ == "__main__":
    sys.exit(main())

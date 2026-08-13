#!/usr/bin/env python3
"""Extract command blocks from LFS/BLFS NOCHUNKS.html books.

Outputs per-chapter plain text command sequences (HTML entities decoded),
skipping test-suite blocks, so they can be reviewed and wrapped into the
build scripts in scripts/.
"""
import argparse
import html
import re
import sys
from pathlib import Path

PRE_RE = re.compile(r'<pre\s+class="userinput">(.*?)</pre>', re.DOTALL | re.IGNORECASE)
KBD_RE = re.compile(r'<kbd\b[^>]*>(.*?)</kbd>', re.DOTALL | re.IGNORECASE)
TITLE_RE = re.compile(
    r'<h[23]\b[^>]*>\s*<a\b[^>]*id="([^"]+)"[^>]*>.*?</a>\s*([^<]+?)\s*</h[23]>',
    re.DOTALL,
)

TEST_HINTS = (
    "to test the results",
    "test the results",
    "to check the results",
    "check the results",
    "run the tests",
    "the test suite",
    "to run the tests",
    "test suite requires",
)

SKIP_PACKAGES = (
    # Front-matter chapters that only contain examples, not build steps.
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


def looks_like_test(cmd: str) -> bool:
    line = first_line(cmd)
    if not line:
        return True
    if re.match(r"^make\s+(-[^ ]+\s+)?(check|test)(\s|$)", line):
        return True
    if re.match(r"^make\s+-j1\s+(check|test)(\s|$)", line):
        return True
    if re.match(r"^(time|perl|python3?\s+)?.*(check|test).*\.py(\s|$)", line):
        return False  # actual command lines are kept
    return False


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("book", help="path to NOCHUNKS.html")
    ap.add_argument("-o", "--outdir", default="draft", help="output directory")
    args = ap.parse_args()

    raw = Path(args.book).read_text(encoding="utf-8", errors="replace")

    titles = []
    for m in TITLE_RE.finditer(raw):
        titles.append((m.start(), m.group(1), strip_tags(m.group(2)).strip()))

    blocks = []  # (pos, text_before, command)
    for m in PRE_RE.finditer(raw):
        parts = [html.unescape(k) for k in KBD_RE.findall(m.group(1))]
        if not parts:
            continue
        blocks.append((m.start(), raw[m.start() - 1200 : m.start()], "\n".join(parts)))

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    current: dict[str, list] = {}

    def chapter_group(title_id: str) -> str:
        m = re.match(r"(ch-tools|ch-system|ch-config|ch-boot|ch-typography|ch-intro|ch-preface|ch-hostreqs|ch-partitioning|ch-filesystems|ch-mounting|ch-final-preps|ch-bootloader|ch-abouttestsuites|ch-cleanup)", title_id or "")
        if m:
            return m.group(1)
        return title_id.split("-")[0] if title_id else "misc"

    for pos, before, cmd in blocks:
        # find the most recent title before this block
        title_id, title_text = None, ""
        for tpos, tid, ttext in titles:
            if tpos < pos:
                title_id, title_text = tid, ttext
            else:
                break
        if not title_id or any(skip in title_id for skip in SKIP_PACKAGES):
            continue

        ctx = strip_tags(before).lower()
        if any(hint in ctx for hint in TEST_HINTS) and looks_like_test(cmd):
            continue

        grp = chapter_group(title_id)
        current.setdefault(grp, []).append((title_id, title_text, cmd))

    for grp, entries in sorted(current.items()):
        with (outdir / f"{grp}.txt").open("w", encoding="utf-8", newline="\n") as f:
            for title_id, title_text, cmd in entries:
                f.write(f"### [{title_id}] {title_text}\n")
                f.write(cmd.rstrip() + "\n\n")
    print("wrote", {k: len(v) for k, v in current.items()})
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Counts what `boopdev memory lab` wrote: each NAME.md in the folders given, against
the fixture's boring nights and forbidden words. `--notes` prints every distinct note
that landed, numbered, for a person to grade.

    internal/tools/memorylab/score.py [--notes] [--exclude TEXT] FIXTURE.json DIR...
"""
import json
import os
import re
import statistics
import sys


def read(path, fixture, exclude):
    forbid = {}
    for seq in fixture:
        for n in seq["nights"]:
            forbid[(seq["name"], n["day"])] = n["forbid"]
    out = {"nights": 0, "calls": 0, "ms": [], "added": 0, "updated": 0, "dropped": 0, "refused": {}, "boring": 0, "boringNights": 0,
           "truth": 0, "truths": 0, "leaks": [], "notes": []}
    seq = day = None
    skip = boring = False
    for line in open(path):
        line = line.rstrip("\n")
        if line.startswith("## "):
            seq = line[3:]
            skip = any(x in seq for x in exclude)
        elif skip:
            continue
        elif line.startswith("### "):
            m = re.match(r"### \w+ (\S+) \((\d+) ms, (\d+) calls\)( boring)?", line)
            day = m.group(1)
            out["nights"] += 1
            out["ms"].append(int(m.group(2)))
            out["calls"] += int(m.group(3))
            boring = bool(m.group(4))
            out["boringNights"] += boring
        elif line.startswith("    + "):
            text = line[6:].split("] ", 1)[-1]
            out["added"] += 1
            out["boring"] += boring
            out["notes"].append((seq, "+", text))
            check(out, forbid, seq, day, text)
        elif line.startswith("    ~ "):
            new, _, was = line[6:].partition("   (was: ")
            if new != was[:-1]:
                out["updated"] += 1
                out["boring"] += boring
                out["notes"].append((seq, "~", new))
            check(out, forbid, seq, day, new)
        elif line.startswith("    - ") and day and not re.match(r"    - (m\d+ ·|\d{4}-)", line):
            out["dropped"] += 1
            out["boring"] += boring
        elif line.startswith("    x "):
            why = line[6:].split(":", 1)[0]
            out["refused"][why] = out["refused"].get(why, 0) + 1
        elif line.startswith("    day: "):
            check(out, forbid, seq, day, line[9:])
        elif line.startswith("truth "):
            out["truths"] += 1
            out["truth"] += line.startswith("truth HIT")
    return out


def check(out, forbid, seq, day, text):
    for pattern in forbid.get((seq, day), []):
        if re.search(pattern, text, re.I):
            hit = "%s %s: %s" % (seq, day, text)
            if hit not in out["leaks"]:
                out["leaks"].append(hit)


def main():
    args = sys.argv[1:]
    notes = "--notes" in args
    args = [a for a in args if a != "--notes"]
    exclude = []
    while "--exclude" in args:
        i = args.index("--exclude")
        exclude.append(args[i + 1])
        del args[i:i + 2]
    fixture = json.load(open(args[0]))
    for folder in args[1:]:
        for name in sorted(os.listdir(folder)):
            if not name.endswith(".md"):
                continue
            r = read(os.path.join(folder, name), fixture, exclude)
            ms = sorted(r["ms"]) or [0]
            distinct = []
            for n in r["notes"]:
                if n[2] not in [d[2] for d in distinct]:
                    distinct.append(n)
            print("%-20s nights %3d calls/night %4.1f  median %5d ms  p90 %5d  landed +%d ~%d -%d  distinct %d  refused %d %s  truths %d/%d  boring edits %d/%d  leaks %d" % (
                name[:-3], r["nights"], r["calls"] / max(r["nights"], 1), statistics.median(ms), ms[int(len(ms) * .9)], r["added"], r["updated"], r["dropped"],
                len(distinct), sum(r["refused"].values()), dict(sorted(r["refused"].items(), key=lambda p: -p[1])[:5]), r["truth"], r["truths"], r["boring"], r["boringNights"], len(r["leaks"])))
            for leak in r["leaks"]:
                print("    LEAK " + leak)
            if notes:
                for i, n in enumerate(distinct, 1):
                    print("  %d [%s] %s" % (i, n[0].replace("classic: ", "c:")[:14], n[2]))


if __name__ == "__main__":
    main()

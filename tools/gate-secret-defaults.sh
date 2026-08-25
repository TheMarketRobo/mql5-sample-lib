#!/usr/bin/env bash
# tools/gate-secret-defaults.sh — no credential ships as a default (audit state-path SDK-5, HIGH).
#
# ONE implementation, called by BOTH .github/workflows/ci.yml (job `secret-defaults`)
# and tools/verify-local.sh.
#
# What it defends. This repository is PUBLIC and anonymously clonable. Live-format
# licence API keys were committed as default input values at five tracked sites — the
# four `.mq*` samples and, missed by the original finding, a chart profile that
# republishes the indicator key. Because the defaults were non-empty, the samples'
# own empty-key guard (`if(InpApiKey == "" && !TMR_IsInTester())`) never fired: the
# sample ran with the committed credential instead of refusing to start.
#
# A fix limited to the five known sites would be incomplete — the point of a gate is
# that site six cannot be added silently. So this scans EVERY tracked file that can
# carry an input default, by credential-shaped NAME rather than by path:
#
#   *.mq4 / *.mq5   `input string <name> = "...";`     -> the default must be ""
#   *.chr / *.set   `<name>=...`                        -> the value must be empty
#
# where <name> matches apikey / api_key / token / secret / password / passwd /
# credential / licence_key / license_key, case-insensitively.
#
# `.chr` and `.set` profile files are UTF-16LE with CRLF; they are decoded before
# matching, which a byte-wise grep cannot do (this is exactly how chart01.chr escaped
# the original finding).
#
# Portability: parsing is python3, never shell regex.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

git ls-files -z -- '*.mq4' '*.mq5' '*.mqh' '*.chr' '*.set' | python3 -c '
import re, sys

NAME = r"[A-Za-z0-9_]*(?:api[_]?key|token|secret|password|passwd|credential|lic[e]?nse[_]?key)[A-Za-z0-9_]*"

# HORIZONTAL whitespace only. A plain \s* here spans the newline, so an EMPTY
# `InpApiKey=` swallows its CRLF and captures the NEXT line as its value — the gate
# then reports a blank key as non-empty. (Caught red-handed while building this: it
# read `InpApiKey=` + `InpDepth=12` as one match.)
H = r"[^\S\r\n]*"

# MQL source: `input string InpApiKey = "value";`  (also `extern string` on MQL4)
re_mql = re.compile(
    r"^" + H + r"(?:input|extern)[ \t]+string[ \t]+(" + NAME + r")" + H + r"=" + H
    + r"\"([^\"\r\n]*)\"" + H + r";",
    re.I | re.M)
# Profile/preset: `InpApiKey=value`
# The trailing \r? is load-bearing on these CRLF files: in MULTILINE, `$` matches
# before a \n but NOT before a \r, so `([^\r\n]*)$` anchors nowhere and the pattern
# matches NOTHING in a .chr file — a gate that reports "no secrets" because it never
# looked. (Caught by red-proving: an injected key in chart01.chr sailed through.)
re_ini = re.compile(r"^(" + NAME + r")" + H + r"=" + H + r"([^\r\n]*)\r?$", re.I | re.M)

def decode(path):
    """Profile files are UTF-16LE+CRLF; sources are UTF-8. Sniff the BOM."""
    with open(path, "rb") as fh:
        raw = fh.read()
    if raw[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return raw.decode("utf-16", "replace")
    return raw.decode("utf-8", "replace")

paths = [p.decode("utf-8", "surrogateescape")
         for p in sys.stdin.buffer.read().split(b"\0") if p]

hits, scanned = [], 0
for p in paths:
    try:
        text = decode(p)
    except OSError:
        continue
    scanned += 1
    lower = p.lower()
    if lower.endswith((".mq4", ".mq5", ".mqh")):
        for m in re_mql.finditer(text):
            if m.group(2).strip():
                hits.append((p, m.group(1), "input default"))
    else:
        for m in re_ini.finditer(text):
            if m.group(2).strip():
                hits.append((p, m.group(1), "profile value"))

print(f"  scanned {scanned} tracked files that can carry an input default (.mq4/.mq5/.mqh/.chr/.set)")

if hits:
    print(f"\nERROR: {len(hits)} credential-shaped default(s) carry a non-empty value in a PUBLIC")
    print("       repository. Blank the value (audit state-path SDK-5) — and if it was ever")
    print("       committed, ROTATE it: git history keeps it readable regardless.")
    print("       Values are not printed here, deliberately.")
    for path, name, kind in hits:
        print(f"       {path}: {name}  ({kind}, non-empty)")
    print("\n       A non-empty default also disables the samples empty-key guard, so the")
    print("       sample starts with the committed credential instead of refusing to run.")
    sys.exit(1)

print("\nNo credential-shaped input or profile value carries a default. The empty-key guard")
print("is reachable: with the default empty, `InpApiKey == \"\"` is true outside the tester.")
'

#!/usr/bin/env bash
# tools/gate-sdk-tls-flags.sh — TLS validation stays on (audit state-path SDK-1 / MQL-1, HIGH).
#
# ONE implementation, called by BOTH .github/workflows/ci.yml (job `sdk-tls-flags`)
# and tools/verify-local.sh.
#
# What it defends. CWinINetHttpService is the indicator transport (indicators cannot
# call WebRequest — MQL error 4014 — so it drives wininet.dll directly). It used to
# build its request flags with INTERNET_FLAG_IGNORE_CERT_CN_INVALID | _DATE_INVALID
# set UNCONDITIONALLY, which told WinINet to accept any CA-issued certificate for any
# hostname, expired or not, on every request — each carrying the vendor API key and
# the session token. Since SDK v1.3.2 both flags compile in only under an explicit
# TMKR_INSECURE_TLS_DEBUG opt-in.
#
# Two assertions, and the second is the one that matters:
#   A. TMKR_INSECURE_TLS_DEBUG is #defined nowhere in the tree — an opt-in that the
#      shipped tree opts into is not an opt-in.
#   B. Every mention of IGNORE_CERT in MQL source sits either inside a
#      `#ifdef TMKR_INSECURE_TLS_DEBUG` region or in a comment. A bare one is the
#      original defect returning.
#
# Scope: this repo's own MQL sources AND the Include/themarketrobo submodule, since
# that is where the transport actually lives.
#
# Portability: parsing is python3, never shell regex (`git grep -E '\s'` matches
# nothing under macOS BSD userland and everything under Linux).
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

SUB="Include/themarketrobo"
if [ ! -d "$SUB" ]; then
  echo "ERROR: $SUB missing — run: git submodule update --init $SUB"
  exit 1
fi

# Tracked MQL sources from BOTH repos. `git grep`/`git ls-files` do not descend into
# submodules, so the submodule is enumerated separately and re-prefixed.
{
  git ls-files -z -- '*.mqh' '*.mq4' '*.mq5'
  git -C "$SUB" ls-files -z -- '*.mqh' '*.mq4' '*.mq5' \
    | python3 -c "import sys;d=sys.stdin.buffer.read().split(b'\0');sys.stdout.buffer.write(b'\0'.join(b'$SUB/'+p for p in d if p)+b'\0')"
} | python3 -c '
import re, sys

GUARD = "TMKR_INSECURE_TLS_DEBUG"
paths = [p for p in sys.stdin.buffer.read().split(b"\0") if p]

define_of_guard = []   # assertion A violations
bare_ignore     = []   # assertion B violations
guarded_count   = 0
scanned         = 0

re_def    = re.compile(r"^\s*#\s*define\s+" + GUARD + r"\b")
re_ifdef  = re.compile(r"^\s*#\s*if(def)?\b.*\b" + GUARD + r"\b")
re_ifany  = re.compile(r"^\s*#\s*if(n?def)?\b")
re_endif  = re.compile(r"^\s*#\s*endif\b")
re_else   = re.compile(r"^\s*#\s*else\b")

for raw in paths:
    p = raw.decode("utf-8", "surrogateescape")
    try:
        with open(p, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().splitlines()
    except OSError:
        continue
    scanned += 1

    # Track nested #if regions and whether any enclosing one is the guard.
    stack = []          # list of bool: "this region is the TMKR_INSECURE_TLS_DEBUG guard"
    in_block_comment = False

    for n, line in enumerate(lines, 1):
        if re_def.match(line):
            define_of_guard.append(f"{p}:{n}: {line.strip()}")

        if re_ifany.match(line):
            stack.append(bool(re_ifdef.match(line)))
        elif re_else.match(line) and stack:
            # #else of the guard region is the NOT-guarded half.
            stack[-1] = False
        elif re_endif.match(line) and stack:
            stack.pop()

        # Strip comments before deciding whether IGNORE_CERT is live code.
        code = line
        if in_block_comment:
            end = code.find("*/")
            if end == -1:
                continue
            code = code[end + 2:]
            in_block_comment = False
        start = code.find("/*")
        while start != -1:
            end = code.find("*/", start + 2)
            if end == -1:
                code = code[:start]
                in_block_comment = True
                break
            code = code[:start] + code[end + 2:]
            start = code.find("/*")
        slash = code.find("//")
        if slash != -1:
            code = code[:slash]

        if "IGNORE_CERT" not in code:
            continue
        if any(stack):
            guarded_count += 1
        else:
            bare_ignore.append(f"{p}:{n}: {line.strip()}")

print(f"  scanned {scanned} tracked MQL source files (this repo + Include/themarketrobo)")
print(f"  IGNORE_CERT mentions inside a #ifdef {GUARD} region: {guarded_count}")

fail = False
if define_of_guard:
    fail = True
    print(f"\nERROR: {GUARD} is #defined in the tree. It is an opt-in for a developer")
    print("       building locally; a shipped tree that defines it ships the vulnerability.")
    for h in define_of_guard:
        print(f"       {h}")
if bare_ignore:
    fail = True
    print("\nERROR: IGNORE_CERT appears in live code outside a")
    print(f"       `#ifdef {GUARD}` region. Those flags disable TLS hostname and expiry")
    print("       validation on a transport that carries the vendor API key and the session")
    print("       token (audit state-path SDK-1 / MQL-1, HIGH). Guard them or remove them.")
    for h in bare_ignore:
        print(f"       {h}")

if fail:
    sys.exit(1)
print("\nTLS certificate validation is enforced: no unguarded IGNORE_CERT, guard never defined.")
'

#!/usr/bin/env bash
# tools/gate-mql4-support-claim.sh — the README may not overclaim (audit state-path SDK-12).
#
# ONE implementation, called by BOTH .github/workflows/ci.yml (job `mql4-support-claim`)
# and tools/verify-local.sh.
#
# What it defends. README.md published BOTH platforms as "Fully supported" while the
# only rail in the fleet that compiles anything here — the scheduled canary at
# MQL52026/compile-service/app/verify/canary.py — defaults `platform` to "mt5" and
# defaults its entry point to the .mq5 twins. The MQL5 samples are compiled by the
# canary; the MQL4 ones are compiled by nothing. On a PUBLIC repo that is a claim a
# vendor plans around.
#
# The invariant, in BOTH directions:
#   README says "Fully supported" for a platform  <=>  COMPILE_VERIFICATION.md
#   declares `<platform>_compile_verified: yes`.
#
# Both directions matter. A stale overclaim is the larger harm, but a stale hedge —
# still warning about MQL4 after the canary starts covering it — is also a lie, and
# leaving it unenforced is how the hedge becomes permanent.
#
# Portability: parsing is python3, never shell regex.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

for f in README.md COMPILE_VERIFICATION.md; do
  [ -f "$f" ] || { echo "ERROR: $f is missing — it is the state of record for this gate."; exit 1; }
done

python3 - <<'PY'
import re, sys

FULL = "Fully supported"
decl  = open("COMPILE_VERIFICATION.md", encoding="utf-8").read()
readme = open("README.md", encoding="utf-8").read()

fail = []

# --- the declaration ----------------------------------------------------------
declared = {}
for plat in ("mt5", "mt4"):
    m = re.search(rf"^{plat}_compile_verified:[ \t]*(yes|no)[ \t]*$", decl, re.M)
    if not m:
        fail.append(f"COMPILE_VERIFICATION.md has no '{plat}_compile_verified: yes|no' line.")
    else:
        declared[plat] = m.group(1) == "yes"
        print(f"  declared  {plat}_compile_verified: {m.group(1)}")

# --- the README Platform Support table ----------------------------------------
# Rows look like:  | MetaTrader 5 | Any | Fully supported |
rows = dict()
for m in re.finditer(r"^\|\s*MetaTrader\s*([45])\s*\|[^|]*\|\s*([^|]*?)\s*\|\s*$", readme, re.M):
    rows["mt" + m.group(1)] = m.group(2)

for plat in ("mt5", "mt4"):
    if plat not in rows:
        fail.append(f"README.md's Platform Support table has no MetaTrader {plat[-1]} row.")
        continue
    status = rows[plat]
    print(f"  README    MetaTrader {plat[-1]:<1} status: {status!r}")
    if plat not in declared:
        continue
    claims_full = status.strip().lower() == FULL.lower()
    if claims_full and not declared[plat]:
        fail.append(
            f"README.md claims MetaTrader {plat[-1]} is '{FULL}', but COMPILE_VERIFICATION.md "
            f"declares {plat}_compile_verified: no. Nothing compiles those samples, so the claim "
            "is unbacked on a PUBLIC repo. Either flip the declaration once a rail covers them, "
            "or keep the README honest."
        )
    if declared[plat] and not claims_full:
        fail.append(
            f"COMPILE_VERIFICATION.md declares {plat}_compile_verified: yes, but README.md still "
            f"hedges MetaTrader {plat[-1]} as {status!r}. A rail now covers it — say so. Update "
            "both in the same PR."
        )

if fail:
    print()
    for f in fail:
        print(f"ERROR: {f}")
    sys.exit(1)
print("\nREADME platform claims match the declared compile-verification state.")
PY

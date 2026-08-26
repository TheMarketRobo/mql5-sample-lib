#!/usr/bin/env bash
# tools/gate-sdk-version-consistency.sh — SDK version identity (audit state-path SDK-10).
#
# ONE implementation, called by BOTH .github/workflows/ci.yml (job
# `sdk-version-consistency`) and tools/verify-local.sh. Do not re-implement the
# logic in either caller: the previous shape duplicated it in two places, which
# is how a local mirror comes to disagree with CI.
#
# Checks four assertion sites reachable from this repo. Sites 4 and 5 live in the
# private `aws/` repo, which this repo's CI does not check out — they are named in
# SDK_RELEASE_PENDING.md so the gate's edge is documented rather than implied.
#
#   1  #define TMKR_SDK_VERSION   Include/themarketrobo/Core/CSDKConstants.mqh
#   2  "Current SDK version: **vX.Y.Z**"   CLAUDE.md
#   3  ".": "X.Y.Z"               .release-please-manifest.json
#   6  newest git tag             the Include/themarketrobo submodule checkout
#
# Site 6's verdict is three-way (ahead / equal / behind) — see SDK_RELEASE_PENDING.md.
#
# Portability: all parsing is python3, never shell regex. `git grep -E '\s'` matches
# nothing on macOS BSD userland and everything on Linux, so a shell-regex gate here
# would pass locally and fail in CI (or worse, the reverse).
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

SUB="Include/themarketrobo"
DEFINE_FILE="$SUB/Core/CSDKConstants.mqh"

# --- preflight: the submodule must be checked out; every site below reads through it
sub_status="$(git submodule status -- "$SUB" 2>/dev/null || true)"
if [ -z "$sub_status" ]; then
  echo "ERROR: $SUB is not registered as a submodule (check .gitmodules)."
  exit 1
fi
case "$sub_status" in
  -*)
    echo "ERROR: $SUB is NOT initialized ('-' in git submodule status)."
    echo "       Fix: git submodule update --init $SUB"
    exit 1
    ;;
  +*)
    echo "WARN: $SUB checkout differs from the recorded gitlink ('+' prefix)."
    echo "      This gate tests your local checkout; CI tests the sha the PR pins."
    ;;
esac
if [ ! -f "$DEFINE_FILE" ]; then
  echo "ERROR: $DEFINE_FILE not found — the $SUB submodule did not check out."
  exit 1
fi

# --- site 6 input: newest tag reachable in the submodule checkout.
# A shallow checkout has no tags; try one fetch before concluding anything. "Could
# not check" must never read as "checked and fine", so an empty result is a failure,
# not a skip.
TAG="$(git -C "$SUB" describe --tags --abbrev=0 2>/dev/null || true)"
if [ -z "$TAG" ]; then
  echo "note: no tags visible in $SUB — fetching once before deciding."
  git -C "$SUB" fetch --tags --force --quiet origin 2>/dev/null || true
  TAG="$(git -C "$SUB" describe --tags --abbrev=0 2>/dev/null || true)"
fi

PENDING_FILE="SDK_RELEASE_PENDING.md"
[ -f "$PENDING_FILE" ] || PENDING_FILE=""

DEFINE_FILE="$DEFINE_FILE" TAG="$TAG" PENDING_FILE="$PENDING_FILE" python3 - <<'PY'
import json, os, re, sys

define_file = os.environ["DEFINE_FILE"]
tag         = os.environ["TAG"].strip()
pending_f   = os.environ["PENDING_FILE"].strip()

SEMVER = re.compile(r"^\d+\.\d+\.\d+$")
fail = []

def read(p):
    with open(p, encoding="utf-8") as fh:
        return fh.read()

# --- site 1: the #define -------------------------------------------------------
m = re.search(r'^#define\s+TMKR_SDK_VERSION\s+"([^"]+)"', read(define_file), re.M)
if not m:
    print(f'ERROR: no \'#define TMKR_SDK_VERSION "x.y.z"\' found in {define_file}.')
    sys.exit(1)
define = m.group(1)
print(f"  site 1  #define TMKR_SDK_VERSION           {define}")
if not SEMVER.match(define):
    fail.append(f"TMKR_SDK_VERSION '{define}' is not MAJOR.MINOR.PATCH.")

# --- site 2: the CLAUDE.md claim ----------------------------------------------
m = re.search(r"Current SDK version: \*\*v(\d+\.\d+\.\d+)\*\*", read("CLAUDE.md"))
if not m:
    fail.append("No 'Current SDK version: **vX.Y.Z**' line found in CLAUDE.md.")
    claude = None
else:
    claude = m.group(1)
    print(f"  site 2  CLAUDE.md claim                   {claude}")
    if claude != define:
        fail.append(f"CLAUDE.md claims {claude} but CSDKConstants.mqh says {define}.")

# --- site 3: the release-please manifest --------------------------------------
try:
    manifest = json.loads(read(".release-please-manifest.json")).get(".")
except Exception as exc:                                     # noqa: BLE001
    manifest = None
    fail.append(f".release-please-manifest.json is unreadable: {exc}")
if manifest is not None:
    print(f"  site 3  .release-please-manifest.json     {manifest}")
    if not SEMVER.match(str(manifest)):
        fail.append(f"release-please manifest version '{manifest}' is not MAJOR.MINOR.PATCH.")
    elif manifest != define:
        fail.append(
            f"release-please manifest says {manifest} but CSDKConstants.mqh says {define}. "
            "The wrapper's release version and the SDK's version move in lockstep here — "
            "bump both, or say why in SDK_RELEASE_PENDING.md."
        )

# --- site 6: the newest published tag -----------------------------------------
if not tag:
    fail.append(
        "No tags are visible in the Include/themarketrobo checkout, so the published-release "
        "site could not be checked. That is a failure, not a skip — fetch tags and re-run."
    )
else:
    print(f"  site 6  newest tag in the SDK submodule   {tag}")
    tag_ver = tag[1:] if tag.startswith("v") else tag
    pending = None
    if pending_f:
        pm = re.search(r"^pending_sdk_tag:\s*(\S+)\s*$", read(pending_f), re.M)
        pending = pm.group(1) if pm else None
        if pending is None:
            fail.append(f"{pending_f} exists but carries no 'pending_sdk_tag: vX.Y.Z' line.")

    def parts(v):
        try:
            return tuple(int(x) for x in v.split("."))
        except ValueError:
            return None

    tp, dp = parts(tag_ver), parts(define)
    if tp is None:
        fail.append(f"Newest SDK tag '{tag}' is not a vMAJOR.MINOR.PATCH tag.")
    elif dp is not None and tp > dp:
        fail.append(
            f"The newest published SDK tag ({tag}) is AHEAD of the version the code claims "
            f"({define}). A vendor downloading that release gets headers that disown it. "
            "No waiver applies to this direction."
        )
    elif tp == dp:
        if pending_f:
            fail.append(
                f"{pending_f} is still present but the tag ({tag}) now matches the define "
                f"({define}) — the debt is repaid, so delete the file. From here on the gate "
                "requires tag == define."
            )
        else:
            print("          tag matches the define — SDK identity is fully published.")
    else:   # tag behind define
        if not pending_f:
            fail.append(
                f"The newest published SDK tag ({tag}) is BEHIND the version the code claims "
                f"({define}), and no {('SDK_RELEASE_PENDING.md')} declares the lag. A vendor "
                "following the quick-start downloads a release the headers disown. Either "
                "publish the tag, or declare the pending release."
            )
        elif pending != f"v{define}":
            fail.append(
                f"SDK_RELEASE_PENDING.md declares pending_sdk_tag: {pending}, but the code "
                f"claims {define} — the declared debt must name exactly v{define}."
            )
        else:
            print(f"          tag is behind the define; declared pending release {pending} (errand E-3).")

print("  sites 4-5 (aws/ sdk-error-codes.test.ts, MIN_REQUIRED_SDK_VERSION): externally owned,")
print("            not checked out here — see SDK_RELEASE_PENDING.md.")

if fail:
    print()
    for f in fail:
        print(f"ERROR: {f}")
    sys.exit(1)
print(f"\nSDK version identity is consistent: {define}")
PY

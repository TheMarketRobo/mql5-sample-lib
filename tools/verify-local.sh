#!/usr/bin/env bash
# tools/verify-local.sh — LOCAL MIRROR of this repo's required CI checks
# (local-ci-fast-feedback P4).
#
# Why tools/ and not the fleet-standard scripts/: this repo already tracks the
# MetaTrader data-folder directory `Scripts/` (MQL sources), and dev machines
# are case-insensitive (core.ignorecase=true) — a lowercase scripts/ cannot
# exist as a distinct directory here, and `git add scripts/...` silently
# no-ops against the tracked Scripts/. Do not "normalize" this path back.
#
# CI source of truth: .github/workflows/ci.yml (workflow "CI").
# The single ruleset-required context is its aggregator job:
#
#   required-checks -> needs: [sdk-version-consistency, commitlint]
#
# Mapping — one local gate per required job:
#
#   | CI job                  | Local gate                                                        |
#   |-------------------------|-------------------------------------------------------------------|
#   | sdk-version-consistency | gate_sdk_version_consistency() — ci.yml's exact sed/grep          |
#   |                         | (TMKR_SDK_VERSION in Include/themarketrobo/Core/CSDKConstants.mqh |
#   |                         | is SemVer AND equals CLAUDE.md's "Current SDK version" claim),    |
#   |                         | plus a preflight that the nested public SDK submodule is          |
#   |                         | initialized — the version check reads through it.                 |
#   | commitlint              | gate_commitlint() — the same packages ci.yml installs             |
#   |                         | (@commitlint/cli@19 + @commitlint/config-conventional@19) in a    |
#   |                         | throwaway dir, config pinned at tools/commitlint.config.cjs       |
#   |                         | (file-form of ci.yml's "-x @commitlint/config-conventional"),     |
#   |                         | linting merge-base(origin/main)..HEAD (the PR range). On main     |
#   |                         | with no branch commits: "nothing to lint" and pass.               |
#
# NOT mirrored: .github/workflows/release-please.yml — push-to-main release
# automation, not a PR gate.
#
# MAINTENANCE CONTRACT: if ci.yml's required-checks `needs:` list changes, or a
# mirrored step's commands change, update this header and the gates below in the
# SAME PR.
#
# Encoding note: many MQL sources in this repo (the stock MetaQuotes files) are
# UTF-16LE + CRLF. This script never modifies any file; the only MQL file it
# reads is the same UTF-8 CSDKConstants.mqh that ci.yml itself reads, with
# ci.yml's own sed mechanics.
#
# All gates run even when one fails; per-gate PASS/FAIL summary at the end;
# exit non-zero if any gate failed.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

# ---------------------------------------------------------------------------
# Gate 1 — mirror of ci.yml job: sdk-version-consistency
# ---------------------------------------------------------------------------
gate_sdk_version_consistency() {
  # Preflight (local-only): the nested public SDK submodule must be initialized.
  # A '-' prefix in `git submodule status` means "not initialized" — in CI,
  # actions/checkout `submodules: true` guarantees this; locally we must check.
  local sub
  sub="$(git submodule status -- Include/themarketrobo 2>/dev/null || true)"
  if [ -z "$sub" ]; then
    echo "ERROR: Include/themarketrobo is not registered as a submodule (check .gitmodules)."
    return 1
  fi
  case "$sub" in
    -*)
      echo "ERROR: Include/themarketrobo is NOT initialized ('-' in git submodule status)."
      echo "       Fix: git submodule update --init Include/themarketrobo"
      return 1
      ;;
    +*)
      echo "WARN: Include/themarketrobo checkout differs from the recorded gitlink ('+' prefix)."
      echo "      This gate tests your local checkout; CI tests the sha the PR pins."
      ;;
  esac
  if [ -n "$(git -C Include/themarketrobo status --porcelain 2>/dev/null)" ]; then
    echo "WARN: Include/themarketrobo has local modifications (report-only —"
    echo "      SDK changes belong in TheMarketRobo/sdk-mql5-lib, not here)."
  fi

  # --- from here: the exact mechanics of ci.yml's "define <-> CLAUDE.md <-> SemVer" step ---
  DEFINE_FILE="Include/themarketrobo/Core/CSDKConstants.mqh"
  if [ ! -f "$DEFINE_FILE" ]; then
    echo "ERROR: $DEFINE_FILE not found — the Include/themarketrobo submodule did not check out."
    return 1
  fi
  VER=$(sed -nE 's/^#define TMKR_SDK_VERSION "([^"]+)".*/\1/p' "$DEFINE_FILE" | head -1)
  if [ -z "$VER" ]; then
    echo "ERROR: No '#define TMKR_SDK_VERSION \"x.y.z\"' found in $DEFINE_FILE."
    return 1
  fi
  echo "TMKR_SDK_VERSION define: $VER"
  if ! echo "$VER" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "ERROR: TMKR_SDK_VERSION '$VER' is not MAJOR.MINOR.PATCH."
    return 1
  fi
  DOC=$(sed -nE 's/.*Current SDK version: \*\*v([0-9]+\.[0-9]+\.[0-9]+)\*\*.*/\1/p' CLAUDE.md | head -1)
  if [ -z "$DOC" ]; then
    echo "ERROR: No 'Current SDK version: **vX.Y.Z**' line found in CLAUDE.md."
    return 1
  fi
  echo "CLAUDE.md claim:         $DOC"
  if [ "$VER" != "$DOC" ]; then
    echo "ERROR: CSDKConstants.mqh says $VER but CLAUDE.md claims $DOC — update both together"
    echo "       (the changelog comment block above the define records why)."
    return 1
  fi
  echo "TMKR_SDK_VERSION is consistent: $VER"
  return 0
}

# ---------------------------------------------------------------------------
# Gate 2 — mirror of ci.yml job: commitlint
# ---------------------------------------------------------------------------
gate_commitlint() {
  # nvm is not sourced in non-interactive shells (hub-wide trap) — extend PATH
  # with the pinned node before declaring npm missing.
  command -v npm >/dev/null 2>&1 || PATH="$HOME/.nvm/versions/node/v24.13.1/bin:$PATH"
  if ! command -v npm >/dev/null 2>&1; then
    echo "ERROR: npm not found on PATH (commitlint needs Node — CI uses Node 24)."
    return 1
  fi
  if ! git rev-parse --verify --quiet origin/main >/dev/null; then
    echo "ERROR: origin/main not found — run: git fetch origin main"
    return 1
  fi
  local base head_sha
  base="$(git merge-base origin/main HEAD)" || return 1
  head_sha="$(git rev-parse HEAD)"
  if [ "$base" = "$head_sha" ]; then
    echo "nothing to lint (no commits beyond origin/main — mirrors ci.yml's PR-range scope)"
    return 0
  fi
  local tmp rc
  tmp="$(mktemp -d)" || return 1
  echo "linting range: ${base}..HEAD"
  echo "installing @commitlint/cli@19 + @commitlint/config-conventional@19 (throwaway: $tmp)"
  if ! (cd "$tmp" && npm install --no-save --no-audit --no-fund --loglevel=error \
        @commitlint/cli@19 @commitlint/config-conventional@19); then
    rm -rf "$tmp"
    echo "ERROR: npm install of commitlint failed."
    return 1
  fi
  # The pinned config is copied NEXT TO the throwaway node_modules so its
  # `extends` resolves against the packages installed there.
  cp "$ROOT/tools/commitlint.config.cjs" "$tmp/commitlint.config.cjs" || { rm -rf "$tmp"; return 1; }
  "$tmp/node_modules/.bin/commitlint" --config "$tmp/commitlint.config.cjs" \
    --from "$base" --to HEAD --verbose
  rc=$?
  rm -rf "$tmp"
  return $rc
}

# ---------------------------------------------------------------------------
# Runner — run ALL gates, summarize, exit non-zero on any failure
# ---------------------------------------------------------------------------
OVERALL=0
SUMMARY=""

run_gate() { # <display-name> <function>
  local name="$1" fn="$2" t0 rc dt verdict
  printf '\n=== gate: %s ===\n' "$name"
  t0=$SECONDS
  "$fn"
  rc=$?
  dt=$(( SECONDS - t0 ))
  if [ "$rc" -eq 0 ]; then verdict="PASS"; else verdict="FAIL"; OVERALL=1; fi
  SUMMARY="${SUMMARY}$(printf '  %-26s %-4s %3ss' "$name" "$verdict" "$dt")
"
}

run_gate "sdk-version-consistency" gate_sdk_version_consistency
run_gate "commitlint"              gate_commitlint

printf '\n=== verify-local summary (mirror of required-checks) ===\n%s' "$SUMMARY"
if [ "$OVERALL" -ne 0 ]; then
  echo "RESULT: FAIL — at least one required gate did not pass."
  exit 1
fi
echo "RESULT: PASS — all required gates green."
exit 0

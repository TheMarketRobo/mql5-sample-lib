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
#   required-checks -> needs: [sdk-version-consistency, sdk-tls-flags, secret-defaults,
#                              mql4-support-claim, commitlint]
#
# Mapping — one local gate per required job:
#
#   | CI job                  | Local gate                                                        |
#   |-------------------------|-------------------------------------------------------------------|
#   | sdk-version-consistency | tools/gate-sdk-version-consistency.sh — THE SAME SCRIPT ci.yml    |
#   |                         | runs. Four assertion sites: the TMKR_SDK_VERSION #define, the     |
#   |                         | CLAUDE.md claim, .release-please-manifest.json, and the newest    |
#   |                         | tag in the SDK submodule (three-way: ahead / equal / behind, the  |
#   |                         | last waived only by SDK_RELEASE_PENDING.md).                      |
#   | sdk-tls-flags           | tools/gate-sdk-tls-flags.sh — same script.                        |
#   | secret-defaults         | tools/gate-secret-defaults.sh — same script.                      |
#   | mql4-support-claim      | tools/gate-mql4-support-claim.sh — same script.                    |
#   | commitlint              | gate_commitlint() — the same packages ci.yml installs             |
#   |                         | (@commitlint/cli@19 + @commitlint/config-conventional@19) in a    |
#   |                         | throwaway dir, config pinned at tools/commitlint.config.cjs       |
#   |                         | (file-form of ci.yml's "-x @commitlint/config-conventional"),     |
#   |                         | linting merge-base(origin/main)..HEAD (the PR range). On main     |
#   |                         | with no branch commits: "nothing to lint" and pass.               |
#
# The four substantive gates are ONE implementation each, called by both this mirror
# and ci.yml. That is deliberate: this file used to carry a hand-copy of the version
# check's sed/grep, and a hand-copy is what drifts. commitlint stays local-only
# because its CI form uses PR-event shas that do not exist on a laptop.
#
# One Δ no local mirror can close: CI reads the submodule at the sha the PR PINS and
# fetches its tags; your checkout may differ. The version gate says so when it does.
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
# Gates 1-4 — mirror of ci.yml jobs sdk-version-consistency, sdk-tls-flags,
# secret-defaults, mql4-support-claim. Each is THE SAME SCRIPT the workflow runs,
# so this mirror cannot drift from CI by transcription.
#
# The version gate additionally reports (report-only) when the local submodule
# checkout differs from the recorded gitlink, since CI tests the pinned sha.
# ---------------------------------------------------------------------------
gate_sdk_version_consistency() { bash "$ROOT/tools/gate-sdk-version-consistency.sh"; }
gate_sdk_tls_flags()           { bash "$ROOT/tools/gate-sdk-tls-flags.sh"; }
gate_secret_defaults()         { bash "$ROOT/tools/gate-secret-defaults.sh"; }
gate_mql4_support_claim()      { bash "$ROOT/tools/gate-mql4-support-claim.sh"; }

# ---------------------------------------------------------------------------
# Gate 5 — mirror of ci.yml job: commitlint
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
run_gate "sdk-tls-flags"           gate_sdk_tls_flags
run_gate "secret-defaults"         gate_secret_defaults
run_gate "mql4-support-claim"      gate_mql4_support_claim
run_gate "commitlint"              gate_commitlint

printf '\n=== verify-local summary (mirror of required-checks) ===\n%s' "$SUMMARY"
if [ "$OVERALL" -ne 0 ]; then
  echo "RESULT: FAIL — at least one required gate did not pass."
  exit 1
fi
echo "RESULT: PASS — all required gates green."
exit 0

# Pending SDK release

**The presence of this file is a debt, not a setting.** It exists only while the SDK version this
repo *claims* has not yet been *published* as a tag a vendor can download.

It is read by CI (`.github/workflows/ci.yml`, job `sdk-version-consistency`) and by the local
mirror (`tools/verify-local.sh`). The machine-readable line is the one below; do not reword it.

```
pending_sdk_tag: v1.3.2
```

## Why it exists (audit `state-path` SDK-10)

The SDK's version is asserted in six places and, before plan `state-path-hardening` P11, the gate
compared two of them:

| # | Assertion | Where | Checked by the gate? |
|---|---|---|---|
| 1 | `#define TMKR_SDK_VERSION` | `Include/themarketrobo/Core/CSDKConstants.mqh` | ✅ hard-fail |
| 2 | `Current SDK version: **vX.Y.Z**` | `CLAUDE.md` | ✅ hard-fail |
| 3 | `.release-please-manifest.json` | this repo | ✅ hard-fail (**new** in P11) |
| 6 | newest git tag in `Include/themarketrobo` | `TheMarketRobo/sdk-mql5-lib` | ✅ **new** in P11 — see below |
| 4 | `sdk-error-codes.test.ts` | `aws/` (private, not checked out here) | ❌ externally owned — errand E-3 |
| 5 | `MIN_REQUIRED_SDK_VERSION` in `sdk-symbols.ts` | `aws/` (private, not checked out here) | ❌ externally owned — a *floor*, not a claim |

Sites 4 and 5 live in the private `aws/` repo, which this repo's CI does not and should not check
out. They are named here so the next reader knows the gate's edge, rather than believing six sites
are covered when four are.

## What the gate does with site 6

Let `DEFINE` be site 1 and `TAG` be the newest tag reachable in the `Include/themarketrobo`
submodule checkout:

| Situation | Verdict |
|---|---|
| `TAG` is **ahead of** `DEFINE` | ❌ **hard fail, always.** A published release the code does not claim is broken in the direction that hurts a vendor: they download something the headers disown. No waiver. |
| `TAG` **equals** `DEFINE` | ✅ pass — **and this file must be deleted.** The gate hard-fails if it is still here, so the debt cannot outlive its repayment. |
| `TAG` is **behind** `DEFINE` | ✅ pass **only if** this file exists and `pending_sdk_tag` equals exactly `v<DEFINE>`. Otherwise ❌ hard fail. |

So the gate can fail in every direction; this file buys a *named, dated* lag, not a silent one.

## Repaying it — errand E-3

At the time of writing, `DEFINE` is `1.3.2` and `TAG` is `v1.2.0`: a vendor following the published
quick-start downloads v1.2.0 and gets headers claiming otherwise. To close it:

1. Merge the `pe/state-path-hardening` branch in `TheMarketRobo/sdk-mql5-lib` (it carries the
   v1.3.2 TLS fix).
2. Tag it **annotated** and push: `git tag -a v1.3.2 -m "SDK v1.3.2" && git push origin v1.3.2`.
   (Annotated and never moved — `.claude/rules/repo-hygiene.md` rule 9.)
3. Bump this repo's `Include/themarketrobo` gitlink to that commit.
4. **Delete this file** in the same PR. The gate now requires `TAG == DEFINE` forever after.
5. Check what `release-please` proposes next: this repo has **zero** tags, so it has never actually
   cut a release. `.release-please-manifest.json` was set to `1.3.2` by hand in P11 to keep site 3
   in lockstep with the SDK. If release-please proposes `1.3.3`, bump `TMKR_SDK_VERSION` and
   `CLAUDE.md` to match rather than letting the wrapper's release version and the SDK's version
   drift apart — the lockstep is the point.
6. Sites 4 and 5 in `aws/`: confirm `MIN_REQUIRED_SDK_VERSION` (currently `1.1.1`) is still the
   intended floor, and that `sdk-error-codes.test.ts` no longer self-skips (audit SDK-3).

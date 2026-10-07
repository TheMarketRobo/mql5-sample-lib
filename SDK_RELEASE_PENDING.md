# SDK release pending

This file exists while the SDK's `#define TMKR_SDK_VERSION` is **ahead of the newest published
git tag** in `TheMarketRobo/sdk-mql5-lib`. It is the declared-debt half of site 6 in
`tools/gate-sdk-version-consistency.sh`, whose verdict on that site is three-way:

| Tag vs define | Verdict |
|---|---|
| tag **ahead** of define | hard fail — no waiver applies; a vendor downloading that release gets headers that disown it |
| tag **equal** to define | fully published — **this file must be deleted**, or the gate fails |
| tag **behind** define | allowed **only** while this file declares the exact pending tag below |

```
pending_sdk_tag: v1.4.3
```

The declared tag must be exactly `v` + the `#define`. The gate fails if it is anything else.

## Why the lag exists right now

SDK 1.4.3 (sdk-mql5-lib #17 and #19) is built and compile-proven, but not released: the fix and the
`TMKR_SDK_VERSION "1.4.3"` bump sit on `sdk-mql5-lib`'s `pe/fleet-sweep-2026-10` branch, and a
customer-facing SDK release waits for the owner's publish decision (hub plan `fleet-sweep-2026-10`,
Phase 9 builds it, the owner-gated Phase 20 releases it). Until then the newest tag is `v1.4.2`,
one patch behind the define, and this file says so instead of the gate failing.

**To repay the debt:** publish the annotated `v1.4.3` tag on `sdk-mql5-lib`, move this repo's
`Include/themarketrobo` gitlink to the tagged commit, and **delete this file in the same change** —
once tag == define the gate fails while it is still present. If the owner declines the publish,
revert this file together with the 1.4.3 identity move (the `CLAUDE.md` claim and the manifest)
instead.

## Sites 4–5 — the externally-owned assertions

The gate checks four of its six sites from this repo. Sites 4 and 5 live in the **private `aws/`
repo**, which this repo's CI does not check out, so they are named here rather than silently
skipped:

| Site | Where | During the lag |
|---|---|---|
| 4 | `aws/src/endpoints/common/sdk-integrator/test/sdk-error-codes.test.ts` | its "SDK version" test derives the expected define from the SDK checkout's newest reachable `v*` tag. On aws `main` it therefore reads **red** against a 1.4.3 checkout until `v1.4.3` is published. aws `d6ee1da3` (fleet-sweep-2026-10 Phase 3, on aws's run branch until that plan releases it) teaches it this file's rule: a define ahead of its tag passes only under an exact `pending_sdk_tag: v<define>` here |
| 5 | `aws/.../sdk-integrator` `MIN_REQUIRED_SDK_VERSION` | does not move: 1.4.3 is additive |

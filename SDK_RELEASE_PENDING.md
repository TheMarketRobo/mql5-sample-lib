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
pending_sdk_tag: v1.3.3
```

The declared tag must be exactly `v` + the `#define`. The gate fails if it is anything else.

## Why the lag exists right now

`mql5-sample-lib` v1.3.3 is this repo's **first `v*` release** (release-please PR #12). Its content
is wrapper-side — blanked committed key defaults, TLS enforcement, and the SDK identity gates.

The gate requires site 1 (the SDK `#define`) and site 3 (`.release-please-manifest.json`) to be
**equal**: this repo's release version and the SDK's version move in lockstep. So publishing v1.3.3
here required `TMKR_SDK_VERSION` to move to `1.3.3` as well
(`sdk-mql5-lib` [#8](https://github.com/TheMarketRobo/sdk-mql5-lib/pull/8), `763563f2`).

But **every `sdk-mql5-lib` commit since `v1.3.2` is CI, githooks or workflow plumbing** — no header,
transport or manager changed, and `MIN_REQUIRED_SDK_VERSION` is unchanged. Cutting a `v1.3.3` SDK
release for that would advertise a library change that did not happen, so the tag was deliberately
withheld and the lag declared here instead.

**To repay the debt:** publish `v1.3.3` on `sdk-mql5-lib` (most naturally when a real SDK change
lands and makes the tag honest), then **delete this file in the same PR** — once tag == define the
gate fails while it is still present.

## Sites 4–5 — the externally-owned assertions

The gate checks four of its six sites from this repo. Sites 4 and 5 live in the **private `aws/`
repo**, which this repo's CI does not check out, so they are named here rather than silently
skipped:

| Site | Where | What it asserts |
|---|---|---|
| 4 | `aws/src/endpoints/common/sdk-integrator/test/sdk-error-codes.test.ts` | the error-code catalog matches the SDK's generated `CSDKErrorCatalog.generated.mqh` |
| 5 | `aws/.../sdk-integrator` `MIN_REQUIRED_SDK_VERSION` | the floor below which the integrator refuses to ship vendor output |

Neither moves for this release: v1.3.3 changes no error code and no SDK source, so
`MIN_REQUIRED_SDK_VERSION` stays where v1.3.2 left it.

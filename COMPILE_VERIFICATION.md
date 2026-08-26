# Compile verification — which platforms a rail actually compiles

This file records, per MetaTrader platform, whether an **automated rail compiles the samples in
this repo**. It is the source of truth for the Platform Support table in `README.md`, and CI
(`.github/workflows/ci.yml`, job `mql4-support-claim`) fails if the two disagree.

The machine-readable lines are these two; do not reword them:

```
mt5_compile_verified: yes
mt4_compile_verified: no
```

## Why this file exists (audit `state-path` SDK-12)

`README.md` published **both** platforms as "Fully supported". Measured, this repo tracks 187
`.mq5` files and **2** `.mq4` files, and the only rail in the fleet that compiles anything here —
the scheduled on-box canary at `MQL52026/compile-service/app/verify/canary.py` — defaults
`platform` to `"mt5"` and defaults its entry point to the `.mq5` twins. **The MQL5 samples are
compiled by the canary; the MQL4 ones are compiled by nothing.**

"Fully supported" was therefore an unbacked claim on the one surface that is already public. The
SDK's MQL4 support is genuinely *built* — `TMR_Platform.mqh` is a real dual-platform compatibility
layer with `#ifdef __MQL4__` sentinel blocks (audit §F.3) — it is simply not *verified*. The README
now says that, and this file is what makes the distinction machine-checkable instead of prose.

## Flipping MQL4 to verified

The MQL4 half of SDK-12 belongs to the `MQL52026` lane, not to this repo — `canary.py` lives there.
When that lane points the canary at the `.mq4` samples (`VERIFY_CANARY_PLATFORM=mt4`, audit §G
recommendation 6):

1. Set `mt4_compile_verified: yes` above.
2. Update the MQL4 row in `README.md`'s Platform Support table to match the MQL5 row's wording.
3. Both in the **same PR** — the `mql4-support-claim` gate fails if they drift, in either direction:
   claiming "Fully supported" without the declaration, *or* declaring `yes` while the README still
   hedges. A stale hedge is a smaller harm than a stale overclaim, but it is still a lie.

## Scope note

This file describes **compile** verification only — that MetaEditor produces a binary from the
tracked sources. It says nothing about runtime behaviour on either platform; the canary's
attach-and-observe step is a separate guarantee, and neither covers a `mode=marketplace`
SDK-bearing indicator entry on either dialect (audit MQL-5, open).

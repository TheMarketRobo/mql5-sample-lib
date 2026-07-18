# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Infrastructure & connections

This repo is an **SDK/source library — nothing here is deployed.** The compiled EAs that consume it
call the platform backend at `https://api.themarketrobo.com` (licence checks, robot-download mint),
which is the **Hetzner box `main-prod`** (renamed from `hetzner-demo` 2026-07-13), not AWS. MQL5 source is compiled to `.ex5` by **MT-CVS**
(`mt-cvs.themarketrobo.xyz`, box `178.104.19.118`) — see `MQL52026/compile-service/`.

Full infrastructure inventory + connection guide: **`../docs/infrastructure-inventory.md`**.

## What This Repo Is

MQL4/MQL5 developer kit and sample implementations for integrating MetaTrader 4 (build 600+) and MetaTrader 5 Expert Advisors (EAs) and Custom Indicators with **TheMarketRobo** platform. The directory layout mirrors the standard MetaTrader `MQL5/` (or `MQL4/`) data folder structure — symlink or copy the repo into that data folder and compile in MetaEditor.

The core SDK lives in `Include/themarketrobo/` as a git submodule pointing at `TheMarketRobo/sdk-mql5-lib`. The SDK ships a single codebase that compiles for both platforms via `#ifdef __MQL4__` / `#ifdef __MQL5__` guards in `TMR_Platform.mqh`. Everything else in this repo is either sample integration code or stock MetaQuotes standard library files.

Current SDK version: **v1.3.1** (defined in `Include/themarketrobo/Core/CSDKConstants.mqh` as `TMKR_SDK_VERSION` — the changelog lives in the comment block above that define). v1.3.1 (2026-07-19) fixed the token-refresh self-DoS: the effective refresh threshold is now clamped to half the token's real lifetime and failed refreshes retry on a 30 s cooldown — previously a threshold ≥ the token lifetime (emitted robots set 300 s against 300 s tokens) produced ~1 `POST /robot/refresh` per second. Earlier: v1.3.0 added the synchronous `ITMKR_SymbolGate` seam; v1.2.1 (2026-07-09) restored the pre-TMKR-rename backwards-compat aliases in `Include/themarketrobo/TMKR_Compat.mqh` — the 2026 rename had shipped without them, which made every legacy-name consumer (these samples included) uncompilable. The Vendor Portal's [SDK Integrator Lambda](#sdk-integrator-pipeline) refuses to ship integrated output for vendors whose local SDK is below `MIN_REQUIRED_SDK_VERSION`.

## Architecture

### SDK Integration Pattern

All integrations extend `CTheMarketRobo_Base` from `<themarketrobo/TheMarketRobo_SDK.mqh>` (single include). The underlying class is now named `CTMKR_RobotBase` after the 2026 TMKR-namespace rename; both names refer to the same type and `IRobotConfig` / `CTheMarketRobo_Bot_Base` are kept as backwards-compatibility aliases so existing vendor code compiles unchanged.

**Robot (Expert Advisor):**
- Constructor: `CTheMarketRobo_Base(uuid, new YourConfig())` — 2-arg, takes a version UUID + `IRobotConfig` implementation
- Init: `on_init(api_key, magic_number)` — registers session via `POST /robot/start`
- Override: `on_tick()`, `on_config_changed(event_json)`, `on_symbol_changed(event_json)`
- Config schema is defined by subclassing `IRobotConfig` with `define_schema()`, `apply_defaults()`, `to_json()`, `update_from_json()`, `update_field()`, `get_field_as_string()`

**Indicator:**
- Constructor: `CTheMarketRobo_Base(uuid)` — 1-arg, no config/magic number
- Init: `on_init(api_key)` — lighter session registration
- Override: `on_calculate(...)` with full MQL5 `OnCalculate` signature
- Indicator buffers must be global (MQL requirement); class handles logic only
- SDK can be compile-time disabled with `#define TMR_SDK_DISABLED` before the SDK include — produces a no-op stub with zero network code or DLL references in the compiled binary

### Cross-Platform (MQL4/MQL5)

`TMR_Platform.mqh` handles all platform differences via `#ifdef __MQL4__` / `#ifdef __MQL5__`:
- **Sentinel values** for MQL5-only enum constants (e.g., `ACCOUNT_MARGIN_MODE`, `SYMBOL_COUNTRY`, `TERMINAL_X64`) — set to `-1` on MQL4, checked with `TMR_IsXPropertyAvailable()`
- **Order type aliases**: `ORDER_TYPE_BUY`/`ORDER_TYPE_SELL` mapped to MQL4's `OP_BUY`/`OP_SELL`
- **Wrapper functions** for APIs whose signatures or availability differ: `TMR_OrderCalcMargin()`, `TMR_ChartIndicatorDelete/Total/Name()`, `TMR_ChartWindowFind()`, `TMR_ChartGetInteger()`, `TMR_MQLInfoString()`, `TMR_MQLInfoInteger()`
- **Platform identifier**: `TMR_PLATFORM` constant (`"mt4"` or `"mt5"`) — sent to backend in session start payload

**MQL4 limitations** (gracefully handled by the SDK):
- `ChartIndicatorDelete()` exists in MQL4 but is restricted to EAs/scripts only — the SDK uses 3-layer secure termination: `ChartIndicatorDelete` (works for self-deletion on many MT4 builds), then functional death (hides all draws, blocks calculation), then a persistent kill file (blocks restart on timeframe change)
- No `OrderCalcMargin()` — margin data reported as 0
- Some `SYMBOL_*` string properties and `ACCOUNT_*` properties are MQL5-only — omitted from payloads on MQL4. Most `TERMINAL_*` properties exist on both platforms (only `TERMINAL_X64` is MQL5-exclusive)
- Indicator buffer setup uses MQL4 syntax: `SetIndexBuffer(idx, buf)` + `SetIndexStyle()` instead of 3-arg `SetIndexBuffer`

### Strategy Tester Bypass (v1.1.0+)

The SDK auto-detects MT4/MT5 Strategy Tester runs and short-circuits the entire session lifecycle — no API key required, no `WebRequest()` calls, no heartbeats. The vendor's `on_tick()` / `on_calculate()` body runs normally; only the SDK plumbing is bypassed.

Detection lives in `TMR_Platform.mqh` and is layered for resilience:

- **Layer 1 (cross-platform):** `MQLInfoInteger(MQL_TESTER / MQL_OPTIMIZATION / MQL_VISUAL_MODE)` — works on MQL4 build 600+ and MQL5.
- **Layer 2 (MT5-only, `#ifdef __MQL5__`):** `MQLInfoInteger(MQL_FRAME_MODE / MQL_FORWARD)` — catches frame mode and forward-testing.
- **Layer 3 (MT4-only, `#ifdef __MQL4__`):** Legacy `IsTesting()` / `IsOptimization()` / `IsVisualMode()`. These MUST stay under `__MQL4__` — MetaEditor 5 rejects them as `undeclared identifier` and there is no compat shim. v1.1.0 shipped Layer 3 unconditionally, which broke MQL5 builds for vendors; v1.1.1 fixed the guard.

Public API:
- `TMR_IsInTester()` — true in any tester run (testing, optimization, visual, frame mode, forward)
- `TMR_IsInOptimization()`, `TMR_IsInVisualMode()`
- `TMR_TesterDetectionTrace()` — returns the name of the signal that fired (`"MQL_TESTER"` etc.) or `"none"`
- `TMR_GetTesterModeLabel()` — returns `"live"`, `"tester"`, `"tester:optimization"`, or `"tester:visual"`

The integrator also rewrites empty-API-key gates so backtests don't abort: an `if(InpApiKey == "") return INIT_FAILED;` becomes `if(InpApiKey == "" && !TMR_IsInTester()) return INIT_FAILED;`.

### MQL4/MQL5 Lifecycle Wiring (both types)

Every MQL4/MQL5 event handler must delegate to the SDK instance (event names are identical on both platforms since MQL4 build 600+):
- `OnInit()` → `instance.on_init(...)`
- `OnDeinit(reason)` → `instance.on_deinit(reason)`
- `OnTimer()` → `instance.on_timer()` (drives heartbeats)
- `OnChartEvent(...)` → `instance.on_chart_event(...)` (SDK custom events: termination, token refresh)
- `OnTick()` → `instance.on_tick()` (robots only)
- `OnCalculate(...)` → `instance.on_calculate(...)` (indicators only)

Always guard calls with `CheckPointer(instance) != POINTER_INVALID`. For vendors who want to collapse the boilerplate, `Include/themarketrobo/TMR_AutoWire.mqh` provides macros (`TMR_DECLARE_ROBOT`, `TMR_DECLARE_INDICATOR`, `TMR_FORWARD_*`).

### Config Schema System (Robots)

`IRobotConfig` subclasses define a typed schema using a builder API:
- Field types: `create_integer`, `create_decimal`, `create_boolean`, `create_radio`, `create_multiple`
- Chained methods: `.with_range()`, `.with_step()`, `.with_precision()`, `.with_option()`, `.with_group()`, `.with_depends_on()`, `.with_description()`, `.with_tooltip()`, `.with_selection_limits()`, `.with_default_selections()`
- Dependencies use `CConfigDependency` with `.set_string_value()` or `.set_bool_value()` for conditional field visibility

### Deferred Self-Removal (Indicators)

When indicator init fails, MQL5 won't fire `OnTimer` / `OnCalculate` if `OnInit` returns failure. The pattern is: return `INIT_SUCCEEDED` anyway, set `g_pending_removal = true`, and call `SDKRemoveIndicatorFromChart(short_name)` on the next timer/calculate tick. If removal fails (common on MQL4), the SDK applies functional death (hides all draws, blocks `OnCalculate`) and writes a persistent kill file that blocks restart on timeframe change. `SDKRemoveIndicatorFromChart` is the legacy name; the post-rename canonical name is `TMKRRemoveIndicatorFromChart` — both work.

## SDK Integrator Pipeline

Vendors don't hand-edit their EAs to add the SDK boilerplate — they upload source through the Vendor Portal and a backend Lambda integrates the SDK automatically. The Lambda lives at `aws/src/endpoints/common/sdk-integrator/` in the sibling `aws/` repo. Relevant cross-cuts:

- The Lambda emits a `-sdk-integrated.{mq4,mq5}` file that `#include`s `<themarketrobo/TheMarketRobo_SDK.mqh>` — vendors compile that file in MetaEditor against THIS repo's `Include/themarketrobo/` headers.
- The Lambda's `validator.ts` runs structural checks on the integrated output. Check #17 (added 2026-05-17) scans for unguarded MQL4-only `IsTesting()` / `IsOptimization()` / `IsVisualMode()` calls — hard error on MQL5 target.
- Symbol rename: SDK class/enum/macro names use the `TMKR_*` namespace post-2026 rename (see `aws/src/endpoints/common/sdk-integrator/src/lib/sdk-symbols.ts` for the authoritative map). Legacy names like `CTheMarketRobo_Base`, `IRobotConfig`, `CJAVal`, `SDKSetLogLevel`, `SDK_LOG_ERROR`, `ENUM_SDK_LOG_LEVEL` remain valid through backward-compat aliases.
- Regression tests for SDK source structure live at `aws/src/endpoints/common/sdk-integrator/test/sdk-headers-platform-guards.test.ts` — these tests **read this repo's `Include/themarketrobo/` files** to assert SDK invariants (enum casts present, `IsTesting()` only inside `#ifdef __MQL4__`, no unprefixed `c0..c9` locals, etc.). If you change SDK headers, run those tests:
  ```bash
  cd ../aws/src/endpoints/common/sdk-integrator && npm test -- --testPathPattern=sdk-headers-platform-guards
  ```

## Key Files

| Path | Role |
|------|------|
| `Experts/sample-ea/SampleTMRBot.mq5` | Reference EA (MQL5) — full SDK integration with 19-field config schema |
| `Experts/sample-ea/SampleTMRBot.mq4` | Reference EA (MQL4) — identical class code, `.mq4` extension |
| `Indicators/sample-in/SampleTMRZigZag.mq5` | Reference indicator (MQL5) — ZigZag + SDK session/heartbeat |
| `Indicators/sample-in/SampleTMRZigZag.mq4` | Reference indicator (MQL4) — adapted buffer setup for MQL4 |
| `Include/themarketrobo/` | SDK submodule (do not edit here; changes go to `TheMarketRobo/sdk-mql5-lib`) |
| `Include/themarketrobo/TheMarketRobo_SDK.mqh` | Single public include — pulls in everything |
| `Include/themarketrobo/TMR_Platform.mqh` | MQL4/MQL5 compatibility layer — platform detection, wrappers, sentinel values, `TMR_IsInTester()` family |
| `Include/themarketrobo/TMR_AutoWire.mqh` | Boilerplate-elimination macros for event handler wiring |
| `Include/themarketrobo/Core/CSDKConstants.mqh` | `TMKR_SDK_VERSION` + `TMR_SDK_DISABLED` toggle + backend URL constants |
| `Experts/Free Robots/` | MetaQuotes candlestick-pattern EAs (CCI/MFI/RSI/Stoch variants) — reference only, not SDK-integrated |
| `Include/Expert/` | MetaQuotes standard Expert framework (signals, money management, trailing) |

## Development

### Setup
```bash
git clone --recurse-submodules <repo_url>
# or if already cloned:
git submodule update --init --recursive
```
Place or symlink repo contents into your MetaTrader 5 `MQL5/` (or MetaTrader 4 `MQL4/`) data folder, then compile the desired `.mq4`/`.mq5` in MetaEditor (F7).

### Testing
- **Local connectivity testing** requires a test license from the [Vendor Portal](https://vendor.themarketrobo.com) — use its API key with the production API (`https://api.themarketrobo.com`); staging has been decommissioned
- **Strategy Tester** runs work without an API key — the SDK auto-detects tester mode and runs offline (`docs/STRATEGY_TESTER_GUIDE.md` in the SDK submodule documents the bypass)
- Unit tests under `Scripts/UnitTests/` are MetaQuotes standard library tests (Alglib, Fuzzy, Generic, Stat), not SDK tests
- There is no CLI build for `.mqh` files — MetaEditor is the only compiler. SDK structural regressions are caught by the Jest tests in the sibling `aws/` repo (see [SDK Integrator Pipeline](#sdk-integrator-pipeline))

### Bumping the SDK submodule pointer

Workflow when a fix lands in `TheMarketRobo/sdk-mql5-lib`:
1. From `Include/themarketrobo/`: pull the new commit on `main`.
2. From `mql5-sample-lib/` root: `git add Include/themarketrobo && git commit -m "chore: bump themarketrobo submodule to ..."`.
3. The parent `hub` repo bumps the `mql5-sample-lib` submodule pointer separately.

### MQL4/MQL5 Conventions
- Language: MQL4/MQL5 (C++-like, `.mq4`/`.mq5` source, `.mqh` headers, `.ex4`/`.ex5` compiled)
- `#property strict` is used in all sample files
- Class naming: `C` prefix (e.g., `CSampleBot`, `CSampleRobotConfig`); SDK-internal classes use the `CTMKR_` namespace prefix
- Input parameters: `Inp` prefix (e.g., `InpApiKey`, `InpDepth`)
- Global pointers: `g_` prefix, always `NULL`-initialized, always `delete` + `NULL` in `OnDeinit`
- SDK-shipped locals that might collide with vendor globals use the `tmkr_` prefix (e.g., `tmkr_i`, `tmkr_c0`, `tmkr_result`) — a recurring source of `declaration of 'X' hides global variable` warnings until SDK v1.1.1
- SDK JSON is handled via `CJAVal` (legacy) / `CTMKR_JAVal` (post-rename canonical) — same class
- SDK log messages use the `"SDK Info: "`, `"SDK Warning: "`, `"SDK Error: "` prefix; user-facing errors go through `SDKUserError()` / `TMKRUserError()`

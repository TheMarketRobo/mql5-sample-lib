# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

MQL4/MQL5 developer kit and sample implementations for integrating MetaTrader 4 (build 600+) and MetaTrader 5 Expert Advisors (EAs) and Custom Indicators with **TheMarketRobo** platform. The directory layout mirrors the standard MetaTrader `MQL5/` (or `MQL4/`) data folder structure.

The core SDK lives in `Include/themarketrobo/` (a git submodule pointing at `TheMarketRobo/sdk-mql5-lib`). Everything else is either sample integration code or stock MetaQuotes standard library files. The SDK uses a single codebase for both platforms via `TMR_Platform.mqh` conditional compilation.

## Architecture

### SDK Integration Pattern

All integrations extend `CTheMarketRobo_Base` from `<themarketrobo/TheMarketRobo_SDK.mqh>` (single include). Two product types exist:

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
- SDK can be compile-time disabled with `#define TMR_SDK_DISABLED` before the SDK include

### Cross-Platform (MQL4/MQL5)

`TMR_Platform.mqh` handles all platform differences via `#ifdef __MQL4__` / `#ifdef __MQL5__`:
- **Sentinel values** for MQL5-only enum constants (e.g., `ACCOUNT_MARGIN_MODE`, `SYMBOL_COUNTRY`, `TERMINAL_X64`) — set to `-1` on MQL4, checked with `TMR_IsXPropertyAvailable()`
- **Order type aliases**: `ORDER_TYPE_BUY`/`ORDER_TYPE_SELL` mapped to MQL4's `OP_BUY`/`OP_SELL`
- **Wrapper functions**: `TMR_OrderCalcMargin()`, `TMR_ChartIndicatorDelete/Total/Name()`, `TMR_ChartWindowFind()`
- **Platform identifier**: `TMR_PLATFORM` constant (`"mt4"` or `"mt5"`) — sent to backend in session start payload

**MQL4 limitations** (gracefully handled):
- `ChartIndicatorDelete()` exists in MQL4 but is restricted to EAs/scripts only — the SDK uses 3-layer secure termination: tries `ChartIndicatorDelete` (works for self-deletion on many MT4 builds), then functional death (hides all draws, blocks calculation), then persistent kill file (blocks restart on timeframe change)
- No `OrderCalcMargin()` — margin data reported as 0
- Some `SYMBOL_*` string properties and `ACCOUNT_*` properties are MQL5-only — omitted from payloads on MQL4. Most `TERMINAL_*` properties exist on both platforms (only `TERMINAL_X64` is MQL5-exclusive)
- Indicator buffer setup uses MQL4 syntax: `SetIndexBuffer(idx, buf)` + `SetIndexStyle()` instead of 3-arg `SetIndexBuffer`

### MQL4/MQL5 Lifecycle Wiring (both types)

Every MQL4/MQL5 event handler must delegate to the SDK instance (event names are identical on both platforms since MQL4 build 600+):
- `OnInit()` → `instance.on_init(...)`
- `OnDeinit(reason)` → `instance.on_deinit(reason)`
- `OnTimer()` → `instance.on_timer()` (drives heartbeats)
- `OnChartEvent(...)` → `instance.on_chart_event(...)` (SDK custom events: termination, token refresh)
- `OnTick()` → `instance.on_tick()` (robots only)
- `OnCalculate(...)` → `instance.on_calculate(...)` (indicators only)

Always guard calls with `CheckPointer(instance) != POINTER_INVALID`.

### Config Schema System (Robots)

`IRobotConfig` subclasses define a typed schema using a builder API:
- Field types: `create_integer`, `create_decimal`, `create_boolean`, `create_radio`, `create_multiple`
- Chained methods: `.with_range()`, `.with_step()`, `.with_precision()`, `.with_option()`, `.with_group()`, `.with_depends_on()`, `.with_description()`, `.with_tooltip()`, `.with_selection_limits()`, `.with_default_selections()`
- Dependencies use `CConfigDependency` with `.set_string_value()` or `.set_bool_value()` for conditional field visibility

### Deferred Self-Removal (Indicators)

When indicator init fails, MQL5 won't fire `OnTimer`/`OnCalculate` if `OnInit` returns failure. The pattern is: return `INIT_SUCCEEDED` anyway, set `g_pending_removal = true`, and call `SDKRemoveIndicatorFromChart(short_name)` on the next timer/calculate tick. If removal fails (common on MQL4), the SDK applies functional death (hides all draws, blocks `OnCalculate`) and writes a persistent kill file that blocks restart on timeframe change.

## Key Files

| Path | Role |
|------|------|
| `Experts/sample-ea/SampleTMRBot.mq5` | Reference EA (MQL5) — full SDK integration with 19-field config schema |
| `Experts/sample-ea/SampleTMRBot.mq4` | Reference EA (MQL4) — identical class code, `.mq4` extension |
| `Indicators/sample-in/SampleTMRZigZag.mq5` | Reference indicator (MQL5) — ZigZag + SDK session/heartbeat |
| `Indicators/sample-in/SampleTMRZigZag.mq4` | Reference indicator (MQL4) — adapted buffer setup for MQL4 |
| `Include/themarketrobo/` | SDK submodule (do not edit here; changes go to `TheMarketRobo/sdk-mql5-lib`) |
| `Include/themarketrobo/TMR_Platform.mqh` | MQL4/MQL5 compatibility layer — platform detection, wrappers, sentinel values |
| `Experts/Free Robots/` | MetaQuotes candlestick-pattern EAs (CCI/MFI/RSI/Stoch variants) — reference only, not SDK-integrated |
| `Include/Expert/` | MetaQuotes standard Expert framework (signals, money management, trailing) |

## Development

### Setup
```bash
git clone --recurse-submodules <repo_url>
# or if already cloned:
git submodule update --init --recursive
```
Place/symlink repo contents into your MetaTrader 5 `MQL5/` (or MetaTrader 4 `MQL4/`) data folder, then compile in MetaEditor.

### Testing
- **Local testing** requires a test license from the [Vendor Portal](https://vendor.themarketrobo.com) — use its API key with staging API (`https://api.staging.themarketrobo.com`)
- Unit tests exist under `Scripts/UnitTests/` but are MetaQuotes standard library tests (Alglib, Fuzzy, Generic, Stat), not SDK tests
- Compile and attach to a chart in MetaTrader 4/5 Strategy Tester or live chart to test SDK connectivity

### MQL4/MQL5 Conventions
- Language: MQL4/MQL5 (C++-like, `.mq4`/`.mq5` source, `.mqh` headers, `.ex4`/`.ex5` compiled)
- `#property strict` is used in all sample files
- Class naming: `C` prefix (e.g., `CSampleBot`, `CSampleRobotConfig`)
- Input parameters: `Inp` prefix (e.g., `InpApiKey`, `InpDepth`)
- Global pointers: `g_` prefix, always `NULL`-initialized, always `delete` + `NULL` in `OnDeinit`
- SDK JSON is handled via `CJAVal` (SDK's JSON class)

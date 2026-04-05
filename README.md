# TheMarketRobo — MQL4/MQL5 Sample Library

This repository contains the complete developer kit and sample implementations for integrating MetaTrader 4 and MetaTrader 5 Expert Advisors and Custom Indicators with TheMarketRobo platform.

## Platform Support

| Platform | Minimum Version | Status |
|----------|----------------|--------|
| MetaTrader 5 | Any | Fully supported |
| MetaTrader 4 | Build 600+ | Fully supported |

The SDK uses a single codebase with conditional compilation (`#ifdef __MQL4__` / `#ifdef __MQL5__`) to support both platforms. The `TMR_Platform.mqh` compatibility header abstracts the few differences between platforms.

## Repository Structure

```text
mql5-sample-lib/
├── Experts/sample-ea/
│   ├── SampleTMRBot.mq5       # Sample EA (MetaTrader 5)
│   └── SampleTMRBot.mq4       # Sample EA (MetaTrader 4)
├── Indicators/sample-in/
│   ├── SampleTMRZigZag.mq5    # Sample Indicator (MetaTrader 5)
│   └── SampleTMRZigZag.mq4    # Sample Indicator (MetaTrader 4)
├── Include/
│   └── themarketrobo/         # TheMarketRobo SDK Submodule
└── README.md
```

## The SDK Submodule

The core logic that communicates with TheMarketRobo Platform lives in the `Include/themarketrobo` folder, which is maintained as a git submodule.

For comprehensive documentation on how the SDK works, its architecture, and the API endpoints it calls:
[**Read the SDK Documentation Here**](Include/themarketrobo/docs/README.md)

### Key Features
- **Cross-Platform:** Single SDK works on both MetaTrader 4 (build 600+) and MetaTrader 5.
- **Session Management:** Graceful start, heartbeat, and termination logic.
- **Config Sync (EAs only):** Real-time remote configuration delivery.
- **Symbol Allowlisting:** Dynamic remote control of allowed trading pairs.
- **Unified Base Class:** Clean object-oriented extension using `CTheMarketRobo_Base`.

## Sample Implementations

### 1. Sample Expert Advisor
- **MQL5:** `Experts/sample-ea/SampleTMRBot.mq5`
- **MQL4:** `Experts/sample-ea/SampleTMRBot.mq4`

The sample Expert Advisor demonstrates a fully-featured integration including:
- Defining an `IRobotConfig` to expose remotely configurable inputs (like Take Profit, Allow Trading).
- Inheriting from `CTheMarketRobo_Base`.
- Handling SDK callbacks like `on_config_changed` and `on_symbol_changed`.

The MQL4 and MQL5 EA samples share identical class code. The SDK's platform abstraction layer handles all differences internally.

### 2. Sample Custom Indicator
- **MQL5:** `Indicators/sample-in/SampleTMRZigZag.mq5`
- **MQL4:** `Indicators/sample-in/SampleTMRZigZag.mq4`

The sample Custom Indicator demonstrates a lighter integration path that:
- Uses the 1-argument indicator constructor to bypass config/magic_number requirements.
- Implements the `OnCalculate` event loop by overriding `on_calculate` in the SDK base class.
- Retains secure session registration and telemetry heartbeats.

The MQL4 version adapts the indicator buffer setup to use MQL4-style `SetIndexBuffer()` and `SetIndexStyle()` calls. The SDK class code and ZigZag logic remain identical.

## Quick Start

1. Clone this repository (with submodules): `git clone --recurse-submodules <repo_url>`
2. Place the contents logically within your MetaTrader data folder:
   - **MT5:** `MetaTrader 5/MQL5/` directory
   - **MT4:** `MetaTrader 4/MQL4/` directory
3. Ensure you have an active **API Key** from TheMarketRobo. **For local testing**, generate a new **test license** from your [Vendor Portal](https://vendor.themarketrobo.com) and use its API key with the staging API (`https://api.staging.themarketrobo.com`).
4. Compile the Sample EA or Indicator using MetaEditor.
5. Attach to a chart and input your API Key to initialize the secure session!

## MQL4 Notes

- **Minimum build:** MQL4 build 600+ is required for OOP support (classes, virtual functions, inheritance).
- **Indicator self-removal:** MQL4 does not support programmatic indicator removal (`ChartIndicatorDelete` is MQL5-only). On MQL4, the SDK will stop the timer and alert the user to manually remove the indicator.
- **Symbol properties:** Some symbol metadata fields (country, sector, industry, etc.) are MQL5-only. These are gracefully omitted on MQL4.
- **OrderCalcMargin:** MQL4 has no equivalent of `OrderCalcMargin()`. Margin data will be reported as 0 (unavailable) on MQL4.

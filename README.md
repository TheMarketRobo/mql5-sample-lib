# TheMarketRobo — MQL5 Sample Library

This repository contains the complete developer kit and sample implementations for integrating MetaTrader 5 Expert Advisors and Custom Indicators with TheMarketRobo platform.

## Repository Structure

```text
mql5-sample-lib/
├── Experts/sample/        # Sample Expert Advisor implementation
│   └── SampleTMRBot.mq5   # The EA integrating the SDK
├── Indicators/sample-in/  # Sample Custom Indicator implementation
│   └── SampleTMRZigZag.mq5# The Indicator integrating the SDK
├── Include/
│   └── themarketrobo/     # TheMarketRobo SDK Submodule
└── README.md
```

## The SDK Submodule

The core logic that communicates with TheMarketRobo Platform lives in the `Include/themarketrobo` folder, which is maintained as a git submodule.

For comprehensive documentation on how the SDK works, its architecture, and the API endpoints it calls:
👉 [**Read the SDK Documentation Here**](Include/themarketrobo/docs/README.md)

### Key Features
- **Session Management:** Graceful start, heartbeat, and termination logic.
- **Config Sync (EAs only):** Real-time remote configuration delivery.
- **Symbol Allowlisting:** Dynamic remote control of allowed trading pairs.
- **Unified Base Class:** Clean object-oriented extension using `CTheMarketRobo_Base`.

## Sample Implementations

### 1. Sample Expert Advisor
Location: `Experts/sample/SampleTMRBot.mq5`

The sample Expert Advisor demonstrates a fully-featured integration including:
- Defining an `IRobotConfig` to expose remotely configurable inputs (like Take Profit, Allow Trading).
- Inheriting from `CTheMarketRobo_Base`.
- Handling SDK callbacks like `on_config_changed` and `on_symbol_changed`.

### 2. Sample Custom Indicator
Location: `Indicators/sample-in/SampleTMRZigZag.mq5`

The sample Custom Indicator demonstrates a lighter integration path that:
- Uses the 1-argument indicator constructor to bypass config/magic_number requirements.
- Implements the MQL5 `OnCalculate` event loop by overriding `on_calculate` in the SDK base class.
- Retains secure session registration and telemetry heartbeats.

## Quick Start

1. Clone this repository (with submodules): `git clone --recurse-submodules <repo_url>`
2. Place the contents logically within your `MetaTrader 5/MQL5` data folder (or map it as an active project).
3. Ensure you have an active **API Key** from TheMarketRobo. **For local testing**, generate a new **test license** from your [Vendor Portal](https://vendor.themarketrobo.com) and use its API key with the staging API (`https://api.staging.themarketrobo.com`).
4. Compile the Sample EA or Indicator.
5. Attach to a chart and input your API Key to initialize the secure session!

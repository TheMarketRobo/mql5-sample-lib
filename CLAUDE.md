# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Infrastructure & connections

This repo is an **SDK/source library — nothing here is deployed.** The compiled EAs that consume it
call the platform backend at `https://api.themarketrobo.com` (licence checks, robot-download mint),
which is the **Hetzner box `main-prod`** (renamed from `hetzner-demo` 2026-07-13), not AWS. MQL5 source is compiled to `.ex5` by **MT-CVS**
(`mt-cvs.themarketrobo.xyz`, box `178.104.19.118`) — see `MQL52026/compile-service/`.

Full infrastructure inventory + connection guide: **`../docs/infrastructure-inventory.md`**.

## graphify

**This repo has no knowledge graph** — it is small enough to read directly, so don't go looking for
`graphify-out/`. If a task genuinely needs one, `/graphify .` builds it (AST-only, no LLM cost) and
you must then add its stats here.

The MQL5 graph you probably want is in **`../MQL52026/`** (8,577 nodes, committed) — the framework,
Experts and Indicators live there. Query it from that repo root with `graphify explain "<Node>"` /
`graphify query "<question>" --budget 1200`; 🚫 never `Read` a `GRAPH_REPORT.md` or `graph.json`
whole, and don't invoke the `/graphify` skill just to ask a question (~12k tokens of SKILL.md — the
CLI alone answers reads). Full contract: `../.claude/rules/graphify.md`.

## Code intelligence — MCP servers

**`serena`** — LSP semantic navigation. Call `activate_project <this repo's path>` first, then
prefer its symbol tools over `grep` whenever you need *exact* references: grep finds strings,
serena finds bindings. **`semgrep`** — 5000+ deterministic rules for injection / authz / unsafe
patterns; scans locally, nothing uploaded. Reach for it **before** hand-auditing a diff
(`semgrep scan --config p/default <path>`). Contract + traps: `../.claude/rules/code-intelligence-mcp.md`.

No `codeatlas` instance is registered for this repo — use graphify for architecture questions.

## What This Repo Is

MQL4/MQL5 developer kit and sample implementations for integrating MetaTrader 4 (build 600+) and MetaTrader 5 Expert Advisors (EAs) and Custom Indicators with **TheMarketRobo** platform. The directory layout mirrors the standard MetaTrader `MQL5/` (or `MQL4/`) data folder structure — symlink or copy the repo into that data folder and compile in MetaEditor.

The core SDK lives in `Include/themarketrobo/` as a git submodule pointing at `TheMarketRobo/sdk-mql5-lib`. The SDK ships a single codebase that compiles for both platforms via `#ifdef __MQL4__` / `#ifdef __MQL5__` guards in `TMR_Platform.mqh`. Everything else in this repo is either sample integration code or stock MetaQuotes standard library files.

Current SDK version: **v1.3.2** (defined in `Include/themarketrobo/Core/CSDKConstants.mqh` as `TMKR_SDK_VERSION` — the changelog lives in the comment block above that define). v1.3.2 (2026-08-25) restored TLS certificate validation on the indicator transport: `CWinINetHttpService` had built its WinINet flags with `INTERNET_FLAG_IGNORE_CERT_CN_INVALID | _DATE_INVALID` set **unconditionally**, so every request it made — each carrying the vendor API key and the session token — accepted any CA-issued certificate for any hostname, expired or not. Both flags now compile in only under an opt-in `TMKR_INSECURE_TLS_DEBUG` macro that is defined nowhere in the shipped tree (CI job `sdk-tls-flags` fails if they go unconditional again). The EA transport (`CHttpService`/`WebRequest`) was never affected. Earlier: v1.3.1 (2026-07-19) fixed the token-refresh self-DoS: the effective refresh threshold is now clamped to half the token's real lifetime and failed refreshes retry on a 30 s cooldown — previously a threshold ≥ the token lifetime (emitted robots set 300 s against 300 s tokens) produced ~1 `POST /robot/refresh` per second. Earlier: v1.3.0 added the synchronous `ITMKR_SymbolGate` seam; v1.2.1 (2026-07-09) restored the pre-TMKR-rename backwards-compat aliases in `Include/themarketrobo/TMKR_Compat.mqh` — the 2026 rename had shipped without them, which made every legacy-name consumer (these samples included) uncompilable. The Vendor Portal's [SDK Integrator Lambda](#sdk-integrator-pipeline) refuses to ship integrated output for vendors whose local SDK is below `MIN_REQUIRED_SDK_VERSION`.

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

## Local verification

**Tier 1 (`pre-commit`) and tier 2 (`pre-push`) are deliberately absent, and `commit-msg` is
deliberately present.** Much of the MQL source here — the stock MetaQuotes standard-library files
under `Include/`, `Indicators/Examples/`, and every `.chr`/`.set` profile — is UTF-16LE + CRLF, and
the fleet's text hooks (trailing-whitespace, end-of-file-fixer, formatters) would **rewrite and
corrupt** those files, which is why local-ci-fast-feedback P3 skipped this repo. `commit-msg` is the
one hook that class of hazard does not reach: it reads `.git/COMMIT_EDITMSG` (always UTF-8, written
by git) and touches no repo file. ci-cd-hardening P13 adopted it (ledger L-13).

```bash
bash tools/install-hooks.sh          # wires core.hooksPath -> .githooks (worktree-scoped)
bash tools/install-hooks.sh --check  # report only
```

The hook's rules are `tools/commit-msg.sh`, a **byte-identical copy** of hub's
`scripts/templates/commit-msg.sh`; `.githooks/commit-msg` is a thin shim supplying only this repo's
type vocabulary. 🚫 Never edit the copy in place — `verify-local.sh`'s `gate0` `cmp`s it against
hub's master and a forked rule set is drift by definition. `--no-verify` is emergency-only and the
commit body must say why; CI runs the full `commitlint` and will red the PR anyway.

**Tier 3 — the full required-checks mirror:**

```bash
bash tools/verify-local.sh
```

(`tools/`, deliberately not the fleet-standard `scripts/`: this repo tracks the MetaTrader
data-folder directory `Scripts/`, and on case-insensitive dev machines (`core.ignorecase=true`) a
distinct lowercase `scripts/` cannot exist — `git add scripts/…` case-folds into `Scripts/` and
silently stages nothing. Do not "normalize" the path back.)

It mirrors `.github/workflows/ci.yml`'s `required-checks` aggregator, which since
delivery-overhaul P3 has aggregated **five** jobs — `needs: [sdk-version-consistency, sdk-tls-flags,
secret-defaults, mql4-support-claim, commitlint]`. (This section claimed a two-job aggregator until
ci-cd-hardening P13; the generated `.github/required-checks.snapshot` is now the machine-checked
answer, asserted equal to both the `needs:` list and the live branch ruleset by hub's
`scripts/verify-ci-invariants.sh`.) One local gate per required job:

| CI job | Local gate |
|---|---|
| `sdk-version-consistency` | `tools/gate-sdk-version-consistency.sh` — **the same script ci.yml runs.** Four assertion sites: the `TMKR_SDK_VERSION` `#define` in `Include/themarketrobo/Core/CSDKConstants.mqh`, the "Current SDK version: **vX.Y.Z**" claim in this file (the line CI parses — never reword it), `.release-please-manifest.json`, and the newest tag in the SDK submodule (three-way: ahead / equal / behind, the last waived only by `SDK_RELEASE_PENDING.md`) |
| `sdk-tls-flags` | `tools/gate-sdk-tls-flags.sh` — same script. `TMKR_INSECURE_TLS_DEBUG` is `#define`d nowhere, and every `IGNORE_CERT` mention sits inside a guard region or a comment |
| `secret-defaults` | `tools/gate-secret-defaults.sh` — same script. No credential-shaped `input string` default or `.chr`/`.set` profile value is non-empty (UTF-16 decoded before matching) |
| `mql4-support-claim` | `tools/gate-mql4-support-claim.sh` — same script. `README.md`'s "Fully supported" claims ⇔ `COMPILE_VERIFICATION.md`'s declared state, in both directions |
| `commitlint` | the same packages ci.yml installs (`@commitlint/cli@19` + `@commitlint/config-conventional@19`, config pinned at `tools/commitlint.config.cjs`) over `merge-base(origin/main)..HEAD`. An **empty** range reports `NOTE`, never `PASS` — `commitlint` exits 0 on zero commits, and calling that a pass claims a gate ran when nothing did |

The verb also runs three **local-only** gates, labelled as such in its header so nobody mistakes
them for CI: `gate0` (the three copied templates are byte-identical to hub's), `commit-msg-hook`
(red-proves the hook — a bad subject must be REFUSED and a good one accepted; "the file exists" is
a claim every uninstalled hook could also make), and `workflow-lint` (`tools/lint-workflows.sh` =
`actionlint` + `zizmor --pedantic` against the committed `.github/zizmor-baseline.txt`). The
workflow lint is deliberately **not** a CI job: installing zizmor on a runner would cost more
billed minutes per PR than this repo's whole gate matrix, and running it on every workflow edit is
already a standing local duty (`../.claude/rules/local-verification.md`). If it is ever promoted,
it joins `required-checks`'s `needs:` and that header in the same PR.

The zizmor baseline is a **shrink-only ratchet**: a new finding fails, and a row that stops firing
also fails until it is deleted. 🚫 Never add a row to silence a new finding — fix the workflow, or
say in the row's reason why the risk is accepted. P13 took this repo from 26 findings to 7 (every
High to zero) by SHA-pinning every action, moving `release-please`'s write scopes onto its one job,
reading commitlint's `${{ }}` values through `env:`, and setting `persist-credentials: false` on the
four checkouts that make no later git network call.

`.github/workflows/release-please.yml` runs on pushes to `main` only (release automation) — it is
not a PR gate and is not mirrored. **Maintenance contract:** any change to ci.yml's required
checks (the aggregator's `needs:` list or a mirrored step's commands) updates
`tools/verify-local.sh`'s mapping header **and** `.github/required-checks.snapshot`
(`bash ../scripts/gen-required-checks-snapshot.sh mql5-sample-lib .github/workflows/ci.yml`) in the
same PR.

**Trap — `ci.yml`'s push `paths-ignore` is four entries long on purpose.** Nearly everything here is
a gate input: `CLAUDE.md` and `.release-please-manifest.json` feed `sdk-version-consistency`,
`README.md`/`COMPILE_VERIFICATION.md` feed `mql4-support-claim`, every `.mq4`/`.mq5`/`.mqh`/`.chr`/
`.set` feeds the two SDK scans, and `tools/**` *is* the gate implementations. An "obvious"
`**/*.md` filter would let a version claim land on `main` unchecked. Check any new entry against the
list written into the workflow before adding it.

## The nested SDK repo (`Include/themarketrobo`)

`TheMarketRobo/sdk-mql5-lib` is a separate public repository, and since ci-cd-hardening P13 it has
CI of its own: `sdk-tls-flags` + `secret-defaults` + `commitlint` behind a `required-checks`
aggregator, `bash tools/verify-local.sh` as its tier-3 verb, and the same `commit-msg` hook. Its
gates scan **its own** tracked sources; this repo's scan the union of both trees, so the SDK's
transport is checked twice and cannot regress on either side of the gitlink. Bumping the pointer is
still the three-step flow in [Bumping the SDK submodule pointer](#bumping-the-sdk-submodule-pointer)
— now with the SDK's own PR gate in front of it.

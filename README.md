# Gold Trades — Breakout EA (MetaTrader 5)

`MT5/Experts/GoldTradesBreakoutEA.mq5` is an MQL5 Expert Advisor built from the
trading rules behind the **Gold Trades** Pine indicator.

## The rules it trades

| | |
|---|---|
| **Entry** | Price breaks above the last **confirmed pivot high** (resistance) |
| **Filter** | Fast MA (9) must be **above** the slow MA (20), read on the closed bar |
| **Exit** | The bar **closes under the 9 MA** |
| **Direction** | Long only |
| **Window** | Entries only during the first 2 hours of the New York session (09:30–11:30 ET) |

Exits are **not** restricted to the window — once you are in, the trade is
managed until it closes under the 9 MA, whatever the time (unless you switch on
`InpCloseAtWindowEnd`).

## Install

1. In MetaTrader 5: **File → Open Data Folder**.
2. Copy `GoldTradesBreakoutEA.mq5` into `MQL5\Experts\`.
3. In MetaEditor press **F7** to compile.
4. Drag the EA onto a gold chart, tick **Allow Algo Trading**.

## Setting the trading window

The EA converts 09:30 New York time into your broker's server time, so it stays
correct across US daylight-saving changes. You only have to tell it one thing:

- `InpBrokerGmtOffsetWin` — your broker's GMT offset **in winter**
  (most brokers are GMT+2 in winter / GMT+3 in summer → enter `2`).
- `InpBrokerFollowsUsDst` — leave `true` for those brokers.

On attach the EA prints the resolved window to the **Experts** tab, e.g.
`Trading window resolved to 16:30 - 18:30 server time (120 min)`. Check that
line matches the 09:30 candle on your chart. If your broker's clock is unusual,
set `InpUseManualWindow = true` and type the start time in server time directly.

The panel in the top-left of the chart shows the window, the 9/20 state, the
current resistance level and whether you are in a trade.

## Inputs worth knowing

**Resistance**
- `InpPivotLeft` / `InpPivotRight` (5/5) — a pivot high needs 5 higher-free bars
  either side. The right side is a **confirmation delay**: the level only becomes
  tradeable 5 bars after the high printed. This matches the indicator.
- `InpBreakMode`
  - `BREAK_ON_CLOSE` *(default)* — enter on the open of the next bar after a bar
    closes above the level. Fewer fakeouts, worse fill.
  - `BREAK_ON_TOUCH` — enter intrabar the moment price trades through. Better
    fill, more fakeouts.
- `InpBreakBufferPts` — require the break by this many points, to filter noise.
- `InpOneEntryPerLevel` — stops the EA re-buying the same level repeatedly.

**Stops — read this**
The rules as you described them have no stop; the only exit is the close under
the 9 MA. That leaves an open trade unprotected through a gap or a disconnect,
so `InpStopMode` defaults to **`SL_SWING_LOW`** (below the lowest low of the last
10 bars, plus a pad). This is an addition on my part, not part of your rules —
**set `InpStopMode = SL_NONE` if you want backtests that match your rules
exactly.** `SL_ATR` and `SL_POINTS` are also available.

`InpTakeProfitR` is off by default (`0`), so the MA close is the only exit.

**Sizing**
- `LOT_FIXED` *(default)* uses `InpFixedLots`.
- `LOT_RISK_PCT` risks `InpRiskPercent` of balance against the stop distance —
  requires a stop mode other than `SL_NONE`.

**Housekeeping**
`InpMaxTradesPerDay` (0 = unlimited), `InpMaxSpreadPts` (0 = off),
`InpMagic`, `InpDeviationPts`.

## How it differs from the Pine indicator

The indicator does a lot more than this strategy needs (ATR panel, matrix
dashboard, extension meter). Only the parts that generate the trade were carried
over. Two deliberate differences:

- The indicator's entry dots also require price above the **1D 200 MA**. Your
  stated rule is 9 > 20 only, so that filter is not in the EA. Add it back by
  putting a 200-period daily MA check next to `maFilter` if you want it.
- The indicator uses `Auto-adjust Entry Pivots by TF` (3/3 on M5, 8/8 on H1 …).
  The EA uses fixed `InpPivotLeft`/`InpPivotRight` so a backtest is reproducible —
  set them to match the timeframe you trade.

## Before running it live

The source has **not** been compiled or backtested here — this container has no
MetaTrader. Compile it in MetaEditor, then run it in the Strategy Tester on your
own gold symbol and timeframe (every-tick modelling) before putting money behind
it. Check in particular that the resolved session window lines up with your
broker's 09:30 ET candle.

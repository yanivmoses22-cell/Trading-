# Gold Trades — Breakout EA (MetaTrader 5)

`MT5/Experts/GoldTradesBreakoutEA.mq5` is an MQL5 Expert Advisor built from the
trading rules behind the **Gold Trades** Pine indicator.

## The rules it trades

| | |
|---|---|
| **Entry** | Price breaks above the **ceiling of a validated consolidation range** |
| **Filter** | Fast MA (9) must be **above** the slow MA (20), read on the closed bar |
| **Size** | Risk % of equity against the stop, then scaled by two extension gates |
| **Fill** | 50% on the breakout, the other 50% if the first bar in the trade closes green |
| **Adds** | A further slice at each +1R, capped |
| **Exit** | The bar **closes under the 9 MA** |
| **Direction** | Long only |
| **Window** | Entries only during the first 2 hours of the New York session (09:30–11:30 ET) |

Exits are **not** restricted to the window — once you are in, the trade is
managed until it closes under the 9 MA, whatever the time (unless you switch on
`InpCloseAtWindowEnd`).

## Install and run it in MetaTrader 5

### 1. Get it compiled

1. MetaTrader 5 → **File → Open Data Folder**.
2. Drop `GoldTradesBreakoutEA.mq5` into `MQL5\Experts\`.
3. **Tools → MetaQuotes Language Editor** (or F4), find the file in the Navigator,
   press **F7**.
4. You want `0 errors, 0 warnings`. The EA then appears under Expert Advisors in
   the terminal's Navigator — right-click → **Refresh** if it doesn't.

### 2. Attach it

1. Open an **M5** chart of the symbol you trade. Timeframe matters: the 150 MA
   and the day-open check both read the chart timeframe, so M5 is what the
   settings are built around.
2. Check your symbol name — brokers differ (`XAUUSD`, `GOLD`, `XAUUSD.m`,
   `XAUUSD.pro`). Use the exact one from Market Watch.
3. Drag the EA on. In the dialog: **Common** tab → tick **Allow Algo Trading**.
4. Toolbar **Algo Trading** button must be green too — the per-EA tick alone is
   not enough.
5. A smiley face in the top-right of the chart means it is running.

### 3. Verify the session window — do not skip this

The single most likely thing to silently break is the trading window, because it
depends on your broker's clock.

1. Open the **Toolbox → Experts** tab. On attach the EA prints:
   `Trading window resolved to 16:30 - 18:30 server time (120 min).`
2. Find 09:30 New York on your chart and check it matches that server time. The
   chart's time axis is in **server** time; Market Watch shows the server clock.
3. If it is wrong, fix `InpBrokerGmtOffsetWin` (your broker's **winter** GMT
   offset — 2 for a GMT+2/+3 broker) and re-check. If your broker's clock is
   unusual, set `InpUseManualWindow = true` and type the start time directly.
4. The on-chart panel shows `Window ... [OPEN]` or `[closed]` live. Watch it hit
   `OPEN` at the right moment before you trust it with money.

### 4. Backtest it here too

**Ctrl+R** opens the Strategy Tester.

- **Expert**: GoldTradesBreakoutEA · **Symbol**: your gold symbol · **Period**: M5
- **Modelling**: *Every tick based on real ticks*. Anything faster will misprice
  the intrabar stop-outs and flatter the results.
- **Date range**: at least a year, and check the trade count — the window plus
  the range test plus two extension gates filter hard.
- Leave optimisation off until the plain run looks sane.

Expect MT5 and TradingView to disagree even with identical settings: different
data feeds, different gold contracts, real spread versus none. Use TradingView to
find settings, MT5 to confirm them.

### 5. Settings to check before the first run

| Input | Why |
|---|---|
| `InpBrokerGmtOffsetWin` | Wrong value = wrong session = wrong strategy |
| `InpLevelSource` | `LEVEL_RANGE_HIGH` for the range breakout, `LEVEL_PIVOT_HIGH` for plain swing highs |
| `InpExtLookback` | 500 bars on M5 is only ~1.7 days of 24h gold, or ~6 days of a 6.5h equity session. Raise it to 1500–2000 for a month of context |
| `InpRiskPercent` | Risk on the **full** planned position, before the gates cut it |
| `InpStopPadPts` | In **points**, not dollars. On gold `_Point` is usually 0.01, so 20 = $0.20 |
| `InpMagic` | Change it if you run more than one EA on the same symbol |

Two things that will stop it trading silently rather than loudly:

- **Lot rounding.** Risk-based sizing on a small account can round the planned
  size below your broker's minimum lot. The EA prints *"Planned size rounds below
  the broker minimum"* to the Experts tab and skips the trade.
- **Extension gates.** A red `Size gate: NO TRADE` on the panel means a gate
  blocked the day. That is the gate working, not a bug.

### 6. Running it unattended

The EA is code running **inside** the terminal — your broker's server has no idea
it exists. So MetaTrader must be running, the chart must stay open (minimised is
fine), and the machine must be awake and online. That is what a VPS is for:
MT5's own **Virtual Hosting** (right-click the account in Navigator → *Register a
Virtual Server*) migrates the chart, the EA and its inputs to a machine in the
broker's datacentre for roughly $10–15/month.

What survives a terminal restart, and what does not:

| | Survives? |
|---|---|
| Stop loss | **Yes** — it sits on the broker's server, and fills with MT5 closed |
| Exit on close under the 9 MA | Yes — the EA only needs to see an open position |
| Planned size, entry, 1R, adds taken | **Yes, since v1.21** — persisted to terminal global variables |
| Everything else (day trade count, day-open gate verdict) | Yes, if the restart is on the same day |

On restart the EA prints what it recovered, e.g.
`Restored open trade: 0.10 of planned 0.20 lots, entry 2401.50, 1R = 4.30, adds 1/3.`
If it instead prints *"Open position found with no saved state"*, the position is
still managed to the 9 MA exit but will take no further adds — check that before
assuming the trade is being scaled.

State keys are namespaced per symbol **and** magic number, so seven charts never
collide. Stored day state is stamped with the date and ignored if it is stale, so
yesterday's trade count never carries into today.

### 7. Before it sees real money

Run it on a **demo account** for a few weeks first and reconcile every fill
against the panel and the Experts log. A backtest cannot show you a broker
rejecting an order, a stop level being refused, or a fill mode mismatch.

## What counts as a range

This is the part that does the cherry-picking. A swing high on its own is not a
setup — price makes new swing highs all the way up a trend. A *range* breakout
needs price to have gone sideways and been rejected at a ceiling first.

Over the last `InpRangeBars` bars (default 20, **excluding** the breakout bar),
the EA takes the highest high and lowest low as the box, then applies two tests:

1. **Tightness** — `height / ATR <= InpMaxRangeATR` (default 3.0). A trending
   leg covers far more than 3 ATR in 20 bars, so it fails here. This is the test
   that rejects "new high in a runaway move".
2. **Touches** — the ceiling must have been tested at least `InpMinTouches`
   times (default 2), counting any bar whose high came within
   `InpTouchTolATR` × ATR of it (default 0.15). One touch is a spike; two or
   more is resistance.

If either test fails there is **no level**, and therefore no trade, no matter
what price does. The chart panel shows the box, its height in ATR, the touch
count and `VALID` / `rejected` live, so you can tune the two thresholds by
watching them against setups you'd actually take.

Because the range window sits entirely behind the trigger bar, a break of the
ceiling is always a genuinely new high — there is no way to re-fire on the same
break, and after a breakout the box widens past the tightness test on its own.

**Tuning:** lower `InpMaxRangeATR` (2.0–2.5) for tighter, rarer coils; raise
`InpMinTouches` to 3 for more-tested ceilings; raise `InpRangeBars` for longer
bases. Every one of these makes the EA more selective.

Set `InpLevelSource = LEVEL_PIVOT_HIGH` to go back to the plain swing-high
breakout with no range requirement.

## The two extension gates

Both answer the same question — *is price already stretched?* — and both are
measured as a **percentile against their own recent history**, not as a fixed
percentage. A fixed % cannot work on two timeframes at once: price sits far
closer to a 150 MA on M5 than on D1, so "2% is extended" is meaningless without
retuning per chart. A percentile is self-calibrating.

Each gate returns a size multiplier, and the **more restrictive one wins**:

| Percentile | Multiplier | Meaning |
|---|---|---|
| below 70 | ×1.0 | normal, full planned size |
| 70–90 | ×0.5 | stretched, half size |
| 90+ | ×0.0 | too extended, no trade |

**Gate 1 — stretch from the 150 MA** (`InpUseExtFilter`). Ranked over the last
500 bars. Only a stretch *above* the MA counts against a long; if price is below
the 150 MA the gate passes at ×1.0, since being below it is not a reason to
refuse an upside breakout.

**Gate 2 — day open versus the 9 MA** (`InpUseOpenCheck`). Evaluated **once a
day, at the close of the first bar of the window**. On an M5 chart that is
literally "once the 5-minute closes". If price is above the 9 MA at that close
and the stretch ranks high, the multiplier applies **for the whole day**. If
price opened below the 9 MA the gate does not apply.

Both gates need history to warm up. Until then they report `n/a` on the panel
and pass at ×1.0 — they do not silently block trades.

## Sizing, scale-in and pyramiding

**Base size** is dynamic: `(risk% × equity) ÷ distance to the stop`. A wide range
gives a smaller position, a tight one a bigger position, and every trade risks the
same money. The extension gates then cut that by half or to zero.

**The split.** The breakout bar is the green candle you enter on. The very next
bar is your first bar in the trade — if *it* closes green, the remaining 50% goes
on. If it closes red the second half is skipped permanently; the EA never adds it
late.

**The +1R adds.** Each time price gains another multiple of the original stop
distance, a slice worth 50% of the planned size is added, up to `InpMaxAdds`.

### Read this before turning off breakeven-on-add

Adding at +1R with the original stop untouched roughly **doubles** your risk on a
trade that was already working:

- Full position `P`, stop distance `D`. Original risk `P × D` = **1R**.
- At +1R you add `0.5P`. That slice sits `2D` above the stop, so it carries
  `0.5P × 2D` = **1R** of risk by itself.
- Stopped out now, you lose **2R** — after being up 1R.

`InpBreakEvenOnAdd` (default **on**) moves the stop to your entry on the first
add, which caps total open risk near 0.5R. Leave it on unless you have a reason
not to, and compare max drawdown both ways in the tester before you decide.

If the planned size is small enough that half of it rounds below your broker's
minimum lot, the EA takes the whole planned size at once rather than splitting.

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

**Range** — `InpRangeBars`, `InpMaxRangeATR`, `InpMinTouches`, `InpTouchTolATR`;
see the section above.

**Pivot high** (only used when `InpLevelSource = LEVEL_PIVOT_HIGH`)
- `InpPivotLeft` / `InpPivotRight` (5/5) — a pivot high needs 5 higher-free bars
  either side. The right side is a **confirmation delay**: the level only becomes
  tradeable 5 bars after the high printed. This matches the indicator.

**Breakout**
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
so `InpStopMode` defaults to **`SL_RANGE_LOW`** — just under the floor of the box
you just broke out of, which is the natural invalidation for a range breakout.
A stop is now structural rather than optional: risk-based sizing and the +1R add
spacing are both measured in units of the stop distance, so there is no longer a
"no stop" mode. `SL_SWING_LOW`, `SL_ATR` and `SL_POINTS` are the alternatives.

`InpTakeProfitR` is off by default (`0`), so the MA close is the only exit.

**Sizing / scale-in** — `InpRiskPercent`, `InpInitialPct`, `InpAddOnGreen`,
`InpPyramid`, `InpPyramidPct`, `InpMaxAdds`, `InpBreakEvenOnAdd`; see above.
`InpLotMode = LOT_FIXED` swaps the risk-based base size for a flat lot, which the
gates still scale.

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
- The indicator has no concept of a range at all; its entry dots fire on any
  swing-high cross. The range tests above are new, and are what make the EA
  selective in the way the manual process is.

## Reading the backtest now that sizing varies

Scaling in makes win rate *less* informative, not more. A trade that took the
green add and three +1R adds is a completely different bet from one that got half
size on a warn-band day and stopped out. Compare **Net Profit** and **Max
Drawdown** across settings; win rate on its own will mislead you here.

Also watch the trade count. A two-hour window, a validated-range requirement and
two extension gates stack multiplicatively — it is easy to filter your way down
to a dozen trades and a beautiful, meaningless equity curve. Check the count
before concluding a gate helped.

## Before running it live

The source has **not** been compiled or backtested here — this container has no
MetaTrader. Compile it in MetaEditor, then run it in the Strategy Tester on your
own gold symbol and timeframe (every-tick modelling) before putting money behind
it. Check in particular that the resolved session window lines up with your
broker's 09:30 ET candle.

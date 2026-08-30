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

## Install

1. In MetaTrader 5: **File → Open Data Folder**.
2. Copy `GoldTradesBreakoutEA.mq5` into `MQL5\Experts\`.
3. In MetaEditor press **F7** to compile.
4. Drag the EA onto a gold chart, tick **Allow Algo Trading**.

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

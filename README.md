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

- **Expert**: GoldTradesBreakoutEA · **Symbol**: your symbol · **Period**: M5
- **Modelling**: *Every tick based on real ticks*. This EA's stop can be hit
  intrabar; anything coarser prices those fills wrong and flatters the results.
  If your broker has no real tick history for the symbol, *Every tick* (generated)
  is the fallback — treat its numbers as softer.
- **Date range**: at least a year, and check the trade count — the window plus
  the range test plus two extension gates filter hard.
- **Delays**: set a realistic execution delay rather than *Zero latency*. Instant
  fills are not a market.
- **Deposit and leverage**: match your real account. Sizing is risk-% of equity,
  so testing a $100k balance tells you nothing about a $5k one.
- Leave optimisation off until the plain run looks sane.

**Visual mode** is worth a run of its own. Tick the box, drop the speed slider,
and watch the panel update bar by bar — the window opening, the range going
`VALID`, the size gate cutting to ×0.5, the green add firing. That catches
misconfiguration far faster than a summary table does.

**Use the Forward setting.** Set *Forward* to `1/2` (or `1/3`) and the tester
holds back the later part of the range, runs your settings on the earlier part,
then reports the unseen remainder separately in a **Forward** tab. If the forward
half looks nothing like the back half, you fitted the settings to noise. This is
the single most useful button in the tester and almost nobody presses it.

Expect MT5 and TradingView to disagree even with identical settings: different
data feeds, different contracts, real spread versus none. Use TradingView to find
settings, MT5 to confirm them.

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

### 7. Paper trading, and the ladder to real money

MT5 has no separate "paper" mode — **a demo account is the paper trading**. It
runs on your broker's live price feed with fake money, and the EA cannot tell the
difference.

**Opening one:** *File → Open an Account* → pick your broker → **Demo**. Two
things people get wrong:

- **Set the deposit to what you will actually trade.** Sizing is a % of equity, so
  a $100,000 demo running 1% risk behaves nothing like the $5,000 account you
  plan to fund. You will also never hit the minimum-lot floor on a big demo and
  so never discover that your real account rounds trades to zero.
- **Demo accounts expire**, typically 30–90 days idle. Check the expiry before
  you start counting on a three-month test.

Work through the ladder in order, and do not skip a rung because the one before
looked good:

| Stage | What it proves | What it cannot prove |
|---|---|---|
| **Backtest** | The logic is profitable on history | Anything about execution |
| **Forward test** (tester) | The settings are not curve-fitted | Anything about execution |
| **Visual mode** | The EA does what you think it does | Whether it makes money |
| **Demo, live feed** | It runs unattended, survives restarts, the session window is right, orders are accepted | Real slippage — demo fills are optimistic |
| **Tiny live** | Actual fills, actual spread, actual rejections | — |

**Demo is not a substitute for a small live account.** Demo servers fill at the
quoted price with no requotes, no partial fills and no meaningful slippage. The
first thing a real account teaches you is how much of the backtest edge the
spread was eating. Run the smallest size your broker allows for a few weeks
before scaling up — that is the only test that includes execution.

While on demo, reconcile rather than glance. For each trade check the **Experts**
log against the panel: the resolved window, `Size gate` when a day was skipped,
whether the green add fired or the first bar closed red, and each `+1R add` line.
Restart the terminal deliberately once while a trade is open and confirm you see
`Restored open trade: ...`.

## Running it on FTMO (or any prop firm)

FTMO's terminal is standard MT5, so nothing here changes. What changes is the
**risk framework you are trading inside**, and it conflicts with two of this EA's
defaults.

### Server time

FTMO servers normally run **GMT+2 in winter, GMT+3 in summer, following US DST** —
which is exactly what `InpBrokerGmtOffsetWin = 2.0` and
`InpBrokerFollowsUsDst = true` already assume. The window should resolve to
**16:30–18:30 server time**. Verify it against the printed line anyway; do not
take it on trust.

### The daily loss limit is the binding constraint

Prop accounts fail on **max daily loss** (commonly 5%) far more often than on the
overall limit, and it counts **floating** P/L, not just closed trades. Three
things in this EA push against it:

- `InpRiskPercent = 1.0` is per trade. Two or three stop-outs in one session is
  an ordinary day, and that is already 2–3% of your limit gone.
- Pyramiding raises open risk. With `InpBreakEvenOnAdd` on it is capped near
  0.5R; with it **off** a +1R add takes open risk to 2R. Do not turn it off on a
  prop account.
- Running several symbols multiplies it. Seven correlated Mag 7 charts at 1% each
  is a 7% day when they all fail together — an instant breach.

Start at **`InpRiskPercent = 0.25–0.5`**, and read **max daily loss** off the
backtest report before funding anything, not just total drawdown.

### Holding overnight and over the weekend

The exit is "close under the 9 MA", which can hold a position for days. Some prop
account types restrict holding through the weekend, and some restrict trading
around high-impact news. **Check the rules for your specific account type** — they
differ between standard and swing accounts and they change.

If your account cannot hold over the weekend, note that the EA has **no
end-of-day or Friday flat logic**. The only lever today is
`InpCloseAtWindowEnd`, which flattens at 11:30 ET and removes the "let it run"
behaviour entirely. A proper "flat by HH:MM" and "flat before the weekend" option
would need adding.

### Do not test on a Challenge account

A Challenge costs money and a breach ends it. Use the **Free Trial**, or a plain
demo from any broker, for everything up to the live-feed stage. The Strategy
Tester does not care which account is logged in — you can backtest on the FTMO
terminal right now without risking a Challenge.

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

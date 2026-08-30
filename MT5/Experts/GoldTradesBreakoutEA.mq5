//+------------------------------------------------------------------+
//|                                        GoldTradesBreakoutEA.mq5  |
//|                                                                  |
//|  Long-only range-breakout EA.                                    |
//|                                                                  |
//|    ENTRY  : close breaks the ceiling of a VALIDATED consolidation |
//|             range, while fast MA (9) > slow MA (20).              |
//|    SIZING : risk % of equity against the stop, then scaled by two |
//|             extension gates (150 MA stretch, day-open 9 MA        |
//|             stretch) - full size, half size, or no trade.         |
//|    FILL   : 50% on the breakout, the other 50% if the first bar   |
//|             in the trade closes green.                            |
//|    ADDS   : a further slice at each +1R, capped.                  |
//|    EXIT   : the bar closes under the fast MA (9).                 |
//|    WINDOW : entries only in the first N minutes of the NY session. |
//|                                                                  |
//|  Run this on M5 to match the indicator: the 150 MA and the        |
//|  "once 5min closes" open check both use the CHART timeframe.      |
//+------------------------------------------------------------------+
#property copyright "Gold Trades"
#property link      ""
#property version   "1.20"
#property description "Range breakout, 9>20 filter, percentile extension gates, split entry with pyramiding, exit on close under the 9 MA."

#include <Trade\Trade.mqh>

//====================================================================
// Enums
//====================================================================
enum ENUM_BREAK_MODE
  {
   BREAK_ON_CLOSE = 0,   // Bar must CLOSE above the level (confirmed)
   BREAK_ON_TOUCH = 1    // Enter intrabar as soon as price trades above
  };

enum ENUM_SL_MODE
  {
   SL_RANGE_LOW  = 0,    // Below the floor of the broken range
   SL_SWING_LOW  = 1,    // Below the lowest low of the last N bars
   SL_ATR        = 2,    // ATR multiple below entry
   SL_POINTS     = 3     // Fixed distance in points
  };

enum ENUM_LEVEL_SOURCE
  {
   LEVEL_RANGE_HIGH = 0, // Ceiling of a validated consolidation range
   LEVEL_PIVOT_HIGH = 1  // Last confirmed swing high (no range required)
  };

enum ENUM_LOT_MODE
  {
   LOT_RISK_PCT  = 0,    // % of equity risked to the stop (dynamic)
   LOT_FIXED     = 1     // Fixed lot size
  };

//====================================================================
// Inputs
//====================================================================
input group "=== Moving averages (the 9 / 20 filter) ==="
input int                InpFastPeriod      = 9;             // Fast MA period (the "9")
input int                InpSlowPeriod      = 20;            // Slow MA period (the "20")
input ENUM_MA_METHOD     InpMaMethod        = MODE_EMA;      // MA method
input ENUM_APPLIED_PRICE InpMaPrice         = PRICE_CLOSE;   // MA applied price

input group "=== What counts as resistance ==="
input ENUM_LEVEL_SOURCE InpLevelSource = LEVEL_RANGE_HIGH; // Level the EA trades the break of

input group "=== Range detection (LEVEL_RANGE_HIGH) ==="
input int    InpRangeBars    = 20;    // Bars that must form the range
input double InpMaxRangeATR  = 3.0;   // Max range height, in ATR (lower = tighter, rarer)
input int    InpMinTouches   = 2;     // Times the ceiling must have been tested
input double InpTouchTolATR  = 0.15;  // How close to the ceiling counts as a touch (ATR)

input group "=== Pivot high (LEVEL_PIVOT_HIGH) ==="
input int    InpPivotLeft     = 5;    // Pivot high - left bars
input int    InpPivotRight    = 5;    // Pivot high - right bars (confirmation delay)
input int    InpPivotScanBars = 300;  // How far back to look for the last pivot

input group "=== Breakout ==="
input ENUM_BREAK_MODE InpBreakMode      = BREAK_ON_CLOSE; // Breakout trigger
input double          InpBreakBufferPts = 0;    // Extra buffer above the level (points)
input bool            InpOneEntryPerLevel = true; // Only one trade per resistance level
input bool            InpRequireGreenBreak = true; // Breakout bar must close green

input group "=== Extension gate: 150 MA (percentile) ==="
input bool   InpUseExtFilter   = true;   // Scale size by how stretched price is from the 150 MA
input int    InpExtMaPeriod    = 150;    // Long MA period
input ENUM_MA_METHOD InpExtMaMethod = MODE_SMA; // Long MA method
input int    InpExtLookback    = 500;    // Bars of history the percentile ranks against
input double InpExtWarnRank    = 70;     // >= this percentile -> reduced size
input double InpExtExtremeRank = 90;     // >= this percentile -> no trade
input double InpExtWarnMult    = 0.5;    // Size multiplier inside the warn band
input double InpExtFloorPct    = 0.0;    // Below this raw |%| always count as normal (0 = off)

input group "=== Extension gate: day open vs the 9 MA ==="
input bool   InpUseOpenCheck    = true;  // Check the stretch at the first window bar's close
input double InpOpenWarnRank    = 70;    // >= this percentile -> reduced size for the day
input double InpOpenExtremeRank = 90;    // >= this percentile -> no trades that day
input double InpOpenWarnMult    = 0.5;   // Size multiplier inside the warn band

input group "=== Trading window (New York open) ==="
input bool   InpUseManualWindow    = false;  // Use a manual server-time window instead
input int    InpManualStartHour    = 16;     // Manual start hour (SERVER time)
input int    InpManualStartMinute  = 30;     // Manual start minute (SERVER time)
input double InpBrokerGmtOffsetWin = 2.0;    // Broker GMT offset in WINTER (e.g. 2 for GMT+2)
input bool   InpBrokerFollowsUsDst = true;   // Broker clock shifts with US DST (+1h in summer)
input int    InpWindowMinutes      = 120;    // Window length in minutes (2 hours)
input bool   InpCloseAtWindowEnd   = false;  // Force-close any open trade when window ends

input group "=== Exit ==="
input double InpExitBufferPts      = 0;      // Close only if the bar closes this far under the 9 MA

input group "=== Stop / target ==="
input ENUM_SL_MODE InpStopMode     = SL_RANGE_LOW; // Protective stop mode
input int          InpSwingLookback= 10;     // SL_SWING_LOW: bars used for the swing low
input double       InpStopPadPts   = 20;     // Pad below the range/swing low (points)
input int          InpAtrPeriod    = 14;     // ATR period (range test, SL_ATR)
input double       InpAtrMult      = 1.5;    // SL_ATR: ATR multiple
input double       InpStopPoints   = 500;    // SL_POINTS: stop distance in points

input group "=== Position sizing ==="
input ENUM_LOT_MODE InpLotMode     = LOT_RISK_PCT; // Sizing mode
input double        InpRiskPercent = 1.0;    // Risk % of equity for the FULL planned position
input double        InpFixedLots   = 0.10;   // LOT_FIXED: full planned position

input group "=== Scale-in / pyramiding ==="
input double InpInitialPct     = 50;    // % of the planned size taken on the breakout
input bool   InpAddOnGreen     = true;  // Add the rest if the first bar in the trade closes green
input bool   InpPyramid        = true;  // Keep adding while the trade works
input double InpPyramidPct     = 50;    // % of the planned size per +1R add
input int    InpMaxAdds        = 3;     // Max +1R adds
input bool   InpBreakEvenOnAdd = true;  // Move the stop to breakeven on the first +1R add

input group "=== Execution / housekeeping ==="
input ulong  InpMagic          = 20260830;   // Magic number
input ulong  InpDeviationPts   = 30;         // Max slippage (points)
input int    InpMaxSpreadPts   = 0;          // Max allowed spread in points (0 = off)
input int    InpMaxTradesPerDay= 0;          // Max entries per day (0 = unlimited)
input bool   InpShowPanel      = true;       // Show status panel on the chart

//====================================================================
// Globals
//====================================================================
CTrade   g_trade;

int      g_hFast = INVALID_HANDLE;
int      g_hSlow = INVALID_HANDLE;
int      g_hExt  = INVALID_HANDLE;
int      g_hAtr  = INVALID_HANDLE;

datetime g_lastBarTime   = 0;
int      g_tradesToday   = 0;
int      g_tradeDay      = -1;
double   g_lastUsedLevel = 0.0;
int      g_windowStartMin= -1;

// Per-trade state
double   g_plannedLots   = 0.0;   // full intended size for the live trade
double   g_entryPrice    = 0.0;
double   g_riskDist      = 0.0;   // entry -> initial stop, one R
double   g_initialStop   = 0.0;
int      g_addsDone      = 0;     // +1R adds already taken
bool     g_secondHalfOn  = false; // the green-candle half is placed (or waived)
datetime g_entryBarTime  = 0;     // open time of the first bar we were in the trade

// Per-day state
bool     g_openChecked   = false;
double   g_dayOpenMult   = 1.0;

// Cached diagnostics for the panel
bool     g_extReady      = false;
double   g_extRank       = 0.0;
double   g_extPct        = 0.0;
double   g_extMult       = 1.0;
double   g_openRank      = 0.0;

//+------------------------------------------------------------------+
//| Helpers - time                                                    |
//+------------------------------------------------------------------+
datetime MidnightOf(const int year,const int mon,const int day)
  {
   return (datetime)StringToTime(StringFormat("%04d.%02d.%02d 00:00:00",year,mon,day));
  }

int NthWeekdayDay(const int year,const int mon,const int weekday,const int nth)
  {
   MqlDateTime d;
   TimeToStruct(MidnightOf(year,mon,1),d);
   return 1 + ((weekday - d.day_of_week) + 7) % 7 + (nth-1)*7;
  }

bool IsUsDst(const datetime utc)
  {
   MqlDateTime d;
   TimeToStruct(utc,d);
   int y = d.year;
   datetime dstOn  = MidnightOf(y,3, NthWeekdayDay(y,3,0,2)) + 7*3600;
   datetime dstOff = MidnightOf(y,11,NthWeekdayDay(y,11,0,1)) + 6*3600;
   return (utc >= dstOn && utc < dstOff);
  }

int ResolveWindowStartMinutes(const datetime serverNow)
  {
   if(InpUseManualWindow)
      return InpManualStartHour*60 + InpManualStartMinute;

   long     offsetSec = (long)MathRound(InpBrokerGmtOffsetWin*3600.0);
   datetime approxUtc = (datetime)((long)serverNow - offsetSec);
   bool     dst       = IsUsDst(approxUtc);

   double nyOpenUtcMin = dst ? (13*60+30) : (14*60+30);
   double brokerOffMin = InpBrokerGmtOffsetWin*60.0 + ((InpBrokerFollowsUsDst && dst) ? 60.0 : 0.0);

   int startMin = (int)MathRound(nyOpenUtcMin + brokerOffMin);
   startMin %= 1440;
   if(startMin < 0)
      startMin += 1440;
   return startMin;
  }

bool InTradingWindow(const datetime t)
  {
   MqlDateTime d;
   TimeToStruct(t,d);
   int nowMin = d.hour*60 + d.min;
   int start  = g_windowStartMin;
   int end    = start + InpWindowMinutes;

   if(end <= 1440)
      return (nowMin >= start && nowMin < end);
   return (nowMin >= start || nowMin < (end - 1440));
  }

//+------------------------------------------------------------------+
//| Helpers - pivots                                                  |
//+------------------------------------------------------------------+
bool IsPivotHighAt(const MqlRates &r[],const int shift,const int left,const int right)
  {
   int total = ArraySize(r);
   if(shift - right < 0 || shift + left >= total)
      return false;

   double h = r[shift].high;
   for(int i=1; i<=left; i++)
      if(r[shift+i].high >= h)
         return false;
   for(int i=1; i<=right; i++)
      if(r[shift-i].high >= h)
         return false;
   return true;
  }

double FindLastPivotHigh(const MqlRates &r[],const int startShift,const int left,const int right,const int maxScan)
  {
   int total = ArraySize(r);
   for(int s=startShift; s<startShift+maxScan && s+left<total; s++)
      if(IsPivotHighAt(r,s,left,right))
         return r[s].high;
   return 0.0;
  }

//+------------------------------------------------------------------+
//| Helpers - range detection                                         |
//+------------------------------------------------------------------+
struct RangeInfo
  {
   bool              valid;
   double            high;
   double            low;
   double            height;
   double            heightAtr;
   int               touches;
  };

void DetectRange(const MqlRates &r[],const int startShift,const double atr,RangeInfo &out)
  {
   out.valid     = false;
   out.high      = 0.0;
   out.low       = 0.0;
   out.height    = 0.0;
   out.heightAtr = 0.0;
   out.touches   = 0;

   int total = ArraySize(r);
   int last  = startShift + InpRangeBars - 1;
   if(InpRangeBars < 2 || last >= total || atr <= 0.0)
      return;

   double hi = r[startShift].high;
   double lo = r[startShift].low;
   for(int i=startShift; i<=last; i++)
     {
      hi = MathMax(hi,r[i].high);
      lo = MathMin(lo,r[i].low);
     }

   out.high   = hi;
   out.low    = lo;
   out.height = hi - lo;
   if(out.height <= 0.0)
      return;
   out.heightAtr = out.height / atr;

   double tol = InpTouchTolATR * atr;
   for(int i=startShift; i<=last; i++)
      if(r[i].high >= hi - tol)
         out.touches++;

   out.valid = (out.heightAtr <= InpMaxRangeATR) && (out.touches >= InpMinTouches);
  }

//+------------------------------------------------------------------+
//| Helpers - extension percentile                                    |
//|                                                                   |
//| A fixed % threshold cannot work on two timeframes at once: price   |
//| sits far closer to a 150 MA on M5 than on D1. Ranking the current  |
//| stretch against its own recent history is self-calibrating, so the |
//| same settings mean the same thing on any chart or symbol.          |
//+------------------------------------------------------------------+
bool ExtensionRank(const int maHandle,const int lookback,double &rankOut,double &extPctOut)
  {
   rankOut   = 0.0;
   extPctOut = 0.0;
   if(maHandle == INVALID_HANDLE || lookback < 10)
      return false;

   int need = lookback + 2;

   double ma[];
   ArraySetAsSeries(ma,true);
   if(CopyBuffer(maHandle,0,0,need,ma) < need)
      return false;

   MqlRates r[];
   ArraySetAsSeries(r,true);
   if(CopyRates(_Symbol,_Period,0,need,r) < need)
      return false;

   // Signed extension on the last closed bar; the rank uses the absolute value.
   if(ma[1] == 0.0)
      return false;
   extPctOut = 100.0 * (r[1].close - ma[1]) / ma[1];

   double cur   = MathAbs(extPctOut);
   int    below = 0;
   int    count = 0;
   for(int i=2; i<=lookback+1; i++)
     {
      if(ma[i] == 0.0)
         continue;
      double e = MathAbs(100.0 * (r[i].close - ma[i]) / ma[i]);
      if(e <= cur)
         below++;
      count++;
     }
   if(count <= 0)
      return false;

   rankOut = 100.0 * below / count;
   return true;
  }

// Percentile -> size multiplier. The raw-% floor stops a dead-flat market from
// reading "extreme" merely because it is the calmest stretch in the lookback.
double RankToMultiplier(const double rank,const double extPct,const double warnRank,
                        const double extremeRank,const double warnMult,const double floorPct)
  {
   if(floorPct > 0.0 && MathAbs(extPct) < floorPct)
      return 1.0;
   if(rank >= extremeRank)
      return 0.0;
   if(rank >= warnRank)
      return warnMult;
   return 1.0;
  }

//+------------------------------------------------------------------+
//| Helpers - positions (aggregate, so scaling in works on both        |
//| netting and hedging accounts)                                      |
//+------------------------------------------------------------------+
bool GetPositionAggregate(double &volume,double &avgPrice,int &count)
  {
   volume   = 0.0;
   avgPrice = 0.0;
   count    = 0;
   double weighted = 0.0;

   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic)
         continue;

      double v = PositionGetDouble(POSITION_VOLUME);
      volume  += v;
      weighted += v * PositionGetDouble(POSITION_PRICE_OPEN);
      count++;
     }

   if(volume > 0.0)
      avgPrice = weighted / volume;
   return (count > 0);
  }

void CloseAllPositions()
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic)
         continue;
      g_trade.PositionClose(t);
     }
  }

void SetStopOnAll(const double sl)
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic)
         continue;
      double tp = PositionGetDouble(POSITION_TP);
      if(MathAbs(PositionGetDouble(POSITION_SL) - sl) > _Point/2.0)
         g_trade.PositionModify(t,sl,tp);
     }
  }

//+------------------------------------------------------------------+
//| Helpers - volume                                                  |
//+------------------------------------------------------------------+
double NormalizeVolume(double v)
  {
   double minv = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxv = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;

   v = MathFloor(v/step) * step;
   if(v > maxv)
      v = maxv;
   if(v < minv)
      v = 0.0;      // below the broker minimum is not tradeable, not "round up"

   int digits = 0;
   double s = step;
   while(s < 1.0 && digits < 8)
     {
      s *= 10.0;
      digits++;
     }
   return NormalizeDouble(v,digits);
  }

double LotsForRisk(const double stopDistance,const double riskMoney)
  {
   if(stopDistance <= 0.0 || riskMoney <= 0.0)
      return 0.0;

   double tickValue = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0)
      return 0.0;

   double lossPerLot = (stopDistance / tickSize) * tickValue;
   if(lossPerLot <= 0.0)
      return 0.0;
   return riskMoney / lossPerLot;
  }

double ClampStopBelow(const double entry,double sl)
  {
   long   stopsLevel = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   double minDist    = (double)stopsLevel * _Point;
   if(minDist <= 0.0)
      minDist = _Point * 2.0;
   if(entry - sl < minDist)
      sl = entry - minDist;
   return NormalizeDouble(sl,_Digits);
  }

void ResetTradeState()
  {
   g_plannedLots  = 0.0;
   g_entryPrice   = 0.0;
   g_riskDist     = 0.0;
   g_initialStop  = 0.0;
   g_addsDone     = 0;
   g_secondHalfOn = false;
   g_entryBarTime = 0;
  }

//+------------------------------------------------------------------+
//| Init / deinit                                                     |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpFastPeriod < 1 || InpSlowPeriod < 1 || InpFastPeriod >= InpSlowPeriod)
     {
      Print("Invalid MA periods: fast must be >=1 and smaller than slow.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpLevelSource == LEVEL_RANGE_HIGH && (InpRangeBars < 2 || InpMinTouches < 1 || InpMaxRangeATR <= 0.0))
     {
      Print("Range detection needs RangeBars >= 2, MinTouches >= 1 and MaxRangeATR > 0.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpWindowMinutes < 1 || InpWindowMinutes > 1440)
     {
      Print("Window length must be between 1 and 1440 minutes.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpInitialPct <= 0.0 || InpInitialPct > 100.0)
     {
      Print("Initial slice must be between 0 and 100 percent of the planned size.");
      return INIT_PARAMETERS_INCORRECT;
     }

   g_hFast = iMA(_Symbol,_Period,InpFastPeriod,0,InpMaMethod,InpMaPrice);
   g_hSlow = iMA(_Symbol,_Period,InpSlowPeriod,0,InpMaMethod,InpMaPrice);
   g_hExt  = iMA(_Symbol,_Period,InpExtMaPeriod,0,InpExtMaMethod,PRICE_CLOSE);
   g_hAtr  = iATR(_Symbol,_Period,InpAtrPeriod);

   if(g_hFast == INVALID_HANDLE || g_hSlow == INVALID_HANDLE ||
      g_hExt == INVALID_HANDLE || g_hAtr == INVALID_HANDLE)
     {
      Print("Failed to create an indicator handle.");
      return INIT_FAILED;
     }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviationPts);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   g_windowStartMin = ResolveWindowStartMinutes(TimeCurrent());
   PrintFormat("Trading window resolved to %02d:%02d - %02d:%02d server time (%d min).",
               g_windowStartMin/60, g_windowStartMin%60,
               ((g_windowStartMin+InpWindowMinutes)%1440)/60,
               ((g_windowStartMin+InpWindowMinutes)%1440)%60,
               InpWindowMinutes);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(g_hFast != INVALID_HANDLE) IndicatorRelease(g_hFast);
   if(g_hSlow != INVALID_HANDLE) IndicatorRelease(g_hSlow);
   if(g_hExt  != INVALID_HANDLE) IndicatorRelease(g_hExt);
   if(g_hAtr  != INVALID_HANDLE) IndicatorRelease(g_hAtr);
   Comment("");
  }

//+------------------------------------------------------------------+
//| Main tick handler                                                 |
//+------------------------------------------------------------------+
void OnTick()
  {
   datetime now = TimeCurrent();

   MqlDateTime dt;
   TimeToStruct(now,dt);
   if(dt.day != g_tradeDay)
     {
      g_tradeDay       = dt.day;
      g_tradesToday    = 0;
      g_lastUsedLevel  = 0.0;
      g_openChecked    = false;
      g_dayOpenMult    = 1.0;
      g_windowStartMin = ResolveWindowStartMinutes(now);
     }

   int needPivot = InpPivotLeft + InpPivotRight + InpPivotScanBars;
   int needRange = InpRangeBars + InpAtrPeriod;
   int need      = MathMax(needPivot,needRange) + 10;

   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   int got = CopyRates(_Symbol,_Period,0,need,rates);
   int minBars = (InpLevelSource == LEVEL_RANGE_HIGH)
                 ? InpRangeBars + 3
                 : InpPivotLeft + InpPivotRight + 5;
   if(got < minBars)
      return;

   double fast[], slow[];
   ArraySetAsSeries(fast,true);
   ArraySetAsSeries(slow,true);
   if(CopyBuffer(g_hFast,0,0,3,fast) < 3) return;
   if(CopyBuffer(g_hSlow,0,0,3,slow) < 3) return;

   if(g_lastBarTime == 0)
     {
      g_lastBarTime = rates[0].time;
      return;
     }

   bool   newBar   = (rates[0].time != g_lastBarTime);
   bool   inWindow = InTradingWindow(now);
   double buffer   = InpBreakBufferPts * _Point;

   double atrBuf[];
   ArraySetAsSeries(atrBuf,true);
   double atrVal = 0.0;
   if(CopyBuffer(g_hAtr,0,0,3,atrBuf) >= 3)
      atrVal = atrBuf[1];

   double posVolume, posAvgPrice;
   int    posCount;
   bool   hasPosition = GetPositionAggregate(posVolume,posAvgPrice,posCount);

   //--- Extension gates, refreshed once per bar --------------------------------
   if(newBar)
     {
      if(InpUseExtFilter)
        {
         double rank, pct;
         if(ExtensionRank(g_hExt,InpExtLookback,rank,pct))
           {
            g_extReady = true;
            g_extRank  = rank;
            g_extPct   = pct;
            // Only a stretch ABOVE the long MA argues against a fresh long.
            g_extMult = (pct <= 0.0)
                        ? 1.0
                        : RankToMultiplier(rank,pct,InpExtWarnRank,InpExtExtremeRank,
                                           InpExtWarnMult,InpExtFloorPct);
           }
        }
      else
         g_extMult = 1.0;

      // "Price opened above the 9 MA but by the first 5-minute close it is
      // already too far" - measured once, at the close of the first window bar.
      if(InpUseOpenCheck && !g_openChecked && InTradingWindow(rates[1].time))
        {
         g_openChecked = true;
         if(rates[1].close > fast[1])
           {
            double rank9, pct9;
            if(ExtensionRank(g_hFast,InpExtLookback,rank9,pct9))
              {
               g_openRank    = rank9;
               g_dayOpenMult = RankToMultiplier(rank9,pct9,InpOpenWarnRank,InpOpenExtremeRank,
                                                InpOpenWarnMult,InpExtFloorPct);
              }
           }
         else
            g_dayOpenMult = 1.0;   // opened below the 9 MA: this gate does not apply
        }
     }

   //--- Range / level ----------------------------------------------------------
   int rangeStart = (InpBreakMode == BREAK_ON_CLOSE) ? 2 : 1;
   RangeInfo rng;
   DetectRange(rates,rangeStart,atrVal,rng);

   double levelNow  = 0.0;
   double levelPrev = 0.0;
   if(InpLevelSource == LEVEL_RANGE_HIGH)
      levelNow = rng.valid ? rng.high : 0.0;
   else
     {
      levelNow  = FindLastPivotHigh(rates,InpPivotRight+1,InpPivotLeft,InpPivotRight,InpPivotScanBars);
      levelPrev = FindLastPivotHigh(rates,InpPivotRight+2,InpPivotLeft,InpPivotRight,InpPivotScanBars);
     }

   //--- 1. Exit, never restricted to the window --------------------------------
   if(newBar && hasPosition)
     {
      if(rates[1].close < fast[1] - InpExitBufferPts * _Point)
        {
         CloseAllPositions();
         ResetTradeState();
         hasPosition = GetPositionAggregate(posVolume,posAvgPrice,posCount);
        }
     }

   if(hasPosition && InpCloseAtWindowEnd && !inWindow)
     {
      CloseAllPositions();
      ResetTradeState();
      hasPosition = GetPositionAggregate(posVolume,posAvgPrice,posCount);
     }

   //--- 2. Scale-in and pyramiding on the live trade ---------------------------
   if(newBar && hasPosition && g_plannedLots > 0.0)
      ManageOpenTrade(rates);

   if(newBar)
      g_lastBarTime = rates[0].time;

   if(hasPosition)
     {
      UpdatePanel(fast[1],slow[1],levelNow,inWindow,posVolume,rng);
      return;
     }

   // Flat: any leftover state belongs to a trade that is already gone.
   if(g_plannedLots > 0.0)
      ResetTradeState();

   //--- 3. Entry ---------------------------------------------------------------
   double sizeMult = MathMin(g_extMult,g_dayOpenMult);

   if(!inWindow || levelNow <= 0.0 || sizeMult <= 0.0)
     {
      UpdatePanel(fast[1],slow[1],levelNow,inWindow,0.0,rng);
      return;
     }
   if(InpMaxTradesPerDay > 0 && g_tradesToday >= InpMaxTradesPerDay)
     {
      UpdatePanel(fast[1],slow[1],levelNow,inWindow,0.0,rng);
      return;
     }

   double sameLevelTol = MathMax(_Point,0.25*atrVal);
   if(InpOneEntryPerLevel && g_lastUsedLevel > 0.0 &&
      MathAbs(levelNow - g_lastUsedLevel) < sameLevelTol)
     {
      UpdatePanel(fast[1],slow[1],levelNow,inWindow,0.0,rng);
      return;
     }

   if(InpMaxSpreadPts > 0 && SymbolInfoInteger(_Symbol,SYMBOL_SPREAD) > InpMaxSpreadPts)
     {
      UpdatePanel(fast[1],slow[1],levelNow,inWindow,0.0,rng);
      return;
     }

   bool maFilter   = (fast[1] > slow[1]);
   bool greenBreak = (!InpRequireGreenBreak || rates[1].close > rates[1].open);

   bool signal = false;
   if(InpLevelSource == LEVEL_RANGE_HIGH)
     {
      if(InpBreakMode == BREAK_ON_CLOSE)
         signal = (newBar && maFilter && greenBreak && rates[1].close > levelNow + buffer);
      else
        {
         double askR = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         signal = (maFilter && askR > levelNow + buffer);
        }
     }
   else if(InpBreakMode == BREAK_ON_CLOSE)
     {
      if(newBar && maFilter && greenBreak && levelPrev > 0.0)
         signal = (rates[1].close > levelNow + buffer && rates[2].close <= levelPrev + buffer);
     }
   else
     {
      double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      if(maFilter && rates[1].close <= levelNow + buffer && ask > levelNow + buffer)
         signal = true;
     }

   if(signal)
      OpenInitial(rates,levelNow,rng,atrVal,sizeMult);

   UpdatePanel(fast[1],slow[1],levelNow,inWindow,0.0,rng);
  }

//+------------------------------------------------------------------+
//| Entry - first slice                                               |
//+------------------------------------------------------------------+
void OpenInitial(const MqlRates &rates[],const double level,const RangeInfo &rng,
                 const double atrVal,const double sizeMult)
  {
   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   if(ask <= 0.0)
      return;

   //--- stop
   double swingLow = rates[1].low;
   int    n        = MathMax(1,MathMin(InpSwingLookback,ArraySize(rates)-1));
   for(int i=1; i<=n; i++)
      swingLow = MathMin(swingLow,rates[i].low);

   double sl = 0.0;
   switch(InpStopMode)
     {
      case SL_RANGE_LOW:
         sl = (rng.valid ? rng.low : swingLow) - InpStopPadPts * _Point;
         break;
      case SL_SWING_LOW:
         sl = swingLow - InpStopPadPts * _Point;
         break;
      case SL_ATR:
         if(atrVal <= 0.0)
            return;
         sl = ask - InpAtrMult * atrVal;
         break;
      case SL_POINTS:
         sl = ask - InpStopPoints * _Point;
         break;
     }

   if(sl >= ask)
     {
      Print("Computed stop is at or above entry - skipping this signal.");
      return;
     }
   sl = ClampStopBelow(ask,sl);
   double riskDist = ask - sl;

   //--- full planned size, then the extension gates scale it
   double planned = 0.0;
   if(InpLotMode == LOT_RISK_PCT)
     {
      double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0;
      planned = LotsForRisk(riskDist,riskMoney);
     }
   else
      planned = InpFixedLots;

   planned *= sizeMult;
   planned  = NormalizeVolume(planned);
   if(planned <= 0.0)
     {
      Print("Planned size rounds below the broker minimum - skipping this signal.");
      return;
     }

   //--- first slice
   double firstSlice = NormalizeVolume(planned * InpInitialPct / 100.0);
   bool   splitOk    = (firstSlice > 0.0 && firstSlice < planned);
   if(!splitOk)
     {
      // Half would round below the minimum lot, so the split is not possible.
      firstSlice = planned;
     }

   if(!g_trade.Buy(firstSlice,_Symbol,0.0,sl,0.0,"GT entry"))
     {
      PrintFormat("Buy failed: retcode=%d %s",g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
      return;
     }

   g_plannedLots   = planned;
   g_entryPrice    = ask;
   g_initialStop   = sl;
   g_riskDist      = riskDist;
   g_addsDone      = 0;
   g_secondHalfOn  = !splitOk;          // no split possible -> nothing left to add
   g_entryBarTime  = rates[0].time;     // the bar we are now trading inside
   g_tradesToday++;
   g_lastUsedLevel = level;

   PrintFormat("Entry %s of planned %s lots @ %s | stop %s (1R = %s) | size x%s",
               DoubleToString(firstSlice,2), DoubleToString(planned,2),
               DoubleToString(ask,_Digits), DoubleToString(sl,_Digits),
               DoubleToString(riskDist,_Digits), DoubleToString(sizeMult,2));
  }

//+------------------------------------------------------------------+
//| Manage a live trade: green-candle half, then +1R adds             |
//+------------------------------------------------------------------+
void ManageOpenTrade(const MqlRates &rates[])
  {
   double posVolume, posAvgPrice;
   int    posCount;
   if(!GetPositionAggregate(posVolume,posAvgPrice,posCount))
      return;

   //--- (a) the other half, if the FIRST bar we were in the trade closed green.
   //    rates[1] is that bar exactly when its open time matches the entry bar.
   if(!g_secondHalfOn && InpAddOnGreen)
     {
      if(rates[1].time == g_entryBarTime)
        {
         g_secondHalfOn = true;                       // this chance happens once
         if(rates[1].close > rates[1].open)
           {
            double rest = NormalizeVolume(g_plannedLots - posVolume);
            if(rest > 0.0)
              {
               if(g_trade.Buy(rest,_Symbol,0.0,g_initialStop,0.0,"GT green add"))
                  PrintFormat("Green-candle add: %s lots (planned %s)",
                              DoubleToString(rest,2), DoubleToString(g_plannedLots,2));
              }
           }
         else
            Print("First bar in the trade closed red - second half skipped.");
        }
      else
         if(rates[1].time > g_entryBarTime)
            g_secondHalfOn = true;                    // missed the window, do not add late
     }

   //--- (b) +1R adds while the trade keeps working
   if(!InpPyramid || g_addsDone >= InpMaxAdds || g_riskDist <= 0.0)
      return;

   double target = g_entryPrice + (g_addsDone + 1) * g_riskDist;
   if(rates[1].close < target)
      return;

   double slice = NormalizeVolume(g_plannedLots * InpPyramidPct / 100.0);
   if(slice <= 0.0)
      return;

   double sl = g_initialStop;
   if(InpBreakEvenOnAdd)
      sl = ClampStopBelow(SymbolInfoDouble(_Symbol,SYMBOL_BID),g_entryPrice);

   if(g_trade.Buy(slice,_Symbol,0.0,sl,0.0,"GT +1R add"))
     {
      g_addsDone++;
      if(InpBreakEvenOnAdd)
         SetStopOnAll(sl);
      PrintFormat("+%dR add: %s lots, stop now %s",
                  g_addsDone, DoubleToString(slice,2), DoubleToString(sl,_Digits));
     }
  }

//+------------------------------------------------------------------+
//| Status panel                                                      |
//+------------------------------------------------------------------+
void UpdatePanel(const double fast,const double slow,const double level,
                 const bool inWindow,const double posVolume,const RangeInfo &rng)
  {
   if(!InpShowPanel)
      return;

   int endMin = (g_windowStartMin + InpWindowMinutes) % 1440;

   string rangeTxt;
   if(InpLevelSource != LEVEL_RANGE_HIGH)
      rangeTxt = "pivot-high mode";
   else
      if(rng.height <= 0.0)
         rangeTxt = "no data";
      else
         rangeTxt = StringFormat("%s ATR (max %s) | %d touch%s | %s",
                                 DoubleToString(rng.heightAtr,2), DoubleToString(InpMaxRangeATR,2),
                                 rng.touches, rng.touches == 1 ? "" : "es",
                                 rng.valid ? "VALID" : "rejected");

   double sizeMult = MathMin(g_extMult,g_dayOpenMult);
   string gateTxt  = sizeMult <= 0.0 ? "NO TRADE" : StringFormat("x%s", DoubleToString(sizeMult,2));

   string tradeTxt = posVolume > 0.0
                     ? StringFormat("LONG %s / planned %s | adds %d/%d",
                                    DoubleToString(posVolume,2), DoubleToString(g_plannedLots,2),
                                    g_addsDone, InpMaxAdds)
                     : "flat";

   string txt = StringFormat(
                   "Gold Trades Breakout EA\n"
                   "Window   : %02d:%02d - %02d:%02d server  [%s]\n"
                   "MA %d/%d  : %s / %s  [%s]\n"
                   "Range    : %s\n"
                   "Resistance: %s\n"
                   "Ext %d MA : %s  ->  x%s\n"
                   "Day open : p%s  ->  x%s\n"
                   "Size gate: %s\n"
                   "Position : %s   Trades today: %d",
                   g_windowStartMin/60, g_windowStartMin%60, endMin/60, endMin%60,
                   inWindow ? "OPEN" : "closed",
                   InpFastPeriod, InpSlowPeriod,
                   DoubleToString(fast,_Digits), DoubleToString(slow,_Digits),
                   fast > slow ? "9 > 20 OK" : "blocked",
                   rangeTxt,
                   level > 0.0 ? DoubleToString(level,_Digits) : "none found",
                   InpExtMaPeriod,
                   g_extReady ? StringFormat("p%s (%s%%)", DoubleToString(g_extRank,0), DoubleToString(g_extPct,2))
                              : "n/a - warming up",
                   DoubleToString(g_extMult,2),
                   DoubleToString(g_openRank,0), DoubleToString(g_dayOpenMult,2),
                   gateTxt,
                   tradeTxt, g_tradesToday);
   Comment(txt);
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                        GoldTradesBreakoutEA.mq5  |
//|                                                                  |
//|  Long-only resistance-breakout EA.                               |
//|                                                                  |
//|  Rules implemented (from the "Gold Trades" Pine indicator):       |
//|    ENTRY  : price breaks the last confirmed pivot high            |
//|             (resistance), AND fast MA (9) > slow MA (20).         |
//|    EXIT   : the bar CLOSES under the fast MA (9).                 |
//|    WINDOW : entries only in the first N minutes (default 120)     |
//|             of the New York session (09:30 ET).                   |
//|                                                                  |
//|  Additions beyond the stated rules, all optional and visible in   |
//|  the inputs: protective stop (default = swing low), optional take |
//|  profit, risk-based lot sizing, spread filter, trade cap per day. |
//|  Set StopMode = SL_NONE for behaviour identical to the raw rules. |
//+------------------------------------------------------------------+
#property copyright "Gold Trades"
#property link      ""
#property version   "1.10"
#property description "Long-only breakout of a validated consolidation range, filtered by 9>20 MA, exit on close under the 9 MA, first two hours of the NY session."

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
   SL_NONE       = 0,    // No stop (pure "exit on close under 9 MA")
   SL_SWING_LOW  = 1,    // Below the lowest low of the last N bars
   SL_ATR        = 2,    // ATR multiple below entry
   SL_POINTS     = 3,    // Fixed distance in points
   SL_RANGE_LOW  = 4     // Below the floor of the broken range
  };

enum ENUM_LEVEL_SOURCE
  {
   LEVEL_RANGE_HIGH = 0, // Ceiling of a validated consolidation range
   LEVEL_PIVOT_HIGH = 1  // Last confirmed swing high (no range required)
  };

enum ENUM_LOT_MODE
  {
   LOT_FIXED     = 0,    // Fixed lot size
   LOT_RISK_PCT  = 1     // % of balance risked to the stop (needs a stop)
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
input int             InpPivotLeft      = 5;      // Pivot high - left bars
input int             InpPivotRight     = 5;      // Pivot high - right bars (confirmation delay)
input int             InpPivotScanBars  = 300;    // How far back to look for the last pivot
input ENUM_BREAK_MODE InpBreakMode      = BREAK_ON_CLOSE; // Breakout trigger
input double          InpBreakBufferPts = 0;      // Extra buffer above the level (points)
input bool            InpOneEntryPerLevel = true; // Only one trade per resistance level

input group "=== Trading window (New York open) ==="
input bool   InpUseManualWindow    = false;  // Use a manual server-time window instead
input int    InpManualStartHour    = 16;     // Manual start hour (SERVER time)
input int    InpManualStartMinute  = 30;     // Manual start minute (SERVER time)
input double InpBrokerGmtOffsetWin = 2.0;    // Broker GMT offset in WINTER (e.g. 2 for GMT+2)
input bool   InpBrokerFollowsUsDst = true;   // Broker clock shifts with US DST (+1h in summer)
input int    InpWindowMinutes      = 120;    // Window length in minutes (2 hours)
input bool   InpCloseAtWindowEnd   = false;  // Force-close any open trade when window ends

input group "=== Exit ==="
input double InpExitBufferPts      = 0;      // Close only if bar closes this far under the 9 MA (points)

input group "=== Risk / stops ==="
input ENUM_SL_MODE InpStopMode     = SL_RANGE_LOW; // Protective stop mode
input int          InpSwingLookback= 10;     // SL_SWING_LOW: bars used for the swing low
input double       InpSwingPadPts  = 20;     // SL_SWING_LOW: pad below the swing low (points)
input int          InpAtrPeriod    = 14;     // ATR period (range test, SL_ATR)
input double       InpAtrMult      = 1.5;    // SL_ATR: ATR multiple
input double       InpRangePadPts  = 20;     // SL_RANGE_LOW: pad below the range floor (points)
input double       InpStopPoints   = 500;    // SL_POINTS: stop distance in points
input double       InpTakeProfitR  = 0;      // Take profit as R multiple (0 = none, exit on MA only)

input group "=== Position sizing ==="
input ENUM_LOT_MODE InpLotMode     = LOT_FIXED; // Lot sizing mode
input double        InpFixedLots   = 0.01;   // Fixed lot size
input double        InpRiskPercent = 1.0;    // Risk % of balance (LOT_RISK_PCT)

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
int      g_hAtr  = INVALID_HANDLE;

datetime g_lastBarTime   = 0;
int      g_tradesToday   = 0;
int      g_tradeDay      = -1;
double   g_lastUsedLevel = 0.0;   // resistance level of the most recent entry
int      g_windowStartMin= -1;    // resolved window start, minutes from server midnight

//+------------------------------------------------------------------+
//| Helpers - time                                                    |
//+------------------------------------------------------------------+
datetime MidnightOf(const int year,const int mon,const int day)
  {
   return (datetime)StringToTime(StringFormat("%04d.%02d.%02d 00:00:00",year,mon,day));
  }

// Day-of-month of the nth given weekday (0=Sunday) in a month.
int NthWeekdayDay(const int year,const int mon,const int weekday,const int nth)
  {
   MqlDateTime d;
   TimeToStruct(MidnightOf(year,mon,1),d);
   int firstDow = d.day_of_week;
   return 1 + ((weekday - firstDow) + 7) % 7 + (nth-1)*7;
  }

// US daylight saving: 2nd Sunday of March 07:00 UTC -> 1st Sunday of November 06:00 UTC.
bool IsUsDst(const datetime utc)
  {
   MqlDateTime d;
   TimeToStruct(utc,d);
   int y = d.year;
   datetime dstOn  = MidnightOf(y,3, NthWeekdayDay(y,3,0,2)) + 7*3600;
   datetime dstOff = MidnightOf(y,11,NthWeekdayDay(y,11,0,1)) + 6*3600;
   return (utc >= dstOn && utc < dstOff);
  }

// Resolve the window start (minutes after server midnight) for the given server time.
int ResolveWindowStartMinutes(const datetime serverNow)
  {
   if(InpUseManualWindow)
      return InpManualStartHour*60 + InpManualStartMinute;

// Approximate UTC using the winter offset - only ambiguous within an hour of a
// DST switch, which is outside the NY window anyway.
   long     offsetSec = (long)MathRound(InpBrokerGmtOffsetWin*3600.0);
   datetime approxUtc = (datetime)((long)serverNow - offsetSec);
   bool     dst       = IsUsDst(approxUtc);

// NY 09:30 ET expressed in UTC: 13:30 during EDT, 14:30 during EST.
   double nyOpenUtcMin = dst ? (13*60+30) : (14*60+30);
   double brokerOffMin = InpBrokerGmtOffsetWin*60.0 + ((InpBrokerFollowsUsDst && dst) ? 60.0 : 0.0);

   int startMin = (int)MathRound(nyOpenUtcMin + brokerOffMin);
   startMin %= 1440;
   if(startMin < 0)
      startMin += 1440;
   return startMin;
  }

bool InTradingWindow(const datetime serverNow)
  {
   MqlDateTime d;
   TimeToStruct(serverNow,d);
   int nowMin = d.hour*60 + d.min;
   int start  = g_windowStartMin;
   int end    = start + InpWindowMinutes;

   if(end <= 1440)
      return (nowMin >= start && nowMin < end);
   return (nowMin >= start || nowMin < (end - 1440));   // window wraps past midnight
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

// Most recent confirmed pivot high at or older than startShift. 0.0 = none found.
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

// Look at InpRangeBars bars starting at startShift and decide whether they form a
// tradeable consolidation: a box that is TIGHT relative to ATR and whose ceiling
// has been TESTED more than once. A clean trend leg fails the tightness test, which
// is the whole point - it is what separates a range breakout from a new swing high.
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
//| Helpers - position / orders                                       |
//+------------------------------------------------------------------+
bool GetOpenPosition(ulong &ticket)
  {
   ticket = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic)
         continue;
      ticket = t;
      return true;
     }
   return false;
  }

double NormalizeVolume(double v)
  {
   double minv = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxv = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;

   v = MathFloor(v/step) * step;
   if(v < minv)
      v = minv;
   if(v > maxv)
      v = maxv;

   int digits = 0;
   double s = step;
   while(s < 1.0 && digits < 8)
     {
      s *= 10.0;
      digits++;
     }
   return NormalizeDouble(v,digits);
  }

double LotsForRisk(const double stopDistance)
  {
   if(stopDistance <= 0.0)
      return 0.0;

   double tickValue = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0)
      return 0.0;

   double lossPerLot = (stopDistance / tickSize) * tickValue;
   if(lossPerLot <= 0.0)
      return 0.0;

   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   return riskMoney / lossPerLot;
  }

// Push the stop far enough away to satisfy the broker's minimum stop distance.
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
   if(InpPivotLeft < 1 || InpPivotRight < 1)
     {
      Print("Pivot left/right bars must be >= 1.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpWindowMinutes < 1 || InpWindowMinutes > 1440)
     {
      Print("Window length must be between 1 and 1440 minutes.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpLevelSource == LEVEL_RANGE_HIGH && (InpRangeBars < 2 || InpMinTouches < 1 || InpMaxRangeATR <= 0.0))
     {
      Print("Range detection needs RangeBars >= 2, MinTouches >= 1 and MaxRangeATR > 0.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpLotMode == LOT_RISK_PCT && InpStopMode == SL_NONE)
     {
      Print("Risk-percent sizing needs a stop loss. Choose a StopMode or switch to fixed lots.");
      return INIT_PARAMETERS_INCORRECT;
     }

   g_hFast = iMA(_Symbol,_Period,InpFastPeriod,0,InpMaMethod,InpMaPrice);
   g_hSlow = iMA(_Symbol,_Period,InpSlowPeriod,0,InpMaMethod,InpMaPrice);
   if(g_hFast == INVALID_HANDLE || g_hSlow == INVALID_HANDLE)
     {
      Print("Failed to create MA handles.");
      return INIT_FAILED;
     }

   // ATR is needed by the range test as well as by SL_ATR, so always create it.
   g_hAtr = iATR(_Symbol,_Period,InpAtrPeriod);
   if(g_hAtr == INVALID_HANDLE)
     {
      Print("Failed to create ATR handle.");
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
   if(g_hFast != INVALID_HANDLE)
      IndicatorRelease(g_hFast);
   if(g_hSlow != INVALID_HANDLE)
      IndicatorRelease(g_hSlow);
   if(g_hAtr != INVALID_HANDLE)
      IndicatorRelease(g_hAtr);
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
      g_windowStartMin = ResolveWindowStartMinutes(now);   // re-resolved once a day (DST)
     }

   // Enough history for whichever level source is active, plus the ATR warm-up.
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
   if(CopyBuffer(g_hFast,0,0,3,fast) < 3)
      return;
   if(CopyBuffer(g_hSlow,0,0,3,slow) < 3)
      return;

   if(g_lastBarTime == 0)
     {
      g_lastBarTime = rates[0].time;   // first tick after attach: sync, never trade off history
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

   // On a confirmed break the range must EXCLUDE the breakout bar, otherwise the
   // bar's own high defines the ceiling and nothing can ever exceed it.
   int rangeStart = (InpBreakMode == BREAK_ON_CLOSE) ? 2 : 1;
   RangeInfo rng;
   DetectRange(rates,rangeStart,atrVal,rng);

   double levelNow  = 0.0;
   double levelPrev = 0.0;
   if(InpLevelSource == LEVEL_RANGE_HIGH)
      levelNow = rng.valid ? rng.high : 0.0;   // no valid range => no level => no trade
   else
     {
      levelNow  = FindLastPivotHigh(rates,InpPivotRight+1,InpPivotLeft,InpPivotRight,InpPivotScanBars);
      levelPrev = FindLastPivotHigh(rates,InpPivotRight+2,InpPivotLeft,InpPivotRight,InpPivotScanBars);
     }

   ulong ticket = 0;
   bool  hasPosition = GetOpenPosition(ticket);

   //--- 1. Exits are evaluated first, and are NOT restricted to the window.
   if(newBar && hasPosition)
     {
      double exitLevel = fast[1] - InpExitBufferPts * _Point;
      if(rates[1].close < exitLevel)
        {
         g_trade.PositionClose(ticket);
         hasPosition = GetOpenPosition(ticket);
        }
     }

   if(hasPosition && InpCloseAtWindowEnd && !inWindow)
     {
      g_trade.PositionClose(ticket);
      hasPosition = GetOpenPosition(ticket);
     }

   //--- 2. Entry
   if(newBar)
      g_lastBarTime = rates[0].time;

   if(hasPosition || !inWindow || levelNow <= 0.0)
     {
      UpdatePanel(fast[1],slow[1],levelNow,inWindow,hasPosition,rng);
      return;
     }

   if(InpMaxTradesPerDay > 0 && g_tradesToday >= InpMaxTradesPerDay)
     {
      UpdatePanel(fast[1],slow[1],levelNow,inWindow,hasPosition,rng);
      return;
     }

   double sameLevelTol = MathMax(_Point,0.25*atrVal);
   if(InpOneEntryPerLevel && g_lastUsedLevel > 0.0 &&
      MathAbs(levelNow - g_lastUsedLevel) < sameLevelTol)
     {
      UpdatePanel(fast[1],slow[1],levelNow,inWindow,hasPosition,rng);
      return;
     }

   if(InpMaxSpreadPts > 0)
     {
      long spread = SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
      if(spread > InpMaxSpreadPts)
        {
         UpdatePanel(fast[1],slow[1],levelNow,inWindow,hasPosition,rng);
         return;
        }
     }

   // The 9 > 20 filter, read on the last closed bar.
   bool maFilter = (fast[1] > slow[1]);

   bool signal = false;
   if(InpLevelSource == LEVEL_RANGE_HIGH)
     {
      // The range window sits entirely behind the trigger, so any break of the
      // ceiling is by construction a fresh one - no cross bookkeeping needed.
      if(InpBreakMode == BREAK_ON_CLOSE)
         signal = (newBar && maFilter && rates[1].close > levelNow + buffer);
      else
        {
         double askR = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         signal = (maFilter && askR > levelNow + buffer);
        }
     }
   else if(InpBreakMode == BREAK_ON_CLOSE)
     {
      // Fresh cross: this bar closed above the level, the one before did not.
      if(newBar && maFilter && levelPrev > 0.0)
         signal = (rates[1].close > levelNow + buffer && rates[2].close <= levelPrev + buffer);
     }
   else
     {
      // Intrabar: last close was still under the level, price is now through it.
      double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      if(maFilter && rates[1].close <= levelNow + buffer && ask > levelNow + buffer)
         signal = true;
     }

   if(signal)
      OpenLong(rates,levelNow,rng.low);

   UpdatePanel(fast[1],slow[1],levelNow,inWindow,hasPosition,rng);
  }

//+------------------------------------------------------------------+
//| Entry                                                             |
//+------------------------------------------------------------------+
void OpenLong(const MqlRates &rates[],const double level,const double rangeLow)
  {
   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   if(ask <= 0.0)
      return;

   //--- stop loss
   double sl = 0.0;
   switch(InpStopMode)
     {
      case SL_SWING_LOW:
        {
         int    n  = MathMax(1,MathMin(InpSwingLookback,ArraySize(rates)-1));
         double lo = rates[1].low;
         for(int i=1; i<=n; i++)
            lo = MathMin(lo,rates[i].low);
         sl = lo - InpSwingPadPts * _Point;
         break;
        }
      case SL_ATR:
        {
         double atr[];
         ArraySetAsSeries(atr,true);
         if(CopyBuffer(g_hAtr,0,0,2,atr) < 2 || atr[1] <= 0.0)
            return;
         sl = ask - InpAtrMult * atr[1];
         break;
        }
      case SL_RANGE_LOW:
        {
         if(rangeLow > 0.0)
            sl = rangeLow - InpRangePadPts * _Point;
         else
           {
            // Pivot mode, or no valid range: fall back to the swing low.
            int    n  = MathMax(1,MathMin(InpSwingLookback,ArraySize(rates)-1));
            double lo = rates[1].low;
            for(int i=1; i<=n; i++)
               lo = MathMin(lo,rates[i].low);
            sl = lo - InpSwingPadPts * _Point;
           }
         break;
        }
      case SL_POINTS:
         sl = ask - InpStopPoints * _Point;
         break;
      case SL_NONE:
      default:
         sl = 0.0;
         break;
     }

   if(sl > 0.0)
     {
      if(sl >= ask)
        {
         Print("Computed stop is above entry - skipping this signal.");
         return;
        }
      sl = ClampStopBelow(ask,sl);
     }

   //--- take profit (R multiple of the actual stop distance)
   double tp = 0.0;
   if(InpTakeProfitR > 0.0 && sl > 0.0)
      tp = NormalizeDouble(ask + (ask - sl) * InpTakeProfitR,_Digits);

   //--- volume
   double lots = InpFixedLots;
   if(InpLotMode == LOT_RISK_PCT)
     {
      lots = LotsForRisk(ask - sl);
      if(lots <= 0.0)
        {
         Print("Risk sizing produced zero lots - skipping this signal.");
         return;
        }
     }
   lots = NormalizeVolume(lots);
   if(lots <= 0.0)
      return;

   if(!g_trade.Buy(lots,_Symbol,0.0,sl,tp,"GT breakout"))
     {
      PrintFormat("Buy failed: retcode=%d %s",g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
      return;
     }

   g_tradesToday++;
   g_lastUsedLevel = level;
   PrintFormat("Long %s lots. Resistance %s, SL %s, TP %s",
               DoubleToString(lots,2),
               DoubleToString(level,_Digits),
               sl > 0.0 ? DoubleToString(sl,_Digits) : "none",
               tp > 0.0 ? DoubleToString(tp,_Digits) : "none");
  }

//+------------------------------------------------------------------+
//| Status panel                                                      |
//+------------------------------------------------------------------+
void UpdatePanel(const double fast,const double slow,const double level,
                 const bool inWindow,const bool hasPosition,const RangeInfo &rng)
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
         rangeTxt = StringFormat("%s - %s | %s ATR (max %s) | %d touch%s | %s",
                                 DoubleToString(rng.low,_Digits),
                                 DoubleToString(rng.high,_Digits),
                                 DoubleToString(rng.heightAtr,2),
                                 DoubleToString(InpMaxRangeATR,2),
                                 rng.touches, rng.touches == 1 ? "" : "es",
                                 rng.valid ? "VALID" : "rejected");

   string txt = StringFormat(
                   "Gold Trades Breakout EA\n"
                   "Window   : %02d:%02d - %02d:%02d server  [%s]\n"
                   "MA %d/%d  : %s / %s  [%s]\n"
                   "Range    : %s\n"
                   "Resistance: %s\n"
                   "Position : %s   Trades today: %d",
                   g_windowStartMin/60, g_windowStartMin%60, endMin/60, endMin%60,
                   inWindow ? "OPEN" : "closed",
                   InpFastPeriod, InpSlowPeriod,
                   DoubleToString(fast,_Digits), DoubleToString(slow,_Digits),
                   fast > slow ? "9 > 20 OK" : "blocked",
                   rangeTxt,
                   level > 0.0 ? DoubleToString(level,_Digits) : "none found",
                   hasPosition ? "LONG" : "flat",
                   g_tradesToday);
   Comment(txt);
  }
//+------------------------------------------------------------------+

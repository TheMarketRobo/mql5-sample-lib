//+------------------------------------------------------------------+
//|                                            SampleTMRZigZag.mq5     |
//|                        Copyright 2024, The Market Robo Inc.       |
//|                                        https://themarketrobo.com   |
//+------------------------------------------------------------------+
//
// SAMPLE INDICATOR — ZigZagColor + TheMarketRobo SDK
// ===================================================
// Based on MetaQuotes ZigzagColor.mq5 sample. Integrates with SDK for
// session registration, heartbeats, and termination handling (indicator path).
//
// What this sample shows:
//   1. Extending CTheMarketRobo_Base with PRODUCT_TYPE_INDICATOR (1-arg constructor)
//   2. Implementing on_calculate() with full ZigZag logic
//   3. Global indicator buffers (required by MQL5) + SDK class for logic
//   4. on_init(api_key) — no magic_number; OnTimer/OnChartEvent for SDK
//
// USAGE:
//   1. Set InpApiKey in inputs
//   2. Attach to any chart; ZigZag draws as usual; SDK runs in background
//
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, The Market Robo Inc."
#property link      "https://themarketrobo.com"
#property version   "1.00"
#property description "Sample ZigZag indicator with TheMarketRobo SDK (INDICATOR product type)"

//--- indicator settings (same as ZigzagColor)
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   1
#property indicator_type1   DRAW_COLOR_ZIGZAG
#property indicator_color1  clrDodgerBlue, clrRed
#property strict

#include <themarketrobo/TheMarketRobo_SDK.mqh>

//--- input parameters
input string InpApiKey     = "";  // API Key (required for SDK)
input int    InpDepth     = 12;  // Depth
input int    InpDeviation = 5;   // Deviation
input int    InpBackstep  = 3;   // Back Step

//--- indicator version UUID (replace with your indicator version UUID from server)
const string INDICATOR_VERSION_UUID = "00000000-0000-0000-0000-000000000000";

//--- indicator buffers (must be global for SetIndexBuffer)
double ZigzagPeakBuffer[];
double ZigzagBottomBuffer[];
double HighMapBuffer[];
double LowMapBuffer[];
double ColorBuffer[];

int ExtRecalc = 3; // recounting's depth

enum EnSearchMode
{
   Extremum = 0,  // searching for the first extremum
   Peak     = 1,  // searching for the next ZigZag peak
   Bottom   = -1  // searching for the next ZigZag bottom
};

//+------------------------------------------------------------------+
//| Get highest value for range                                      |
//+------------------------------------------------------------------+
double Highest(const double &array[], int count, int start)
{
   double res = array[start];
   for(int i = start - 1; i > start - count && i >= 0; i--)
      if(res < array[i])
         res = array[i];
   return res;
}

//+------------------------------------------------------------------+
//| Get lowest value for range                                       |
//+------------------------------------------------------------------+
double Lowest(const double &array[], int count, int start)
{
   double res = array[start];
   for(int i = start - 1; i > start - count && i >= 0; i--)
      if(res > array[i])
         res = array[i];
   return res;
}

//+------------------------------------------------------------------+
//| Sample ZigZag indicator class — SDK + ZigZag logic                |
//+------------------------------------------------------------------+
class CSampleZigZagIndicator : public CTheMarketRobo_Base
{
public:
   CSampleZigZagIndicator() : CTheMarketRobo_Base(INDICATOR_VERSION_UUID)
   {
      Print("SampleTMRZigZag: Indicator instance created (SDK product type: INDICATOR)");
   }

   virtual int on_calculate(const int rates_total,
                           const int prev_calculated,
                           const datetime &time[],
                           const double   &open[],
                           const double   &high[],
                           const double   &low[],
                           const double   &close[],
                           const long     &tick_volume[],
                           const long     &volume[],
                           const int      &spread[]) override
   {
      if(rates_total < 100)
         return 0;

      int    i, start = 0;
      int    extreme_counter = 0, extreme_search = Extremum;
      int    shift, back = 0, last_high_pos = 0, last_low_pos = 0;
      double val = 0, res = 0;
      double cur_low = 0, cur_high = 0, last_high = 0, last_low = 0;

      if(prev_calculated == 0)
      {
         ArrayInitialize(ZigzagPeakBuffer, 0.0);
         ArrayInitialize(ZigzagBottomBuffer, 0.0);
         ArrayInitialize(HighMapBuffer, 0.0);
         ArrayInitialize(LowMapBuffer, 0.0);
         start = InpDepth - 1;
      }

      if(prev_calculated > 0)
      {
         i = rates_total - 1;
         while(extreme_counter < ExtRecalc && i > rates_total - 100)
         {
            res = (ZigzagPeakBuffer[i] + ZigzagBottomBuffer[i]);
            if(res != 0)
               extreme_counter++;
            i--;
         }
         i++;
         start = i;
         if(LowMapBuffer[i] != 0)
         {
            cur_low = LowMapBuffer[i];
            extreme_search = Peak;
         }
         else
         {
            cur_high = HighMapBuffer[i];
            extreme_search = Bottom;
         }
         for(i = start + 1; i < rates_total && !IsStopped(); i++)
         {
            ZigzagPeakBuffer[i]   = 0.0;
            ZigzagBottomBuffer[i] = 0.0;
            LowMapBuffer[i]       = 0.0;
            HighMapBuffer[i]      = 0.0;
         }
      }

      for(shift = start; shift < rates_total && !IsStopped(); shift++)
      {
         val = Lowest(low, InpDepth, shift);
         if(val == last_low)
            val = 0.0;
         else
         {
            last_low = val;
            if((low[shift] - val) > (InpDeviation * _Point))
               val = 0.0;
            else
            {
               for(back = InpBackstep; back >= 1; back--)
               {
                  res = LowMapBuffer[shift - back];
                  if((res != 0) && (res > val))
                     LowMapBuffer[shift - back] = 0.0;
               }
            }
         }
         if(low[shift] == val)
            LowMapBuffer[shift] = val;
         else
            LowMapBuffer[shift] = 0.0;

         val = Highest(high, InpDepth, shift);
         if(val == last_high)
            val = 0.0;
         else
         {
            last_high = val;
            if((val - high[shift]) > (InpDeviation * _Point))
               val = 0.0;
            else
            {
               for(back = InpBackstep; back >= 1; back--)
               {
                  res = HighMapBuffer[shift - back];
                  if((res != 0) && (res < val))
                     HighMapBuffer[shift - back] = 0.0;
               }
            }
         }
         if(high[shift] == val)
            HighMapBuffer[shift] = val;
         else
            HighMapBuffer[shift] = 0.0;
      }

      if(extreme_search == 0)
      {
         last_low  = 0;
         last_high = 0;
      }
      else
      {
         last_low  = cur_low;
         last_high = cur_high;
      }

      for(shift = start; shift < rates_total && !IsStopped(); shift++)
      {
         res = 0.0;
         switch(extreme_search)
         {
            case Extremum:
               if(last_low == 0 && last_high == 0)
               {
                  if(HighMapBuffer[shift] != 0)
                  {
                     last_high = high[shift];
                     last_high_pos = shift;
                     extreme_search = -1;
                     ZigzagPeakBuffer[shift] = last_high;
                     ColorBuffer[shift] = 0;
                     res = 1;
                  }
                  if(LowMapBuffer[shift] != 0)
                  {
                     last_low = low[shift];
                     last_low_pos = shift;
                     extreme_search = 1;
                     ZigzagBottomBuffer[shift] = last_low;
                     ColorBuffer[shift] = 1;
                     res = 1;
                  }
               }
               break;
            case Peak:
               if(LowMapBuffer[shift] != 0.0 && LowMapBuffer[shift] < last_low &&
                  HighMapBuffer[shift] == 0.0)
               {
                  ZigzagBottomBuffer[last_low_pos] = 0.0;
                  last_low_pos = shift;
                  last_low = LowMapBuffer[shift];
                  ZigzagBottomBuffer[shift] = last_low;
                  ColorBuffer[shift] = 1;
                  res = 1;
               }
               if(HighMapBuffer[shift] != 0.0 && LowMapBuffer[shift] == 0.0)
               {
                  last_high = HighMapBuffer[shift];
                  last_high_pos = shift;
                  ZigzagPeakBuffer[shift] = last_high;
                  ColorBuffer[shift] = 0;
                  extreme_search = Bottom;
                  res = 1;
               }
               break;
            case Bottom:
               if(HighMapBuffer[shift] != 0.0 &&
                  HighMapBuffer[shift] > last_high &&
                  LowMapBuffer[shift] == 0.0)
               {
                  ZigzagPeakBuffer[last_high_pos] = 0.0;
                  last_high_pos = shift;
                  last_high = HighMapBuffer[shift];
                  ZigzagPeakBuffer[shift] = last_high;
                  ColorBuffer[shift] = 0;
               }
               if(LowMapBuffer[shift] != 0.0 && HighMapBuffer[shift] == 0.0)
               {
                  last_low = LowMapBuffer[shift];
                  last_low_pos = shift;
                  ZigzagBottomBuffer[shift] = last_low;
                  ColorBuffer[shift] = 1;
                  extreme_search = Peak;
               }
               break;
            default:
               return rates_total;
         }
      }

      return rates_total;
   }
};

CSampleZigZagIndicator *g_indicator = NULL;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                           |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, ZigzagPeakBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, ZigzagBottomBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, ColorBuffer, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(3, HighMapBuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(4, LowMapBuffer, INDICATOR_CALCULATIONS);

   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   string short_name = StringFormat("SampleTMRZigZag(%d,%d,%d)", InpDepth, InpDeviation, InpBackstep);
   IndicatorSetString(INDICATOR_SHORTNAME, short_name);
   PlotIndexSetString(0, PLOT_LABEL, short_name);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);

   if(InpApiKey == "")
   {
      Print("SampleTMRZigZag: API Key is required. Set InpApiKey for SDK integration.");
      Alert("SampleTMRZigZag: API Key is required — set InpApiKey input.");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_indicator = new CSampleZigZagIndicator();
   if(CheckPointer(g_indicator) == POINTER_INVALID)
   {
      Print("SampleTMRZigZag: Failed to create indicator instance.");
      return INIT_FAILED;
   }

   int result = g_indicator.on_init(InpApiKey);
   if(result != INIT_SUCCEEDED)
   {
      Print("SampleTMRZigZag: SDK init failed (code=", result, ")");
      delete g_indicator;
      g_indicator = NULL;
      return result;
   }

   Print("SampleTMRZigZag: Initialized with SDK. ZigZag + heartbeat/termination active.");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(CheckPointer(g_indicator) != POINTER_INVALID)
   {
      g_indicator.on_deinit(reason);
      delete g_indicator;
      g_indicator = NULL;
   }
   Print("SampleTMRZigZag: Deinitialized (reason=", reason, ")");
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                               |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
   if(CheckPointer(g_indicator) != POINTER_INVALID)
      return g_indicator.on_calculate(rates_total, prev_calculated, time, open, high, low, close, tick_volume, volume, spread);
   return rates_total;
}

//+------------------------------------------------------------------+
//| Timer — SDK heartbeat                                             |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(CheckPointer(g_indicator) != POINTER_INVALID)
      g_indicator.on_timer();
}

//+------------------------------------------------------------------+
//| Chart event — SDK events (termination, token refresh, etc.)        |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(CheckPointer(g_indicator) != POINTER_INVALID)
      g_indicator.on_chart_event(id, lparam, dparam, sparam);
}

//+------------------------------------------------------------------+

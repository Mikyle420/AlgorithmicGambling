//+------------------------------------------------------------------+
//|                                       AlgorithmicMoneyMagnet.mq5 |
//|                                Copyright 2025, Phumlani Mbabela. |
//|                                  https://www.phumlanimbabela.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Phumlani Mbabela."
#property link      "https://www.phumlanimbabela.com"
#property version   "1.01"

//+------------------------------------------------------------------+
//| Includes                                                         |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include "CandleUtils\ThreeCandlestickPatterns.mqh"
#include "CandleUtils\TwoCandlestickPatterns.mqh"
#include "CandleUtils\OneCandlestickPatterns.mqh"
#include "Notification\Notification.mqh"

#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

#property indicator_type1   DRAW_LINE
#property indicator_color1  clrBlue
#property indicator_label1  "Opening High"

#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_label2  "Opening Low"

#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDodgerBlue
#property indicator_label3  "Fast MA"

#property indicator_type4   DRAW_LINE
#property indicator_color4  clrOrange
#property indicator_label4  "Slow MA"



//+------------------------------------------------------------------+
//| Input Variables                                                  |
//+------------------------------------------------------------------+
input bool UseEAInAutoMode = true;                          // Use EA in Active Mode.
input int BarsToWaitPriorTrading = 10;                      // Number of bars to wait before trading
input int InpFastPeriod = 4;                                // Fast period.
input int InpSlowPeriod = 7;                                // Slow period.
input double InpLotSize = 0.33 ;                            // Lot size.
input double InpTakeProfitUSD = 20.0;                       // Take Profit in USD.
input double InpStopLossUSD = 10.0;                         // Stop Loss in USD.
input double InpLossThresholdUSD = 5.0;                     // Loss threshold in USD
input ulong InpMagicNumber = 998206073;                     // Magic Number.
input int MaxOpenTradesPerSession = 1;                      // Max open trades per session.

input double CrossOverFastSlowDistanceTollerance = 0.00010; // Crossover Fast vs Slow Distance Tollerance
input double FastSlowDistanceTollerance = 0.00015;          // Fast vs Slow Distance Tollerance
input double CloseWhenProfitGreaterThan = 10.0;             // Close When Profit Greater Than
input double CloseWhenLossGreaterThan = -10.0;              // Close When Loss Greater Than
input ulong InpRequestDeviationInPoints = 1.0;             // InpRequest Deviation In Points

input ENUM_TIMEFRAMES SESSION_PERIOD_RESOLUTION=PERIOD_M1;  // SESSION_PERIOD_RESOLUTION
input ENUM_TIMEFRAMES Timeseries_SameDirection_RESOLUTION=PERIOD_M5;  // Timeseries_SameDirection_RESOLUTION
input ENUM_TIMEFRAMES DRAW_BASELINE_SESSION_PERIOD_RESOLUTION=PERIOD_M5;  // DRAW_BASELINE_SESSION_PERIOD_RESOLUTION

input bool BEBUG_BOT = true;                                // BEBUG_BOT mode

// Define thresholds for speed classification
input double fastThreshold = 0.00110;                       // Fast Threshold speed classification
input double slowThreshold = 0.00011;                       // Slow Threshold speed classification
input bool   EnableSpeedThreshold = true;                   // Enable Speed Threshold

input int CrossoverPredictionCandles = 1;                   // Crossover prediction candles.

input int BullBearRunCandleDepth = 3;                       // BullBearRunCandleDepth
input int BullRunCandleCount = 2;                           // BullRunCandleCount
input int BearRunCandleCount = 2;                           // BearRunCandleCount
input bool IgnoreDetectMAConvergence = true;                // IgnoreDetectMAConvergence
input double IgnoreDetectMAConvergenceTollerrance=0.000100; // IgnoreDetectMAConvergenceTollerrance
input bool IgnoreCandleStickPremonition = true;            // IgnoreCandleStickPremonition

input double StickEntryCutoffPipsize = 4.0;                 // StickEntryCutoffPipsize
input int GoodBadTradesInThePastNCandlesticks = 1;          // GoodBadTradesInThePastNCandlesticks

input string InpCrossReferenceTimePeriod= "M1,M5,M10,M15";     // InpCrossReferenceTimePeriod "M1,M5,M15,M30,H1,H4,D1,W1,MN"

input double SpreadThreshold = 100.0;                         // Spread Threshold Points (not pips)

input bool EnteringAtTheBeggingOfCandleStickAvoidance = true;   // AvoidEnteringAtTheBeggingOfCandleStick
input int EnteringAtTheBeggingOfCandleStickAvoidanceDelay = 10; // AvoidEnteringAtTheBeggingOfCandleStickDelay

input bool InpRunConsensusOnlyOnThePreviousCandleStick = true; // InpRunConsensusOnlyOnThePreviousCandleStick




//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
int fastHandle;
int slowHandle;
double fastBuffer[];
double slowBuffer[];
CTrade trade;
int barsTotal = 0;
int barsTotalPriceAdjustment = 0;
int barsForCandlestickPattern = 0;
int barsForFutureLineCross = 0;
int barsCreateObject = 0;
int CountOpenTradesPerSession = 0;
datetime lastTradeTime = 0;
string marketPatternSpeed = "";
bool buyEntry  = false;
bool sellEntry = false;

// Used to delay trading so that the MA's
datetime lastBarTime = 0;
int newBarCount = 0;

bool showOverlay = true;
double maxProfit[100];
double minProfit[100];

bool EAInitialised = false;

//+------------------------------------------------------------------+
//| Pattern detection algorithms.                                    |
//+------------------------------------------------------------------+
OneCandlestickPatterns     oneCandlestickPattern;
TwoCandlestickPatterns     twoCandlestickPattern;
ThreeCandlestickPatterns   threeCandlestickPattern;

//+------------------------------------------------------------------+
//| Pattern detection algorithms.                                    |
//+------------------------------------------------------------------+
Notification notification;

double highLineBuffer[], lowLineBuffer[];

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool resultConsensusCandleStick0 = false;
bool resultConsensusCandleStick1 = false;
string DetectMarketMovement0 = "";
string DetectMarketMovement1 = "";
bool SameDirection0 = false;
bool SameDirection1 = false;

//+------------------------------------------------------------------+
//| Convert string to timeframe enum                                 |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES TimeframeFromString(string tf) {
   if(tf=="M1")  return PERIOD_M1;
   if(tf=="M5")  return PERIOD_M5;
   if(tf=="M15") return PERIOD_M15;
   if(tf=="M30") return PERIOD_M30;
   if(tf=="H1")  return PERIOD_H1;
   if(tf=="H4")  return PERIOD_H4;
   if(tf=="D1")  return PERIOD_D1;
   if(tf=="W1")  return PERIOD_W1;
   if(tf=="MN")  return PERIOD_MN1;
   return (ENUM_TIMEFRAMES)-1;
}

struct TradeAnalysisResult {
   bool isProfitable;
   int badTradesInLastNCandles;
   int goodTradesInLastNCandles;
   int totalTradesInLastNCandles;
};

//+------------------------------------------------------------------+
//| Determine candlestick direction                                  |
//+------------------------------------------------------------------+
string GetCandleNature(MqlRates &candle) {
   if (candle.close > candle.open)
      return "Bullish";
   else if (candle.close < candle.open)
      return "Bearish";
   else
      return "Neutral";
}

//+------------------------------------------------------------------+
//| Main comparison function                                         |
//+------------------------------------------------------------------+
bool DoesMajorityAgreeWithM1(string symbol, string commaSeparatedTimeframes, const int candleStick ) {
   string timeframes[];
   int tfCount = StringSplit(commaSeparatedTimeframes, ',', timeframes);
   if (tfCount < 1) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Invalid or too few timeframes.");
      return false;
   }

   string mapDirections[10];
//ArrayResize(mapDirections, tfCount);
   int indexM1 = -1;

   for (int i = 0; i < tfCount; i++) {
      ENUM_TIMEFRAMES tf = TimeframeFromString(timeframes[i]);
      if (tf == -1) {
         if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Skiped M1 timeframe: ", timeframes[i]);
         continue;
      }

      MqlRates rates[2];
      if (CopyRates(symbol, tf, 0, 2, rates) != 2) {
         if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Failed to get candle for: ", timeframes[i]);
         continue;
      }

      string nature = GetCandleNature(rates[candleStick]);  // previous candle
      mapDirections[i] = nature;

      if (timeframes[i] == "M1")
         indexM1 = i;

      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat("Timeframe %s: %s", timeframes[i], nature);
   }

   if (indexM1 == -1) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("M1 not found in timeframe list.");
      return false;
   }

   string m1Nature = mapDirections[indexM1];
   int agree = 0, disagree = 0;

   for (int i = 0; i < tfCount; i++) {
      if (i == indexM1 || mapDirections[i] == "Neutral") continue;

      if (mapDirections[i] == m1Nature)
         agree++;
      else
         disagree++;
   }

   if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat("M1 Nature: %s | Agree: %d | Disagree: %d", m1Nature, agree, disagree);
   return (agree > disagree);
}


bool areGoodTradesBiggerThanBadTradesInThePastNCandlesticks(ulong ticket = 0, int lookback = 3) {

   TradeAnalysisResult res = AnalyzeTrade(ticket, lookback);

   if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Trade was profitable: ", res.isProfitable);
   if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Trade was profitable: ", res.isProfitable);
   if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Total trades in last ", lookback, " candles: ", res.totalTradesInLastNCandles);
   if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Good trades: ", res.goodTradesInLastNCandles);
   if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Bad trades: ", res.badTradesInLastNCandles);

   if ( res.goodTradesInLastNCandles >res.badTradesInLastNCandles )
      return true;
   else
      return false;
}


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
TradeAnalysisResult AnalyzeTrade(ulong ticketId, int candlesBack) {
   TradeAnalysisResult result;
   result.isProfitable = false;
   result.badTradesInLastNCandles = 0;
   result.goodTradesInLastNCandles = 0;
   result.totalTradesInLastNCandles = 0;

// Select the ticket
   if (!HistoryDealSelect(ticketId)) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Trade ticket not found: ", ticketId);
      return result;
   }

   double profit = HistoryDealGetDouble(ticketId, DEAL_PROFIT);
   result.isProfitable = (profit > 0);

// Define the time range: from N candles ago to now
   datetime endTime = TimeCurrent();
   datetime startTime = iTime(_Symbol, _Period, candlesBack);
   if (startTime == 0) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Invalid candle index: ", candlesBack);
      return result;
   }

// Loop through the deal history
   int total = HistoryDealsTotal();
   for (int i = total - 1; i >= 0; i--) {
      ulong deal = HistoryDealGetTicket(i);
      if (deal == 0 || !HistoryDealSelect(deal)) continue;

      datetime dealTime = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      if (dealTime < startTime) break;
      if (dealTime > endTime) continue;

      result.totalTradesInLastNCandles++;
      //FIX - Wrong.
      double dealProfit = HistoryDealGetDouble(deal, DEAL_PROFIT);
      if (dealProfit > 0)
         result.goodTradesInLastNCandles++;
      else if (dealProfit < 0)
         result.badTradesInLastNCandles++;
   }

   return result;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int GetRandomInt(int min, int max) {
// Ensure we initialize the random seed once (e.g., in OnInit())
   return min + MathRand() % (max - min + 1);
}


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool AvoidEnteringAtTheBeggingOfTheCandleStick() {

   int seconds = 0;
   if(SESSION_PERIOD_RESOLUTION==PERIOD_M1) {
      seconds = GetRandomInt(3,55);
   } else if(SESSION_PERIOD_RESOLUTION==PERIOD_M5) {
      seconds = GetRandomInt(200,300);
   } else if(SESSION_PERIOD_RESOLUTION==PERIOD_M30) {
      seconds = GetRandomInt(600,1600);
   } else if(SESSION_PERIOD_RESOLUTION==PERIOD_H1) {
      seconds = GetRandomInt(1200,23000);
   } else if(SESSION_PERIOD_RESOLUTION==PERIOD_H4) {
      seconds = GetRandomInt(4800,12100);
   } else if(SESSION_PERIOD_RESOLUTION==PERIOD_D1) {
      seconds = GetRandomInt(28800,83400);
   } else {
      seconds = 50;
   }

   if ((TimeCurrent() - lastTradeTime >= seconds) && (lastTradeTime != iTime(_Symbol,PERIOD_CURRENT,0)) ) // Wait 10 seconds after new candle
      return true;  // Exit early, skip trading
   else
      return false;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   MACrossoverInit();
   if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " LAST PING=%.5f ms", TerminalInfoInteger(TERMINAL_PING_LAST)/1000.);

   InitialiseButtons();
   MathSrand( (int)TimeLocal() ); // Seed with current time.

   EventKillTimer();
   EventSetTimer(5);
   CreateOverlayToggleButton();
   ChartRedraw();

   return(INIT_SUCCEEDED);
}


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void InitialiseButtons() {
   SetIndexBuffer(0, highLineBuffer);
   SetIndexBuffer(1, lowLineBuffer);
   SetIndexBuffer(2, fastBuffer);
   SetIndexBuffer(3, slowBuffer);

   if(!UseEAInAutoMode) {
      CreateButton("btnBuy", "Buy", 10, 30, clrGreen);
      CreateButton("btnSell", "Sell", 100, 30, clrRed);
      CreateButton("btnCloseMBuy", "Close-M-Buy", 190, 30, clrBlue);
      CreateButton("btnCloseMSell", "Close-M-Sell", 280, 30, clrBlue);
      CreateButton("btnCloseAMSell", "Close-AM-All", 370, 30, clrBlue);
      CreateButton("btnAdjustSLTPUP", "😊 SL/TP", 460, 30, clrGreen);
      CreateButton("btnAdjustSLTPDown", "☹️ SL/TP",550, 30, clrRed);
   }
}



//+------------------------------------------------------------------+
//| Button Creation                                                  |
//+------------------------------------------------------------------+
void CreateButton(string name, string text, int x, int y, color clr) {
   if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0))
      return;

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, 70);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, 25);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

//+------------------------------------------------------------------+
//|  Draw Baseline                                                   |
//+------------------------------------------------------------------+
void DrawBaseline() {
   double highVal = iHigh(_Symbol, DRAW_BASELINE_SESSION_PERIOD_RESOLUTION, 0);
   double lowVal = iLow(_Symbol, DRAW_BASELINE_SESSION_PERIOD_RESOLUTION, 0);

   int testHandle = iMA(_Symbol,DRAW_BASELINE_SESSION_PERIOD_RESOLUTION,0,20,MODE_SMA,PRICE_CLOSE);
   if(testHandle == INVALID_HANDLE) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"Failed to create fast handle.");
   }

   int barsEntry = iBars(_Symbol, PERIOD_CURRENT);
   if(barsEntry<10) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("MA buffer not ready yet. (InpSlowPeriod)=",InpSlowPeriod);
      return;
   } else {
      ArrayResize(highLineBuffer, 10);
      ArrayResize(lowLineBuffer, 10);
      for(int i = 0; i < 10; i++) {
         highLineBuffer[i] = highVal;
         lowLineBuffer[i] = lowVal;
      }
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " EA deinitialised.");

   MACrossoverDeInit();

   EventKillTimer();
   ObjectDelete(0, "OverlayToggleBtn");
   ObjectDelete(0, "AccountOverlay");
   ObjectDelete(0, "OverlayBackground");

   if(!UseEAInAutoMode) {
      ObjectDelete(0, "btnBuy");
      ObjectDelete(0, "btnSell");
      ObjectDelete(0, "btnCloseMBuy");
      ObjectDelete(0, "btnCloseMSell");
      ObjectDelete(0, "btnCloseAMSell");
      ObjectDelete(0, "btnAdjustSLTPUP");
      ObjectDelete(0, "btnAdjustSLTPDown");
   }
}


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool OnTickSpread() {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread = (ask - bid) / _Point;

// Format the string
   string info = StringFormat("Symbol: %s\nBid: %.5f\nAsk: %.5f\nSpread: %.1f points", _Symbol, bid, ask, spread);

// Print it or use it for a label
   if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print(info);

// Example of setting it to a chart label
   string labelName = "SpreadInfo";
   if (!ObjectFind(0, labelName))
      ObjectCreate(0, labelName, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, labelName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, 30);
   ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 12);
   ObjectSetInteger(0, labelName, OBJPROP_COLOR, clrWhite);
   ObjectSetString(0, labelName, OBJPROP_TEXT, info);

   if( spread <= SpreadThreshold) {
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetProfitInUSD(ulong ticket) {
   if (HistoryDealSelect(ticket)) {
      // DEAL_PROFIT returns profit in the deposit currency (e.g., USD)
      double profit = PositionGetDouble( POSITION_PROFIT);
      return profit;
   }
   return 0.0;
}

//+------------------------------------------------------------------+
//| Convert USD to Pips                                              |
//+------------------------------------------------------------------+
double UsdToPips(string symbol, double usdAmount, double lotSize) {
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

   if (tickValue == 0.0 || tickSize == 0.0) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Error retrieving tick info for ", symbol);
      return 0.0;
   }

   double pipSize  = SymbolInfoDouble(symbol, SYMBOL_POINT) * 10; // 1 pip = 10 points
   double pipValue = (tickValue / tickSize) * pipSize * lotSize;

   if (pipValue == 0.0) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Invalid pip value calculation");
      return 0.0;
   }

   return usdAmount / pipValue;
}


//+------------------------------------------------------------------+
//| Open Trade with SL/TP in USD                                     |
//+------------------------------------------------------------------+
bool OpenTradeWithSLTPinUSD(string symbol, double lotSize, double slUSD, double tpUSD, bool isBuy, color clr, string label) {
   if (!SymbolSelect(symbol, true)) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Symbol not available: ", symbol);
      return false;
   }

   double price     = isBuy ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);
   double pipSize   = SymbolInfoDouble(symbol, SYMBOL_POINT) * 10;
   int    digits    = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   double slPips    = UsdToPips(symbol, slUSD, lotSize);
   double tpPips    = UsdToPips(symbol, tpUSD, lotSize);

   double slPrice   = isBuy ? price - slPips * pipSize : price + slPips * pipSize;
   double tpPrice   = isBuy ? price + tpPips * pipSize : price - tpPips * pipSize;

   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = symbol;
   request.volume    = lotSize;
   request.type      = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request.price     = NormalizeDouble(price, digits);
   request.sl        = NormalizeDouble(slPrice, digits);
   request.tp        = NormalizeDouble(tpPrice, digits);
   request.deviation = InpRequestDeviationInPoints;
   request.magic     = InpMagicNumber;
   request.comment   = isBuy ? "Buy with SL("+DoubleToString(slUSD)+")/TP("+DoubleToString(tpUSD)+") in USD" : "Sell with SL("+DoubleToString(slUSD)+")/TP("+DoubleToString(tpUSD)+") in USD";

   if ( (buyEntry||sellEntry) && !OrderSend(request, result)) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("OrderSend failed. Code: ", result.retcode);
      return false;
   } else {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Order placed successfully. Ticket: ", result.order);
      createObject(iTime(_Symbol, PERIOD_CURRENT, 0), fastBuffer[0], 300,0, clr, label);
      string message = StringFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"I just sold a symbol(%s), bid(%.5f), stopLoss(%.5f), takeProfit(%.5f), lotSize(%.5f) ", _Symbol, price,slPrice,tpPrice,InpLotSize);
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(message);

      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) createObject(iTime(_Symbol, PERIOD_CURRENT, 0), fastBuffer[0], 300,0, clr, label);

      if(UseEAInAutoMode) {
         if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) notification.SendEmailNotification("EA-SELL -> " + message, message);
      } else {
         if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) {
            PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"ERROR - Failed to sell a symbol(%s), bid(%.5f), stopLoss(%.5f), takeProfit(%.5f), lotSize(%.5f) ", _Symbol, price,slPrice,tpPrice,InpLotSize);
            notification.SendEmailNotification("User(Trader)-SELL -> " + message, message);
         }
      }
      return true;
   }

}


// TODO investigte this code.
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DrawSLTPAndTradeLine(string symbol, ulong ticket, color slColor, color tpColor, color tradeLineColor) {
   if(PositionSelect(symbol)) {
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      datetime entryTime = (datetime)PositionGetInteger(POSITION_TIME);
      long type = PositionGetInteger(POSITION_TYPE);
      double currentPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
      datetime nowTime = TimeCurrent();

      // --- Names for chart objects
      string slName = StringFormat("SL_%d", ticket);
      string tpName = StringFormat("TP_%d", ticket);
      string tradeLineName = StringFormat("TradeLine_%d", ticket);

      // --- Delete previous objects
      ObjectDelete(0, slName);
      ObjectDelete(0, tpName);
      ObjectDelete(0, tradeLineName);

      // --- Draw SL
      if(sl > 0) {
         ObjectCreate(0, slName, OBJ_HLINE, 0, 0, sl);
         ObjectSetInteger(0, slName, OBJPROP_COLOR, slColor);
         ObjectSetInteger(0, slName, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, slName, OBJPROP_WIDTH, 1);
      }

      // --- Draw TP
      if(tp > 0) {
         ObjectCreate(0, tpName, OBJ_HLINE, 0, 0, tp);
         ObjectSetInteger(0, tpName, OBJPROP_COLOR, tpColor);
         ObjectSetInteger(0, tpName, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, tpName, OBJPROP_WIDTH, 1);
      }

      // --- Draw Trade Line (entry to current price)
      ObjectCreate(0, tradeLineName, OBJ_TREND, 0, entryTime, entryPrice, nowTime, currentPrice);
      ObjectSetInteger(0, tradeLineName, OBJPROP_COLOR, tradeLineColor);
      ObjectSetInteger(0, tradeLineName, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, tradeLineName, OBJPROP_RAY_RIGHT, false);
   }
}


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DeleteDrawSLTP(string symbol, ulong ticket) {
   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);

   if(PositionSelect(symbol)) {
      string sl_name = StringFormat("SL_%d", ticket);
      string tp_name = StringFormat("TP_%d", ticket);
      string tradeLineName = StringFormat("TradeLine_%d", ticket);
      // Delete previous lines if they exist
      ObjectDelete(0, sl_name);
      ObjectDelete(0, tp_name);
      ObjectDelete(0, tradeLineName);
   }
}


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetCurrentCandlePipSize() {
   double high = iHigh(_Symbol, _Period, 0);
   double low  = iLow(_Symbol, _Period, 0);
   double pointSize = _Point;

   if ( (_Digits == 5) || (_Digits == 3) ) {
      return (high - low) / (pointSize * 10);  // Convert to pips
   } else {
      return (high - low) / pointSize;
   }
}


//+------------------------------------------------------------------+
//| Called on every trade transaction                                |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result) {

// Filter for transaction type: DEAL (meaning a trade occurred)
   if (trans.type == TRADE_TRANSACTION_DEAL_ADD && (!MQL5InfoInteger(MQL5_OPTIMIZATION)) ) {
      Print("==== New Deal Executed ====");
      Print("Deal Ticket: ", trans.deal);
      Print("Symbol: ", trans.symbol);
      Print("Deal Type: ", EnumToString((ENUM_DEAL_TYPE)trans.deal_type));
      Print("Volume: ", trans.volume);
      Print("Price: ", trans.price);
      //Print("Profit: ", trans.profit);
   }

// Check if it was a successful trade order placement
   if (trans.type == TRADE_TRANSACTION_ORDER_ADD && result.retcode == TRADE_RETCODE_DONE && (!MQL5InfoInteger(MQL5_OPTIMIZATION)) ) {
      Print("==== Order Placed Successfully ====");
      Print("Order Ticket: ", trans.order);
      Print("Symbol: ", trans.symbol);
      Print("Order Type: ", EnumToString((ENUM_ORDER_TYPE)request.type));
      Print("Volume: ", request.volume);
      Print("Price: ", request.price);

      long entry_type = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

      if (entry_type == DEAL_ENTRY_OUT) { // trade closed
         DeleteDrawSLTP(_Symbol, trans.position);
         double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
         CountOpenTradesPerSession--;
         lastTradeTime = iTime(_Symbol,PERIOD_CURRENT,0);
         if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("DEAL_ENTRY_OUT Position closed: Deal #", trans.deal, " | Position #", trans.position, " | Symbol: ", trans.symbol, " | Profit: ", profit, " | CountOpenTradesPerSession: ", CountOpenTradesPerSession);
         if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Alert("DEAL_ENTRY_OUT Position closed: Deal #", trans.deal, " | Position #", trans.position, " | Symbol: ", trans.symbol, " | Profit: ", profit, " | CountOpenTradesPerSession: ", CountOpenTradesPerSession);
         if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PlaySound("alert.wav");  // 🔊 Play sound when trade is closed
      } else if (entry_type == DEAL_ENTRY_IN && (!MQL5InfoInteger(MQL5_OPTIMIZATION)) ) { // trade opened

         DeleteDrawSLTP(_Symbol, trans.position);
         if (CountOpenTradesPerSession>=MaxOpenTradesPerSession)
            CountOpenTradesPerSession--;
         else
            CountOpenTradesPerSession++;

         lastTradeTime = iTime(_Symbol,PERIOD_CURRENT,0);
         if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("DEAL_ENTRY_IN Position opened: Deal #", trans.deal, " | Symbol: ", trans.symbol, " | Volume: ", trans.volume, " | CountOpenTradesPerSession: ", CountOpenTradesPerSession);
         if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Alert("DEAL_ENTRY_IN Position opened: Deal #", trans.deal, " | Symbol: ", trans.symbol, " | Volume: ", trans.volume, " | CountOpenTradesPerSession: ", CountOpenTradesPerSession);
         if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PlaySound("ok.wav");
      } else if (entry_type == DEAL_ENTRY_OUT_BY) { // Close a position by an opposite one
         DeleteDrawSLTP(_Symbol, trans.position);
         CountOpenTradesPerSession--;
         lastTradeTime = iTime(_Symbol,PERIOD_CURRENT,0);
         if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("DEAL_ENTRY_OUT_BY Position opened: Deal #", trans.deal, " | Symbol: ", trans.symbol, " | Volume: ", trans.volume, " | CountOpenTradesPerSession: ", CountOpenTradesPerSession);
         if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Alert("DEAL_ENTRY_OUT_BY Position opened: Deal #", trans.deal, " | Symbol: ", trans.symbol, " | Volume: ", trans.volume, " | CountOpenTradesPerSession: ", CountOpenTradesPerSession);
         if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PlaySound("ok.wav");
      } else if (entry_type == DEAL_ENTRY_INOUT) {
         DeleteDrawSLTP(_Symbol, trans.position);
         CountOpenTradesPerSession--;
         if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("🔁 DEAL_ENTRY_INOUT Position closed by another: Deal #", trans.deal, " | Symbol: ", trans.symbol, " | CountOpenTradesPerSession: ", CountOpenTradesPerSession);
         if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Alert("🔁 DEAL_ENTRY_INOUT Position closed by another: Deal #", trans.deal, " | Symbol: ", trans.symbol, " | CountOpenTradesPerSession: ", CountOpenTradesPerSession);
         if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PlaySound("closeby.wav");
      } else {
         if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("🔁 The deal type is entry_type=", entry_type, " | CountOpenTradesPerSession: ", CountOpenTradesPerSession);
         if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Alert("🔁 The deal type is entry_type=", entry_type, " | CountOpenTradesPerSession: ", CountOpenTradesPerSession);
      }
   }

// Handle other types of trade transactions
   if (trans.type == TRADE_TRANSACTION_ORDER_DELETE) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Order Deleted: ", trans.order);
   }

// Optional: handle SL/TP modifications, etc.
   if (trans.type == TRADE_TRANSACTION_ORDER_UPDATE) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Order Updated: ", trans.order);
   }
}


//+------------------------------------------------------------------+
//| Function to detect MA convergence or divergence                  |
//| Returns 1 for divergence, -1 for convergence, 0 for neutral     |
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int DetectMAConvergence() {

   if( ArraySize(fastBuffer)>InpFastPeriod && ArraySize(slowBuffer)>InpSlowPeriod  ) {
      double ma1_current = fastBuffer[0];
      double ma2_current = slowBuffer[0];
      double ma1_prev    = fastBuffer[1];
      double ma2_prev    = slowBuffer[1];

      double diff_current = ma1_current - ma2_current;
      double diff_prev    = ma1_prev    - ma2_prev;

      if(MathAbs(diff_current) > MathAbs(diff_prev)) {
         if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print(__FUNCTION__ +"-"+IntegerToString(__LINE__) + " - ⚠ ️Diverging !");
         if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) createObject(iTime(_Symbol, PERIOD_CURRENT, 0), fastBuffer[0], 302,1, clrMagenta, "⚠Div");
         return 1;  // Diverging
      } else if(MathAbs(diff_current) < MathAbs(diff_prev)) {
         if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print(__FUNCTION__ +"-"+IntegerToString(__LINE__) + " - ⚠ ️Converging !");
         if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) createObject(iTime(_Symbol, PERIOD_CURRENT, 0), fastBuffer[0], 301,1, clrRosyBrown, "⚠Con");
         if (IgnoreDetectMAConvergence) {
            if (MathAbs(fastBuffer[0]-slowBuffer[0]) > IgnoreDetectMAConvergenceTollerrance) {
               return 1;
            }
         }
         return -1; // Converging
      }
   }
   if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print(__FUNCTION__ +"-"+IntegerToString(__LINE__) + " - ⚠ ️Neutral !");
   return 0; // Neutral
}


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool PredictMACross() {
   int bars = iBars(_Symbol, PERIOD_CURRENT);
   if(barsForFutureLineCross != bars) {
      barsForFutureLineCross = bars;

      // Calculate Slope for Both MAs using last two known values
      double fastSlope = fastBuffer[0] - fastBuffer[1];
      double slowSlope = slowBuffer[0] - slowBuffer[1];

      // Predict future values and check if they cross
      for(int i = 1; i <= CrossoverPredictionCandles; i++) {
         double fastFuture = fastBuffer[0] + fastSlope * i;
         double slowFuture = slowBuffer[0] + slowSlope * i;

         // Check for a potential cross
         if((fastBuffer[0] > slowBuffer[0] && fastFuture < slowFuture)) {
            if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print(__FUNCTION__ +"-"+IntegerToString(__LINE__) + " - ⚠️ Possible MA Cross in " + IntegerToString(i)+" candles!");
            if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) createObject(iTime(_Symbol, PERIOD_CURRENT, 0), fastBuffer[0], 300,0, clrTeal, IntegerToString(i)+"+Cross");
            return true;
         } else if((fastBuffer[0] < slowBuffer[0] && fastFuture > slowFuture)) {
            if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print(__FUNCTION__ +"-"+IntegerToString(__LINE__) + " - ⚠️ Possible MA Cross in " + IntegerToString(i)+" candles!");
            if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) createObject(iTime(_Symbol, PERIOD_CURRENT, 0), fastBuffer[0], 300,0, clrOrange, IntegerToString(i)+"-Cross");
            return true;
         }
      }
   }
   return false;
}


//+------------------------------------------------------------------+
//| Close all buy open trades - Trend Finished                       |
//+------------------------------------------------------------------+
bool closeAllBuyOpenTrades_TrendFinished(const bool skipChecks = false) {
   if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " We need to close buy trades");
   bool result = false;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong positionTicket = PositionGetTicket(i);
      if(PositionSelectByTicket(positionTicket)) {

         long magic = (long)HistoryDealGetInteger(positionTicket, DEAL_MAGIC);
         if (InpMagicNumber ==magic) {
            if((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)) {
               if(skipChecks || ((AreWeInABearRun() && (slowBuffer[1]>fastBuffer[1]) && (StrCompare(marketPatternSpeed,"Fast Downtrend") || StrCompare(marketPatternSpeed,"Slow Downtrend"))))) {
                  if(skipChecks || ((DetectMAConvergence()!=-1) && (!PredictMACross()))) {

                     bool moreGoodThanBad = areGoodTradesBiggerThanBadTradesInThePastNCandlesticks(positionTicket, GoodBadTradesInThePastNCandlesticks);
                     //if((trade.RequestMagic()==InpMagicNumber) && !moreGoodThanBad && trade.PositionClose(positionTicket)) {
                     if((trade.RequestMagic()==InpMagicNumber) && trade.PositionClose(positionTicket)) {
                        --CountOpenTradesPerSession;
                        result = true;
                        if(!MQL5InfoInteger(MQL5_OPTIMIZATION))  PrintPositionStats(positionTicket);
                        if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " > BUY position Pos #%d was automatically closed by the EA. The Trend Finished.", positionTicket);
                        if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) notification.SendEmailNotification("EA->Closed a BUY trade", __FUNCTION__ + "-" + IntegerToString(__LINE__) + " > BUY position Pos #"+IntegerToString(positionTicket)+" was automatically closed by the EA. The Trend Finished.");
                     } else if(CheckManualTradeViaComment(positionTicket) && trade.PositionClose(positionTicket)) {
                        if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " > BUY position Pos #%d was manually closed by the trader(Human).", positionTicket);
                        if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) notification.SendEmailNotification("Trader->Closed a BUY trade",__FUNCTION__ + "-" + IntegerToString(__LINE__) + " > BUY position Pos "+IntegerToString(positionTicket)+" was manually closed by the trader(Human).");
                     }
                  }
               }
            }
         }
      }
   }
   return result;
}


//+------------------------------------------------------------------+
//| Close all open trades                                            |
//+------------------------------------------------------------------+
void closeAllOpenTrades() {
   if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " We need to close open trades");
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong positionTicket = PositionGetTicket(i);
      if(PositionSelectByTicket(positionTicket)) {
         long magic = (long)HistoryDealGetInteger(positionTicket, DEAL_MAGIC);
         if (InpMagicNumber ==magic) {
            trade.PositionClose(positionTicket);
            if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) notification.SendEmailNotification("Trader closing position ticket #"+IntegerToString(positionTicket),"Position closed.");
         }
      }
   }
   if( PositionsTotal() > 0 && (!MQL5InfoInteger(MQL5_OPTIMIZATION))  ) {
      notification.SendEmailNotification("Trader->CloseAllOpenTrades", "User(Trader) closed all open trades.");
   }
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CheckManualTradeViaComment(ulong positionTicket) {
   if(PositionSelectByTicket(positionTicket)) {
      string comment = PositionGetString(POSITION_COMMENT);

      long magic = (long)HistoryDealGetInteger(positionTicket, DEAL_MAGIC);
      if (InpMagicNumber == magic) {
         if(StringFind(comment, "Manual") == 0) {
            if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("This trade comment starts with 'Manual': ", comment);
            return true;
         } else {
            if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Trade comment does NOT start with 'Manual': ", comment);
            return false;
         }
      }
   }
   return false;
}


//+------------------------------------------------------------------+
//| Close all sell open trades - Trend Finished                      |
//+------------------------------------------------------------------+
bool closeAllSellOpenTrades_TrendFinished(const bool skipChecks = false) {
   if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " We need to close sell trades");
   bool result=false;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong positionTicket = PositionGetTicket(i);
      if(PositionSelectByTicket(positionTicket)) {

         long magic = (long)HistoryDealGetInteger(positionTicket, DEAL_MAGIC);
         if (InpMagicNumber ==magic) {
            if((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)) {
               if((skipChecks) || ((AreWeInABullRun() && (fastBuffer[1]>slowBuffer[1]) && (StrCompare(marketPatternSpeed,"Slow Uptrend") || StrCompare(marketPatternSpeed,"Fast Uptrend"))))) {
                  if((skipChecks) || ((DetectMAConvergence()!=-1) && (!PredictMACross()))) {
                     bool moreGoodThanBad = areGoodTradesBiggerThanBadTradesInThePastNCandlesticks(positionTicket, GoodBadTradesInThePastNCandlesticks);
                     //if((trade.RequestMagic()==InpMagicNumber) && !moreGoodThanBad && trade.PositionClose(positionTicket)) {
                     if((trade.RequestMagic()==InpMagicNumber) && trade.PositionClose(positionTicket)) {
                        --CountOpenTradesPerSession;
                        result = true;
                        PrintPositionStats(positionTicket);
                        if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " > SELL position Pos #%d was manually closed by the EA. The Trend Finished",positionTicket);
                        if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) notification.SendEmailNotification("closeAllSellOpenTrades_TrendFinished",__FUNCTION__ + "-" + IntegerToString(__LINE__) + " > SELL position Pos #"+IntegerToString(positionTicket)+" was manually closed by the EA. The Trend Finished");
                     }
                  }
               }
            }
         }
      }
   }
   return result;
}


//+------------------------------------------------------------------+
//|Did the lines cross                                               |
//+------------------------------------------------------------------+
int DidTheLinesCross() {
   if(fastBuffer[1] < slowBuffer[1] && ((fastBuffer[0]) > slowBuffer[0])) {        //Check for a cross - buy.
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" This means we need to buy.");
      return 1;
   } else if(fastBuffer[1] > slowBuffer[1] && ((fastBuffer[0]) < slowBuffer[0])) { //Check for a cross - sell.
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" This means we need to sell.");
      return -1;
   } else {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" We cant buy nor sell, this means we should consider adjusting TP and SL using this permutation.");
      return 0;
   }
}

//+------------------------------------------------------------------+
//| Enter if they are far apart                                      |
//+------------------------------------------------------------------+
bool EnterIfTheyAreFarApart(const double tolerrance = 0.00003, string enter ="Enter", color colour = clrLimeGreen, int buyOrsell=0 ) {
   if(MathAbs(fastBuffer[1] - slowBuffer[1]) > (tolerrance)) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"We can enter, the lines are far apart. The tolerrance is %.5f the actual difference is %.5f",tolerrance,MathAbs(fastBuffer[1] - slowBuffer[1]) );
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) createObject(iTime(_Symbol, PERIOD_CURRENT, 0), fastBuffer[0], 213,buyOrsell, colour, enter);
      return true;
   }
   if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"We can not enter, the lines are not far apart. The tolerrance is %.5f , the actual difference is %.5f ",tolerrance,MathAbs(fastBuffer[1] - slowBuffer[1]));
   return false;
}

//+------------------------------------------------------------------+
//| Are we in a bull run?                                            |
//+------------------------------------------------------------------+
bool AreWeInABullRun(bool ignoreBullRun = false) {
   int fBufferSize = ArraySize(fastBuffer);
   int counts = 0;

   for(int i =0 ; i<BullBearRunCandleDepth; i++) {
      if(fBufferSize >=(3+i) && fastBuffer[(1+i)] > fastBuffer[(2+i)])
         counts++;
   }

   if(ignoreBullRun) {
      return true;
   }

   if((counts>= (BullRunCandleCount)) && (fastBuffer[1] > slowBuffer[1]) && (fastBuffer[2] > slowBuffer[2])) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"We are in a Bull run. fBufferSize(%d) and the count is counts(%d)", fBufferSize, counts);
      return true;
   } else {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"We are not in a Bull run. fBufferSize(%d) and the count is counts(%d)", fBufferSize, counts);
      return false;
   }
}

//+------------------------------------------------------------------+
//| Should we enter a bull run.                                      |
//+------------------------------------------------------------------+
bool ShouldWeEnterABullRun(double fsDistanceTollerance = 0.0 ) {
   if((fastBuffer[0] > slowBuffer[0]) && (MathAbs(fastBuffer[0] - slowBuffer[0]) > fsDistanceTollerance)) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"Enter the bull cross over. The distance between the FAST[0](%.5f) v.s SLOW[0](%.5f) buffer is %.5f",fastBuffer[0], slowBuffer[0], (fastBuffer[0] - slowBuffer[0]));
      return true;
   } else {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"Dont enter the bull cross over. The distance between the FAST[0](%.5f) v.s SLOW[0](%.5f) buffer is %.5f",fastBuffer[0], slowBuffer[0], (fastBuffer[0] - slowBuffer[0]));
      return false;
   }
}

//+------------------------------------------------------------------+
//| Are we in a bear run?                                            |
//+------------------------------------------------------------------+
bool AreWeInABearRun(bool ignoreBearRun = false) {

   int fBufferSize = ArraySize(fastBuffer);
   int counts = 0;

   for(int i =0 ; i<BullBearRunCandleDepth; i++) {
      if(fBufferSize >=(3+i) && fastBuffer[(1+i)] > fastBuffer[(2+i)])
         counts++;
   }

   if(ignoreBearRun) {
      return true;
   }

   if(counts>=BearRunCandleCount && (fastBuffer[1] < slowBuffer[1]) && (fastBuffer[2] < slowBuffer[2])) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" We are in a Bear run. fBufferSize(%d) the count is counts(%d) and MarketPatternSpeed(%s)",fBufferSize,counts, marketPatternSpeed);
      return true;
   } else {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" We are not in a Bear run. fBufferSize(%d), the count is counts(%d) and MarketPatternSpeed(%s)", fBufferSize,counts, marketPatternSpeed);
      return false;
   }
}


//+------------------------------------------------------------------+
//| Should we enter a bear run.                                      |
//+------------------------------------------------------------------+
bool ShouldWeEnterABearRun(double fsDistanceTollerance) {
   if((fastBuffer[0] < slowBuffer[0]) && (MathAbs(fastBuffer[0] - slowBuffer[0]) > fsDistanceTollerance)) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" Yes, we should enter the bear run. The distance between the FAST v.s SLOW buffer is %.5f and the MarketPatternSpeed = %s",(fastBuffer[1] - slowBuffer[1]), marketPatternSpeed);
      return true;
   } else {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" No, we should not enter the bear run.. The distance between the FAST v.s SLOW buffer is %.5f and the MarketPatternSpeed = %s",(fastBuffer[1] - slowBuffer[1]), marketPatternSpeed);
      return false;
   }
}

//+------------------------------------------------------------------+
//|  MA Crossover DeInit                                             |
//+------------------------------------------------------------------+
void MACrossoverDeInit() {
   if(fastHandle != INVALID_HANDLE)
      IndicatorRelease(fastHandle);
   if(slowHandle != INVALID_HANDLE)
      IndicatorRelease(slowHandle);
}



//+------------------------------------------------------------------+
//|  MA Crossover Init                                               |
//+------------------------------------------------------------------+
int MACrossoverInit() {
// Check user input.
   if(InpFastPeriod<=0) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"(InpFastPeriod<=0) InpFastPeriod= ", InpFastPeriod);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpSlowPeriod<=0) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"(InpSlowPeriod<=0) InpSlowPeriod= ", InpSlowPeriod);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpFastPeriod >= InpSlowPeriod) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"(InpFastPeriod >= InpSlowPeriod) InpFastPeriod= ", InpFastPeriod," InpSlowPeriod=", InpSlowPeriod);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpStopLossUSD <=0) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION))  PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"Stop loss is equal ", InpStopLossUSD);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpTakeProfitUSD <=0) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"Take Profit is equal ", InpTakeProfitUSD);
      return INIT_PARAMETERS_INCORRECT;
   }

// Create handles.
   fastHandle = iMA(_Symbol,PERIOD_CURRENT,InpFastPeriod,0,MODE_SMA,PRICE_CLOSE);
   if(fastHandle == INVALID_HANDLE) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"Failed to create fast handle.");
      return INIT_FAILED;
   }
   slowHandle = iMA(_Symbol,PERIOD_CURRENT,InpSlowPeriod,0,MODE_SMA,PRICE_CLOSE);
   if(slowHandle == INVALID_HANDLE) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"Failed to create slow handle.");
      return INIT_FAILED;
   }

   int countF = CopyBuffer(fastHandle,0,0,InpFastPeriod,fastBuffer);
   int countS = CopyBuffer(slowHandle,0,0,InpSlowPeriod,slowBuffer);
   if(countF != InpFastPeriod) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" Not enough data for fast moving average");
   }
   if(countS != InpSlowPeriod) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" Not enough data for fast moving average");
   }

   if( (countF != InpFastPeriod) && (countS != InpSlowPeriod) ) {
      ArraySetAsSeries(fastBuffer,true);
      ArraySetAsSeries(slowBuffer,true);
      EAInitialised = INIT_SUCCEEDED;
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void UpdateMACrossoverBuffers() {
// Create handles.
   fastHandle = iMA(_Symbol,PERIOD_CURRENT,InpFastPeriod,0,MODE_SMA,PRICE_CLOSE);
   if(fastHandle == INVALID_HANDLE) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"Failed to update fast handle.");
   }
   slowHandle = iMA(_Symbol,PERIOD_CURRENT,InpSlowPeriod,0,MODE_SMA,PRICE_CLOSE);
   if(slowHandle == INVALID_HANDLE) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"Failed to update slow handle.");
   }
   int count = CopyBuffer(fastHandle,0,0,InpFastPeriod,fastBuffer);
   if(count != InpFastPeriod) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" Not enough data for fast moving average");
   }
   count = CopyBuffer(slowHandle,0,0,InpSlowPeriod,slowBuffer);
   if(count != InpSlowPeriod) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" Not enough data for fast moving average");
   }

   ArraySetAsSeries(fastBuffer,true);
   ArraySetAsSeries(slowBuffer,true);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string GetEURUSDMarketSession() {
   datetime now = TimeGMT();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   int totalMinutes = dt.hour * 60 + dt.min;

// Define sessions
   struct SessionInfo {
      string name;
      int startMinUTC;
      int endMinUTC;
   };

   SessionInfo sessions[] = {
      {"Sydney Session",         1320, 1440},  // 22:00 – 00:00 next day
      {"Sydney Session",            0, 420},   // 00:00 – 07:00
      {"Tokyo Session",             0, 540},   // 00:00 – 09:00
      {"Frankfurt Session",       360, 840},   // 06:00 – 14:00
      {"London Session",          420, 960},   // 07:00 – 16:00
      {"New York Session",        720, 1260},  // 12:00 – 21:00
      {"Tokyo + Frankfurt Overlap", 360, 540}, // 06:00 – 09:00
      {"Frankfurt + London Overlap", 420, 840},// 07:00 – 14:00
      {"London + New York Overlap", 720, 960}  // 12:00 – 16:00
   };

   for (int i = 0; i < ArraySize(sessions); i++) {
      int start = sessions[i].startMinUTC;
      int end   = sessions[i].endMinUTC;

      bool inSession = false;

      // Handle wrap-around sessions like Sydney 22:00 – 07:00
      if (start > end)
         inSession = (totalMinutes >= start || totalMinutes < end);
      else
         inSession = (totalMinutes >= start && totalMinutes < end);

      if (inSession) {
         // Format time in UTC
         string startUTC = TimeToString(start * 60, TIME_SECONDS);
         string endUTC   = TimeToString(end * 60, TIME_SECONDS);

         // Adjust to UTC+2
         string startUTC2 = TimeToString((start + 120) % 1440 * 60, TIME_SECONDS);
         string endUTC2   = TimeToString((end + 120) % 1440 * 60, TIME_SECONDS);

         return startUTC + " UTC " + sessions[i].name + " " + endUTC2 + " UTC+2";
      }
   }

   return "Session not active";
}


//+------------------------------------------------------------------+
//| Function to print stats of a specific position in MetaTrader 5  |
//+------------------------------------------------------------------+
void PrintPositionStats(ulong position_ticket) {
// Retrieve position details
   if(!MQL5InfoInteger(MQL5_OPTIMIZATION) && PositionSelectByTicket(position_ticket) ) {
      ulong ticket = position_ticket;
      string symbol = PositionGetString(POSITION_SYMBOL);
      long type = PositionGetInteger(POSITION_TYPE);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double price_open = PositionGetDouble(POSITION_PRICE_OPEN);
      double price_current = PositionGetDouble(POSITION_PRICE_CURRENT);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double profit = PositionGetDouble(POSITION_PROFIT);
      double swap = PositionGetDouble(POSITION_SWAP);
      double commission = PositionGetDouble(POSITION_COMMISSION);
      long magic = PositionGetInteger(POSITION_MAGIC);

      // Print position details
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) {
         Print("Position Ticket: ", ticket);
         Print("Symbol:          ", symbol);
         Print("Type:            ", (type == POSITION_TYPE_BUY) ? "Buy" : "Sell");
         Print("Volume:          ", volume);
         Print("Open Price:      ", price_open);
         Print("Current Price:   ", price_current);
         Print("Stop Loss:       ", sl);
         Print("Take Profit:     ", tp);
         Print("Profit:          ", profit);
         Print("Swap:            ", swap);
         Print("Commission:      ", commission);
         Print("Magic Number:    ", magic);
      }
   } else {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"- Error: Position with ticket " + IntegerToString(position_ticket) + " not found.");
   }
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Function to check trade result                                   |
//+------------------------------------------------------------------+
void CheckTradeResult(const MqlTradeResult &result) {
   if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat("Trade result code: %d", result.retcode);
   if(result.retcode == TRADE_RETCODE_DONE) {  // Trade executed successfully
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"-","Trade executed successfully.");
      if(result.deal > 0) {
         if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"-","Deal ticket: %d", result.deal);
      } else {
         if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"-","Warning: No valid deal ticket returned!");
      }
   } else {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"-","Trade execution failed. Error code: %d", result.retcode);
   }
}


//+------------------------------------------------------------------+
//| Function to detect the speed of price movement                   |
//+------------------------------------------------------------------+
string DetectTrendSpeed(int period = 3) {
   double priceArray[];

// Get closing prices for the given period
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, period, priceArray) < period) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"-","Error: Not enough data available.");
      return "Error";
   }

// Calculate the linear regression slope
   double sumX = 0, sumY = 0, sumXY = 0, sumXX = 0;
   for(int i = 0; i < period; i++) {
      sumX += i;
      sumY += priceArray[i];
      sumXY += i * priceArray[i];
      sumXX += i * i;
   }

// Compute slope (rate of price change)
   double slope = (period * sumXY - sumX * sumY) / (period * sumXX - sumX * sumX);

// Classify speed and direction
   if(slope > fastThreshold) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat("***********"+__FUNCTION__ + "-" + IntegerToString(__LINE__) +"-" + "slope(%0.7f) - Fast Uptrend - fastThreshold(%0.7f)", slope, fastThreshold);
      return "Fast Uptrend";
   } else if(slope > slowThreshold) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat("***********"+__FUNCTION__ + "-" + IntegerToString(__LINE__) +"-" + "slope(%0.7f) - Slow Uptrend - fastThreshold(%0.7f)", slope, slowThreshold);
      return "Slow Uptrend️";
   } else if(slope < -fastThreshold) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat("***********"+__FUNCTION__ + "-" + IntegerToString(__LINE__) +"-" + "slope(%0.7f) - Fast Downtrend - -fastThreshold(%0.7f)", slope, -fastThreshold);
      return "Fast Downtrend";
   } else if(slope < -slowThreshold) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat("***********"+__FUNCTION__ + "-" + IntegerToString(__LINE__) +"-" + "slope(%0.7f) - Slow Downtrend - -slowThreshold(%0.7f)", slope, -slowThreshold);
      return "Slow Downtrend️";
   } else {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat("***********"+__FUNCTION__ + "-" + IntegerToString(__LINE__) +"-" + "slope(%0.7f) - Sideways Market ➡ - slowThreshold(%0.7f) - fastThreshold(%0.7f)", slope, slowThreshold, fastThreshold);
      return "Sideways Market️";
   }
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void createObject(datetime time, double price, int arrowCode,int direction, color clr, string txt) {

   if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) {
      int bars = iBars(_Symbol, PERIOD_CURRENT);
      if(barsCreateObject != bars) {
         barsCreateObject = bars;
         string objName = "";
         StringConcatenate(objName,"Signal@",time,"at",DoubleToString(price,_Digits),"(", arrowCode,")");
         if(ObjectCreate(0,objName,OBJ_ARROW,0,time,price)) {
            ObjectSetInteger(0,objName,OBJPROP_ARROWCODE,arrowCode);
            ObjectSetInteger(0,objName,OBJPROP_COLOR,clr);
            ObjectSetInteger(0,objName, OBJPROP_FONTSIZE, 6);  // Set font size
            if(direction > 0)
               ObjectSetInteger(0,objName, OBJPROP_ANCHOR, ANCHOR_TOP);
            if(direction < 0)
               ObjectSetInteger(0,objName, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
         }
         string objNameDesc = objName+txt;
         if(ObjectCreate(0,objNameDesc,OBJ_TEXT,0,time,price)) {
            ObjectSetString(0,objNameDesc,OBJPROP_TEXT," "+txt);
            ObjectSetInteger(0,objNameDesc,OBJPROP_COLOR,clr);
            ObjectSetInteger(0,objNameDesc, OBJPROP_FONTSIZE, 8);  // Set font size
         }
      }
   }
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool StrCompare(string a, string b) {
   return StringCompare(a,b) == 0 ? true : false;
}


//+------------------------------------------------------------------+
//| Creates an arrow and text object on the chart                   |
//| Params:                                                         |
//|   time      - signal time                                       |
//|   price     - price level of the signal                         |
//|   arrowCode - arrow character code (Wingdings)                  |
//|   direction - >0 anchor top, <0 anchor bottom                   |
//|   clr       - color of arrow and text                           |
//|   txt       - description text                                  |
//+------------------------------------------------------------------+
void createObject_(datetime time, double price, int arrowCode, int direction, color clr, string txt) {
   int currentBars = iBars(_Symbol, PERIOD_CURRENT);

   if (barsCreateObject == currentBars)
      return;

   barsCreateObject = currentBars;

// Create a unique object name using timestamp, price, and arrow code
   string objName = StringFormat("Signal@%s_at%.%df_(%d)", TimeToString(time, TIME_MINUTES), _Digits, price, arrowCode);

// Create the arrow object
   if (ObjectCreate(0, objName, OBJ_ARROW, 0, time, price)) {
      ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, arrowCode);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);

      if (direction > 0)
         ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_TOP);
      else if (direction < 0)
         ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
   }

// Create the accompanying text object
   string textName = objName + "_label";
   if (ObjectCreate(0, textName, OBJ_TEXT, 0, time, price)) {
      ObjectSetString(0, textName, OBJPROP_TEXT, " " + txt);
      ObjectSetInteger(0, textName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, textName, OBJPROP_FONTSIZE, 10);
   }
}

//+------------------------------------------------------------------+
//| Chart Event Handler                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   if(id == CHARTEVENT_OBJECT_CLICK) {

      if(sparam == "btnBuy") {
         Print(__FUNCTION__+"-"+IntegerToString(__LINE__)+ " > BUTTON btnBuy was clicked.");
         //MACrossoverBuy(clrGreenYellow, "Manual Buy", "Manual Buy");
      } else if(sparam == "btnSell") {
         Print(__FUNCTION__+"-"+IntegerToString(__LINE__)+ " > BUTTON btnSell was clicked.");
         //MACrossoverSell(clrRed, "Manual Sell", "Manual Sell");
      } else if(sparam == "btnCloseMBuy") {
         Print(__FUNCTION__+"-"+IntegerToString(__LINE__)+ " > BUTTON btnCloseMBuy was clicked.");
         //closeAllBuyOpenTrades_TrendFinished(true);
      } else if(sparam == "btnCloseMSell") {
         Print(__FUNCTION__+"-"+IntegerToString(__LINE__)+ " > BUTTON btnCloseMSell was clicked.");
         //closeAllSellOpenTrades_TrendFinished(true);
      } else if(sparam == "btnCloseAMAll") {
         Print(__FUNCTION__+"-"+IntegerToString(__LINE__)+ " > BUTTON btnCloseAMAll was clicked.");
         //closeAllOpenTrades();
      } else if(sparam == "btnAdjustSLTPUP") {
         Print(__FUNCTION__+"-"+IntegerToString(__LINE__)+ " > BUTTON btnAdjustSLTPUP was clicked.");
         //maximiseProfits();
      } else if(sparam == "btnAdjustSLTPDown") {
         Print(__FUNCTION__+"-"+IntegerToString(__LINE__)+ " > BUTTON btnAdjustSLTPDown was clicked.");
         //minimiseLosses();
      } else if(sparam == "btnRefreshNews") {

      } else if (sparam == "OverlayToggleBtn") {
         Alert("Zatara");
         Print("Zatara");
         showOverlay = !showOverlay;
         ObjectSetString(0, "OverlayToggleBtn", OBJPROP_TEXT, showOverlay ? "Overlay: ON" : "Overlay: OFF");
         DrawOverlay();
      }
   }
}

//+------------------------------------------------------------------+
//| Draws a moving average line on the chart                        |
//| Parameters:                                                     |
//|   maHandle     - handle of the MA indicator                     |
//|   objectName   - name of the object to draw                     |
//|   lineColor    - color of the line                              |
//|   barsToDraw   - how many bars of MA to draw                    |
//+------------------------------------------------------------------+
void DrawMA_Segments(int maHandle, string prefix, color lineColor, int barsToDraw) {

   if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) {
      if (maHandle == INVALID_HANDLE) {
         if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Invalid MA handle");
         return;
      }

      double maBuffer[];
      datetime timeBuffer[];

      if (CopyBuffer(maHandle, 0, 0, barsToDraw + 1, maBuffer) <= 0 ||
            CopyTime(_Symbol, _Period, 0, barsToDraw + 1, timeBuffer) <= 0) {
         if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Failed to copy MA or time data");
         return;
      }

// Delete old segments
      for (int i = 0; i < barsToDraw; i++)
         ObjectDelete(0, prefix + IntegerToString(i));

// Draw lines between points
      for (int i = 0; i < barsToDraw; i++) {
         string objName = prefix + IntegerToString(i);
         if (!ObjectCreate(0, objName, OBJ_TREND, 0, timeBuffer[i], maBuffer[i], timeBuffer[i+1], maBuffer[i+1])) {
            if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Failed to create object: ", objName);
            continue;
         }

         ObjectSetInteger(0, objName, OBJPROP_COLOR, lineColor);
         ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
      }

   }

}
//+------------------------------------------------------------------+



// Returns a list of EA trades
int GetEATrades( ulong magic_number) {

   int total = PositionsTotal();
   int count = 0;

   for (int i = 0; i < total; i++) {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket)) {
         if ((ulong)PositionGetInteger(POSITION_MAGIC) == magic_number) {
            count++;
         }
      }
   }
   return count;
}


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool AreBothTimeseriesSameDirection(ENUM_TIMEFRAMES tf1, ENUM_TIMEFRAMES tf2, int index, string &marketMovement) {
   string symbol = _Symbol;

   double open1[], close1[];
   double open2[], close2[];


// Copy one candle's data at the specified index
   if (CopyOpen(symbol, tf1, 0, index+1, open1) <= 0 || CopyClose(symbol, tf1, 0, index+1, close1) <= 0)
      return false;

   if (CopyOpen(symbol, tf2, 0, index+1, open2) <= 0 || CopyClose(symbol, tf2, 0, index+1, close2) <= 0)
      return false;

   int c1 = ArraySize(close1);
   int o1 = ArraySize(open1);
   int c2 = ArraySize(close1);
   int o2 = ArraySize(open1);

   bool tf1Bullish=false, tf1Bearish=false, tf2Bullish=false, tf2Bearish=false;
   if( (c1>0) && (o1>0) && (c2>0) && (o2>0) ) {
      // Check direction
      tf1Bullish = (close1[index] > open1[index]);
      tf1Bearish = (close1[index] < open1[index]);
      tf2Bullish = (close2[index] > open2[index]);
      tf2Bearish = (close2[index] < open2[index]);
   }

   if ( (tf1Bullish && tf2Bullish) ) marketMovement = "Bullish";
   if ( (tf1Bearish && tf2Bearish) ) marketMovement = "Bearish";

   if ((tf1Bullish && tf2Bullish) || (tf1Bearish && tf2Bearish))
      return true;

   return false;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DrawOverlay() {
   if (!showOverlay) {
      ObjectDelete(0, "OverlayBackground");
      ObjectDelete(0, "AccountOverlay");
      ChartRedraw();
      return;
   }

// Account info
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double free      = AccountInfoDouble(ACCOUNT_FREEMARGIN);
   double marginPerLot = 0.0;

   if (!SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL, marginPerLot))
      marginPerLot = 0.0;

   double drawdownPct = (balance > 0) ? 100.0 * (balance - equity) / balance : 0.0;
   double maxLot = (marginPerLot > 0) ? free / marginPerLot : 0.0;

// Spread
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = (ask - bid) / _Point;

// Open trades
   double totalOpenProfit = 0;
   int openTrades = PositionsTotal();
   for (int i = 0; i < openTrades; i++) {
      if (PositionGetTicket(i))
         totalOpenProfit += PositionGetDouble(POSITION_PROFIT);
   }

// Closed trade stats
   int winCount = 0, lossCount = 0;
   GetClosedTradeStats(winCount, lossCount);

// Daily profit
   double dailyProfit = GetTodayProfit();

// Symbol trend and session
   string trend = GetSymbolTrend(_Symbol, PERIOD_CURRENT);


   string trend1 = GetSymbolTrend(_Symbol, PERIOD_M1);
   string trend5 = GetSymbolTrend(_Symbol, PERIOD_M5);
   string trend10 = GetSymbolTrend(_Symbol, PERIOD_M10);
   string trend15 = GetSymbolTrend(_Symbol, PERIOD_M15);


   string session = GetEURUSDMarketSession();



   string marketDirection = "Neutral";
   int barsEntry = iBars(_Symbol, PERIOD_CURRENT);
   if(barsEntry<20) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("MA buffer not ready yet. (InpSlowPeriod)=",InpSlowPeriod);

   } else {
      int direction = DetectMAConvergence();
      if( direction == 1) {
         marketDirection = "⚠Div";
      } else if( direction == -1 ) {
         marketDirection = "⚠Con";
      }
   }

// Build text
   string text = StringFormat(
                    "💼 ACCOUNT INFO\n\r" +
                    "Balance:        %.2f\n"+
                    "Equity:         %.2f\n"+
                    "Free Margin:    %.2f\n"+
                    "Drawdown:       %.2f\n"+
                    "Max Lot Size:   %.2f\n"+
                    "📈 Open Trades: %d\n"+
                    "💹 Floating PnL:%.2f\n"+
                    "📊 Spread:      %.1f points\n"+
                    "🗓️ Daily Profit %.2f\n"+
                    "📊 Trend (M1 ): %s SD0=%s SD1=%s\n"+
                    "📊 Trend (M5 ): %s \n"+
                    "📊 Trend (M10): %s\n"+
                    "📊 Trend (M15): %s\n"+
                    "🕐 Session:     %s\n\n"+
                    "✅ Wins:        %d\n"+
                    "❌ Losses:      %d\n"+
                    "📈 Direction:   %s\n",
                    balance, equity, free, drawdownPct, maxLot,
                    openTrades, totalOpenProfit, spread, dailyProfit,
                    trend1,SameDirection0?"true":"false",SameDirection1?"true":"false",trend5,trend10,trend15, session, winCount, lossCount,marketDirection
                 );

// Draw background rectangle (use dark color to simulate transparency)
   ObjectCreate(0, "OverlayBackground", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "OverlayBackground", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "OverlayBackground", OBJPROP_XDISTANCE, 5);
   ObjectSetInteger(0, "OverlayBackground", OBJPROP_YDISTANCE, 5);
   ObjectSetInteger(0, "OverlayBackground", OBJPROP_XSIZE, 390);
   ObjectSetInteger(0, "OverlayBackground", OBJPROP_YSIZE, 360);
   ObjectSetInteger(0, "OverlayBackground", OBJPROP_COLOR, clrYellowGreen);  // simulate transparency
   ObjectSetInteger(0, "OverlayBackground", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, "OverlayBackground", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, "OverlayBackground", OBJPROP_BACK, true);
   ObjectSetInteger(0, "OverlayBackground", OBJPROP_HIDDEN, true);

   /*
      ObjectCreate(0, "AccountOverlay", OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, "AccountOverlay", OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, "AccountOverlay", OBJPROP_YDISTANCE, 10);
      ObjectSetInteger(0, "AccountOverlay", OBJPROP_XSIZE, 10);
      ObjectSetInteger(0, "AccountOverlay", OBJPROP_YSIZE, 10);
      ObjectSetInteger(0, "AccountOverlay", OBJPROP_COLOR, clrBlack);  // simulate transparency
      ObjectSetInteger(0, "AccountOverlay", OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, "AccountOverlay", OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, "AccountOverlay", OBJPROP_BACK, true);
      ObjectSetString(0, "AccountOverlay", OBJPROP_TEXT, text);
   */

// Draw text label
   DisplayMultilineText("AccountOverlay", text, 10, 20,16,clrBlack);
   ChartRedraw();

}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DisplayMultilineText(string baseName, string text, int x = 10, int y = 20, int lineSpacing = 16, color clr = clrBlack) {

// Split the text manually
   string lines[];
   StringSplit(text, '\n', lines);

// Remove old lines if any
   for (int i = 0; i < ArraySize(lines); i++) { // supports up to 20 lines
      string name = baseName + "_line" + IntegerToString(i);
      ObjectDelete(0, name);
   }

   for (int i = 0; i < ArraySize(lines); i++) {
      string objName = baseName + "_line" + IntegerToString(i);
      ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y + i * lineSpacing);
      ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 10);


      ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);


      ObjectSetString(0, objName, OBJPROP_TEXT, lines[i]);
      ObjectSetInteger(0, objName, OBJPROP_BACK, false);
      ObjectSetDouble(0,objName,OBJPROP_ANGLE,0);
      ObjectSetInteger(0,objName,OBJPROP_SELECTABLE,false);
      ChartRedraw();
   }
}


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void GetClosedTradeStats(int &wins, int &losses) {
   wins = 0;
   losses = 0;
   int total = HistoryDealsTotal();

   for (int i = 0; i < total; i++) {
      ulong ticket = HistoryDealGetTicket(i);
      if (HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT) {
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         if (profit > 0)
            wins++;
         else if (profit < 0)
            losses++;
      }
   }
}




//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTimer() {
   if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) {
      DrawOverlay();
      ChartRedraw();
   }
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CreateOverlayToggleButton() {
   ObjectCreate(0, "OverlayToggleBtn", OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, "OverlayToggleBtn", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, "OverlayToggleBtn", OBJPROP_XDISTANCE, 200);
   ObjectSetInteger(0, "OverlayToggleBtn", OBJPROP_YDISTANCE, 10);
   ObjectSetInteger(0, "OverlayToggleBtn", OBJPROP_XSIZE, 100);
   ObjectSetInteger(0, "OverlayToggleBtn", OBJPROP_YSIZE, 20);
   ObjectSetInteger(0, "OverlayToggleBtn", OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, "OverlayToggleBtn", OBJPROP_TEXT, "Overlay: ON");
   ChartRedraw();
}


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetTodayProfit() {
   datetime start_of_day;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   start_of_day = StructToTime(dt);

   double profit = 0;
   int total = HistoryDealsTotal();

   for (int i = 0; i < total; i++) {
      ulong ticket = HistoryDealGetTicket(i);
      if (HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT) {
         datetime closeTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         if (closeTime >= start_of_day)
            profit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
      }
   }
   return profit;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string GetSymbolTrend(string symbol, ENUM_TIMEFRAMES tf) {
   double open[], close[];
   if (CopyOpen(symbol, tf, 1, 1, open) <= 0 || CopyClose(symbol, tf, 1, 1, close) <= 0)
      return "Unknown";

   if (close[0] > open[0]) return "📈 Bullish";
   if (close[0] < open[0]) return "📉 Bearish";
   return "⚖️ Neutral";
}

//+------------------------------------------------------------------+
//| Close Profitable Trade and Reopen in Same Direction              |
//+------------------------------------------------------------------+
void CloseAndReopenProfitableTrades(string symbol) {
   int total = PositionsTotal();

   for (int i = total - 1; i >= 0; i--) {
      if (PositionGetSymbol(i) == symbol) {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentPrice = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
         double profit = PositionGetDouble(POSITION_PROFIT);
         double volume = PositionGetDouble(POSITION_VOLUME);
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

         long magic = (long)HistoryDealGetInteger(ticket, DEAL_MAGIC);
         if (InpMagicNumber ==magic) {
            // Only proceed if trade is profitable by CloseWhenProfitGreaterThan
            if (profit <= CloseWhenProfitGreaterThan ) {
               if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Trade is not profitable. Skipping.");
               continue;
            }

            // Close the current position
            MqlTradeRequest request;
            MqlTradeResult result;
            ZeroMemory(request);
            ZeroMemory(result);

            request.action = TRADE_ACTION_DEAL;
            request.symbol = symbol;
            request.position = ticket;
            request.volume = volume;
            request.deviation = InpRequestDeviationInPoints;
            request.magic = InpMagicNumber;
            request.price = currentPrice;
            request.type = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL ;
            request.type_filling = ORDER_FILLING_IOC;

            if (!OrderSend(request, result) || result.retcode != TRADE_RETCODE_DONE) {
               if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Failed to close position: ", result.retcode);
               return;
            }

            // Immediately open a new trade in the same direction
            ZeroMemory(request);
            ZeroMemory(result);
            CountOpenTradesPerSession--;

            if (CountOpenTradesPerSession < MaxOpenTradesPerSession) {
               request.action = TRADE_ACTION_DEAL;
               request.symbol = symbol;
               request.volume = volume;
               request.deviation = InpRequestDeviationInPoints;
               request.magic = InpMagicNumber;
               request.type = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
               request.price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);
               request.type_filling = ORDER_FILLING_IOC;

               if (!OrderSend(request, result) || result.retcode != TRADE_RETCODE_DONE) {
                  if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Failed to open new trade: ", result.retcode);
               } else {
                  if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Closed profitable trade and reopened in same direction.");
                  CountOpenTradesPerSession++;
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Function to monitor and close less profitable trades             |
//+------------------------------------------------------------------+
void MonitorAndCloseDecliningProfit(double lossThreshold = 5.0) {
   string symbol = Symbol(); // Current chart symbol

   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      if (!PositionGetTicket(i)) continue; // Ensure ticket is valid
      ulong ticket = PositionGetTicket(i);

      if (!PositionSelect(symbol)) continue; // Only handle current symbol

      // Track profit only for current chart symbol
      if (PositionGetInteger(POSITION_TICKET) != ticket) continue;

      long magic = (long)HistoryDealGetInteger(ticket, DEAL_MAGIC);
      if (InpMagicNumber ==magic) {
         double currentProfit = PositionGetDouble(POSITION_PROFIT);
         double volume = PositionGetDouble(POSITION_VOLUME);
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

         // Update maxProfit for this position index
         if (currentProfit > maxProfit[i])
            maxProfit[i] = currentProfit;

         double profitDrop = maxProfit[i] - currentProfit;

         if (maxProfit[i] > 0 && profitDrop >= lossThreshold) {
            double closePrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);

            MqlTradeRequest request;
            MqlTradeResult result;
            ZeroMemory(request);
            ZeroMemory(result);

            request.action = TRADE_ACTION_DEAL;
            request.symbol = symbol;
            request.volume = volume;
            request.type = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.price = closePrice;
            request.deviation = 10;
            request.position = ticket;
            request.type_filling = ORDER_FILLING_IOC;

            if (OrderSend(request, result) && result.retcode == TRADE_RETCODE_DONE) {
               if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Closed trade at index ", i, " on ", symbol, " due to declining profit.");
               maxProfit[i] = 0; // Reset after closing
               CountOpenTradesPerSession--;
            } else {
               if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Failed to close trade at index ", i, ": ", result.retcode);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MonitorAndCloseWorseningLosses(const double lossIncreaseThreshold = 5.0, const string marketMovement="Bullish", const bool areSpreadsGood = false) {
   string symbol = Symbol(); // Current chart symbol

   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      if (!PositionGetTicket(i)) continue;
      ulong ticket = PositionGetTicket(i);

      if (!PositionSelect(symbol)) continue; // Only for current chart symbol

      if (PositionGetInteger(POSITION_TICKET) != ticket) continue;



      double currentProfit = PositionGetDouble(POSITION_PROFIT);
      double volume = PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      // Initialize or update the worst (most negative) profit
      if (minProfit[i] == 0 || currentProfit < minProfit[i])
         minProfit[i] = currentProfit;

      double lossIncrease = currentProfit - minProfit[i]; // Will be positive if loss is worsening

      // If current loss has worsened by threshold, close the trade
      if (minProfit[i] < 0 && lossIncrease <= -lossIncreaseThreshold) {
         double closePrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);

         MqlTradeRequest request;
         MqlTradeResult result;
         ZeroMemory(request);
         ZeroMemory(result);

         request.action = TRADE_ACTION_DEAL;
         request.symbol = symbol;
         request.volume = volume;
         request.type = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         request.price = closePrice;
         request.deviation = 10;
         request.position = ticket;
         request.type_filling = ORDER_FILLING_IOC;

         if (OrderSend(request, result) && result.retcode == TRADE_RETCODE_DONE) {
            if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Closed losing trade at index ", i, " due to increasing loss.");
            minProfit[i] = 0; // Reset after closing
            CountOpenTradesPerSession--;
            if(marketMovement=="Bullish") {
               if( areSpreadsGood && (CountOpenTradesPerSession <= MaxOpenTradesPerSession) && OpenTradeWithSLTPinUSD(_Symbol, InpLotSize, InpStopLossUSD, InpTakeProfitUSD, true, clrGreen, "EA Buy  3-#") ) {
                  CountOpenTradesPerSession++;
               }
            } else if(marketMovement=="Bearish") {
               if( areSpreadsGood && (CountOpenTradesPerSession <= MaxOpenTradesPerSession) && OpenTradeWithSLTPinUSD(_Symbol, InpLotSize, InpStopLossUSD, InpTakeProfitUSD, false, clrGreenYellow, "EA Sell  3-#") ) {
                  CountOpenTradesPerSession++;
               }
            }

         } else {
            if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) Print("Failed to close losing trade at index ", i, ": ", result.retcode);
         }
      }
   }
}


//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {

   if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " OnTick() - Start");
   }

   int barsEntry = iBars(_Symbol, PERIOD_CURRENT);
   if(barsEntry<20) {
      if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat("MA buffer not ready yet. (InpSlowPeriod)=%d barsEntry=%d",InpSlowPeriod,barsEntry);
      return;
   }

//if (!EAInitialised) {
//   EAInitialised = OnInit();
//   return;
//}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
   int bars = iBars(_Symbol, PERIOD_CURRENT);
   if(barsForCandlestickPattern != bars) {
      barsForCandlestickPattern = bars;
      // Evaluate the candle sticks, 3 pattern, 2 pattern and 1 pattern
      int buy1 = oneCandlestickPattern.OneShouldBuy();
      int buy2 = twoCandlestickPattern.TwoShouldBuy();
      int buy3 = threeCandlestickPattern.ThreeShouldBuy(1, SESSION_PERIOD_RESOLUTION);
      int sell1 = oneCandlestickPattern.OneShouldSell();
      int sell2 = twoCandlestickPattern.TwoShouldSell();
      int sell3 = threeCandlestickPattern.ThreeShouldSell();

      buyEntry  = (buy1  || buy2  || buy3  || IgnoreCandleStickPremonition );
      sellEntry = (sell1 || sell2 || sell3 || IgnoreCandleStickPremonition );
   }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
   UpdateMACrossoverBuffers();
   DrawBaseline();
   DrawMA_Segments(fastHandle, "FastMA", clrYellow, 50);
   DrawMA_Segments(slowHandle, "SlowMA", clrTeal, 50);

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
   bool PredictMACrossVar = PredictMACross();
   bool DetectMAConvergenceVar =(DetectMAConvergence()!=-1);
   int lineCross = DidTheLinesCross();
   marketPatternSpeed = DetectTrendSpeed(3);

//--- Get EURUSD Market Session
   string session = GetEURUSDMarketSession();
   Comment("🕒 Market Session:\n", session);

// Good spreads.
   bool CanTradeSpreadsGood = OnTickSpread();

   CountOpenTradesPerSession = GetEATrades( InpMagicNumber);

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+

   resultConsensusCandleStick0 = DoesMajorityAgreeWithM1(_Symbol, InpCrossReferenceTimePeriod,0);
   resultConsensusCandleStick1 = DoesMajorityAgreeWithM1(_Symbol, InpCrossReferenceTimePeriod,1);
   DetectMarketMovement0 = "";
   DetectMarketMovement1 = "";
   SameDirection0 = AreBothTimeseriesSameDirection(PERIOD_CURRENT, Timeseries_SameDirection_RESOLUTION, 0, DetectMarketMovement0);
   SameDirection1 = AreBothTimeseriesSameDirection(PERIOD_CURRENT, Timeseries_SameDirection_RESOLUTION, 1, DetectMarketMovement1 );

   if( UseEAInAutoMode && CountOpenTradesPerSession <= MaxOpenTradesPerSession && CanTradeSpreadsGood) {
      if( InpRunConsensusOnlyOnThePreviousCandleStick && resultConsensusCandleStick1 ) {
         if(SameDirection1) {
            if(StringCompare(DetectMarketMovement1,"Bullish")) {
               if( OpenTradeWithSLTPinUSD(_Symbol, InpLotSize, InpStopLossUSD, InpTakeProfitUSD, true, clrGreen, "EA Buy  0->") ) {
                  CountOpenTradesPerSession++;
               }
            } else if(StringCompare(DetectMarketMovement1,"Bearish")) {
               if( OpenTradeWithSLTPinUSD(_Symbol, InpLotSize, InpStopLossUSD, InpTakeProfitUSD, false, clrGreenYellow, "EA Sell  0->") ) {
                  CountOpenTradesPerSession++;
               }
            }
         }
      } else if( resultConsensusCandleStick0 && resultConsensusCandleStick1 ) {
         if(SameDirection0 && SameDirection1) {
            if( StringCompare(DetectMarketMovement0,"Bullish") && StringCompare(DetectMarketMovement1,"Bullish")) {
               if( OpenTradeWithSLTPinUSD(_Symbol, InpLotSize, InpStopLossUSD, InpTakeProfitUSD, true, clrGreen, "EA Buy  0->1") ) {
                  CountOpenTradesPerSession++;
               }
            } else if(StringCompare(DetectMarketMovement0,"Bearish") && StringCompare(DetectMarketMovement1,"Bearish") ) {
               if( OpenTradeWithSLTPinUSD(_Symbol, InpLotSize, InpStopLossUSD, InpTakeProfitUSD, false, clrGreenYellow, "EA Sell 0->1") ) {
                  CountOpenTradesPerSession++;
               }
            }
         }
      }
   }

   if(UseEAInAutoMode) {
      //validateIndicatorDetails();
      CloseAndReopenProfitableTrades(_Symbol);

      if(lineCross==1) { //Check for a cross - buy - Going up.
         MonitorAndCloseDecliningProfit(InpLossThresholdUSD);
      } else if(lineCross==-1) { //Check for a cross - sell - Going down.
         MonitorAndCloseDecliningProfit(InpLossThresholdUSD);
      } else if(lineCross==0) {
         MonitorAndCloseWorseningLosses(InpStopLossUSD, DetectMarketMovement0);
      }
   }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
   if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat("Consensus : CandleStick[0]=%s and CandleStick[1]=%s ", resultConsensusCandleStick0?"true":"false",resultConsensusCandleStick1?"true":"false");
   if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) PrintFormat("Direction : SameDirection[0]=%s and SameDirection[1]=%s ", SameDirection0?"true":"false",SameDirection1?"true":"false");

   if(!MQL5InfoInteger(MQL5_OPTIMIZATION)) {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " OnTick() - End");
   }
}
//+------------------------------------------------------------------+

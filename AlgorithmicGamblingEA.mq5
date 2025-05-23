//+------------------------------------------------------------------+
//|                                                      ProjectName |
//|                                      Copyright 2020, CompanyName |
//|                                       http://www.companyname.net |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.11"

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
//| Includes                                                         |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include "CandleUtils\ThreeCandlestickPatterns.mqh"
#include "CandleUtils\TwoCandlestickPatterns.mqh"
#include "CandleUtils\OneCandlestickPatterns.mqh"
#include "Notification\Notification.mqh"


//+------------------------------------------------------------------+
//| Input Variables                                                  |
//+------------------------------------------------------------------+
input bool UseEAInAutoMode = true;                        // Use EA in Active Mode.
input int InpFastPeriod = 2;                                // Fast period.
input int InpSlowPeriod = 5;                               // Slow period.
input double lotSize = 0.1 ;                               // Lot size.
input int InpTakeProfit = 200;                              // Take Profit in points.
input int InpStopLoss = 100;                                // Stop Loss in points.
input double InpStopLossAdjustment   = 0.0001;              // Stop Loss Adjustment.
input double InpTakeProfitAdjustment = 0.0001;              // Take Profit Adjustment.
input ulong InpMagicNumber = 820607;                        // Magic Number.

//input int InpNumberOfCandlesTrailingSL = 10;                // Number Of Candles Trailing SL.
//---Trailing stop input variables
//input bool UseTrailing = true;                              //Use trailing stop.
//input int WhenToTrail  = 50;                                //When to start trailing in pips.
//input int TrailBy      = 20;                                //TrailingStop even in pips.

input bool CalculateDynamicTP_SL = true;                    //Calculate Dynamic TP SL
input double CalculateDynamicTP_SL_Steps = 0.5;             //Calculate Dynamic TP SL Steps
input bool FactorVolatilityIn_TP_SL_Calculation = false;    //Factor Volatility In TP/SL Calculations
input int MaxOpenTradesPerSession = 2;                      //Max open trades per session.
input double CrossOverFastSlowDistanceTollerance = 0.00010; //Crossover Fast vs Slow Distance Tollerance
input double FastSlowDistanceTollerance = 0.00020;          //Fast vs Slow Distance Tollerance

//input ENUM_DRAW_TYPE  DrawType  = DRAW_LINE;
//input ENUM_LINE_STYLE LineStyle = STYLE_SOLID;

input ENUM_TIMEFRAMES SESSION_PERIOD_RESOLUTION=PERIOD_M1;  // Session Period

input bool BEBUG_BOT = true;                                //BEBUG_BOT mode

// Define thresholds for speed classification
input double fastThreshold = 0.00110;                       // Fast Threshold speed classification
input double slowThreshold = 0.00011;                       // Slow Threshold speed classification
input bool   EnableSpeedThreshold = true;                   // Enable Speed Threshold

input int CrossoverPredictionCandles = 3;                   // Crossover prediction candles.

input int BullBearRunCandleDepth = 3;                       // BullBearRunCandleDepth
input int BullRunCandleCount = 2;                           // BullRunCandleCount
input int BearRunCandleCount = 2;                           // BearRunCandleCount
input bool IgnoreDetectMAConvergence = true;                // IgnoreDetectMAConvergence
input double IgnoreDetectMAConvergenceTollerrance=0.00100;  // IgnoreDetectMAConvergenceTollerrance
input bool   EnableScalpingMode = true;                     // EnableScalpingMode
input bool IgnoreCandleStickPremonition = false;             // IgnoreCandleStickPremonition

input double StickEntryCutoffPipsize = 4.0;                 // StickEntryCutoffPipsize
input int GoodBadTradesInThePastNCandlesticks = 1;          //GoodBadTradesInThePastNCandlesticks
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
double volatility = 0;                                     // ATR-based volatility
double rangeVolatility = 0 ;                               // High-low range
string marketPatternSpeed = "";
bool buyEntry  = false;
bool sellEntry = false;

string SessionID = "";

// === INPUT SETTINGS - Market News ===
//https://www.myfxbook.com/api/login.json?email=pmbabela@gmail.com&password=<3py2Xs49R#L
input int HoursAhead = 24;
input int MinutesBeforeAlert = 5;
input string NewsCurrency = "USD"; // Filter e.g. "USD", "EUR"
input bool HighImpactOnly = true;
input int AutoRefreshInterval_Minutes = 10;
input string email = "pmbabela@gmail.com";                  //myfxbook email
input string password = "<3py2Xs49R#L";                     // password myfxbook

// === INTERNAL STORAGE ===
struct NewsEvent {
   datetime          time;
   string            title;
   string            currency;
   string            impact;
   bool              alerted;
};

struct TradeAnalysisResult {
   bool isProfitable;
   int badTradesInLastNCandles;
   int goodTradesInLastNCandles;
   int totalTradesInLastNCandles;
};



double highLineBuffer[], lowLineBuffer[];
NewsEvent newsList[100];
int newsCount = 0;

//+------------------------------------------------------------------+
//| Pattern detection algorithms.                                    |
//+------------------------------------------------------------------+
OneCandlestickPatterns     oneCandlestickPattern;
TwoCandlestickPatterns     twoCandlestickPattern;
ThreeCandlestickPatterns   threeCandlestickPattern;

Notification notification;


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   MACrossoverInit();
   PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " LAST PING=%.5f ms", TerminalInfoInteger(TERMINAL_PING_LAST)/1000.);
   if(!UseEAInAutoMode) {
      InitialiseButtons();
   }

   MathSrand((int)TimeLocal()); // Seed with current time

//SessionID = MyfxbookLogin();
//string resError = StringFormat("WebRequest failed: MyfxbookLogin()=%d , SessionID=%s", GetLastError(),SessionID);
//MessageBox(resError, "WebRequest Error", MB_ICONERROR);

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
   if(!UseEAInAutoMode) {
      //CreateButton("btnRefreshNews", "️🔄 News",640, 30, clrOrange);
   } else {
      //CreateButton("btnRefreshNews", "️🔄 News",20, 30, clrOrange);
   }
//FetchMyfxbookNews();
//UpdateLastUpdatedLabel();
//EventSetTimer(AutoRefreshInterval_Minutes * 60);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DrawBaseline() {
   double highVal = iHigh(_Symbol, PERIOD_D1, 0);
   double lowVal = iLow(_Symbol, PERIOD_D1, 0);
   for(int i = 0; i < 100; i++) {
      highLineBuffer[i] = highVal;
      lowLineBuffer[i] = lowVal;
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " EA deinitialised.");
   MACrossoverDeInit();

   EventKillTimer();
   ObjectDelete(0, "btnRefreshNews");
   ObjectDelete(0, "LastUpdatedLabel");
   ClearOldNewsObjects();

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
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {

   UpdateMACrossoverBuffers();

   PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " OnTick() - Start");
   volatility = GetMarketVolatility();                                                 // ATR-based volatility
//rangeVolatility = GetHighLowVolatility();                                         // High-low range
//Print("ATR Volatility: ", volatility," ,ATR Volatility: ", volatility," ,(10 * _Point) = ",10 * _Point, " | High-Low Volatility: ", rangeVolatility);;

   validateIndicatorDetails();
   int lineCross = DidTheLinesCross();
   marketPatternSpeed = DetectTrendSpeed(3);

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

      buyEntry  = (buy1  || buy2  || buy3 || IgnoreCandleStickPremonition );
      sellEntry = (sell1 || sell2 || sell3 || IgnoreCandleStickPremonition );
   }

//Cleanup of old and counter productive trade.
   if(UseEAInAutoMode) {
      closeAllBuyOpenTrades_TrendFinished();
      closeAllSellOpenTrades_TrendFinished();
   }

   DrawMA_Segments(fastHandle, "FastMA", clrYellow, 50);
   DrawMA_Segments(slowHandle, "SlowMA", clrTeal, 50);

// Adjust the Stop Loss and Take Profit.
   adjustTakeProfitAndStopLossesForAllOpenTrades();

   bool fastUpTrendNoCross ;
   bool slowUpTrendNoCross ;
   bool fastDownTrendNoCross;
   bool slowDownTrendNoCross;

   bool EnterIfTheyAreFarApartVar ;
   bool PredictMACrossVar = PredictMACross();
   bool DetectMAConvergenceVar =(DetectMAConvergence()!=-1);
   bool IsBullishVar = IsBullish();

   double pipSize = GetCurrentCandlePipSize();

   if ( (lastTradeTime != iTime(_Symbol,PERIOD_CURRENT,0)) && PredictMACrossVar ) {
      closeAllSellOpenTrades_TrendFinished(true);
      closeAllBuyOpenTrades_TrendFinished(true);
   }

   if(lineCross==1) { //Check for a cross - buy.

      PrintFormat(__FUNCTION__ +"-"+IntegerToString(__LINE__)+ " - Lines did cross :- Preparing to buy. But prior that, we nee to close all Sell Open Trades.");
      EnterIfTheyAreFarApartVar = EnterIfTheyAreFarApart(CrossOverFastSlowDistanceTollerance,"Enter Buy+1",clrLimeGreen,1);
      fastUpTrendNoCross = (StrCompare(marketPatternSpeed,"Fast Uptrend") && (fastBuffer[0]>slowBuffer[0]) && (!EnterIfTheyAreFarApartVar) && (DetectMAConvergenceVar));
      slowUpTrendNoCross = (((AreWeInABullRun(EnableScalpingMode) ||  StrCompare(marketPatternSpeed,"Slow Uptrend")) && (fastBuffer[0]>slowBuffer[0])) && (!PredictMACrossVar) && (DetectMAConvergenceVar));
      closeAllSellOpenTrades_TrendFinished(true);
      if( (fastUpTrendNoCross || slowUpTrendNoCross) && !StrCompare(marketPatternSpeed,"Sideways Market") && IsBullishVar && EnterIfTheyAreFarApartVar) {
         PrintFormat("CROSS BUY - CountOpenTradesPerSession(%d) and MaxOpenTradesPerSession(%d)",CountOpenTradesPerSession,MaxOpenTradesPerSession);
         if(UseEAInAutoMode && (CountOpenTradesPerSession < MaxOpenTradesPerSession) && ( AvoidEnteringAtTheBeggingOfTheCandleStick() )) {
            MACrossoverBuy(clrGreen,"X1");
            createObject(SymbolInfoInteger(_Symbol, SYMBOL_TIME), SymbolInfoDouble(_Symbol, SYMBOL_ASK), 200,1, clrPink, "Buy");
         }
      }
   } else if(lineCross==-1) { //Check for a cross - sell.
      PrintFormat(__FUNCTION__ +"-"+IntegerToString(__LINE__)+ " - Lines did cross :- Preparing to sell. But prior that, we nee to close all Sell Buy Trades.");
      EnterIfTheyAreFarApartVar = EnterIfTheyAreFarApart(CrossOverFastSlowDistanceTollerance,"Enter Sell-1", clrRed,0);
      fastDownTrendNoCross = (StrCompare(marketPatternSpeed,"Fast Downtrend") && (slowBuffer[0]>fastBuffer[0]) && (!PredictMACrossVar && (DetectMAConvergenceVar)));
      slowDownTrendNoCross = (((AreWeInABearRun(EnableScalpingMode) ||  StrCompare(marketPatternSpeed,"Slow Downtrend")) && (slowBuffer[0]>fastBuffer[0])) && (!PredictMACrossVar && (DetectMAConvergenceVar)));
      closeAllBuyOpenTrades_TrendFinished(true);
      if( (fastDownTrendNoCross || slowDownTrendNoCross) && !StrCompare(marketPatternSpeed,"Sideways Market") && !IsBullishVar && EnterIfTheyAreFarApartVar) {
         PrintFormat("CROSS SELL - CountOpenTradesPerSession(%d) and MaxOpenTradesPerSession(%d)",CountOpenTradesPerSession,MaxOpenTradesPerSession);
         if(UseEAInAutoMode && (CountOpenTradesPerSession < MaxOpenTradesPerSession) && ( AvoidEnteringAtTheBeggingOfTheCandleStick() )) {
            MACrossoverSell(clrOrangeRed,"X-1");
            createObject(SymbolInfoInteger(_Symbol, SYMBOL_TIME), SymbolInfoDouble(_Symbol, SYMBOL_BID), 201,0, clrOrange, "Sell");
         }
      }
   } else if(lineCross==0) {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " Lines didn't cross.");

      fastUpTrendNoCross = (StrCompare(marketPatternSpeed,"Fast Uptrend") && (fastBuffer[1]>slowBuffer[1]) && (!PredictMACrossVar && (DetectMAConvergenceVar)));
      slowUpTrendNoCross = (((AreWeInABullRun(false) ||  StrCompare(marketPatternSpeed,"Slow Uptrend")) && (fastBuffer[1]>slowBuffer[1])) && (!PredictMACrossVar && (DetectMAConvergenceVar)));

      fastDownTrendNoCross = (StrCompare(marketPatternSpeed,"Fast Downtrend") && (slowBuffer[1]>fastBuffer[1]) && (!PredictMACrossVar && ( DetectMAConvergenceVar) ) );
      slowDownTrendNoCross = (((AreWeInABearRun(false) ||  StrCompare(marketPatternSpeed,"Slow Downtrend")) && (slowBuffer[1]>fastBuffer[1])) && (!PredictMACrossVar && (DetectMAConvergenceVar)));

      if( (fastUpTrendNoCross || slowUpTrendNoCross) && !StrCompare(marketPatternSpeed,"Sideways Market") && (buyEntry) && IsBullishVar && (pipSize<= StickEntryCutoffPipsize) ) {
         EnterIfTheyAreFarApartVar = EnterIfTheyAreFarApart(FastSlowDistanceTollerance,"Enter Buy0",clrLimeGreen,1);
         PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " Lines didn't cross :- Preparing to buy");
         if(UseEAInAutoMode && EnterIfTheyAreFarApartVar && (CountOpenTradesPerSession < MaxOpenTradesPerSession) && ( AvoidEnteringAtTheBeggingOfTheCandleStick() )) {
            PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" Lines didn't cross :- Passed all checks and balances - Preparing to buy");
            MACrossoverBuy(clrBrown,"x1");
            createObject(SymbolInfoInteger(_Symbol, SYMBOL_TIME), SymbolInfoDouble(_Symbol, SYMBOL_ASK), 202,1, clrViolet, "Buy");
         }
      } else if( (fastDownTrendNoCross || slowDownTrendNoCross) && !StrCompare(marketPatternSpeed,"Sideways Market") && (sellEntry) && !IsBullishVar && (pipSize<= StickEntryCutoffPipsize) ) {
         PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" Lines didn't cross :- Preparing to sell");
         EnterIfTheyAreFarApartVar = EnterIfTheyAreFarApart(FastSlowDistanceTollerance,"Enter Sell0",clrRed,0);
         if(UseEAInAutoMode && EnterIfTheyAreFarApartVar && (CountOpenTradesPerSession < MaxOpenTradesPerSession) && ( AvoidEnteringAtTheBeggingOfTheCandleStick() )) {
            PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" Lines didn't cross :- Passed all checks and balances - Preparing to sell");
            MACrossoverSell(clrBeige,"x-1");
            createObject(SymbolInfoInteger(_Symbol, SYMBOL_TIME), SymbolInfoDouble(_Symbol, SYMBOL_BID), 203,0, clrAqua, "Sell");
         }
      }
   }


   PrintFormat("pipSize(%.9f)",pipSize);
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   PrintFormat("lastTradeTime(%s) != iTime(_Symbol,PERIOD_CURRENT,0)(%s)", TimeToString(lastTradeTime ), TimeToString(barTime, TIME_DATE | TIME_SECONDS ));
   PrintFormat("fastUpTrendNoCross(%s) slowUpTrendNoCross(%s) fastDownTrendNoCross(%s) IsBullishVar(%s) ",fastUpTrendNoCross?"True":"Fals", slowUpTrendNoCross?"True":"Fals",fastDownTrendNoCross?"True":"Fals",IsBullishVar?"True":"Fals" );
   PrintFormat("EnterIfTheyAreFarApartVar(%s) PredictMACrossVar(%s) DetectMAConvergenceVar(%s) IsBullishVar(%s) ",EnterIfTheyAreFarApartVar?"True":"Fals", PredictMACrossVar?"True":"Fals",DetectMAConvergenceVar?"True":"Fals",IsBullishVar?"True":"Fals" );
   PrintFormat("CountOpenTradesPerSession(%d) MarketPatternSpeed(%s) fastUpTrendNoCross(%s) slowUpTrendNoCross(%s) fastDownTrendNoCross(%s) slowDownTrendNoCross(%s) buyEntry(%s) sellEntry(%s)",CountOpenTradesPerSession, marketPatternSpeed, fastUpTrendNoCross ? "true" : "false", slowUpTrendNoCross ? "true" : "false", fastDownTrendNoCross ? "true" : "false", slowDownTrendNoCross ? "true" : "false", buyEntry ? "true" : "false",sellEntry ? "true" : "false");
   PrintFormat("PredictMACross(%d) DetectMAConvergence(%d) ",PredictMACrossVar, DetectMAConvergenceVar);
   PrintFormat("slowDownTrendNoCross(%s) buyEntry(%s) sellEntry(%s)", slowDownTrendNoCross ? "true" : "false", buyEntry ? "true" : "false",sellEntry ? "true" : "false");

   PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" OnTick() - End");
}
//+------------------------------------------------------------------+


bool areGoodTradesBiggerThanBadTradesInThePastNCandlesticks(ulong ticket = 0, int lookback = 3) {

   TradeAnalysisResult res = AnalyzeTrade(ticket, lookback);

   Print("Trade was profitable: ", res.isProfitable);
   Print("Trade was profitable: ", res.isProfitable);
   Print("Total trades in last ", lookback, " candles: ", res.totalTradesInLastNCandles);
   Print("Good trades: ", res.goodTradesInLastNCandles);
   Print("Bad trades: ", res.badTradesInLastNCandles);

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
      Print("Trade ticket not found: ", ticketId);
      return result;
   }

   double profit = HistoryDealGetDouble(ticketId, DEAL_PROFIT);
   result.isProfitable = (profit > 0);

// Define the time range: from N candles ago to now
   datetime endTime = TimeCurrent();
   datetime startTime = iTime(_Symbol, _Period, candlesBack);
   if (startTime == 0) {
      Print("Invalid candle index: ", candlesBack);
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
      seconds = GetRandomInt(40,55);
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
/*
void DrawSLTP(string symbol, ulong ticket)
{
   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);

   if(PositionSelect(symbol))
   {
      string sl_name = StringFormat("SL_%d", ticket);
      string tp_name = StringFormat("TP_%d", ticket);

      // Delete previous lines if they exist
      ObjectDelete(0, sl_name);
      ObjectDelete(0, tp_name);

      // Draw Stop Loss line
      if(sl > 0)
      {
         ObjectCreate(0, sl_name, OBJ_HLINE, 0, 0, sl);
         ObjectSetInteger(0, sl_name, OBJPROP_COLOR, clrRed);
         ObjectSetInteger(0, sl_name, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, sl_name, OBJPROP_WIDTH, 1);
      }

      // Draw Take Profit line
      if(tp > 0)
      {
         ObjectCreate(0, tp_name, OBJ_HLINE, 0, 0, tp);
         ObjectSetInteger(0, tp_name, OBJPROP_COLOR, clrGreen);
         ObjectSetInteger(0, tp_name, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, tp_name, OBJPROP_WIDTH, 1);
      }
   }
}
*/

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
//| On Trade Transaction                                             |
//+------------------------------------------------------------------+
bool IsBullish(int stickIndex=0) {
   double open = iOpen(_Symbol, _Period, stickIndex);
   double close = iClose(_Symbol, _Period, stickIndex);

   if (close > open)
      return true;
   else if (close < open)
      return false;
   else
      return false;
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
//| On Trade Transaction                                             |
//+------------------------------------------------------------------+
/*
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result) {

   CDealInfo  objDeal;
   long reason=-1;
   Print(__FUNCTION__ + "-" + IntegerToString(__LINE__) +", An interesting event has happened. Evaluating the nature of the event.");
   CheckTradeResult(result);

//--- get transaction type as enumeration value
   ENUM_TRADE_TRANSACTION_TYPE type=trans.type;
//--- if transaction is result of addition of the transaction in history
   if(type==TRADE_TRANSACTION_DEAL_ADD) {
      if(HistoryDealSelect(trans.deal))
         objDeal.Ticket(trans.deal);
      else {
         Print(__FUNCTION__ + "-" + IntegerToString(__LINE__) +", ERROR: HistoryDealSelect(",trans.deal,")");
         return;
      }
      //---
      if(!objDeal.InfoInteger(DEAL_REASON,reason)) {
         PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +", ERROR: InfoInteger(DEAL_REASON,reason)");
         CountOpenTradesPerSession--;
         return;
      }

      if((ENUM_DEAL_REASON)reason==DEAL_REASON_SL && trans.deal_type==DEAL_TYPE_BUY) {
         //Handle when price hit SL
         PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" SL is HIT! -> for a BUY");
         lastTradeTime = iTime(_Symbol,PERIOD_CURRENT,0);
         CountOpenTradesPerSession--;
      } else if((ENUM_DEAL_REASON)reason==DEAL_REASON_SL && trans.deal_type==DEAL_TYPE_SELL) {
         //Handle when price hit SL
         PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" SL is HIT! -> for a SELL");
         lastTradeTime = iTime(_Symbol,PERIOD_CURRENT,0);
         CountOpenTradesPerSession--;
      } else if((ENUM_DEAL_REASON)reason==DEAL_REASON_TP && trans.deal_type==DEAL_TYPE_BUY) {
         //Handle when price hit TP
         PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" TP is HIT! -> for a BUY");
         lastTradeTime = iTime(_Symbol,PERIOD_CURRENT,0);
         CountOpenTradesPerSession--;
      } else if((ENUM_DEAL_REASON)reason==DEAL_REASON_TP && trans.deal_type==DEAL_TYPE_SELL) {
         //Handle when price hit TP
         PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" TP is HIT! -> for a SELL");
         lastTradeTime = iTime(_Symbol,PERIOD_CURRENT,0);
         CountOpenTradesPerSession--;
      }
   }
}
*/

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result) {

   if (trans.type == TRADE_TRANSACTION_DEAL_ADD) {
      long entry_type = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

      if (entry_type == DEAL_ENTRY_OUT) { // trade closed
         DeleteDrawSLTP(_Symbol, trans.position);
         double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
         CountOpenTradesPerSession--;
         lastTradeTime = iTime(_Symbol,PERIOD_CURRENT,0);
         Print("DEAL_ENTRY_OUT Position closed: Deal #", trans.deal, " | Position #", trans.position, " | Symbol: ", trans.symbol, " | Profit: ", profit, " | CountOpenTradesPerSession: ", CountOpenTradesPerSession);
         Alert("DEAL_ENTRY_OUT Position closed: Deal #", trans.deal, " | Position #", trans.position, " | Symbol: ", trans.symbol, " | Profit: ", profit, " | CountOpenTradesPerSession: ", CountOpenTradesPerSession);
         PlaySound("alert.wav");  // 🔊 Play sound when trade is closed
      } else if (entry_type == DEAL_ENTRY_IN) { // trade opened

         DeleteDrawSLTP(_Symbol, trans.position);
         if (CountOpenTradesPerSession>=MaxOpenTradesPerSession)
            CountOpenTradesPerSession--;
         else
            CountOpenTradesPerSession++;

         lastTradeTime = iTime(_Symbol,PERIOD_CURRENT,0);
         Print("DEAL_ENTRY_IN Position opened: Deal #", trans.deal, " | Symbol: ", trans.symbol, " | Volume: ", trans.volume, " | CountOpenTradesPerSession: ", CountOpenTradesPerSession);
         Alert("DEAL_ENTRY_IN Position opened: Deal #", trans.deal, " | Symbol: ", trans.symbol, " | Volume: ", trans.volume, " | CountOpenTradesPerSession: ", CountOpenTradesPerSession);
         PlaySound("ok.wav");
      } else if (entry_type == DEAL_ENTRY_OUT_BY) { // Close a position by an opposite one
         DeleteDrawSLTP(_Symbol, trans.position);
         CountOpenTradesPerSession--;
         lastTradeTime = iTime(_Symbol,PERIOD_CURRENT,0);
         Print("DEAL_ENTRY_OUT_BY Position opened: Deal #", trans.deal, " | Symbol: ", trans.symbol, " | Volume: ", trans.volume, " | CountOpenTradesPerSession: ", CountOpenTradesPerSession);
         Alert("DEAL_ENTRY_OUT_BY Position opened: Deal #", trans.deal, " | Symbol: ", trans.symbol, " | Volume: ", trans.volume, " | CountOpenTradesPerSession: ", CountOpenTradesPerSession);
         PlaySound("ok.wav");
      } else if (entry_type == DEAL_ENTRY_INOUT) {
         DeleteDrawSLTP(_Symbol, trans.position);
         CountOpenTradesPerSession--;
         Print("🔁 DEAL_ENTRY_INOUT Position closed by another: Deal #", trans.deal, " | Symbol: ", trans.symbol, " | CountOpenTradesPerSession: ", CountOpenTradesPerSession);
         Alert("🔁 DEAL_ENTRY_INOUT Position closed by another: Deal #", trans.deal, " | Symbol: ", trans.symbol, " | CountOpenTradesPerSession: ", CountOpenTradesPerSession);
         PlaySound("closeby.wav");
      } else {
         Print("🔁 The deal type is entry_type=", entry_type, " | CountOpenTradesPerSession: ", CountOpenTradesPerSession);
         Alert("🔁 The deal type is entry_type=", entry_type, " | CountOpenTradesPerSession: ", CountOpenTradesPerSession);
      }
   }
}



//+------------------------------------------------------------------+
//| Function to detect MA convergence or divergence                  |
//| Returns 1 for divergence, -1 for convergence, 0 for neutral     |
//+------------------------------------------------------------------+
int DetectMAConvergence() {
   double ma1_current = fastBuffer[0];
   double ma2_current = slowBuffer[0];
   double ma1_prev    = fastBuffer[1];
   double ma2_prev    = slowBuffer[1];

   double diff_current = ma1_current - ma2_current;
   double diff_prev    = ma1_prev - ma2_prev;

   if(MathAbs(diff_current) > MathAbs(diff_prev)) {
      Print(__FUNCTION__ +"-"+IntegerToString(__LINE__) + " - ⚠ ️Diverging !");
      //createObject(iTime(_Symbol, PERIOD_CURRENT, 0), fastBuffer[0], 302,1, clrMagenta, "⚠Div");
      return 1;  // Diverging
   } else if(MathAbs(diff_current) < MathAbs(diff_prev)) {
      Print(__FUNCTION__ +"-"+IntegerToString(__LINE__) + " - ⚠ ️Converging !");
      //createObject(iTime(_Symbol, PERIOD_CURRENT, 0), fastBuffer[0], 301,1, clrRosyBrown, "⚠Con");
      if (IgnoreDetectMAConvergence) {
         if (MathAbs(fastBuffer[0]-slowBuffer[0]) > IgnoreDetectMAConvergenceTollerrance) {
            return 1;
         }
      }
      return -1; // Converging
   }
   Print(__FUNCTION__ +"-"+IntegerToString(__LINE__) + " - ⚠ ️Neutral !");
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
            Print(__FUNCTION__ +"-"+IntegerToString(__LINE__) + " - ⚠️ Possible MA Cross in ", i, " candles!");
            createObject(iTime(_Symbol, PERIOD_CURRENT, 0), fastBuffer[0], 300,0, clrTeal, "+Cross");
            return true;
         } else if((fastBuffer[0] < slowBuffer[0] && fastFuture > slowFuture)) {
            Print(__FUNCTION__ +"-"+IntegerToString(__LINE__) + " - ⚠️ Possible MA Cross in ", i, " candles!");
            createObject(iTime(_Symbol, PERIOD_CURRENT, 0), fastBuffer[0], 300,0, clrOrange, "-Cross");
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Close all buy open trades - Trend Finished                       |
//+------------------------------------------------------------------+
void closeAllBuyOpenTrades_TrendFinished(const bool skipChecks = false) {
   PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " We need to close buy trades");
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong positionTicket = PositionGetTicket(i);
      if(PositionSelectByTicket(positionTicket)) {
         if((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)) {
            if(skipChecks || ((AreWeInABearRun() && (slowBuffer[1]>fastBuffer[1]) && (StrCompare(marketPatternSpeed,"Fast Downtrend") || StrCompare(marketPatternSpeed,"Slow Downtrend"))))) {
               if(skipChecks || ((DetectMAConvergence()!=-1) && (!PredictMACross()))) {

                  bool moreGoodThanBad = areGoodTradesBiggerThanBadTradesInThePastNCandlesticks(positionTicket, GoodBadTradesInThePastNCandlesticks);
                  
                  if((trade.RequestMagic()==InpMagicNumber) && !moreGoodThanBad && trade.PositionClose(positionTicket)) {
                     //--CountOpenTradesPerSession;
                     PrintPositionStats(positionTicket);
                     Print(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " > BUY position Pos #%d was automatically closed by the EA. The Trend Finished.", positionTicket);
                     notification.SendEmailNotification("EA->Closed a BUY trade", __FUNCTION__ + "-" + IntegerToString(__LINE__) + " > BUY position Pos #"+IntegerToString(positionTicket)+" was automatically closed by the EA. The Trend Finished.");
                  } else if(CheckManualTradeViaComment(positionTicket) && trade.PositionClose(positionTicket)) {
                     Print(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " > BUY position Pos #%d was manually closed by the trader(Human).", positionTicket);
                     notification.SendEmailNotification("Trader->Closed a BUY trade",__FUNCTION__ + "-" + IntegerToString(__LINE__) + " > BUY position Pos "+IntegerToString(positionTicket)+" was manually closed by the trader(Human).");
                  }
               }
            }
         }
      }
   }
}


//+------------------------------------------------------------------+
//| Close all open trades                                            |
//+------------------------------------------------------------------+
void closeAllOpenTrades() {
   PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " We need to close open trades");
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong positionTicket = PositionGetTicket(i);
      if(PositionSelectByTicket(positionTicket)) {
         trade.PositionClose(positionTicket);
         notification.SendEmailNotification("Trader closing position ticket #"+IntegerToString(positionTicket),"Position closed.");
      }
   }
   if( PositionsTotal() > 0 ) {
      notification.SendEmailNotification("Trader->CloseAllOpenTrades", "User(Trader) closed all open trades.");
   }
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CheckManualTradeViaComment(ulong positionTicket) {
   if(PositionSelectByTicket(positionTicket)) {
      string comment = PositionGetString(POSITION_COMMENT);
      if(StringFind(comment, "Manual") == 0) {
         Print("This trade comment starts with 'Manual': ", comment);
         return true;
      } else {
         Print("Trade comment does NOT start with 'Manual': ", comment);
         return false;
      }
   }
   return false;
}


//+------------------------------------------------------------------+
//| Close all sell open trades - Trend Finished                      |
//+------------------------------------------------------------------+
void closeAllSellOpenTrades_TrendFinished(const bool skipChecks = false) {
   PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " We need to close sell trades");
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong positionTicket = PositionGetTicket(i);
      if(PositionSelectByTicket(positionTicket)) {
         if((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)) {
            if((skipChecks) || ((AreWeInABullRun() && (fastBuffer[1]>slowBuffer[1]) && (StrCompare(marketPatternSpeed,"Slow Uptrend") || StrCompare(marketPatternSpeed,"Fast Uptrend"))))) {
               if((skipChecks) || ((DetectMAConvergence()!=-1) && (!PredictMACross()))) {

                  bool moreGoodThanBad = areGoodTradesBiggerThanBadTradesInThePastNCandlesticks(positionTicket, GoodBadTradesInThePastNCandlesticks);

                  if((trade.RequestMagic()==InpMagicNumber) && !moreGoodThanBad && trade.PositionClose(positionTicket)) {
                     //--CountOpenTradesPerSession;
                     PrintPositionStats(positionTicket);
                     PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " > SELL position Pos #%d was manually closed by the EA. The Trend Finished",positionTicket);
                     notification.SendEmailNotification("closeAllSellOpenTrades_TrendFinished",__FUNCTION__ + "-" + IntegerToString(__LINE__) + " > SELL position Pos #"+IntegerToString(positionTicket)+" was manually closed by the EA. The Trend Finished");
                  }
               }
            }
         }
      }
   }
}


//+------------------------------------------------------------------+
//|Did the lines cross                                               |
//+------------------------------------------------------------------+
int DidTheLinesCross() {
   if(fastBuffer[1] < slowBuffer[1] && ((fastBuffer[0]) > slowBuffer[0])) {        //Check for a cross - buy.
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" This means we need to buy.");
      return 1;
   } else if(fastBuffer[1] > slowBuffer[1] && ((fastBuffer[0]) < slowBuffer[0])) { //Check for a cross - sell.
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" This means we need to sell.");
      return -1;
   } else {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" We cant buy nor sell, this means we should consider adjusting TP and SL using this permutation.");
      return 0;
   }
}

//TODO Delete this method.
//+------------------------------------------------------------------+
//| Enter if they are far apart                                      |
//+------------------------------------------------------------------+
bool EnterIfTheyAreFarApart(const double tolerrance = 0.00003, string enter ="Enter", color colour = clrLimeGreen, int buyOrsell=0 ) {
   if(MathAbs(fastBuffer[1] - slowBuffer[1]) > (tolerrance)) {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"We can enter, the lines are far apart. The tolerrance is %.5f the actual difference is %.5f",tolerrance,MathAbs(fastBuffer[1] - slowBuffer[1]) );
      createObject(iTime(_Symbol, PERIOD_CURRENT, 0), fastBuffer[0], 213,buyOrsell, colour, enter);
      return true;
   }
   PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"We can not enter, the lines are not far apart. The tolerrance is %.5f , the actual difference is %.5f ",tolerrance,MathAbs(fastBuffer[1] - slowBuffer[1]));
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
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"We are in a Bull run. fBufferSize(%d) and the count is counts(%d)", fBufferSize, counts);
      return true;
   } else {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"We are not in a Bull run. fBufferSize(%d) and the count is counts(%d)", fBufferSize, counts);
      return false;
   }
}

//+------------------------------------------------------------------+
//| Should we enter a bull run.                                      |
//+------------------------------------------------------------------+
bool ShouldWeEnterABullRun(double fsDistanceTollerance = 0 ) {
   if((fastBuffer[0] > slowBuffer[0]) && (MathAbs(fastBuffer[0] - slowBuffer[0]) > fsDistanceTollerance)) {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"Enter the bull cross over. The distance between the FAST[0](%.5f) v.s SLOW[0](%.5f) buffer is %.5f",fastBuffer[0], slowBuffer[0], (fastBuffer[0] - slowBuffer[0]));
      return true;
   } else {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"Dont enter the bull cross over. The distance between the FAST[0](%.5f) v.s SLOW[0](%.5f) buffer is %.5f",fastBuffer[0], slowBuffer[0], (fastBuffer[0] - slowBuffer[0]));
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
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" We are in a Bear run. fBufferSize(%d) the count is counts(%d) and MarketPatternSpeed(%s)",fBufferSize,counts, marketPatternSpeed);
      return true;
   } else {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" We are not in a Bear run. fBufferSize(%d), the count is counts(%d) and MarketPatternSpeed(%s)", fBufferSize,counts, marketPatternSpeed);
      return false;
   }
}

//+------------------------------------------------------------------+
//| Should we enter a bear run.                                      |
//+------------------------------------------------------------------+
bool ShouldWeEnterABearRun(double fsDistanceTollerance) {
   if((fastBuffer[0] < slowBuffer[0]) && (MathAbs(fastBuffer[0] - slowBuffer[0]) > fsDistanceTollerance)) {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" Yes, we should enter the bear run. The distance between the FAST v.s SLOW buffer is %.5f and the MarketPatternSpeed = %s",(fastBuffer[1] - slowBuffer[1]), marketPatternSpeed);
      return true;
   } else {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" No, we should not enter the bear run.. The distance between the FAST v.s SLOW buffer is %.5f and the MarketPatternSpeed = %s",(fastBuffer[1] - slowBuffer[1]), marketPatternSpeed);
      return false;
   }
}

//+------------------------------------------------------------------+
//| Adjust Take Profit and Stop Losses for all open trades.          |
//+------------------------------------------------------------------+
void adjustTakeProfitAndStopLossesForAllOpenTrades() {
   int bars = iBars(_Symbol, PERIOD_CURRENT);
   if(barsTotalPriceAdjustment != bars) {
      barsTotalPriceAdjustment = bars;
      for(int i = PositionsTotal()-1; i >= 0; i--) {
         ulong positionTicket = PositionGetTicket(i);
         if(PositionSelectByTicket(positionTicket)) {

            ulong magicNumber = (ulong)PositionGetInteger(POSITION_MAGIC);
            if ( magicNumber != InpMagicNumber )
               continue;

            double positionSL = NormalizeDouble(PositionGetDouble(POSITION_SL), _Digits);
            double positionTP = NormalizeDouble(PositionGetDouble(POSITION_TP), _Digits);
            bool closeBadDeal = false;

            //DrawSLTPAndTradeLine(_Symbol, positionTicket, clrRed, clrGreen, clrYellowGreen);

            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
               PrintFormat(__FUNCTION__+"-"+IntegerToString(__LINE__) + " . Ticket(%d) is a buy order.",positionTicket);
               if(fastBuffer[1] > slowBuffer[1]) {          //Uptrend Market - GOOD Position
                  PrintFormat(__FUNCTION__+"-"+IntegerToString(__LINE__) + " . Ticket(%d) is a buy order in a GOOD position.",positionTicket);
                  if(CalculateDynamicTP_SL) {
                     CalculateDynamic_TP_SL("buy",positionSL, positionTP, CalculateDynamicTP_SL_Steps, CalculateDynamicTP_SL_Steps, 14);
                  } else {
                     if(FactorVolatilityIn_TP_SL_Calculation) {
                        positionSL = positionSL + positionSL * InpStopLossAdjustment   + positionSL * volatility ;
                        positionTP = positionTP + positionTP * InpTakeProfitAdjustment + positionTP * volatility ;
                     } else {
                        positionSL = positionSL + positionSL * InpStopLossAdjustment   ;
                        positionTP = positionTP + positionTP * InpTakeProfitAdjustment ;
                     }
                  }

                  PrintFormat(__FUNCTION__+"-"+IntegerToString(__LINE__) + " . Ticket's(%d) positionSL(%s) and positionTP(%s) prior to market speed adjustment.",positionTicket,positionSL,positionTP);

                  if(StrCompare(marketPatternSpeed,"Fast Uptrend")) {
                     positionTP = positionTP + positionTP/4;
                     positionSL = positionSL + positionSL/4;
                  } else if(StrCompare(marketPatternSpeed,"Slow Uptrend")) {
                     positionTP = positionTP + positionTP/8;
                     positionSL = positionSL + positionSL/8;
                  } else if(StrCompare(marketPatternSpeed,"Fast Downtrend")) {
                     positionSL = positionSL + positionSL/4;
                     closeBadDeal = true;
                  } else if(StrCompare(marketPatternSpeed,"Slow Downtrend")) {
                     positionSL = positionSL + positionSL/8;
                  }

                  PrintFormat(__FUNCTION__+"-"+IntegerToString(__LINE__) + " . Ticket's(%d) positionSL(%s) and positionTP(%s) post to market speed adjustment. MarketPatternSpeed(%s)",positionTicket,positionSL,positionTP,marketPatternSpeed);

                  if(closeBadDeal) {
                     if(trade.PositionClose(positionTicket)) {
                        //CountOpenTradesPerSession--;
                        DeleteDrawSLTP(_Symbol, positionTicket);
                        PrintFormat(__FUNCTION__ + "-"+ IntegerToString(__LINE__) + " > Closed a BAD BUY DEAL Pos #%d", positionTicket);
                        notification.SendEmailNotification("EA closed a bad BUY trade #" + IntegerToString(positionTicket), "");
                     }
                  } else if(trade.PositionModify(positionTicket,positionSL,positionTP)) {
                     PrintFormat(__FUNCTION__ +"-"+IntegerToString(__LINE__)+ " > BUY Pos #%d was modified. GOOD Position.", positionTicket);
                  }
               } else if(fastBuffer[1] < slowBuffer[1]) {  //Downtrend Market - BAD Position
                  PrintFormat(__FUNCTION__+"-"+IntegerToString(__LINE__) + " . Ticket(%d) is a buy order in a BAD position.",positionTicket);
                  if(CalculateDynamicTP_SL) {
                     CalculateDynamic_TP_SL("buy",positionSL, positionTP, CalculateDynamicTP_SL_Steps, CalculateDynamicTP_SL_Steps, 14);
                  } else {
                     if(FactorVolatilityIn_TP_SL_Calculation) {
                        positionTP = positionTP + positionTP * InpTakeProfitAdjustment + positionTP * volatility ;
                        positionSL = positionSL + positionSL * InpStopLossAdjustment   + positionSL * volatility ;
                     } else {
                        positionTP = positionTP + positionTP * InpTakeProfitAdjustment;
                        positionSL = positionSL + positionSL * InpStopLossAdjustment ;
                     }
                  }

                  PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " . Ticket's(%d) positionSL(%s) and positionTP(%s) prior to market speed adjustment.",positionTicket,positionSL,positionTP);

                  if(StrCompare(marketPatternSpeed,"Fast Uptrend")) {
                     positionTP = positionTP + positionTP/4;
                     positionSL = positionSL + positionSL/6;
                  } else if(StrCompare(marketPatternSpeed,"Slow Uptrend")) {
                     positionTP = positionTP + positionTP/8;
                     positionSL = positionSL + positionSL/10;
                  } else if(StrCompare(marketPatternSpeed,"Fast Downtrend")) {
                     positionSL = positionSL + positionSL/4;
                     closeBadDeal = true;
                  } else if(StrCompare(marketPatternSpeed,"Slow Downtrend")) {
                     positionSL = positionSL + positionSL/8;
                  }

                  PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " . Ticket's(%d) positionSL(%s) and positionTP(%s) post to market speed adjustment. MarketPatternSpeed(%s)",positionTicket,positionSL,positionTP,marketPatternSpeed);

                  if(closeBadDeal) {
                     if(trade.PositionClose(positionTicket)) {
                        //CountOpenTradesPerSession--;
                        DeleteDrawSLTP(_Symbol, positionTicket);
                        Print(__FUNCTION__+"-"+IntegerToString(__LINE__) + " > Closed a BAD BUY DEAL Pos #", positionTicket);
                        notification.SendEmailNotification("EA closed a bad BUY trade #" + IntegerToString(positionTicket), "");
                     }
                  } else if(trade.PositionModify(positionTicket,positionSL,positionTP)) {
                     Print(__FUNCTION__+"-"+IntegerToString(__LINE__) + " > BUY Pos #", positionTicket, "was modified. BAD Position.");
                  }
               }

            } else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {

               if(fastBuffer[1] > slowBuffer[1]) {          //Uptrend Market
                  PrintFormat(__FUNCTION__+"-"+IntegerToString(__LINE__) + " . Ticket(%d) is a sell order in a BAD position.",positionTicket);
                  if(CalculateDynamicTP_SL) {
                     CalculateDynamic_TP_SL("sell",positionSL, positionTP, CalculateDynamicTP_SL_Steps, CalculateDynamicTP_SL_Steps, 14);
                  } else {
                     if(FactorVolatilityIn_TP_SL_Calculation) {
                        positionSL = positionSL - positionSL * InpStopLossAdjustment   - positionSL * volatility;
                        positionTP = positionTP - positionTP * InpTakeProfitAdjustment - positionTP * volatility;
                     } else {
                        positionSL = positionSL - positionSL * InpStopLossAdjustment ;
                        positionTP = positionTP - positionTP * InpTakeProfitAdjustment;
                     }
                  }

                  PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " . Ticket's(%d) positionSL(%s) and positionTP(%s) prior to market speed adjustment.",positionTicket,positionSL,positionTP);

                  if(StrCompare(marketPatternSpeed,"Fast Uptrend")) {
                     closeBadDeal = true;
                  } else if(StrCompare(marketPatternSpeed,"Slow Uptrend")) {
                     positionTP = positionTP + positionTP/8;
                     positionSL = positionSL + positionSL/8;
                  } else if(StrCompare(marketPatternSpeed,"Fast Downtrend")) {
                     positionTP = positionTP - positionTP/4;
                     positionSL = positionSL - positionSL/4;
                  } else if(StrCompare(marketPatternSpeed,"Slow Downtrend")) {
                     positionTP = positionTP - positionTP/8;
                     positionSL = positionSL - positionSL/8;
                  }

                  PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " . Ticket's(%d) positionSL(%s) and positionTP(%s) post to market speed adjustment. MarketPatternSpeed(%s)",positionTicket,positionSL,positionTP,marketPatternSpeed);

                  if(closeBadDeal) {
                     if(trade.PositionClose(positionTicket)) {
                        //CountOpenTradesPerSession--;
                        DeleteDrawSLTP(_Symbol, positionTicket);
                        Print(__FUNCTION__+"-"+IntegerToString(__LINE__)+ " > CLOSED A BAD SELL Pos #%d", positionTicket);
                        notification.SendEmailNotification("EA closed a bad SELL trade #" + IntegerToString(positionTicket), "");
                     }
                  } else if(trade.PositionModify(positionTicket,positionSL,positionTP)) {
                     Print(__FUNCTION__+"-"+IntegerToString(__LINE__)+ " > SELL Pos #%d was modified. BAD Position.", positionTicket);
                  }
               } else if(fastBuffer[1] < slowBuffer[1]) {  //Downtrend Market
                  PrintFormat(__FUNCTION__+"-"+IntegerToString(__LINE__)+ " . Ticket(%d) is a sell order in a good position.",positionTicket);
                  if(CalculateDynamicTP_SL) {
                     CalculateDynamic_TP_SL("sell",positionSL, positionTP, CalculateDynamicTP_SL_Steps, CalculateDynamicTP_SL_Steps, 14);
                  } else {
                     if(FactorVolatilityIn_TP_SL_Calculation) {
                        positionSL = positionSL - positionSL * InpStopLossAdjustment   - positionSL * volatility;
                        positionTP = positionTP - positionTP * InpTakeProfitAdjustment - positionTP * volatility;
                     } else {
                        positionSL = positionSL - positionSL * InpStopLossAdjustment;
                        positionTP = positionTP - positionTP * InpTakeProfitAdjustment;
                     }
                  }

                  PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " . Ticket's(%d) positionSL(%s) and positionTP(%s) prior to market speed adjustment.",positionTicket,positionSL,positionTP);

                  if(StrCompare(marketPatternSpeed,"Fast Uptrend")) {
                     closeBadDeal = true;
                  } else if(StrCompare(marketPatternSpeed,"Slow Uptrend")) {
                     positionTP = positionTP + positionTP/8;
                     positionSL = positionSL + positionSL/8;
                  } else if(StrCompare(marketPatternSpeed,"Fast Downtrend")) {
                     positionTP = positionTP - positionTP/4;
                     positionSL = positionSL - positionSL/4;
                  } else if(StrCompare(marketPatternSpeed,"Slow Downtrend")) {
                     positionTP = positionTP - positionTP/8;
                     positionSL = positionSL - positionSL/8;
                  }

                  PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) + " . Ticket's(%d) positionSL(%s) and positionTP(%s) post to market speed adjustment. MarketPatternSpeed(%s)",positionTicket,positionSL,positionTP,marketPatternSpeed);

                  if(closeBadDeal) {
                     if(trade.PositionClose(positionTicket)) {
                        //CountOpenTradesPerSession--;
                        DeleteDrawSLTP(_Symbol, positionTicket);
                        Print(__FUNCTION__ +"-"+IntegerToString(__LINE__)+ " > CLOSE BAD SELL Pos #%d", positionTicket);
                        notification.SendEmailNotification("EA closed a bad SELL trade #" + IntegerToString(positionTicket), "");
                     }
                  } else if(trade.PositionModify(positionTicket,positionSL,positionTP)) {
                     Print(__FUNCTION__ +"-"+IntegerToString(__LINE__) + " > SELL Pos # %d was modified. GOOD Position.", positionTicket);
                  }
               }
            }
         } else {
            PrintFormat(__FUNCTION__+"-"+IntegerToString(__LINE__) + " . Failed to select ticket PositionSelectByTicket(%d)",positionTicket);
         }
      }
   } else {
      PrintFormat(__FUNCTION__+"-"+IntegerToString(__LINE__) + " . Price adjustment skiped because : barsTotalPriceAdjustment(%d) != bars(%d)",barsTotalPriceAdjustment,bars);
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
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"(InpFastPeriod<=0) InpFastPeriod= ", InpFastPeriod);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpSlowPeriod<=0) {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"(InpSlowPeriod<=0) InpSlowPeriod= ", InpSlowPeriod);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpFastPeriod >= InpSlowPeriod) {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"(InpFastPeriod >= InpSlowPeriod) InpFastPeriod= ", InpFastPeriod," InpSlowPeriod=", InpSlowPeriod);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpStopLoss <=0) {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"Stop loss is equal ", InpStopLoss);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpTakeProfit <=0) {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"Take Profit is equal ", InpTakeProfit);
      return INIT_PARAMETERS_INCORRECT;
   }

// Create handles.
   fastHandle = iMA(_Symbol,PERIOD_CURRENT,InpFastPeriod,0,MODE_SMA,PRICE_CLOSE);
   if(fastHandle == INVALID_HANDLE) {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"Failed to create fast handle.");
      return INIT_FAILED;
   }
   slowHandle = iMA(_Symbol,PERIOD_CURRENT,InpSlowPeriod,0,MODE_SMA,PRICE_CLOSE);
   if(slowHandle == INVALID_HANDLE) {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"Failed to create slow handle.");
      return INIT_FAILED;
   }

   int count = CopyBuffer(fastHandle,0,0,InpFastPeriod,fastBuffer);
   if(count != 8) {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" Not enough data for fast moving average");
   }
   count = CopyBuffer(slowHandle,0,0,InpSlowPeriod,slowBuffer);
   if(count != 8) {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" Not enough data for fast moving average");
   }

   ArraySetAsSeries(fastBuffer,true);
   ArraySetAsSeries(slowBuffer,true);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void UpdateMACrossoverBuffers() {
// Create handles.
   fastHandle = iMA(_Symbol,PERIOD_CURRENT,InpFastPeriod,0,MODE_SMA,PRICE_CLOSE);
   if(fastHandle == INVALID_HANDLE) {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"Failed to update fast handle.");
   }
   slowHandle = iMA(_Symbol,PERIOD_CURRENT,InpSlowPeriod,0,MODE_SMA,PRICE_CLOSE);
   if(slowHandle == INVALID_HANDLE) {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"Failed to update slow handle.");
   }
   int count = CopyBuffer(fastHandle,0,0,InpFastPeriod,fastBuffer);
   if(count != InpFastPeriod) {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" Not enough data for fast moving average");
   }
   count = CopyBuffer(slowHandle,0,0,InpSlowPeriod,slowBuffer);
   if(count != InpSlowPeriod) {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" Not enough data for fast moving average");
   }

   ArraySetAsSeries(fastBuffer,true);
   ArraySetAsSeries(slowBuffer,true);
}

//+------------------------------------------------------------------+
//|  MA Crossover Buy                                                |
//+------------------------------------------------------------------+
void MACrossoverBuy(color clr, string label) {
   double ask = NormalizeDouble(SymbolInfoDouble(_Symbol,SYMBOL_ASK), _Digits);
   double stopLoss = NormalizeDouble(ask - InpStopLoss * SymbolInfoDouble(_Symbol,SYMBOL_POINT), _Digits);
   double takeProfit = NormalizeDouble(ask + InpTakeProfit * SymbolInfoDouble(_Symbol,SYMBOL_POINT), _Digits);
   lastTradeTime = iTime(_Symbol,PERIOD_CURRENT,0);
   if(UseEAInAutoMode) {
      trade.SetExpertMagicNumber(InpMagicNumber);
   }
   if(trade.PositionOpen(_Symbol,ORDER_TYPE_BUY,lotSize,ask,stopLoss,takeProfit,"+MA Cross EA")) {
      string message = StringFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"I just bought a symbol(%s), ask(%.5f), stopLoss(%.5f), takeProfit(%.5f), lotSize(%.5f) ", _Symbol, ask,stopLoss,takeProfit,lotSize);
      PrintFormat(message);
      //CountOpenTradesPerSession++;
      createObject(iTime(_Symbol, PERIOD_CURRENT, 0), fastBuffer[0], 300,0, clr, label);
      if(UseEAInAutoMode) {
         notification.SendEmailNotification("EA-BUY -> " + message, message);
      } else {
         notification.SendEmailNotification("User(Trader)-BUY -> " + message, message);
      }
   } else {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"ERROR - Failed to buy a symbol(%s), ask(%.5f), stopLoss(%.5f), takeProfit(%.5f), lotSize(%.5f) ", _Symbol, ask,stopLoss,takeProfit,lotSize);
   }
}

//+------------------------------------------------------------------+
//| MA Crossover Sell                                                |
//+------------------------------------------------------------------+
void MACrossoverSell(color clr, string label) {
   double bid = NormalizeDouble(SymbolInfoDouble(_Symbol,SYMBOL_BID), _Digits);
   double stopLoss = NormalizeDouble(bid + InpStopLoss * SymbolInfoDouble(_Symbol,SYMBOL_POINT), _Digits);
   double takeProfit = NormalizeDouble(bid - InpTakeProfit * SymbolInfoDouble(_Symbol,SYMBOL_POINT), _Digits);
   lastTradeTime = iTime(_Symbol,PERIOD_CURRENT,0);
   if(UseEAInAutoMode) {
      trade.SetExpertMagicNumber(InpMagicNumber);
   }
   if(trade.PositionOpen(_Symbol,ORDER_TYPE_SELL,lotSize,bid,stopLoss,takeProfit,"-MA Cross EA")) {
      string message = StringFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"I just sold a symbol(%s), bid(%.5f), stopLoss(%.5f), takeProfit(%.5f), lotSize(%.5f) ", _Symbol, bid,stopLoss,takeProfit,lotSize);
      PrintFormat(message);
      //CountOpenTradesPerSession++;
      createObject(iTime(_Symbol, PERIOD_CURRENT, 0), fastBuffer[0], 300,0, clr, label);

      if(UseEAInAutoMode) {
         notification.SendEmailNotification("EA-SELL -> " + message, message);
      } else {
         notification.SendEmailNotification("User(Trader)-SELL -> " + message, message);
      }

   } else {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"ERROR - Failed to sell a symbol(%s), bid(%.5f), stopLoss(%.5f), takeProfit(%.5f), lotSize(%.5f) ", _Symbol, bid,stopLoss,takeProfit,lotSize);
   }
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void validateIndicatorDetails() {
// Get indicator values.
   int count = CopyBuffer(fastHandle,0,0,8,fastBuffer);
   if(count != 8) {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" Not enough data for fast moving average");
   }
   count = CopyBuffer(slowHandle,0,0,8,slowBuffer);
   if(count != 8) {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +" Not enough data for slow moving average");
   }

//Comment("fast[0]:",fastBuffer[0],"\n", "fast[1]:",fastBuffer[1],"\n", "slow[0]:",slowBuffer[0],"\n", "slow[1]:",slowBuffer[1],"\n");
}
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//|  Function to measure market volatility                           |
//+------------------------------------------------------------------+
double GetMarketVolatility(int period = 14) {
// Handle for ATR indicator
   int atrHandle = iATR(_Symbol, PERIOD_CURRENT, period);

   if(atrHandle == INVALID_HANDLE) {
      Print("Error creating ATR handle!");
      return -1;
   }

   double atrValue[]; // Array to store ATR values

// Copy the latest ATR value (0 = most recent candle)
   if(!CopyBuffer(atrHandle, 0, 0, 1, atrValue)) {
      Print("Error copying ATR values!");
      IndicatorRelease(atrHandle); // Free indicator handle
      return -1;
   }

   IndicatorRelease(atrHandle); // Free indicator handle to avoid memory leaks
   return atrValue[0]; // Return the latest ATR value
}

//+------------------------------------------------------------------+
//| Alternative: Calculate high-low range over N candles             |
//+------------------------------------------------------------------+
double GetHighLowVolatility(int period = 14) {
   double highestHigh = iHigh(_Symbol, PERIOD_CURRENT, 0);
   double lowestLow   =  iLow(_Symbol, PERIOD_CURRENT, 0);

   for(int i = 1; i < period; i++) {
      double high = iHigh(_Symbol, PERIOD_CURRENT, i);
      double low  =  iLow(_Symbol, PERIOD_CURRENT, i);

      if(high > highestHigh)
         highestHigh = high;
      if(low  < lowestLow)
         lowestLow   = low;
   }

   return highestHigh - lowestLow; // Volatility range in pips
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Function to calculate ATR-based TP & SL                          |
//+------------------------------------------------------------------+
void CalculateDynamic_TP_SL(const string positionType, double &stopLoss, double &takeProfit, double slMultiplier = 2, double tpMultiplier = 3, int atrPeriod = 14) {
   int atrHandle = iATR(_Symbol, PERIOD_CURRENT, atrPeriod);
   if(atrHandle == INVALID_HANDLE)
      return;

   double atrValue[];
   if(!CopyBuffer(atrHandle, 0, 0, 1, atrValue)) {
      IndicatorRelease(atrHandle);
      return;
   }

   IndicatorRelease(atrHandle);

// Dynamic TP & SL based on ATR
   if(FactorVolatilityIn_TP_SL_Calculation) {
      if(positionType=="buy") {
         stopLoss   = stopLoss   + stopLoss   * atrValue[0] * slMultiplier + stopLoss * volatility;
         takeProfit = takeProfit + takeProfit * atrValue[0] * tpMultiplier + takeProfit * volatility;
         PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"-"," BUY  - stopLoss(%0.5f), takeProfit(%0.5f)",stopLoss,takeProfit);
      } else if(positionType=="sell") {
         stopLoss   = stopLoss   - stopLoss   * atrValue[0] * slMultiplier - stopLoss * volatility;
         takeProfit = takeProfit - takeProfit * atrValue[0] * tpMultiplier - takeProfit * volatility;
         PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"-"," SELL - stopLoss(%0.5f), takeProfit(%0.5f)",stopLoss,takeProfit);
      }
   } else {
      if(positionType=="buy") {
         stopLoss   = stopLoss   + stopLoss   * atrValue[0] * slMultiplier ;
         takeProfit = takeProfit + takeProfit * atrValue[0] * tpMultiplier ;
         PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"-"," BUY  - stopLoss(%0.5f), takeProfit(%0.5f)",stopLoss,takeProfit);
      } else if(positionType=="sell") {
         stopLoss   = stopLoss   - stopLoss   * atrValue[0] * slMultiplier ;
         takeProfit = takeProfit - takeProfit * atrValue[0] * tpMultiplier ;
         PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"-"," SELL - stopLoss(%0.5f), takeProfit(%0.5f)",stopLoss,takeProfit);
      }
   }
}

//+------------------------------------------------------------------+
//| Function to print stats of a specific position in MetaTrader 5  |
//+------------------------------------------------------------------+
void PrintPositionStats(ulong position_ticket) {
// Retrieve position details
   if(PositionSelectByTicket(position_ticket)) {
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
   } else {
      Print(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"- Error: Position with ticket " + IntegerToString(position_ticket) + " not found.");
   }
}
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//| Function to check trade result                                   |
//+------------------------------------------------------------------+
void CheckTradeResult(const MqlTradeResult &result) {
   PrintFormat("Trade result code: %d", result.retcode);
   if(result.retcode == TRADE_RETCODE_DONE) {  // Trade executed successfully
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"-","Trade executed successfully.");
      if(result.deal > 0) {
         PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"-","Deal ticket: %dlu", result.deal);
      } else {
         Print(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"-","Warning: No valid deal ticket returned!");
      }
   } else {
      PrintFormat(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"-","Trade execution failed. Error code: %d", result.retcode);
      //CountOpenTradesPerSession--;
   }
}

//+------------------------------------------------------------------+
//| Function to detect the speed of price movement                   |
//+------------------------------------------------------------------+
string DetectTrendSpeed(int period = 3) {
   double priceArray[];

// Get closing prices for the given period
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, period, priceArray) < period) {
      Print(__FUNCTION__ + "-" + IntegerToString(__LINE__) +"-","Error: Not enough data available.");
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
      PrintFormat("***********"+__FUNCTION__ + "-" + IntegerToString(__LINE__) +"-" + "slope(%0.7f) - Fast Uptrend - fastThreshold(%0.7f)", slope, fastThreshold);
      return "Fast Uptrend";
   } else if(slope > slowThreshold) {
      PrintFormat("***********"+__FUNCTION__ + "-" + IntegerToString(__LINE__) +"-" + "slope(%0.7f) - Slow Uptrend - fastThreshold(%0.7f)", slope, slowThreshold);
      return "Slow Uptrend️";
   } else if(slope < -fastThreshold) {
      PrintFormat("***********"+__FUNCTION__ + "-" + IntegerToString(__LINE__) +"-" + "slope(%0.7f) - Fast Downtrend - -fastThreshold(%0.7f)", slope, -fastThreshold);
      return "Fast Downtrend";
   } else if(slope < -slowThreshold) {
      PrintFormat("***********"+__FUNCTION__ + "-" + IntegerToString(__LINE__) +"-" + "slope(%0.7f) - Slow Downtrend - -slowThreshold(%0.7f)", slope, -slowThreshold);
      return "Slow Downtrend️";
   } else {
      PrintFormat("***********"+__FUNCTION__ + "-" + IntegerToString(__LINE__) +"-" + "slope(%0.7f) - Sideways Market ➡ - slowThreshold(%0.7f) - fastThreshold(%0.7f)", slope, slowThreshold, fastThreshold);
      return "Sideways Market️";
   }
}


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void createObject(datetime time, double price, int arrowCode,int direction, color clr, string txt) {
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
   string objName = StringFormat("Signal@%s_at%.%df_(%d)",
                                 TimeToString(time, TIME_MINUTES),
                                 _Digits, price, arrowCode);

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
//|                                                                  |
//+------------------------------------------------------------------+
bool StrCompare(string a, string b) {
   return StringCompare(a,b) == 0 ? true : false;
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| FETCH NEWS                                                       |
//+------------------------------------------------------------------+
bool FetchMyfxbookNews() {
   string url = "https://www.myfxbook.com/api/get-economic-calendar.json?session=" + SessionID;
   char post[];
   char result[];
   string headers;

   ResetLastError();
   int timeout = 5000;
   int res = WebRequest("GET", url, headers, timeout, post, result, headers);

   if(res != 200) {
      Print("WebRequest failed: ", GetLastError());
      string resError = StringFormat("GetLastError()=%d , res=%d , url=%s",GetLastError(),res,url );
      MessageBox(resError, "WebRequest Error", MB_ICONERROR);
      MessageBox("Please enable WebRequest for 'www.myfxbook.com' in MT5 settings.", "WebRequest Error", MB_ICONERROR);
      notification.SendEmailNotification("Function FetchMyfxbookNews is not working.","Please investigate why the FetchMyfxbookNews function is not working." );
      return false;
   }

   string body = CharArrayToString(result);
   ParseNews(body);
   return true;
}

//+------------------------------------------------------------------+
//| PARSE NEWS JSON                                                  |
//+------------------------------------------------------------------+
void ParseNews(string json) {
   newsCount = 0;
   datetime now = TimeCurrent();
   datetime future = now + HoursAhead * 3600;

   int i = StringFind(json, "{\"calendar\"");
   if(i < 0)
      return;

   int pos = 0;
   while((pos = StringFind(json, "\"title\"", pos)) > 0 && newsCount < 100) {
      string title = ExtractField(json, "\"title\"", pos);
      string currency = ExtractField(json, "\"currency\"", pos);
      string impact = ExtractField(json, "\"impact\"", pos);
      string dateStr = ExtractField(json, "\"date\"", pos);
      string timeStr = ExtractField(json, "\"time\"", pos);
      datetime dt = StringToTime(dateStr + " " + timeStr);

      if(dt < now || dt > future)
         continue;
      if(StringLen(NewsCurrency) > 0 && NewsCurrency != currency)
         continue;
      if(HighImpactOnly && StringFind(impact, "High") == -1)
         continue;

      newsList[newsCount].time     = dt;
      newsList[newsCount].title    = title;
      newsList[newsCount].currency = currency;
      newsList[newsCount].impact   = impact;
      newsList[newsCount].alerted  = false;

      DrawNewsOnChart(newsCount);
      newsCount++;
   }
}

//+------------------------------------------------------------------+
//| HELPER: EXTRACT JSON FIELD                                       |
//+------------------------------------------------------------------+
string ExtractField(string json, string field, int &start) {
   int key = StringFind(json, field, start);
   if(key == -1)
      return "";
   int colon = StringFind(json, ":", key);
   int q1 = StringFind(json, "\"", colon + 1);
   int q2 = StringFind(json, "\"", q1 + 1);
   start = q2;
   return StringSubstr(json, q1 + 1, q2 - q1 - 1);
}

//+------------------------------------------------------------------+
//| DRAW EVENT LINE + LABEL                                          |
//+------------------------------------------------------------------+
void DrawNewsOnChart(int index) {
   NewsEvent ev = newsList[index];
   string line = "MyfxNewsLine_" + IntegerToString(index);
   string label = "MyfxNewsLabel_" + IntegerToString(index);

   ObjectCreate(0, line, OBJ_VLINE, 0, ev.time, 0);
   ObjectSetInteger(0, line, OBJPROP_COLOR, clrOrange);

   ObjectCreate(0, label, OBJ_TEXT, 0, ev.time, 0);
   ObjectSetInteger(0, label, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, label, OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, label, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, label, OBJPROP_TEXT, ev.currency + " " + ev.title);
}

//+------------------------------------------------------------------+
//| CLEAR EXISTING OBJECTS                                           |
//+------------------------------------------------------------------+
void ClearOldNewsObjects() {
   for(int i = 0; i < newsCount; i++) {
      ObjectDelete(0, "MyfxNewsLine_" + IntegerToString(i));
      ObjectDelete(0, "MyfxNewsLabel_" + IntegerToString(i));
   }
   newsCount = 0;
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
//| UPDATE LAST UPDATED LABEL                                        |
//+------------------------------------------------------------------+
void UpdateLastUpdatedLabel() {
   datetime now = TimeCurrent();
   string timeStr = TimeToString(now, TIME_DATE | TIME_MINUTES);
   string labelText = "🕒 Last Updated: " + timeStr;

   if(!ObjectCreate(0, "LastUpdatedLabel", OBJ_LABEL, 0, 0, 0))
      ObjectCreate(0, "LastUpdatedLabel", OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, "LastUpdatedLabel", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, "LastUpdatedLabel", OBJPROP_XDISTANCE, 300);
   ObjectSetInteger(0, "LastUpdatedLabel", OBJPROP_YDISTANCE, 30);
   ObjectSetInteger(0, "LastUpdatedLabel", OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, "LastUpdatedLabel", OBJPROP_COLOR, clrSilver);
   ObjectSetString(0, "LastUpdatedLabel", OBJPROP_TEXT, labelText);
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Chart Event Handler                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   if(id == CHARTEVENT_OBJECT_CLICK) {

      if(sparam == "btnBuy") {
         Print(__FUNCTION__+"-"+IntegerToString(__LINE__)+ " > BUTTON btnBuy was clicked.");
         MACrossoverBuy(clrGreenYellow, "Manual Buy");
      } else if(sparam == "btnSell") {
         Print(__FUNCTION__+"-"+IntegerToString(__LINE__)+ " > BUTTON btnSell was clicked.");
         MACrossoverSell(clrRed, "Manual Sell");
      } else if(sparam == "btnCloseMBuy") {
         Print(__FUNCTION__+"-"+IntegerToString(__LINE__)+ " > BUTTON btnCloseMBuy was clicked.");
         closeAllBuyOpenTrades_TrendFinished(true);
      } else if(sparam == "btnCloseMSell") {
         Print(__FUNCTION__+"-"+IntegerToString(__LINE__)+ " > BUTTON btnCloseMSell was clicked.");
         closeAllSellOpenTrades_TrendFinished(true);
      } else if(sparam == "btnCloseAMAll") {
         Print(__FUNCTION__+"-"+IntegerToString(__LINE__)+ " > BUTTON btnCloseAMAll was clicked.");
         closeAllOpenTrades();
      } else if(sparam == "btnAdjustSLTPUP") {
         Print(__FUNCTION__+"-"+IntegerToString(__LINE__)+ " > BUTTON btnAdjustSLTPUP was clicked.");
         maximiseProfits();
      } else if(sparam == "btnAdjustSLTPDown") {
         Print(__FUNCTION__+"-"+IntegerToString(__LINE__)+ " > BUTTON btnAdjustSLTPDown was clicked.");
         minimiseLosses();
      } else if(sparam == "btnRefreshNews") {
         Print(__FUNCTION__+"-"+IntegerToString(__LINE__)+ " > BUTTON btnRefreshNews was clicked.");
         ClearOldNewsObjects();
         FetchMyfxbookNews();
         UpdateLastUpdatedLabel();
      }
   }
}

//+------------------------------------------------------------------+
//| Maximise Profits                                                 |
//+------------------------------------------------------------------+
void maximiseProfits() {

   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong positionTicket = PositionGetTicket(i);
      if(PositionSelectByTicket(positionTicket)) {
         double positionSL = NormalizeDouble(PositionGetDouble(POSITION_SL), _Digits);
         double positionTP = NormalizeDouble(PositionGetDouble(POSITION_TP), _Digits);

         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
            if(CalculateDynamicTP_SL) {
               CalculateDynamic_TP_SL("buy",positionSL, positionTP, CalculateDynamicTP_SL_Steps, CalculateDynamicTP_SL_Steps, 14);
            } else {
               if(FactorVolatilityIn_TP_SL_Calculation) {
                  positionSL = positionSL + positionSL * InpStopLossAdjustment   + positionSL * volatility ;
                  positionTP = positionTP + positionTP * InpTakeProfitAdjustment + positionTP * volatility ;
               } else {
                  positionSL = positionSL + positionSL * InpStopLossAdjustment   ;
                  positionTP = positionTP + positionTP * InpTakeProfitAdjustment ;
               }
            }
            if(trade.PositionModify(positionTicket,NormalizeDouble(PositionGetDouble(POSITION_SL), _Digits),positionTP)) {
               PrintFormat(__FUNCTION__ +"-"+IntegerToString(__LINE__)+ " > BUY Pos #%d was modified. GOOD Position.", positionTicket);
            }

         } else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
            if(CalculateDynamicTP_SL) {
               CalculateDynamic_TP_SL("sell",positionSL, positionTP, CalculateDynamicTP_SL_Steps, CalculateDynamicTP_SL_Steps, 14);
            } else {
               if(FactorVolatilityIn_TP_SL_Calculation) {
                  positionSL = positionSL - positionSL * InpStopLossAdjustment   - positionSL * volatility;
                  positionTP = positionTP - positionTP * InpTakeProfitAdjustment - positionTP * volatility;
               } else {
                  positionSL = positionSL - positionSL * InpStopLossAdjustment ;
                  positionTP = positionTP - positionTP * InpTakeProfitAdjustment;
               }
            }
            if(trade.PositionModify(positionTicket,NormalizeDouble(PositionGetDouble(POSITION_SL), _Digits),positionTP)) {
               Print(__FUNCTION__+"-"+IntegerToString(__LINE__)+ " > SELL Pos #%d was modified. BAD Position.", positionTicket);
            }
         }

      }
   }
}
//+------------------------------------------------------------------+
//| Maximise Losses                                                  |
//+------------------------------------------------------------------+
void minimiseLosses() {

   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong positionTicket = PositionGetTicket(i);
      if(PositionSelectByTicket(positionTicket)) {
         double positionSL = NormalizeDouble(PositionGetDouble(POSITION_SL), _Digits);
         double positionTP = NormalizeDouble(PositionGetDouble(POSITION_TP), _Digits);

         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
            if(CalculateDynamicTP_SL) {
               CalculateDynamic_TP_SL("buy",positionSL, positionTP, CalculateDynamicTP_SL_Steps, CalculateDynamicTP_SL_Steps, 14);
            } else {
               if(FactorVolatilityIn_TP_SL_Calculation) {
                  positionSL = positionSL + positionSL * InpStopLossAdjustment   + positionSL * volatility ;
                  positionTP = positionTP + positionTP * InpTakeProfitAdjustment + positionTP * volatility ;
               } else {
                  positionSL = positionSL + positionSL * InpStopLossAdjustment   ;
                  positionTP = positionTP + positionTP * InpTakeProfitAdjustment ;
               }
            }
            if(trade.PositionModify(positionTicket,positionSL,NormalizeDouble(PositionGetDouble(POSITION_TP), _Digits))) {
               PrintFormat(__FUNCTION__ +"-"+IntegerToString(__LINE__)+ " > BUY Pos #%d was modified. GOOD Position.", positionTicket);
            }

         } else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
            if(CalculateDynamicTP_SL) {
               CalculateDynamic_TP_SL("sell",positionSL, positionTP, CalculateDynamicTP_SL_Steps, CalculateDynamicTP_SL_Steps, 14);
            } else {
               if(FactorVolatilityIn_TP_SL_Calculation) {
                  positionSL = positionSL - positionSL * InpStopLossAdjustment   - positionSL * volatility;
                  positionTP = positionTP - positionTP * InpTakeProfitAdjustment - positionTP * volatility;
               } else {
                  positionSL = positionSL - positionSL * InpStopLossAdjustment ;
                  positionTP = positionTP - positionTP * InpTakeProfitAdjustment;
               }
            }
            if(trade.PositionModify(positionTicket,positionSL,NormalizeDouble(PositionGetDouble(POSITION_TP), _Digits))) {
               Print(__FUNCTION__+"-"+IntegerToString(__LINE__)+ " > SELL Pos #%d was modified. BAD Position.", positionTicket);
            }
         }
      }
   }
}


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string MyfxbookLogin() {
   string url = StringFormat(
                   "https://www.myfxbook.com/api/login.json?email=%s&password=%s",
                   email, password
                );

   char post_data[];                     // Empty for GET
   char result[];                        // Response will be stored here
   string result_headers = "";          // Store response headers here
   string session_id = "";
   int timeout = 5000;

   ResetLastError();

   int response = WebRequest(
                     "GET",
                     url,
                     "",
                     timeout,
                     post_data,
                     result,
                     result_headers
                  );

   if(response == -1) {
      Print("WebRequest failed. Error: ", GetLastError());
      return "";
   }

   string json = CharArrayToString(result);
   Print("Raw JSON response: ", json);

// Simple JSON parsing to extract session ID
   int start = StringFind(json, "\"session\":\"");
   if(start >= 0) {
      start += StringLen("\"session\":\"");
      int end = StringFind(json, "\"", start);
      if(end > start) {
         session_id = StringSubstr(json, start, end - start);
         Print("Myfxbook Session ID: ", session_id);
      }
   } else {
      Print("Session ID not found in JSON.");
   }

   return session_id;
}

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Draws a moving average line on the chart                        |
//| Parameters:                                                     |
//|   maHandle     - handle of the MA indicator                     |
//|   objectName   - name of the object to draw                     |
//|   lineColor    - color of the line                              |
//|   barsToDraw   - how many bars of MA to draw                    |
//+------------------------------------------------------------------+
void DrawMA_Segments(int maHandle, string prefix, color lineColor, int barsToDraw) {
   if (maHandle == INVALID_HANDLE) {
      Print("Invalid MA handle");
      return;
   }

   double maBuffer[];
   datetime timeBuffer[];

   if (CopyBuffer(maHandle, 0, 0, barsToDraw + 1, maBuffer) <= 0 ||
         CopyTime(_Symbol, _Period, 0, barsToDraw + 1, timeBuffer) <= 0) {
      Print("Failed to copy MA or time data");
      return;
   }

// Delete old segments
   for (int i = 0; i < barsToDraw; i++)
      ObjectDelete(0, prefix + IntegerToString(i));

// Draw lines between points
   for (int i = 0; i < barsToDraw; i++) {
      string objName = prefix + IntegerToString(i);
      if (!ObjectCreate(0, objName, OBJ_TREND, 0, timeBuffer[i], maBuffer[i], timeBuffer[i+1], maBuffer[i+1])) {
         Print("Failed to create object: ", objName);
         continue;
      }

      ObjectSetInteger(0, objName, OBJPROP_COLOR, lineColor);
      ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
   }
}
//+------------------------------------------------------------------+

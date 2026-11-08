
#property strict
#property version "1.00"
#property description "GoldScalper EA - Low Risk"

#include <Trade/Trade.mqh>
CTrade trade;

//---- INPUT SETTINGS
input double RiskPercent = 0.5;
input int FastEMA = 9;
input int SlowEMA = 21;
input int StopLossPoints = 300;
input int TakeProfitPoints = 450;
input int MaxSpreadPoints = 80;
input double MaxFloatingLoss = 3.0;
input ulong MagicNumber = 20261108;

//---- VARIABLES
int fastHandle;
int slowHandle;
datetime lastBarTime = 0;

//---- INITIALIZATION
int OnInit()
{
   if(FastEMA <= 0 || SlowEMA <= FastEMA)
      return INIT_PARAMETERS_INCORRECT;

   fastHandle = iMA(_Symbol, PERIOD_M5,
                    FastEMA, 0, MODE_EMA, PRICE_CLOSE);

   slowHandle = iMA(_Symbol, PERIOD_M5,
                    SlowEMA, 0, MODE_EMA, PRICE_CLOSE);

   if(fastHandle == INVALID_HANDLE ||
      slowHandle == INVALID_HANDLE)
      return INIT_FAILED;

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(20);

   Print("GoldScalper EA initialized");

   return INIT_SUCCEEDED;
}

//---- RELEASE INDICATORS
void OnDeinit(const int reason)
{
   IndicatorRelease(fastHandle);
   IndicatorRelease(slowHandle);
}

//---- CHECK EXISTING POSITION
bool HasPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            return true;
      }
   }

   return false;
}

//---- FLOATING LOSS PROTECTION
void CheckFloatingLoss()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            double profit =
               PositionGetDouble(POSITION_PROFIT) +
               PositionGetDouble(POSITION_SWAP);

            if(profit <= -MaxFloatingLoss)
            {
               trade.PositionClose(ticket);
               Print("Floating-loss protection activated");
            }
         }
      }
   }
}

//---- CALCULATE SAFE LOT SIZE
double CalculateLotSize()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * RiskPercent / 100.0;

   double tickValue =
      SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   double tickSize =
      SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   double minLot =
      SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double maxLot =
      SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   double lotStep =
      SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(tickValue <= 0 || tickSize <= 0 ||
      point <= 0 || lotStep <= 0)
      return 0;

   double lossPerLot =
      (StopLossPoints * point / tickSize) * tickValue;

   if(lossPerLot <= 0)
      return 0;

   double lot = riskMoney / lossPerLot;

   // Minimum-lot protection:
   // Do not force a larger lot if risk is too high.
   if(lot < minLot)
      return 0;

   lot = MathFloor(lot / lotStep) * lotStep;

   lot = MathMin(lot, maxLot);

   return NormalizeDouble(lot, 8);
}

//---- CHECK NEW CANDLE
bool IsNewBar()
{
   datetime currentBar = iTime(_Symbol, PERIOD_M5, 0);

   if(currentBar != lastBarTime)
   {
      lastBarTime = currentBar;
      return true;
   }

   return false;
}

//---- MAIN TRADING LOGIC
void OnTick()
{
   CheckFloatingLoss();

   // Only trade Gold symbols
   if(StringFind(_Symbol, "XAU") < 0)
      return;

   // Spread protection
   double spread =
      (SymbolInfoDouble(_Symbol, SYMBOL_ASK) -
       SymbolInfoDouble(_Symbol, SYMBOL_BID)) /
       SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(spread > MaxSpreadPoints)
      return;

   // One position at a time
   if(HasPosition())
      return;

   // Trade only once per new M5 candle
   if(!IsNewBar())
      return;

   double fast[3];
   double slow[3];

   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);

   if(CopyBuffer(fastHandle, 0, 0, 3, fast) < 3)
      return;

   if(CopyBuffer(slowHandle, 0, 0, 3, slow) < 3)
      return;

   double lot = CalculateLotSize();

   if(lot <= 0)
   {
      Print("Lot too small for risk settings. No trade.");
      return;
   }

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // BUY signal: fast EMA crosses above slow EMA
   if(fast[2] <= slow[2] && fast[1] > slow[1])
   {
      double sl = ask - StopLossPoints * point;
      double tp = ask + TakeProfitPoints * point;

      trade.Buy(lot, _Symbol, ask, sl, tp, "GoldScalper Buy");
   }

   // SELL signal: fast EMA crosses below slow EMA
   if(fast[2] >= slow[2] && fast[1] < slow[1])
   {
      double sl = bid + StopLossPoints * point;
      double tp = bid - TakeProfitPoints * point;

      trade.Sell(lot, _Symbol, bid, sl, tp, "GoldScalper Sell");
   }
}

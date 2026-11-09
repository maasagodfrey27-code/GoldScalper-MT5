
#property strict
#include <Trade/Trade.mqh>

CTrade trade;

input double LotSize = 0.01;
input int StopLossPoints = 300;
input int TakeProfitPoints = 450;
input int MaxSpreadPoints = 60;
input double MaxFloatingLoss = 5.0;
input int FastMA = 9;
input int SlowMA = 21;
input ulong MagicNumber = 20261109;

int fastHandle;
int slowHandle;
datetime lastBar = 0;

// Initialize EA
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);

   fastHandle = iMA(_Symbol, PERIOD_M5,
                    FastMA, 0, MODE_EMA, PRICE_CLOSE);

   slowHandle = iMA(_Symbol, PERIOD_M5,
                    SlowMA, 0, MODE_EMA, PRICE_CLOSE);

   if(fastHandle == INVALID_HANDLE ||
      slowHandle == INVALID_HANDLE)
      return INIT_FAILED;

   return INIT_SUCCEEDED;
}

// Check open GoldScalper positions
bool HasPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket > 0 &&
         PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         return true;
   }

   return false;
}

// Protect against excessive floating loss
void CheckFloatingLoss()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket > 0 &&
         PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         double loss = PositionGetDouble(POSITION_PROFIT);

         if(loss <= -MaxFloatingLoss)
            trade.PositionClose(ticket);
      }
   }
}

// Main trading rules
void OnTick()
{
   CheckFloatingLoss();

   if(_Symbol != "XAUUSD")
      return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   double spread = (ask - bid) / point;

   if(spread > MaxSpreadPoints)
      return;

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   if(LotSize < minLot)
      return;

   if(HasPosition())
      return;

   datetime currentBar = iTime(_Symbol, PERIOD_M5, 0);

   if(currentBar == lastBar)
      return;

   double fast[];
   double slow[];

   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);

   if(CopyBuffer(fastHandle, 0, 0, 3, fast) < 3)
      return;

   if(CopyBuffer(slowHandle, 0, 0, 3, slow) < 3)
      return;

   lastBar = currentBar;

   // Buy signal
   if(fast[2] <= slow[2] && fast[1] > slow[1])
   {
      double sl = ask - StopLossPoints * point;
      double tp = ask + TakeProfitPoints * point;

      trade.Buy(LotSize, _Symbol, ask, sl, tp,
                "GoldScalper Buy");
   }

   // Sell signal
   if(fast[2] >= slow[2] && fast[1] < slow[1])
   {
      double sl = bid + StopLossPoints * point;
      double tp = bid - TakeProfitPoints * point;

      trade.Sell(LotSize, _Symbol, bid, sl, tp,
                 "GoldScalper Sell");
   }
}

// Release indicators
void OnDeinit(const int reason)
{
   IndicatorRelease(fastHandle);
   IndicatorRelease(slowHandle);
}


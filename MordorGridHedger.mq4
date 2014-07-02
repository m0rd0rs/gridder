/*
+------------------------------------------------------------------+
|                                                                  |
|                                     Mordor's Multiple Hedging EA |
|                                                      Version 0.1 |
|                                 Copyright © 2013 Stoill Barzakov |
|                                             http://www.m0rd0r.eu |
|                                                                  |
+------------------------------------------------------------------+
|                                                                  |
|  Drop on any timeline or currency pair                           |
|                                                                  |
|  This EA does not make difference between 1m or 30m              |
|                                                                  |
|  It works on any time frame                                      |
|                                                                  |
|  By default - it will not autoclose after successfull trade      |
|  If you want it to stop - set CloseAfterSuccess = true           |
|                                                                  |
+------------------------------------------------------------------+
*/

// necessary header files for EA autoclose and standard errors.
#include <WinUser32.mqh>       
#include <stdlib.mqh>

// Some useless properties, MQH files above will overwrite them.
#property copyright "Stoill Barzakov"
#property      link "www.m0rd0r.eu"

// define retries, delays and other constants.
#define		COMMIT_RETRIES		10
#define		COMMIT_DELAY		500
#define		LONG			1
#define		SHORT			-1
#define		ALL			0

// Globals
extern   bool	CloseAfterSuccess	=  true;	// Remove the EA from the chart after successfull profit is taken.
extern   bool	GrabAndRun		=  true;	// If All open positions profit is bigger than GrabAndRunTarget - close all.
extern   bool	AggresiveHedge		=  true;	// Will hedge the opposite ammount of lots minus the already open lots.
							// e.g. If you have 6 longs and 1 short, this will open next order x5
extern   int	MagicNumber		=  4400;	// Pazardjik's postal code in Bulgaria :P
extern   double	GrabAndRunTarget	=  2; 		// In base account currency. Can be a fraction like 0.3 (e.g. 30 EURO cents)
extern   double	InitialLots		=  0.01;	// This will be multiplied if necessary
extern   int	PipsPerStep		=  25;		// This will establish the distance between each step.
extern   double	DailyTarget		=  100;		// Stop trading if reached. EUR 100 per day is quite good achievement for now.

extern   bool	LogMessages		=  true;

// Some temp params needed to be globals as well.
int		Slippage 		=  3;		// 3 is not always acceptable, but will do in stronger trends.
int		handle;
bool		successfullTrade	=  false;
bool            check;

// Order count
double
		lots_Long,
		lots_Short;
int
		orders_Long,
		orders_Short;

// More temp params.
double 		totalPL,
		totalSwap,
		order_minimal,
		order_maximal;

int init() {

	return(0);
}

int deinit() { return(0); }

int start() { 

	double lots = InitialLots;
	double longDelta, shortDelta;
	double longPipDistance, shortPipDistance;
	
	double currentPrice = MarketInfo(Symbol(),MODE_BID);
	int orders_Total = CountOrders();

	// Check if we are just starting and place positions
	if( orders_Total == 0) {
      
		check = CreatePendingOrders(LONG, OP_BUY, Ask, lots, 0, 0, ""); // rewrite this function!!!~
		check = CreatePendingOrders(SHORT, OP_SELL, Bid, lots, 0, 0, "");
	}

	orders_Total = CountOrders();
	
	if( orders_Total > 0) {
		longDelta = (currentPrice - order_maximal);
		shortDelta = (order_minimal - currentPrice);
		longPipDistance = longDelta * 10000;
		shortPipDistance = shortDelta * 10000;
		if (longPipDistance > PipsPerStep) {
			if (AggresiveHedge == true) {lots = lots_Short;}
			check = CreatePendingOrders(LONG, OP_BUY, Ask, lots, 0, 0, ""); 
		}
		if (shortPipDistance > PipsPerStep) {
			if (AggresiveHedge == true) {lots = lots_Long;}
			check = CreatePendingOrders(SHORT, OP_SELL, Bid, lots, 0, 0, "");
		}
	}
	
	// Target reached, close profit and restart or close
	if( GrabAndRun == true && (GetCurrentPL () >= GrabAndRunTarget )) {

		while (orders_Total > 0) {
			ExitAll( LONG );
			ExitAll( SHORT );
			orders_Total = CountOrders();
		}

		// We are done for this whole lot of open positions :)
		PlaySound("alert.wav");
		if (CloseAfterSuccess == true) {PostMessageA( WindowHandle( Symbol(), Period()), WM_COMMAND, 33050, 0);}
	}

	// Show what's open and what is the profit in the top-left corner.
	if (LogMessages) {
		longDelta = (currentPrice - order_maximal);
		shortDelta = (order_minimal - currentPrice);
		string info = 
			"Broker: " + AccountCompany() +
			"\nTotal long orders:" + orders_Long +
			"\nLong order lots:" + lots_Long +
			"\nHighest long:" + order_maximal +
			"\nDelta long:" + longDelta +
			"\nTotal short orders:" + orders_Short +
			"\nShort order lots:" + lots_Short +
			"\nLowest short:" + order_minimal +
			"\nDelta short:" + shortDelta +
			"\nTotal profit:" + DoubleToStr(totalPL, 2) +
			"\nTotal Swap:" + DoubleToStr(totalSwap, 2);
		Comment (info);
		//Print (info);
	}
	Sleep(5000);
        return (0);
}

int CountOrders() {

	int count = 0;
	totalPL = 0;
	totalSwap = 0;
	orders_Short = 0;
	orders_Long = 0;
	lots_Long = 0;
	lots_Short = 0;
	order_minimal = 9999.9;
	order_maximal = 0;
  
	for( int i = OrdersTotal() - 1; i >= 0; i--) {
	
		check = OrderSelect( i, SELECT_BY_POS);
		
		if( OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber ) {
		
			count++;
			totalPL += OrderProfit();

			if( OrderType() == OP_BUY ) { 
				orders_Long++;
				lots_Long += OrderLots();
				if (OrderOpenPrice()  > order_maximal) {
					order_maximal = OrderOpenPrice();
				}
			}
			if( OrderType() == OP_SELL ) {
				orders_Short++;
				lots_Short += OrderLots();
				if (OrderOpenPrice()  < order_minimal) {
					order_minimal = OrderOpenPrice();
				}
			}
		}
	}
	totalSwap = GetCurrentSwap();
	return( count );
}

double CheckLots(double lots)
{
	double lot, lotmin, lotmax, lotstep, margin;
    
	lotmin = MarketInfo(Symbol(), MODE_MINLOT);
	lotmax = MarketInfo(Symbol(), MODE_MAXLOT);
	lotstep = MarketInfo(Symbol(), MODE_LOTSTEP);
	margin = MarketInfo(Symbol(), MODE_MARGINREQUIRED);

	if (lots*margin > AccountFreeMargin()) lots = AccountFreeMargin() / margin;

	lot = MathFloor(lots/lotstep + 0.5) * lotstep;

	if (lot < lotmin) lot = lotmin;
	if (lot > lotmax) lot = lotmax;

	return (lot);
}

void ExitAll(int direction) {

	for (int i = 0; i <= OrdersTotal(); i++) {
		check = OrderSelect(i, SELECT_BY_POS, MODE_TRADES);

		if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber) {
			if (OrderType() == OP_BUY && direction == LONG) 
				{ Exit(OrderTicket(), LONG, OrderLots(), Blue); }
			if (OrderType() == OP_SELL && direction == SHORT)
				{ Exit( OrderTicket(), SHORT, OrderLots(), Red); }
		}
	}
}

bool Exit(int ticket, int dir, double volume, color clr, int t = 0)  {

	int i, j;
	double prc;
	string cmt;

	bool closed;

	if (LogMessages == true)
		{Print("Exit(" + dir + "," + DoubleToStr(volume,3) + "," + t + ")");}

	for (i=0; i<COMMIT_RETRIES; i++) {
		for (j=0; (j<50) && IsTradeContextBusy(); j++) Sleep(100);
		RefreshRates();

		if (dir == LONG) {
			prc = Bid;
		}

		if (dir == SHORT) {
			prc = Ask;
		}
		
		if (LogMessages == true)
			{ Print("Exit: price = " + DoubleToStr(prc,Digits));}

		closed = OrderClose(ticket,volume,prc,Slippage,clr);
		
		if (closed) {
			if (LogMessages == true) {Print("Trade closed");}

			return (true);
		}

		if (LogMessages == true) {
			Print("Exit: error \'" +
			ErrorDescription(GetLastError()) + 
			"\' when exiting with " + 
			DoubleToStr(volume,3) + 
			" @"+DoubleToStr(prc,Digits));
		}
		
		Sleep(COMMIT_DELAY);
	}

	if (LogMessages == true) {Print("Exit: can\'t enter after " + COMMIT_RETRIES + " retries");}
	return (false);
}

double GetCurrentPL () {

	double currentPL = 0;
	

	for( int i = 0; i <= OrdersTotal(); i++) {

		check = OrderSelect( i, SELECT_BY_POS, MODE_TRADES);

		if( OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber ) {
			currentPL += OrderProfit();
		}
	}

	return( currentPL );
}

double GetCurrentSwap () {

	double currentSwap = 0;

	for( int i = 0; i <= OrdersTotal(); i++) {

		check = OrderSelect( i, SELECT_BY_POS, MODE_TRADES);

		if( OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber ) {
			currentSwap += OrderSwap();
		}
	}

	return( currentSwap );
}

bool CreatePendingOrders(int dir, int pendingType, double entryPrice, double volume, int stop, int take, string comment)  {

	double sl, tp;

	int retVal = 0;

	double lots = CheckLots(volume);
	string info;
   
	for (int i=0; i<COMMIT_RETRIES; i++) {
		for (int j=0; (j<50) && IsTradeContextBusy(); j++) Sleep(100);
		RefreshRates();

		switch(dir)  {
			case LONG:
				if (stop != 0) { sl = entryPrice-(stop*Point); }
				else { sl = 0; }
				if (take != 0) { tp = entryPrice +(take*Point); }
				else { tp = 0; }
                
				if (LogMessages == true) {
					info = "Type: " + pendingType + ", \nentryPrice: " + DoubleToStr(entryPrice, Digits) + ", \nAsk " + DoubleToStr(Ask,Digits)
					+ ", \nLots " + DoubleToStr(lots, 2) + " , \nStop: " + DoubleToStr(sl, Digits)  
					+ ", \nTP: " + DoubleToStr(tp, Digits);
					Print(info);
					Comment(info);
				}

				retVal = OrderSend(Symbol(), pendingType, lots, entryPrice, Slippage, sl, tp, comment, MagicNumber, 0, Blue);
				break;

			case SHORT:
				if (stop != 0) { sl = entryPrice+(stop*Point); }
				else { sl = 0; }
				if (take != 0) { tp = entryPrice-(take*Point); }
				else { tp = 0; }

				if (LogMessages == true) {
					info = "Type: " + pendingType + ", \nentryPrice: " + DoubleToStr(entryPrice, Digits) + ", \nBid " + DoubleToStr(Bid,Digits)
					+ ", \nLots " + DoubleToStr(lots, 2) + " , \nStop: " + DoubleToStr(sl, Digits)  
					+ ", \nTP: " + DoubleToStr(tp, Digits);
					Print(info);
					Comment(info);
				}
          
				retVal = OrderSend(Symbol(), pendingType, lots, entryPrice, Slippage, sl, tp, comment, MagicNumber, 0, Red);
				break;
		}
           
		if( retVal > 0 ) { return( true ); }
			else {
				Print("CreatePendingOrders: error \'"+ErrorDescription(GetLastError())+"\' when setting entry order");
				Sleep(COMMIT_DELAY);      
			}
	}
   
	return( false );
}
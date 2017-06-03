#Global Exchange

This mod provides a server-wide trading exchange for items. It is available
under GNU GPL version 3 or any later version. lsqlite3 is required by this mod,
and can be installed through luarocks. ($ sudo luarocks install lsqlite3)

Nodes
=====
 - ATM (global_exchange:atm) - Used by players to make an account, to view their
 balance, and to send money to other players.
 - Exchange (global_exchange:exchange) - Used by players to search and post
 orders, and to view a summary of current market prices.
 - Digital Mailbox (global_exchange:mailbox) - Used by players to claim items
 sent to buy orders.

Using the Exchange
==================
Overview
-----------
At the top of the exchange form there are four tabs: Market Summary, Buy, Sell,
and Your Orders. Pressing each tab will take you to the indicated screen as
described below.

Market Summary
--------------
This summarizes the various items available on the exchange. From left to right,
the columns display the item name, the description (what is shown in inventory),
the tool wear if applicable, the amount requested by buyers, the maximum rate
offered by buyers, the amount offered by sellers, and the minimum rate offered
by sellers. It is updated periodically.

Buy
-----------
The upper-left corner shows the open order book for the selected item,
consisting of the three best sell offers (lowest asking price and least tool
wear) followed by the three best buy offers (highest offer price and highest
acceptable tool wear). To the right is an image of the selected item, entry
fields for the quantity and offer price, and a drop-down field for the desired
tool wear: "New" (no wear), "Good" (up to 10% wear), "Worn" (up to 50% wear),
and "Junk" (any amount of wear). To qualify, a seller must offer an item with
wear equal to or less than the indicated amount (e.g. if you select "Good" you
may receive an item with only 5% wear, but not one 15% worn). Similarly, the
offer price is the highest price you are willing to pay; in practice you may
pay less depending on the open sell orders. Orders are always fulfilled at the
price listed in the open order book.

At the bottom of the form is a grid similar to the creative inventory. You can
page through the available items using the "<<" and ">>" buttons and select the
item you wish to buy simply by clicking on it.

To finalize the order, press the "Place Bid" button. Note that it is permitted
to enter an order which exceeds your available funds at the time the order is
placed. As matching sell orders are located, the order will be fulfulled until
there are insufficient funds to cover the next item, at which point the
remainder of the order will be cancelled.

Sell
-----------
As with the Buy screen, the upper-left corner shows the open order book for
the selected item. Instead of a static image, the selected item appears as a
1x1 inventory. At the bottom of the screen is the standard 8x4 player
inventory. To choose the type and quantity of items to sell, move the items
from your player inventory to the exchange inventory. Below the exchange
inventory is an entry field for the desired asking price. To finalize the
order, press the "Sell" button. As with buy orders, the asking price is the
lowest price you are willing to accept, and you may receive a higher price
depending on the open buy orders.

Unsold items in the exchange inventory are returned to the player inventory
when the form is closed, or to the player's Inbox if the inventory is full.
(However, items in the exchange inventory at the time of a server crash, or
other abnormal condition, may be lost.)

Your Orders
-----------
This screen lets you see and cancel your orders. To cancel an order, click the
order and press the "Cancel" button. If the order was sell order, the items
held in "escrow" are returned to your player inventory. If any of the items do
not fit in the inventory they are placed in your Inbox instead to be claimed
later.

Buying/Selling
==============
Once you have opened the exchange, you have a few options. If you don't already
know what you want to buy or sell, you can look at the Market Summary to get a
glance at what people are offering. After you have decided on what you are
going to do, return to the Buy or Sell page.

When selling, the Ask field is the minimum price you will accept for each
item. When buying, the Bid field determines the maximum amount you are willing
to pay. If there are matching offers (i.e. there are one or more offers with a
price at least as good and a compatible tool wear level), then that part of
your offer will immediately be filled. For example, if you post a buy order
for 10 cobblestone at 5 credits each, and there is a sell offer for 5
cobblestone at 3 credits each, it will give you 5 cobble immediately at a
total cost of 15 credits (the order-book price), and leave an order on the
exchange for 5 more cobblestone at 5 credits each.

Once your offer is on the exchange, you can view or cancel it from the "Your
Orders" menu.

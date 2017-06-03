
local insecure_env = ...
local sql = insecure_env.require("lsqlite3")
local exports = {}

local order_book_cache = (function(cache)
	return function(ex_name)
		local maybe_cache = cache[ex_name]
		if not maybe_cache then
			maybe_cache = {}
			cache[ex_name] = maybe_cache
		end
		return maybe_cache
	end
end)({})

local init_query = [=[
BEGIN TRANSACTION;
CREATE TABLE IF NOT EXISTS Credit
(
	Owner TEXT PRIMARY KEY NOT NULL,
	Balance INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS Log
(
	Id INTEGER PRIMARY KEY AUTOINCREMENT,
	Recipient TEXT NOT NULL,
	Time INTEGER NOT NULL,
	Message TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS Orders
(
	Id INTEGER PRIMARY KEY AUTOINCREMENT,
	Poster TEXT NOT NULL,
	Exchange TEXT NOT NULL,
	Type TEXT NOT NULL CHECK(Type IN ("buy", "sell")),
	Time INTEGER NOT NULL,
	Item TEXT NOT NULL,
	Wear INTEGER NOT NULL CHECK(Wear >= 0 AND Wear <= 65535),
	Amount INTEGER NOT NULL CHECK(Amount > 0),
	Rate INTEGER NOT NULL CHECK(Rate > 0)
);

CREATE TABLE IF NOT EXISTS Inbox
(
	Id INTEGER PRIMARY KEY AUTOINCREMENT,
	Recipient TEXT NOT NULL,
	Item TEXT NOT NULL,
	Wear INTEGER NOT NULL CHECK(Wear >= 0 AND Wear <= 65535),
	Amount INTEGER NOT NULL CHECK(Amount > 0)
);

CREATE INDEX IF NOT EXISTS index_log
ON Log (Recipient, Time);

CREATE INDEX IF NOT EXISTS index_orders
ON Orders (Exchange, Type, Item, Rate, Wear, Time);

CREATE INDEX IF NOT EXISTS index_own_orders
ON Orders (Poster, Time);

CREATE INDEX IF NOT EXISTS index_inbox
ON Inbox (Recipient, Item, Wear);

CREATE VIEW IF NOT EXISTS distinct_items AS
SELECT DISTINCT Item, Wear FROM Orders;

CREATE VIEW IF NOT EXISTS market_summary AS
SELECT
  distinct_items.Item AS Item,
  distinct_items.Wear AS Wear,
  (
    SELECT SUM(Orders.Amount) FROM Orders
    WHERE Orders.Item = distinct_items.Item
	AND Orders.Wear >= distinct_items.Wear
    AND Orders.Type = "buy"
  ) AS Buy_Volume,
  (
    SELECT MAX(Orders.Rate) FROM Orders
    WHERE Orders.Item = distinct_items.Item
	AND Orders.Wear >= distinct_items.Wear
    AND Orders.Type = "buy"
  ) AS Buy_Max,
  (
    SELECT SUM(Orders.Amount) FROM Orders
    WHERE Orders.Item = distinct_items.Item
	AND Orders.Wear <= distinct_items.Wear
    AND Orders.Type = "sell"
  ) AS Sell_Volume,
  (
    SELECT MIN(Orders.Rate) FROM Orders
    WHERE Orders.Item = distinct_items.Item
	AND Orders.Wear <= distinct_items.Wear
    AND Orders.Type = "sell"
  ) AS Sell_Min
FROM distinct_items;


END TRANSACTION;
]=]

local new_act_query = [=[
INSERT INTO Credit (Owner, Balance)
VALUES (:owner, :start_balance);
]=]

local get_balance_query = [[
SELECT Balance FROM Credit
WHERE Owner = ?;
]]

local set_balance_query = [[
UPDATE Credit
SET Balance = :new_balance
WHERE Owner = :p_name;
]]

local log_query = [[
INSERT INTO Log (Recipient, Time, Message)
VALUES(:recipient, :time, :message);
]]

local add_order_query = [=[
INSERT INTO Orders (Poster, Exchange, Type, Time, Item, Wear, Amount, Rate)
VALUES (:p_name, :ex_name, :order_type, :time, :item_name, :wear, :amount, :rate);
]=]

local del_order_query = [=[
DELETE FROM Orders
WHERE Id = ?;
]=]

local reduce_order_query = [=[
UPDATE Orders
SET Amount = Amount - :delta
WHERE Id = :id;
]=]

local get_order_query = [=[
SELECT * FROM Orders
WHERE Id = ?
]=]

local cancel_order_query = [=[
DELETE FROM Orders
WHERE Id = :id
AND Poster = :p_name
]=]

local search_bids_query = [=[
SELECT * FROM Orders
WHERE Exchange = :ex_name
AND Type = "buy"
AND Item = :item_name
ORDER BY Rate ASC, Wear DESC;
]=]

local search_asks_query = [=[
SELECT * FROM Orders
WHERE Exchange = :ex_name
AND Type = "sell"
AND Item = :item_name
ORDER BY Rate DESC, Wear ASC;
]=]

local qual_bids_query = [=[
SELECT * FROM Orders
WHERE Exchange = :ex_name
AND Type = "buy"
AND Item = :item_name
AND Rate >= :rate_min
AND Wear >= :wear_min
ORDER BY Rate DESC, Time ASC;
]=]

local qual_asks_query = [=[
SELECT * FROM Orders
WHERE Exchange = :ex_name
AND Type = "sell"
AND Item = :item_name
AND Rate <= :rate_max
AND Wear <= :wear_max
ORDER BY Rate ASC, Time ASC;
]=]

local search_own_query = [=[
SELECT * FROM Orders
WHERE Poster = ?
ORDER BY Time ASC;
]=]

local order_book_asks_query = [=[
SELECT Type, Rate, Wear, SUM(Amount) AS Amount FROM Orders
GROUP BY Rate, Wear
HAVING Exchange = :ex_name
AND Type = "sell"
AND Item = :item_name
ORDER BY Rate ASC, Wear ASC
LIMIT 3;
]=]

local order_book_bids_query = [=[
SELECT Type, Rate, Wear, SUM(Amount) AS Amount FROM Orders
GROUP BY Rate, Wear
HAVING Exchange = :ex_name
AND Type = "buy"
AND Item = :item_name
ORDER BY Rate DESC, Wear DESC
LIMIT 3;
]=]

local insert_inbox_query = [=[
INSERT INTO Inbox(Recipient, Item, Wear, Amount)
VALUES(:p_name, :item_name, :wear, :amount);
]=]

local add_inbox_query = [=[
UPDATE Inbox
SET Amount = Amount + :change
WHERE Id = :id;
]=]

local view_inbox_query = [=[
SELECT * FROM Inbox
WHERE Recipient = ?
ORDER BY Item ASC, Wear ASC;
]=]

local search_inbox_query = [=[
SELECT * FROM Inbox
WHERE Recipient = :p_name
AND Item = :item_name
AND Wear = :wear;
]=]

local get_inbox_query = [=[
SELECT Amount, Wear FROM Inbox
WHERE Id = :id;
]=]

local red_inbox_query = [=[
UPDATE Inbox
SET Amount = Amount - :change
WHERE Id = :id;
]=]

local del_inbox_query = [=[
DELETE FROM Inbox
WHERE Id = :id;
]=]

local summary_query = [=[
SELECT * FROM market_summary;
]=]

local transaction_log_query = [=[
SELECT Time, Message FROM Log
WHERE Recipient = ?
ORDER BY Time DESC;
]=]


local ex_methods = {}
local ex_meta = { __index = ex_methods }


local function sql_error(err)
	error("SQL error: " .. err)
end


local function is_integer(x)
	local num = tonumber(x)
	return num and math.floor(num) == num
end


local function exec_stmt(db, stmt, names)
	stmt:bind_names(names)

	local res = stmt:step()
	stmt:reset()

	if res == sqlite3.BUSY then
		return false, "Database Busy."
	elseif res ~= sqlite3.DONE then
		sql_error(db:errmsg())
	else
		return true
	end
end


function exports.open_exchange(path)
	local db = assert(sqlite3.open(path))

	local res = db:exec(init_query)

	if res ~= sqlite3.OK then
		sql_error(db:errmsg())
	end

	local stmts = {
		new_act_stmt         = assert(db:prepare(new_act_query)),
		get_balance_stmt     = assert(db:prepare(get_balance_query)),
		set_balance_stmt     = assert(db:prepare(set_balance_query)),
		log_stmt             = assert(db:prepare(log_query)),
		search_asks_stmt     = assert(db:prepare(search_asks_query)),
		search_bids_stmt     = assert(db:prepare(search_bids_query)),
		qual_asks_stmt       = assert(db:prepare(qual_asks_query)),
		qual_bids_stmt       = assert(db:prepare(qual_bids_query)),
		search_own_stmt      = assert(db:prepare(search_own_query)),
		add_order_stmt       = assert(db:prepare(add_order_query)),
		get_order_stmt       = assert(db:prepare(get_order_query)),
		del_order_stmt       = assert(db:prepare(del_order_query)),
		reduce_order_stmt    = assert(db:prepare(reduce_order_query)),
		cancel_order_stmt    = assert(db:prepare(cancel_order_query)),
		insert_inbox_stmt    = assert(db:prepare(insert_inbox_query)),
		add_inbox_stmt       = assert(db:prepare(add_inbox_query)),
		order_book_bids_stmt = assert(db:prepare(order_book_bids_query)),
		order_book_asks_stmt = assert(db:prepare(order_book_asks_query)),
		view_inbox_stmt      = assert(db:prepare(view_inbox_query)),
		search_inbox_stmt    = assert(db:prepare(search_inbox_query)),
		get_inbox_stmt       = assert(db:prepare(get_inbox_query)),
		red_inbox_stmt       = assert(db:prepare(red_inbox_query)),
		del_inbox_stmt       = assert(db:prepare(del_inbox_query)),
		summary_stmt         = assert(db:prepare(summary_query)),
		transaction_log_stmt = assert(db:prepare(transaction_log_query)),
	}


	local ret = {
		db    = db,
		stmts = stmts,
	}
	setmetatable(ret, ex_meta)

	return ret
end


function ex_methods.close(self)
	for k, v in pairs(self.stmts) do
		v:finalize()
	end

	self.db:close()
end

-- Returns success boolean
function ex_methods.log(self, message, recipient)
	recipient = recipient or ""

	local db = self.db
	local stmt = self.stmts.log_stmt

	stmt:bind_names({
		recipient = recipient,
		time      = os.time(),
		message   = message,
	})

	local res = stmt:step()
	stmt:reset()

	if res == sqlite3.ERROR then
		sql_error(db:errmsg())
	elseif res == sqlite3.MISUSE then
		error("Programmer error.")
	elseif res == sqlite3.BUSY then
		return false, "Failed to log message."
	else
		return true
	end
end


-- Returns success boolean and error.
function ex_methods.new_account(self, p_name, amt)
	local db = self.db
	amt = amt or 0

	local exists = self:get_balance(p_name)

	if exists then
		return false, "Account already exists."
	end

	db:exec("BEGIN TRANSACTION;")

	local stmt = self.stmts.new_act_stmt

	stmt:bind_names({
		owner         = p_name,
		start_balance = amt,
		time          = os.time(),
	})

	local res = stmt:step()

	if res == sqlite3.MISUSE then
		error("Programmer error.")
	elseif res == sqlite3.BUSY then
		stmt:reset()
		db:exec("ROLLBACK;")
		return false, "Database Busy."
	elseif res ~= sqlite3.DONE then
		sql_error(db:errmsg())
	end

	stmt:reset()

	local log_succ1, log_err1 =
		self:log("Account opened with balance " .. amt, p_name)
	local log_succ2, log_err2 =
		self:log(p_name .. " opened an account with balance " .. amt)

	if not log_succ1 then
		db:exec("ROLLBACK;")
		return false, log_err1
	end

	if not log_succ2 then
		db:exec("ROLLBACK;")
		return false, log_err2
	end

	db:exec("COMMIT;")

	return true
end


-- Returns nil if no balance.
function ex_methods.get_balance(self, p_name)
	local db = self.db
	local stmt = self.stmts.get_balance_stmt

	stmt:bind_values(p_name)
	local res = stmt:step()

	if res == sqlite3.ERROR then
		sql_error(db:errmsg())
	elseif res == sqlite3.MISUSE then
		error("Programmer error.")
	elseif res == sqlite3.ROW then
		local balance = stmt:get_value(0)
		stmt:reset()

		return balance
	end

	stmt:reset()
	return nil
end


-- Returns success boolean, and error message if false.
function ex_methods.set_balance(self, p_name, new_bal)
	local db = self.db
	local set_stmt = self.stmts.set_balance_stmt

	local bal = self:get_balance(p_name)

	if not bal then
		return false, p_name .. " does not have an account."
	end

	set_stmt:bind_names({
		p_name      = p_name,
		new_balance = new_bal,
	})

	local res = set_stmt:step()

	if res == sqlite3.ERROR then
		sql_error(db:errmsg())
	elseif res == sqlite3.MISUSE then
		error("Programmer error.")
	elseif res == sqlite3.BUSY then
		set_stmt:reset()
		return false, "Database busy"
	else
		set_stmt:reset()
		return true
	end
end


-- Change balance by the given amount. Returns a success boolean, and error
-- message on fail.
function ex_methods.change_balance(self, p_name, delta)
	if not is_integer(delta) then
		error("Non-integer credit delta")
	end

	local bal = self:get_balance(p_name)

	if not bal then
		return false, p_name .. " does not have an account."
	end

	if bal + delta < 0 then
		return false, p_name .. " does not have enough money."
	end

	return self:set_balance(p_name, bal + delta)
end


-- Sends credits from one user to another. Returns a success boolean, and error
-- message on fail.
function ex_methods.transfer_credits(self, sender, receiver, amt)
	local db = self.db

	if not is_integer(amt) then
		return false, "Non-integer credit amount"
	end

	db:exec("BEGIN TRANSACTION;")

	local succ_minus, err = self:change_balance(sender, -amt)

	if not succ_minus then
		db:exec("ROLLBACK")
		return false, err
	end

	local succ_plus, err = self:change_balance(receiver, amt)

	if not succ_plus then
		db:exec("ROLLBACK")
		return false, err
	end

	local succ_log1 = self:log("Sent " .. amt .. " credits to " .. receiver, sender)

	if not succ_log1 then
		db:exec("ROLLBACK")
		return false, "Failed to log sender message"
	end

	local succ_log2 = self:log("Received " .. amt .. " credits from " .. sender, receiver)

	if not succ_log2 then
		db:exec("ROLLBACK")
		return false, "Failed to log receiver message"
	end

	db:exec("COMMIT;")

	return true
end


function ex_methods.give_credits(self, p_name, amt, msg)
	local db = self.db

	db:exec("BEGIN TRANSACTION;")

	local succ_change, err = self:change_balance(p_name, amt)

	if not succ_change then
		db:exec("ROLLBACK;")
		return false, err
	end

	local succ_log, err = self:log(msg, p_name)

	if not succ_log then
		db:exec("ROLLBACK;")
		return false, er
	end

	db:exec("COMMIT;")

	return true
end


-- The best asks & bids for an item, grouped and sorted by rate and wear.
-- Result fields: Type, Rate, Wear, Amount.
function ex_methods.order_book(self, ex_name, item_name)
	if not ex_name or not item_name then return {} end

	local ex_cache = order_book_cache(ex_name)
	if ex_cache[item_name] then
		return ex_cache[item_name]
	end

	local res = {}

	local stmt = self.stmts.order_book_asks_stmt
	stmt:bind_names({
		ex_name   = ex_name,
		item_name = item_name,
	})

	-- Insert asks in reverse order
	for row in stmt:nrows() do
		table.insert(res, 1, row)
	end
	
	stmt:reset()

	local stmt = self.stmts.order_book_bids_stmt
	stmt:bind_names({
		ex_name   = ex_name,
		item_name = item_name,
	})

	-- Append bids in normal order
	for row in stmt:nrows() do
		table.insert(res, row)
	end
	
	stmt:reset()

	ex_cache[item_name] = res

	return res
end


-- Returns a list of orders, sorted by price.
function ex_methods.search_orders(self, ex_name, order_type, item_name)
	local stmt
	if order_type == "buy" then
		stmt = self.stmts.search_bids_stmt
	else
		stmt = self.stmts.search_asks_stmt
	end

	stmt:bind_names({
		ex_name   = ex_name,
		item_name = item_name,
	})

	local orders = {}

	for tab in stmt:nrows() do
		table.insert(orders, tab)
	end

	stmt:reset()
	return orders
end


-- Same as above, except not sorted in any particular order.
function ex_methods.search_player_orders(self, p_name)
	local stmt = self.stmts.search_own_stmt

	stmt:bind_values(p_name)

	local orders = {}

	for tab in stmt:nrows() do
		table.insert(orders, tab)
	end

	stmt:reset()
	return orders
end


-- Adds a new order. Returns success, and an error string if failed.
function ex_methods.add_order(self, p_name, ex_name, order_type, item_name, wear, amount, rate)
	if not is_integer(amount) then
		return false, "Noninteger quantity"
	elseif amount <= 0 then
		return false, "Nonpositive quantity"
	elseif not is_integer(rate) then
		return false, "Noninteger rate"
	elseif rate <= 0 then
		return false, "Nonpositive rate"
	elseif not is_integer(wear) then
		return false, "Noninteger wear"
	elseif wear < 0 or wear > 65535 then
		return false, "Invalid wear"
	end

	order_book_cache(ex_name)[item_name] = nil

	local db = self.db
	local stmt = self.stmts.add_order_stmt

	stmt:bind_names({
		p_name     = p_name,
		ex_name    = ex_name,
		order_type = order_type,
		time       = os.time(),
		item_name  = item_name,
		wear       = wear,
		amount     = amount,
		rate       = rate,
	})

	local res = stmt:step()

	if res == sqlite3.BUSY then
		stmt:reset()
		return false, "Database Busy"
	elseif res ~= sqlite3.DONE then
		sql_error(db:errmsg())
	end

	stmt:reset()
	return true
end


-- Returns true, or false and an error message.
function ex_methods.cancel_order(self, p_name, id)
	local params = {
		p_name = p_name,
		id     = id,
	}

	local db = self.db
	db:exec("BEGIN TRANSACTION;")

	local get_stmt = self.stmts.get_order_stmt
	get_stmt:bind_values(id)
	local res = get_stmt:step()
	local order

	if res == sqlite3.ERROR then
		sql_error(db:errmsg())
	elseif res == sqlite3.MISUSE then
		error("Programmer error.")
	elseif res == sqlite3.ROW then
		order = get_stmt:get_named_values()
		get_stmt:reset()
	else
		db:exec("ROLLBACK;")
		return false, "No such order."
	end

	order_book_cache(order.Exchange)[order.Item] = nil

	local cancel_stmt = self.stmts.cancel_order_stmt
	local canc_succ, canc_err = exec_stmt(db, cancel_stmt, params)
	if not canc_succ then
		db:exec("ROLLBACK;")
		return false, canc_err
	end

	local message = "Cancelled an order to " ..
		order.Type .. " " .. order.Amount .. " " .. order.Item .. "."

	local succ, err = self:log(message, p_name)
	if not succ then
		db:exec("ROLLBACK")
		return false, err
	end

	db:exec("COMMIT;")

	return true, order
end


-- Puts things in a player's item inbox. Returns success, and also returns an
-- error message if failed.
function ex_methods.put_in_inbox(self, p_name, item_name, wear, amount)
	local db = self.db
	local search_stmt = self.stmts.search_inbox_stmt

	db:exec("BEGIN TRANSACTION;")

	search_stmt:bind_names({
		p_name    = p_name,
		item_name = item_name,
		wear      = wear,
	})

	local res = search_stmt:step()
	local row = nil

	if res == sqlite3.BUSY then
		search_stmt:reset()
		db:exec("ROLLBACK;")
		return false, "Database Busy."
	elseif res == sqlite3.ROW then
		row = search_stmt:get_named_values()
	elseif res ~= sqlite3.DONE then
		sql_error(db:errmsg())
	end

	search_stmt:reset()

	local stmt

	if row then
		stmt = self.stmts.add_inbox_stmt

		stmt:bind_names({
			id     = row.Id,
			change = amount,
		})
	else
		stmt = self.stmts.insert_inbox_stmt

		stmt:bind_names({
			p_name    = p_name,
			item_name = item_name,
			wear      = wear,
			amount    = amount,
		})
	end

	local res = stmt:step()

	if res == sqlite3.BUSY then
		stmt:reset()
		db:exec("ROLLBACK;")
		return false, "Database Busy."
	elseif res ~= sqlite3.DONE then
		sql_error(db:errmsg())
	end

	stmt:reset()

	db:exec("COMMIT;")

	return true
end


-- Tries to buy from orders at the provided rate, and posts an offer with any
-- remaining desired amount. Returns success. If succeeded, also returns amount
-- bought. If failed, returns an error message
function ex_methods.buy(self, p_name, ex_name, item_name, wear, amount, rate)
	if not is_integer(amount) then
		return false, "Noninteger quantity"
	elseif amount <= 0 then
		return false, "Nonpositive quantity"
	elseif not is_integer(rate) then
		return false, "Noninteger rate"
	elseif rate <= 0 then
		return false, "Nonpositive rate"
	elseif not is_integer(wear) then
		return false, "Noninteger wear"
	elseif wear < 0 or wear > 65535 then
		return false, "Invalid wear"
	end

	local db = self.db

	db:exec("BEGIN TRANSACTION");

	local balance = self:get_balance(p_name)
	
	if not balance then
		db:exec("ROLLBACK;")
		return false, p_name .. " does not have an account."
	end

	local bought = {}
	local remaining = amount
	local out_of_funds = false
	local last_row_rate = rate

	local del_stmt = self.stmts.del_order_stmt
	local red_stmt = self.stmts.reduce_order_stmt
	local search_stmt = self.stmts.qual_asks_stmt

	search_stmt:bind_names({
		ex_name   = ex_name,
		item_name = item_name,
		rate_max  = rate,
		wear_max  = wear,
	})

	for row in search_stmt:nrows() do
		local poster     = row.Poster
		local row_wear   = row.Wear
		local row_amount = row.Amount
		local row_rate   = row.Rate
		local row_bought = math.min(row_amount, remaining)

		if poster ~= p_name then
			local can_afford = math.floor(balance / row_rate)
			last_row_rate = row_rate
			out_of_funds = row_bought < can_afford
			row_bought = math.min(row_bought, can_afford)
			-- asking prices can only increase from here
			if row_bought == 0 then break end
		end

		local red_del_stmt

		if row_bought < row_amount then
			red_stmt:bind_names({
				id    = row.Id,
				delta = row_bought,
			})
			red_del_stmt = red_stmt
		else -- row_bought == row_amount
			del_stmt:bind_values(row.Id)
			red_del_stmt = del_stmt
		end

		local red_del_res = red_del_stmt:step()
		if red_del_res == sqlite3.BUSY then
			red_del_stmt:reset()
			search_stmt:reset()
			db:exec("ROLLBACK;")
			return false, "Database Busy."
		elseif red_del_res ~= sqlite3.DONE then
			red_del_stmt:reset()
			search_stmt:reset()
			sql_error(db:errmsg())
		end
		red_del_stmt:reset()

		if poster ~= p_name then
			local cost = row_rate * row_bought

			local ch_succ, ch_err = self:change_balance(poster, cost)
			if not ch_succ then
				search_stmt:reset()
				db:exec("ROLLBACK;")
				return false, ch_err
			end

			local ch_succ, ch_err = self:change_balance(p_name, -cost)
			if not ch_succ then
				search_stmt:reset()
				db:exec("ROLLBACK;")
				return false, ch_err
			end

			balance = balance - cost

			local log_succ, log_err =
				self:log(p_name .. " bought " .. row_bought .. " " ..
						item_name .. " from you. (+" .. cost .. ")",
						poster)
			if not log_succ then
				search_stmt:reset()
				db:exec("ROLLBACK;")
				return false, log_err
			end

			local log_succ, log_err =
				self:log("Bought " .. row_bought .. " " .. item_name ..
						" from " .. poster .. ". (-" .. cost .. ")",
						p_name)
			if not log_succ then
				search_stmt:reset()
				db:exec("ROLLBACK;")
				return false, log_err
			end
		else
			local log_succ, log_err =
				self:log("Bought " .. row_bought .. " " ..
				         item_name .. " from yourself.",
				         p_name)
			if not log_succ then
				search_stmt:reset()
				db:exec("ROLLBACK;")
				return false, log_err
			end
		end

		order_book_cache(ex_name)[item_name] = nil

		table.insert(bought, { amount = row_bought, wear = row_wear })

		remaining = remaining - row_bought

		if remaining == 0 or out_of_funds then break end
	end

	search_stmt:reset()

	if remaining > 0 then
		if out_of_funds then
			local log_succ, log_err =
				self:log("Insufficient funds to buy " .. remaining .. " " ..
						item_name .. " at " .. last_row_rate .. "/ea.",
						p_name)
			if not log_succ then
				db:exec("ROLLBACK;")
				return false, log_err
			end
		else
			local add_succ, add_err =
				self:add_order(p_name, ex_name, "buy", item_name, wear, remaining, rate)

			if not add_succ then
				db:exec("ROLLBACK;")
				return false, add_err
			end

			local log_succ, log_err =
				self:log("Posted buy offer for " .. remaining .. " " ..
						item_name .. " at " .. rate .. "/ea.",
						p_name)
			if not log_succ then
				db:exec("ROLLBACK;")
				return false, log_err
			end
		end
	end

	db:exec("COMMIT;")

	return true, bought
end


-- Tries to sell to orders at the provided rate, and posts an offer with any
-- remaining desired amount. Returns success. If failed, returns an error message.
function ex_methods.sell(self, p_name, ex_name, item_name, wear, amount, rate)
	if not is_integer(amount) then
		return false, "Noninteger quantity"
	elseif amount <= 0 then
		return false, "Nonpositive quantity"
	elseif not is_integer(rate) then
		return false, "Noninteger rate"
	elseif rate <= 0 then
		return false, "Nonpositive rate"
	elseif not is_integer(wear) then
		return false, "Noninteger wear"
	elseif wear < 0 or wear > 65535 then
		return false, "Invalid wear"
	end

	local db = self.db

	db:exec("BEGIN TRANSACTION");

	local remaining = amount

	local del_stmt = self.stmts.del_order_stmt
	local red_stmt = self.stmts.reduce_order_stmt
	local search_stmt = self.stmts.qual_bids_stmt

	search_stmt:bind_names({
		ex_name   = ex_name,
		item_name = item_name,
		rate_min  = rate,
		wear_min  = wear,
	})

	for row in search_stmt:nrows() do
		local poster     = row.Poster
		local row_amount = row.Amount
		local row_rate   = row.Rate
		local row_sold   = math.min(row_amount, remaining)

		local out_of_funds = false

		if poster ~= p_name then
			local bal = self:get_balance(poster)

			if not bal then
				search_stmt:reset()
				db:exec("ROLLBACK;")
				return false, poster .. " does not have an account."
			end

			local can_afford = math.floor(bal / row_rate)
			out_of_funds = can_afford < row_sold
			row_sold = math.min(row_sold, can_afford)
		end

		local red_del_stmt

		if row_sold < row_amount and not out_of_funds then
			red_stmt:bind_names({
				id    = row.Id,
				delta = row_sold,
			})
			red_del_stmt = red_stmt
		else -- row_sold == row_amount or out_of_funds
			del_stmt:bind_values(row.Id)
			red_del_stmt = del_stmt
		end

		local red_del_res = red_del_stmt:step()
		red_del_stmt:reset()
		if red_del_res == sqlite3.BUSY then
			search_stmt:reset()
			db:exec("ROLLBACK;")
			return false, "Database Busy."
		elseif red_del_res ~= sqlite3.DONE then
			search_stmt:reset()
			sql_error(db:errmsg())
		end

		local in_succ, in_err =
			self:put_in_inbox(poster, item_name, wear, row_sold)
		if not in_succ then
			search_stmt:reset()
			db:exec("ROLLBACK;")
			return false, in_err
		end

		if poster ~= p_name then
			local revenue = row_sold * row_rate

			local ch_succ, ch_err = self:change_balance(poster, -revenue)
			if not ch_succ then
				search_stmt:reset()
				db:exec("ROLLBACK;")
				return false, ch_err
			end

			local ch_succ, ch_err = self:change_balance(p_name, revenue)
			if not ch_succ then
				search_stmt:reset()
				db:exec("ROLLBACK;")
				return false, ch_err
			end

			local log_succ, log_err =
				self:log(p_name .. " sold " .. row_sold .. " " ..
						item_name .. " to you. (-" .. revenue .. ")",
						poster)
			if not log_succ then
				search_stmt:reset()
				db:exec("ROLLBACK;")
				return false, log_err
			end

			if out_of_funds then
				local log_succ, log_err =
					self:log("Insufficient funds to buy " ..
							math.min(row_amount - row_sold, remaining) ..
							" " .. item_name .. " from " .. p_name ..
							" at " .. row_rate .. "/ea.",
							poster)
				if not log_succ then
					db:exec("ROLLBACK;")
					return false, log_err
				end
			end

			local log_succ, log_err =
				self:log("Sold " .. row_sold .. " " .. item_name ..
						" to " .. poster .. "(+" .. revenue .. ")",
						p_name)
			if not log_succ then
				search_stmt:reset()
				db:exec("ROLLBACK;")
				return false, log_err
			end
		else
			local log_succ, log_err =
				self:log("Sold " .. row_sold .. " " ..
							item_name .. " to yourself.",
							p_name)
			if not log_succ then
				search_stmt:reset()
				db:exec("ROLLBACK;")
				return false, log_err
			end
		end

		order_book_cache(ex_name)[item_name] = nil

		remaining = remaining - row_sold

		if remaining == 0 then break end
	end

	search_stmt:reset()

	if remaining > 0 then
		local add_succ, add_err =
			self:add_order(p_name, ex_name, "sell", item_name, wear, remaining, rate)

		if not add_succ then
			db:exec("ROLLBACK;")
			return false, add_err
		end
	end

	db:exec("COMMIT;")

	return true
end


-- On success, returns true and a list of inbox entries.
-- TODO: On failure, return false and an error message.
function ex_methods.view_inbox(self, p_name)
	local stmt = self.stmts.view_inbox_stmt

	stmt:bind_values(p_name)

	local res = {}

	for row in stmt:nrows() do
		table.insert(res, row)
	end

	stmt:reset()

	return true, res
end


-- Returns success boolean. On success, also returns the number actually
-- taken. On failure, also returns an error message
function ex_methods.take_inbox(self, id, amount)
	local db = self.db
	local get_stmt = self.stmts.get_inbox_stmt
	local red_stmt = self.stmts.red_inbox_stmt
	local del_stmt = self.stmts.del_inbox_stmt

	get_stmt:bind_names({ id = id })

	local res = get_stmt:step()

	if res == sqlite3.BUSY then
		get_stmt:reset()
		return false, "Database Busy."
	elseif res == sqlite3.DONE then
		get_stmt:reset()
		return false, "Order does not exist."
	elseif res ~= sqlite3.ROW then
		sql_error(db:errmsg())
	end

	local available = get_stmt:get_value(0)
	get_stmt:reset()

	db:exec("BEGIN TRANSACTION;")

	local red_del_stmt

	if available > amount then
		red_stmt:bind_names({
			id     = id,
			change = amount
		})

		red_del_stmt = red_stmt
	else
		del_stmt:bind_values(id)
		red_del_stmt = del_stmt
	end

	local red_del_res = red_del_stmt:step()

	if red_del_res == sqlite3.BUSY then
		red_del_stmt:reset()
		db:exec("ROLLBACK;")
		return false, "Database Busy."
	elseif red_del_res ~= sqlite3.DONE then
		sql_error(db:errmsg())
	end

	red_del_stmt:reset()

	db:exec("COMMIT;")
	return true, math.min(amount, available)
end


-- Returns a list of tables with fields:
--   item_name: Name of the item
--   buy_volume: Number of items sought
--   buy_max: Maximum buy rate
--   sell_volume: Number of items for sale
--   sell_min: Minimum sell rate
function ex_methods.market_summary(self)
	local stmt = self.stmts.summary_stmt

	local res = {}
	for a in stmt:nrows() do
		table.insert(res, a)
	end
	stmt:reset()

	return res
end


-- Returns a list of log entries, sorted by time.
function ex_methods.player_log(self, p_name)
	local stmt = self.stmts.transaction_log_stmt
	stmt:bind_values(p_name)

	local res = {}

	for row in stmt:nrows() do
		table.insert(res, row)
	end

	stmt:reset()

	return res
end

function exports.test()
	local ex = exports.open_exchange("test.db")

	local alice_bal = ex:get_balance("Alice")
	local bob_bal = ex:get_balance("Bob")


	local function print_balances()
		print("Alice: ", ex:get_balance("Alice"))
		print("Bob: ", ex:get_balance("Bob"))
	end


	-- Initialize balances
	if alice_bal then
		ex:set_balance("Alice", 420)
	else
		ex:new_account("Alice", 420)
	end

	if bob_bal then
		ex:set_balance("Bob", 2015)
	else
		ex:new_account("Bob", 2015)
	end

	print_balances()


	-- Transfer a valid amount
	print("Transfering 1000 credits from Bob to Alice")

	local succ, err = ex:transfer_credits("Bob", "Alice", 1000)

	print("Success: ", succ, " ", err)
	print_balances()


	-- Transfer an invalid amount
	print("Transfering 3000 credits from Alice to Bob")

	local succ, err = ex:transfer_credits("Alice", "Bob", 3000)

	print("Success: ", succ, " ", err)
	print_balances()


	-- Simulate a transaction
	print("Alice posting an offer to buy 10 cobble at 2 credits each")
	local succ, err = ex:buy("Alice", "", "default:cobble", 32767, 10, 2)
	print("Success: ", succ, " ", err)
	print_balances()

	print("Bob posting an offer to sell 20 cobble at 1 credits each")
	local succ, err = ex:sell("Bob", "", "default:cobble", 32767, 20, 1)
	print("Success: ", succ, " ", err)
	print_balances()

	ex:close()
end


return exports
-- vim:set ts=4 sw=4 noet:

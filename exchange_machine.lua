local exchange, formlib = ...

local search_cooldown = 2
local summary_interval = 600

local global_inv = nil

local function is_integer(x)
	return math.floor(x) == x
end

local summary_fs = ""
local function mk_summary_fs()
	local fs = formlib.Builder()

	fs("tablecolumns[text;text;text;text;text;text]")
	fs("table[0,0;11.75,9;summary_table;")
	fs("Item,Description,Buy Vol,Buy Max,Sell Vol,Sell Min")

	local all_items = minetest.registered_items
	for i, row in ipairs(exchange:market_summary()) do
		local def = all_items[row.item_name] or {}
		fs(",", formlib.escape(row.item_name))
		fs(",", formlib.escape(def.description or "Unknown Item"))
		fs(",", formlib.escape(row.buy_volume  or 0))
		fs(",", formlib.escape(row.buy_max     or "N/A"))
		fs(",", formlib.escape(row.sell_volume or 0))
		fs(",", formlib.escape(row.sell_min    or "N/A"))
	end

	fs("]")

	summary_fs = tostring(fs)
end

minetest.after(0, mk_summary_fs)


local elapsed = 0
minetest.register_globalstep(function(dtime)
	elapsed = elapsed + dtime
	if elapsed >= summary_interval then
		mk_summary_fs()
		elapsed = 0
	end
end)


local wear_levels = {
	[1] = { index = 1, text = "New (-0%)",    wear = math.floor(0.00*65535) },
	[2] = { index = 2, text = "Good (-10%)",  wear = math.floor(0.10*65535) },
	[3] = { index = 3, text = "Worn (-50%)",  wear = math.floor(0.50*65535) },
	[4] = { index = 4, text = "Junk (-100%)", wear = math.floor(1.00*65535) },
}

-- Allow lookup by text label as well as index
for _,v in ipairs(wear_levels) do
	wear_levels[tostring(v.text)] = v
end

local function wear_string(wear)
	return "-" .. math.ceil(100 * wear / 65535) .. "%"
end


local main_state = {}
-- ^ A per-player state for the main form.

minetest.register_on_joinplayer(function(player)
	exchange:new_account(player:get_player_name()) --just to make sure
	main_state[player:get_player_name()] = {
		tab            = 1,
		buy_item       = "",
		buy_wear       = wear_levels[1].text,
		buy_price      = "",
		buy_amount     = "1",
		sell_price     = "",
		buy_page       = 1,
		selected_index = 0,
	}
end)

minetest.register_on_leaveplayer(function(player)
	main_state[player:get_player_name()] = nil
end)


-- Something similar to creative inventory
local pagemax = 1
local pagewidth = 12
local pageheight = 4
local pageitems = pagewidth * pageheight
local selectable_list = {}

-- Create inventory list after loading all mods
minetest.after(0, function()
	for name, def in pairs(minetest.registered_items) do
		if (def.groups.not_in_creative_inventory or 0) == 0 and
		   (def.description or "") ~= "" then
			selectable_list[#selectable_list + 1] = name
		end
	end
	table.sort(selectable_list)

	pagemax = math.max(math.ceil(#selectable_list / pageitems), 1)
end)

local main_form = "global_exchange:exchange_main"

local function table_from_results(fs, results, name, x, y, w, h, selected)
	fs("tablecolumns[text;text;text;text;text;text;text]")
	fs("table[", x, ",", y, ";", w, ",", h, ";")
	fs(formlib.escape(name), ";")
	fs("Poster,Type,Item,Description,Wear,Amount,Rate")

	local all_items = minetest.registered_items

	for i, row in ipairs(results) do
		local def = all_items[row.Item] or {}
		fs(",", formlib.escape(row.Poster))
		fs(",", formlib.escape(row.Type))
		fs(",", formlib.escape(row.Item))
		fs(",", formlib.escape(def.description or "Unknown Item"))
		if row.Wear > 0 then
			fs(",", formlib.escape("-" .. math.ceil(100 * row.Wear / 65535) .. "%"))
		else
			fs(",---")
		end
		fs(",", formlib.escape(row.Amount))
		fs(",", formlib.escape(row.Rate))
	end

	local sel_num = math.max(0, tonumber(selected) or 0)
	fs(";", sel_num + 1, "]")
end

local function mk_main_market_fs(fs, p_name, state)
	fs(summary_fs)
end

local function mk_main_order_book_fs(fs, p_name, x, y, w, h, item_name)
	local order_book = exchange:order_book("", item_name)

	fs("tablecolumns[text;text;text;text]")
	fs("table[", x, ",", y, ";", w, ",", h, ";", "order_book;")
	fs("Type,Rate,Wear,Amount")

	for _,row in ipairs(order_book) do
		fs(",", formlib.escape(row.Type))
		fs(",", formlib.escape(row.Rate))
		if row.Wear > 0 then
			fs(",", formlib.escape(wear_string(row.Wear)))
		else
			fs(",---")
		end
		fs(",", formlib.escape(row.Amount))
	end

	fs(";1]")
end

local function mk_main_buy_fs(fs, p_name, state)
	mk_main_order_book_fs(fs, p_name, 0, 0, 8.75, 3.75, state.buy_item)

	fs:item_image_button(9,0, 1,1, "buy_item", state.buy_item)

	fs:field(10.25,0.40, 2,1, "buy_amount", "Quantity", state.buy_amount, false)

	local wear = wear_levels[state.buy_wear] or wear_levels[1]
	fs("dropdown[9,1;3;buy_wear;")
	local sep = nil
	for _,v in ipairs(wear_levels) do
		if sep then fs(sep) end
		fs:escape(v.text)
		sep = ","
	end
	fs(";", wear.index, "]")

	fs:field(9.35,2.40, 2.9,1, "buy_price", "Bid (ea.)", state.buy_price, false)

	fs:button(9,3, 3,1, "buy", "Place Bid")

	fs:container(0,4, function()
		fs:button( 0,0.25, 1,1, "buy_left",  "<<")
		fs:button( 5,0.25, 2,1, "position",  state.buy_page .. "/" .. pagemax)
		fs:button(11,0.25, 1,1, "buy_right", ">>")

		local firstitem = ((state.buy_page - 1) * pageitems)
		for y=0,(pageheight-1) do
			for x=0,(pagewidth-1) do
				local index = firstitem + (pagewidth * y) + x + 1
				if selectable_list[index] then
					fs:item_image_button(x,1.25+y, 1,1, "select_" .. index,
						selectable_list[index])
				end
			end
		end
	end)
end

local function mk_main_sell_fs(fs, p_name, state)
	local sell_stack = global_inv:get_stack("p_" .. p_name, 1)
	local sell_item = (not sell_stack:is_empty()
	                   and sell_stack:get_name()) or ""

	mk_main_order_book_fs(fs, p_name, 0, 0, 8.75, 3.75, sell_item)

	fs:list(9,0, 1,1, "detached:global_exchange", "p_" .. p_name)

	fs:field(9.35,2.40, 2.9,1, "sell_price", "Ask (ea.)", state.sell_price, false)

	fs:button(9,3, 3,1, "sell", "Sell")

	fs:box(1.9375,5.1875, 7.96875,4.03, "#00000020")

	fs:list(2,5.25, 8,4, "current_player", "main")
end

local function mk_main_own_orders_fs(fs, p_name, state)
	if not state.own_results then
		state.own_results = exchange:search_player_orders(p_name) or {}
	end

	state.selected_index = math.min(state.selected_index or 0, #state.own_results)

	table_from_results(fs, state.own_results, "result_table", 0, 0, 11.75, 8.5, state.selected_index)
	fs:button(4.5,8.5, 3,1, "cancel", "Cancel Order")
end

local main_tabs = {
	[1] = { text = "Market",    mk_fs = mk_main_market_fs     },
	[2] = { text = "Buy",       mk_fs = mk_main_buy_fs        },
	[3] = { text = "Sell",      mk_fs = mk_main_sell_fs       },
	[4] = { text = "My Orders", mk_fs = mk_main_own_orders_fs },
}

local function mk_main_fs(fs, p_name, err_str, success)
	local state = main_state[p_name]
	if not state then return end -- Should have been initialized on player join
	
	fs:size(12,10)
	fs:bgcolor("#606060", false)

	fs("tabheader[0,0.65;tab;")
	local sep = nil
	for _,tab in ipairs(main_tabs) do
		if sep then fs(sep) end
		fs:escape(tab.text)
		sep = ","
	end
	fs(";", state.tab or 1, ";false;true]")

	local bal = exchange:get_balance(p_name)
	fs:label(0,0.37, "Balance: " .. bal)

	if err_str then
		fs:label(4,0.37, err_str)
	elseif success then
		fs:label(4,0.37, "Success!")
	end

	if main_tabs[state.tab] then
		fs:container(0,1, main_tabs[state.tab].mk_fs, p_name, state)
	end
end


local function show_main(p_name, err_str, success)
	local fs = formlib.Builder()
	mk_main_fs(fs, p_name, err_str, success)
	minetest.show_formspec(p_name, main_form, tostring(fs))
end


minetest.register_on_joinplayer(function(player)
	-- the inventory list name (for selling) is "p_"..player_name
	global_inv:set_size("p_"  .. player:get_player_name(), 1)
end)


-- Returns success, and also returns an error message if failed.
local function post_buy(player, ex_name, item_name, wear_str, amount_str, rate_str)
	local p_name = player:get_player_name()

	if (item_name or "") == "" then
		return false, "You must input an item"
	elseif not minetest.registered_items[item_name] then
		return false, "That item does not exist."
	end

	local wear_level = wear_levels[wear_str]
	if not wear_level then
		return false, "Invalid wear."
	end

	local amount = tonumber(amount_str)
	local rate   = tonumber(rate_str)

	if not amount or not is_integer(amount) or amount < 1 then
		return false, "Invalid amount."
	elseif not rate or not is_integer(rate) or rate < 1 then
		return false, "Invalid rate."
	end

	local p_inv = player:get_inventory()
	local stack = ItemStack(item_name)

	local succ, res = exchange:buy(p_name, ex_name, item_name, wear_level.wear, amount, rate)
	if not succ then
		return false, res
	end

	for _,row in ipairs(res) do
		stack:set_count(row.amount)
		stack:set_wear(row.wear)

		local leftover = p_inv:add_item("main", stack)

		-- Put anything that won't fit in the inventory in the player's inbox
		if not leftover:is_empty() then
			exchange:put_in_inbox(p_name, item_name, row.wear, leftover:get_count())
		end
	end

	-- Refresh market summary "soonish"
	elapsed = math.max(elapsed, summary_interval - 5)

	return true
end

-- Returns success, and also returns an error message if failed.
-- The item to sell is determined by the player's list in global_inv.
local function post_sell(player, ex_name, rate_str)
	local p_name = player:get_player_name()
	local stack  = global_inv:get_stack("p_" .. p_name, 1)

	if not stack or stack:is_empty() then
		return false, "You must input an item"
	elseif not minetest.registered_items[stack:get_name()] then
		return false, "That item does not exist."
	end

	if stack.get_meta then
		local meta     = stack:get_meta()
		local def_meta = ItemStack(stack:get_name()):get_meta()

		if not stack:get_meta():equals(def_meta) then
			return false, "Cannot sell an item with metadata."
		end
	elseif (stack:get_metadata() or "") ~= "" then
		return false, "Cannot sell an item with metadata."
	end

	local rate = tonumber(rate_str)

	if not rate or not is_integer(rate) or rate < 1 then
		return false, "Invalid rate."
	end

	local item_name = stack:get_name()
	local wear      = stack:get_wear()
	local amount    = stack:get_count()

	local succ, res = exchange:sell(p_name, ex_name, item_name, wear, amount, rate)
	if not succ then
		return false, res
	end

	stack:clear()
	global_inv:set_stack("p_" .. p_name, 1, stack)

	-- Refresh market summary "soonish"
	elapsed = math.max(elapsed, summary_interval - 5)

	return true
end


local function handle_main(player, fields)
	local p_name = player:get_player_name()
	local state = main_state[p_name]

	local copy_fields = {
		"buy_wear",
		"buy_amount",
		"buy_price",
		"sell_price"
	}
	for _,k in ipairs(copy_fields) do
		if fields[k] then
			state[k] = fields[k]
		end
	end

	if fields.tab then
		state.tab = tonumber(fields.tab) or 1
		show_main(p_name)
	end

	if fields.buy_left then
		state.buy_page = (((state.buy_page or 1) + ((2*pagemax-1) - 1)) % pagemax) + 1
		show_main(p_name)
	end

	if fields.buy_right then
		state.buy_page = (((state.buy_page or 1) + ((2*pagemax-1) + 1)) % pagemax) + 1
		show_main(p_name)
	end

	for name in pairs(fields) do
		local index = tonumber(string.match(name, "select_([0-9]+)"))
		if index and index >= 1 and index < #selectable_list then
			state.buy_item = selectable_list[index]
			show_main(p_name)
		end
	end

	if fields.buy then
		local succ, err =
			post_buy(player, "", state.buy_item, fields.buy_wear,
			         fields.buy_amount, fields.buy_price)
		if succ then
			state.buy_amount = "1"
			state.buy_price = ""
			state.own_results = nil
			show_main(p_name, nil, true)
		else
			show_main(p_name, err)
		end
	end

	if fields.sell then
		local succ, err = post_sell(player, "", fields.sell_price)
		if succ then
			state.sell_price = ""
			state.own_results = nil
			show_main(p_name, nil, true)
		else
			show_main(p_name, err)
		end
	end

	local idx = state.selected_index
	local own_results = state.own_results or {}

	if fields.cancel and own_results[idx] then
		local succ, res = exchange:cancel_order(p_name, own_results[idx].Id)
		if succ then
			if res.Type == "sell" then
				local p_inv = player:get_inventory()
				local stack = ItemStack(res.Item)
				stack:set_count(res.Amount)
				stack:set_wear(res.Wear)
				local leftover = p_inv:add_item("main", stack)

				-- Put anything that won't fit in the inventory in the player's inbox
				if not leftover:is_empty() then
					exchange:put_in_inbox(p_name, res.Item, res.Wear, leftover:get_count())
				end
			end

			-- Refresh market summary "soonish"
			elapsed = math.max(elapsed, summary_interval - 5)
		end

		state.own_results = nil
		show_main(p_name)
	end

	if fields.result_table then
		local event = minetest.explode_table_event(fields.result_table)
		if event.type == "CHG" then
			state.selected_index = event.row - 1
			show_main(p_name)
		end
	end

	if fields.quit then
		-- Return the player's unsold inventory, if any
		local stack = global_inv:get_stack("p_" .. p_name, 1)
		local p_inv = player:get_inventory()
		local leftover = p_inv:add_item("main", stack)

		-- Whatever doesn't fit in the player's inventory stays in the form.
		-- Note that any items in the form when the server exits are lost.
		global_inv:set_stack("p_" .. p_name, 1, leftover)

		state.own_results = nil
	end
end


minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname == main_form then
		handle_main(player, fields)
	else
		return
	end
	return true
end)


global_inv = minetest.create_detached_inventory("global_exchange", {
	allow_move = function(inv,from_list,from_index,to_list,to_index,count,player)
		return 0
	end,
	allow_put = function(inv,to_list,to_index,stack,player)
		local p_name = player:get_player_name()

		if to_list == "p_" .. p_name then
			return stack:get_count()
		else
			return 0
		end
	end,
	allow_take = function(inv,from_list,from_index,stack,player)
		local p_name = player:get_player_name()

		if from_list == "p_" .. p_name then
			return stack:get_count()
		else
			return 0
		end
	end,
	on_put = function(inv,to_list,to_index,stack,player)
		show_main(player:get_player_name())
	end,
	on_take = function(inv,from_list,from_index,stack,player)
		show_main(player:get_player_name())
	end,
})


minetest.register_node("global_exchange:exchange", {
	description = "Exchange Terminal",
	drawtype = "nodebox",
	tiles = {
		"global_exchange_terminal_top.png",
		"global_exchange_terminal_bottom.png",
		"global_exchange_terminal_right.png",
		"global_exchange_terminal_right.png^[transform4",
		"global_exchange_terminal_back.png",
		"global_exchange_terminal_front.png",
	},
	paramtype = "light",
	paramtype2 = "facedir",
	groups = {cracky=2},
	is_ground_content = false,
	stack_max = 1,
	light_source = 3,
	node_box = {
		type = "fixed",
		fixed = {
			{-8/16, -4/16,  3/16, 8/16,  8/16,  5/16},--screens
			{-1/16, -7/16,  5/16, 1/16,  5/16,  7/16},--screen leg
			{-3/16, -8/16,  4/16, 3/16, -7/16,  8/16},--leg platform
			{-7/16, -8/16, -8/16, 2/16, -6/16, -3/16},--keyboard
			{ 3/16, -8/16, -3/16, 7/16, -7/16,  3/16},--phone low
			{ 4/16, -7/16, -1/16, 6/16, -6/16,  3/16},--phone hi
			{ 2/16, -7/16,  0/16, 8/16, -5/16,  2/16},--phone speaker
		}
	},
	on_rightclick = function(_, _, clicker)
		local p_name = clicker:get_player_name()
		local state = main_state[p_name]
		if state then
			state.search_results = {}
		end

		show_main(p_name)
	end,
})


minetest.register_craft( {
	output = "global_exchange:exchange",
	recipe = {
		{ "default:steel_ingot",  "default:steel_ingot", "default:steel_ingot" },
		{ "default:mese_crystal", "default:steel_ingot", "default:diamond"     },
		{ "default:steel_ingot",  "default:steel_ingot", "default:steel_ingot" },
	}
})
-- vim:set ts=4 sw=4 noet:

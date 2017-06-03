-- A telling machine. Call this file with the exchange argument.
local exchange, formlib = ...

local atm_form = "global_exchange:atm_form"


local unique = (function(unique_num)
	return function()
		unique_num = unique_num + 1
		return unique_num
	end
end)(0)


local function info_fs(fs, p_name)
	local balance = exchange:get_balance(p_name)

	fs:size(4,3)

	if balance then
		fs:label(0.5,0.5, "Balance: " .. balance)
	else
		fs:label(0.5,0.5, "You don't have an account.")
	end

	fs:button(1,2, 2,1, "logout", "Log Out")
end


local function wire_fs(fs, p_name)
	local balance = exchange:get_balance(p_name)

	fs:size(4,5)

	if balance then
		-- To detect duplicate/stale form submission
		fs:field(-100, -100, 0,0, "trans_id", "", unique())

		fs:label(0.50,0.325, "Balance: " .. balance)
		fs:field(0.75,1.750, 3,1, "recipient", "Send to:", "")
		fs:field(0.75,3.000, 3,1, "amount", "Amount", "")

		fs:button(0,4.25, 2,1, "logout", "Log Out")
		fs:button(2,4.25, 2,1, "send", "Send")
	else
		fs:button(0,4, 2,1, "logout", "Back")
		fs:label(0.5,0.5, "You don't have an account.")
	end
end


local function send_fs(fs, p_name, receiver, amt_str)
	fs:size(10,3)

	fs:button(4,2, 2,1, "wire", "Back")

	local amt = tonumber(amt_str)
	local msg = nil

	if not amt or amt <= 0 then
		msg = "Invalid transfer amount."
	else
		local succ, err = exchange:transfer_credits(p_name, receiver, amt)

		if not succ then
			msg = "Error: " .. err
		else
			msg = "Successfully sent " .. amt ..
				" credits to " .. receiver .. "."
		end
	end

	fs:label(0.5,0.5, msg)
end


local function log_fs(fs, p_name)
	fs:size(14,8)

	fs:label(0,0, "Transaction Log")

	fs:element("tablecolumns", "text", "text")

	fs("table[0,0.75;13.75,6.75;log_table;Time,Message")
	for _, entry in ipairs(exchange:player_log(p_name)) do
		fs(","):escape_list(entry.Time, entry.Message)
	end
	fs("]")

	fs:button(6,7.5, 2,1, "logout", "Log Out")
end


local function main_menu_fs(fs, p_name)
	fs:size(6,2)
	fs:button(0.50,0.125, 2.5,1, "info", "Account Info")
	fs:button(3.00,0.125, 2.5,1, "wire", "Wire Monies")
	fs:button(0.50,1.125, 5.0,1, "transaction_log", "Transaction Log")
end


local function show_atm_form(fs_fn, p_name, ...)
	local fs = formlib.Builder()
	fs_fn(fs, p_name, ...)
	minetest.show_formspec(p_name, atm_form, tostring(fs))
end


local trans_ids = {}

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= atm_form then return end
	if fields.quit then return true end

	local p_name = player:get_player_name()

	local this_id = tonumber(fields.trans_id)

	if this_id and trans_ids[p_name] and this_id <= trans_ids[p_name] then
		-- Ignore duplicate/stale form submittal
		return true
	end

	trans_ids[p_name] = this_id

	if fields.logout then
		show_atm_form(main_menu_fs, p_name)
	elseif fields.info then
		show_atm_form(info_fs, p_name)
	elseif fields.wire then
		show_atm_form(wire_fs, p_name)
	elseif fields.send then
		show_atm_form(send_fs, p_name, fields.recipient, fields.amount)
	elseif fields.transaction_log then
		show_atm_form(log_fs, p_name)
	end

	return true
end)


minetest.register_node("global_exchange:atm_bottom", {
	description = "ATM",
	inventory_image = "global_exchange_atm_icon.png",
	wield_image = "global_exchange_atm_hi_front.png",
	drawtype = "nodebox",
	tiles = {
		"global_exchange_atm_lo_top.png",
		"global_exchange_atm_side.png",
		"global_exchange_atm_side.png",
		"global_exchange_atm_side.png",
		"global_exchange_atm_back.png^[transform2",
		"global_exchange_atm_lo_front.png",
	},
	paramtype = "light",
	paramtype2 = "facedir",
	is_ground_content = false,
	stack_max = 1,
	light_source = 3,
	node_box = {
		type = "fixed",
		fixed = {
		{-0.5, -0.5, -0.5, 0.5, 0.5, 0.5},
		}
	},
	selection_box = {
		type = "fixed",
		fixed = {
			{-0.500, -0.500, -0.5000,  0.500, 0.500,  0.50},
			{-0.500,  0.500, -0.5000, -0.375, 1.125, -0.25},
			{ 0.375,  0.500, -0.5000,  0.500, 1.125, -0.25},
			{-0.500,  0.500, -0.2500,  0.500, 1.500,  0.50},
			{-0.500,  1.125, -0.4375, -0.375, 1.250, -0.25},
			{ 0.375,  1.125, -0.4375,  0.500, 1.250, -0.25},
			{-0.500,  1.250, -0.3750, -0.375, 1.375, -0.25},
			{ 0.375,  1.250, -0.3750,  0.500, 1.375, -0.25},
			{-0.500,  1.375, -0.3125, -0.375, 1.500, -0.25},
			{ 0.375,  1.375, -0.3125,  0.500, 1.500, -0.25},
		},
	},
	on_place = function(itemstack, placer, pointed_thing)
		local under = pointed_thing.under
		local pos
		if minetest.registered_items[minetest.get_node(under).name].buildable_to then
			pos = under
		else
			pos = pointed_thing.above
		end
		if minetest.is_protected(pos, placer:get_player_name()) and
				not minetest.check_player_privs(placer, "protection_bypass") then
			minetest.record_protection_violation(pos, placer:get_player_name())
			return itemstack
		end
		local def = minetest.registered_nodes[minetest.get_node(pos).name]
		if not def or not def.buildable_to then
			minetest.remove_node(pos)
			return itemstack
		end
		local dir = minetest.dir_to_facedir(placer:get_look_dir())
		local pos2 = {x = pos.x, y = pos.y + 1, z = pos.z}
		local def2 = minetest.registered_nodes[minetest.get_node(pos2).name]
		if not def2 or not def2.buildable_to then
			return itemstack
		end
		minetest.set_node(pos, {name = "global_exchange:atm_bottom", param2 = dir})
		minetest.set_node(pos2, {name = "global_exchange:atm_top", param2 = dir})
		if not minetest.setting_getbool("creative_mode") then
			itemstack:take_item()
			return itemstack
		end
	end,
	on_destruct = function(pos)
		local pos2 = {x = pos.x, y = pos.y + 1, z = pos.z}
		local n2 = minetest.get_node(pos2)
		if minetest.get_item_group(n2.name, "atm") == 2 then
			minetest.remove_node(pos2)
		end
	end,
	groups = {cracky=2, atm = 1},
	on_rightclick = function(pos, _, clicker)
		minetest.sound_play("atm_beep", {pos = pos, gain = 0.3, max_hear_distance = 5})
		show_atm_form(main_menu_fs, clicker:get_player_name())
	end,
})

minetest.register_node("global_exchange:atm_top", {
	drawtype = "nodebox",
	tiles = {
		"global_exchange_atm_hi_top.png",
		"global_exchange_atm_side.png",--not visible anyway
		"global_exchange_atm_side.png",
		"global_exchange_atm_side.png",
		"global_exchange_atm_back.png",
		"global_exchange_atm_hi_front.png",
	},
	paramtype = "light",
	paramtype2 = "facedir",
	is_ground_content = false,
	light_source = 3,
	node_box = {
		type = "fixed",
		fixed = {
			{-0.500, -0.500, -0.5000, -0.375, 0.125, -0.25},
			{ 0.375, -0.500, -0.5000,  0.500, 0.125, -0.25},
			{-0.500, -0.500, -0.2500,  0.500, 0.500,  0.50},
			{-0.500,  0.125, -0.4375, -0.375, 0.250, -0.25},
			{ 0.375,  0.125, -0.4375,  0.500, 0.250, -0.25},
			{-0.500,  0.250, -0.3750, -0.375, 0.375, -0.25},
			{ 0.375,  0.250, -0.3750,  0.500, 0.375, -0.25},
			{-0.500,  0.375, -0.3125, -0.375, 0.500, -0.25},
			{ 0.375,  0.375, -0.3125,  0.500, 0.500, -0.25},
		}
	},
	selection_box = {
		type = "fixed",
		fixed = {0, 0, 0, 0, 0, 0},
	},
	groups = {
		atm = 2,
		not_in_creative_inventory = 1
	},
})

minetest.register_craft( {
	output = "global_exchange:atm",
	recipe = {
		{ "default:stone", "default:stone",      "default:stone" },
		{ "default:stone", "default:gold_ingot", "default:stone" },
		{ "default:stone", "default:stone",      "default:stone" },
	}
})

minetest.register_alias("global_exchange:atm", "global_exchange:atm_bottom")
-- vim:set ts=4 sw=4 noet:

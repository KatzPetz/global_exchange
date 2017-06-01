local exchange, formlib = ...

local mailbox_form = "global_exchange:digital_mailbox"

local mailbox_contents = {}
local selected_index = {}

-- Map from player names to their most recent search result
local function get_mail(p_name)
	local mail_maybe = mailbox_contents[p_name]

	if not mail_maybe then
		local _,res = exchange:view_inbox(p_name)
		mail_maybe = res or {}
		mailbox_contents[p_name] = mail_maybe
		selected_index[p_name] = math.min(selected_index[p_name] or 0, #mail_maybe)
	end

	return mail_maybe
end


local function wear_string(wear)
	return "-" .. math.ceil(100 * wear / 65535) .. "%"
end


local function mk_inbox_list(fs, results, x, y, w, h)
	fs("textlist[", x, ",", y, ";", w, ",", h, ";result_list;")

	local sep = nil
	for i, row in ipairs(results) do
		fs(sep)
		fs:escape(row.Amount, " ", row.Item)
		if row.Wear > 0 then
			fs:escape(" (", wear_string(row.Wear), ")")
		end
		sep = ","
	end

	fs("]")
end


local function mk_mail_fs(fs, p_name, results, err_str)
	fs:size(8,8)
	fs:label(0,0, "Inbox")

	if err_str then
		fs:label(3,0, "Error: " .. err_str)
	end

	mk_inbox_list(fs, results, 0, 1, 7.75, 6.25)

	fs:button(3,7.35, 2,1, "claim", "Claim")
end


local function show_mail(p_name, err_str)
	local fs = formlib.Builder()
	mk_mail_fs(fs, p_name, get_mail(p_name), err_str)
	minetest.show_formspec(p_name, mailbox_form, tostring(fs))
end


minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= mailbox_form then return end
	if fields.quit then return true end

	local p_name = player:get_player_name()

	if fields.result_list then
		local event = minetest.explode_textlist_event(fields.result_list)

		if event.type == "CHG" then
			selected_index[p_name] = event.index
		end
	end

	if fields.claim then
		local idx = selected_index[p_name]
		local row = get_mail(p_name)[idx]

		if row then
			local stack = ItemStack(row.Item)
			stack:set_count(row.Amount)
			stack:set_wear(row.Wear)

			local p_inv = player:get_inventory()
			local leftover = p_inv:add_item("main", stack)
			local took_amount = row.Amount - leftover:get_count()

			mailbox_contents[p_name] = nil

			local succ, res = exchange:take_inbox(row.Id, took_amount)
			if succ then
				show_mail(p_name)
			else
				show_mail(p_name, res)
			end
		end
	end

	return true
end)


minetest.register_node("global_exchange:mailbox", {
	description = "Digital Mailbox",
	tiles = {
		"global_exchange_box.png",
		"global_exchange_box.png",
		"global_exchange_box.png^global_exchange_mailbox_side.png",
	},
	is_ground_content = false,
	stack_max = 1,
	groups = {cracky=2},
	on_rightclick = function(pos, node, clicker)
		local p_name = clicker:get_player_name()
		mailbox_contents[p_name] = nil
		show_mail(p_name)
	end,
})


minetest.register_craft( {
	output = "global_exchange:mailbox",
	recipe = {
		{ "default:stone", "default:gold_ingot", "default:stone" },
		{ "default:stone", "default:chest",      "default:stone" },
		{ "default:stone", "default:stone",      "default:stone" },
	}
})
-- vim:set ts=4 sw=4 noet:

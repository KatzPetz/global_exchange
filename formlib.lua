local formlib = {}
local builder_methods = {}

function formlib.escape(x)
	if x == nil then return "" end
	return minetest.formspec_escape(tostring(x))
end

function formlib.bool(x)
	-- nil and false are returned as-is, everything else maps to true
	return x and true
end

function builder_methods.append(fs, ...)
	for i=1,select("#", ...) do
		local x = select(i, ...)
		if x ~= nil then table.insert(fs, tostring(x)) end
	end
	return fs
end

function builder_methods.escape(fs, ...)
	for i=1,select("#", ...) do
		local x = select(i, ...)
		if x ~= nil then table.insert(fs, formlib.escape(x)) end
	end
	return fs
end

function builder_methods.escape_list(fs, ...)
	for i=1,select("#", ...) do
		local x = select(i, ...)
		if i > 1 then fs(",") end
		fs:escape(x)
	end
	return fs
end

function builder_methods.escape_groups(fs, ...)
	for i=1,select("#", ...) do
		local group = select(i, ...)
		if i > 1 then fs(";") end
		if type(group) == "table" then
			fs:escape_list(unpack(group))
		else
			fs:escape(group)
		end
	end
	return fs
end

function builder_methods.element(fs, name, ...)
	return fs(name, "["):escape_groups(...):append("]")
end

function builder_methods.size(fs, w,h, fixed)
	if fixed == nil then
		return fs:element("size", {w,h})
	else
		return fs:element("size", {w,h, formlib.bool(fixed)})
	end
end

function builder_methods.bgcolor(fs, color, fullscreen)
	if fullscreen == nil then
		return fs:element("bgcolor", {color})
	else
		return fs:element("bgcolor", {color}, {formlib.bool(fullscreen)})
	end
end

function builder_methods.list(fs, x,y, w,h, inv_loc, inv_list, start_idx)
	return fs:element("list", {inv_loc}, {inv_list}, {x,y}, {w,h}, {start_idx})
end

function builder_methods.button(fs, x,y, w,h, name, text)
	return fs:element("button", {x,y}, {w,h}, {name}, {text})
end

function builder_methods.item_image_button(fs, x,y, w,h, name, item, text)
	return fs:element("item_image_button", {x,y}, {w,h}, {item}, {name}, {text})
end

function builder_methods.label(fs, x,y, text)
	return fs:element("label", {x,y}, {text})
end

function builder_methods.field(fs, x,y, w,h, name, label, default, close_on_enter)
	fs:element("field", {x,y}, {w,h}, {name}, {label}, {default})
	if close_on_enter ~= nil then
		fs:element("field_close_on_enter", {name}, {formlib.bool(close_on_enter)})
	end
	return fs
end

function builder_methods.box(fs, x,y, w,h, color)
	return fs:element("box", {x,y}, {w,h}, {color})
end

function builder_methods.dropdown(fs, x,y, w, name, body_fn, selected_idx)
	fs("dropdown["):escape_groups({x,y}, {w}, {name}):append(";")
	local first = true
	local results = { body_fn(function(...)
		if first then first = false else fs(",") end
		fs:escape(...)
	end) }
	if selected_idx ~= nil then fs(";"):escape(selected_idx) end
	return fs("]"), unpack(results)
end

function builder_methods.tabheader(fs, x,y, name, body_fn, current_tab, transparent, draw_border)
	fs("tabheader["):escape_groups({x,y}, {name}):append(";")
	local first = true
	local results = { body_fn(function(...)
		if first then first = false else fs(",") end
		fs:escape(...)
	end) }
	fs(";"):escape_groups({current_tab}, {formlib.bool(transparent)}, {formlib.bool(draw_border)})
	return fs("]"), unpack(results)
end

function builder_methods.textlist(fs, x,y, w,h, name, body_fn, selected_idx, transparent)
	fs("textlist["):escape_groups({x,y}, {w,h}, {name}):append(";")
	local first = true
	local results = { body_fn(function(...)
		if first then first = false else fs(",") end
		fs:escape(...)
	end) }
	fs(";"):escape_groups({selected_idx}, {formlib.bool(transparent)})
	return fs("]"), unpack(results)
end

function builder_methods.tableoptions(fs, ...)
	return fs:element("tableoptions", ...)
end

function builder_methods.tablecolumns(fs, ...)
	return fs:element("tablecolumns", ...)
end

function builder_methods.table(fs, x,y, w,h, name, body_fn, selected_idx)
	fs("table["):escape_groups({x,y}, {w,h}, {name}):append(";")
	local first = true
	local results = { body_fn(function(...)
		if first then first = false else fs(",") end
		fs:escape_list(...)
	end) }
	if selected_idx ~= nil then fs(";"):escape(selected_idx) end
	return fs("]"), unpack(results)
end

function builder_methods.container(fs, x,y, sub_fn, ...)
	fs:element("container", {x,y})
	local results = { sub_fn(fs, ...) }
	return fs("container_end[]"), unpack(results)
end

local builder_meta = {
	__metatable = "protected",
	__index = builder_methods,
	__call = builder_methods.append,
	__tostring = table.concat,
}

function formlib.Builder()
	local fs = {}
	setmetatable(fs, builder_meta)
	return fs
end

return formlib
-- vim:set ts=4 sw=4 noet:

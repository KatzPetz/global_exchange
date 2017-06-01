local formlib = {}
local builder_methods = {}

function formlib.escape(x)
	return minetest.formspec_escape(tostring(x or ""))
end

function builder_methods.escape(fs, ...)
	for _,x in ipairs({...}) do
		if x then fs(formlib.escape(x)) end
	end
end

function builder_methods.size(fs, w,h, fixed)
	if fixed == false then
		fs("size[", w, ",", h, ",false]")
	elseif fixed then
		fs("size[", w, ",", h, ",true]")
	else
		fs("size[", w, ",", h, "]")
	end
end

function builder_methods.bgcolor(fs, color, fullscreen)
	if fullscreen == false then
		fs("bgcolor[", formlib.escape(color), ";false]")
	elseif fullscreen then
		fs("bgcolor[", formlib.escape(color), ";true]")
	else
		fs("bgcolor[", formlib.escape(color), "]")
	end
end

function builder_methods.list(fs, x,y, w,h, inv_loc, inv_list, start_idx)
	fs("list[", formlib.escape(inv_loc), ";", formlib.escape(inv_list), ";",
		x, ",", y, ";", w, ",", h, ";", formlib.escape(start_idx), "]")
end

function builder_methods.button(fs, x,y, w,h, name, text)
	fs("button[", x, ",", y, ";", w, ",", h, ";",
		formlib.escape(name), ";", formlib.escape(text), "]")
end

function builder_methods.item_image_button(fs, x,y, w,h, name, item, text)
	fs("item_image_button[", x, ",", y, ";", w, ",", h, ";",
		formlib.escape(item), ";", formlib.escape(name), ";",
		formlib.escape(text), "]")
end

function builder_methods.label(fs, x,y, text)
	fs("label[", x, ",", y, ";", formlib.escape(text), "]")
end

function builder_methods.field(fs, x,y, w,h, name, label, default, close_on_enter)
	fs("field[", x, ",", y, ";", w, ",", h, ";",
		formlib.escape(name), ";", formlib.escape(label), ";",
		formlib.escape(default), "]")

	if close_on_enter == false then
		fs("field_close_on_enter[", formlib.escape(name), ";false]")
	end
end

function builder_methods.container(fs, x,y, sub_fn, ...)
	fs("container[", x, ",", y, "]")
	sub_fn(fs, ...)
	fs("container_end[]")
end

function builder_methods.box(fs, x,y, w,h, color)
	fs("box[", x, ",", y, ";", w, ",", h, ";", formlib.escape(color), "]")
end

local builder_meta = {
	__metatable = "protected",
	__index = builder_methods,
	__call = function(fs, ...)
		for _,x in ipairs({...}) do
			if x then table.insert(fs, tostring(x)) end
		end
	end,
	__tostring = table.concat,
}

function formlib.Builder()
	local fs = {}
	setmetatable(fs, builder_meta)
	return fs
end

return formlib
-- vim:set ts=4 sw=4 noet:

local insecure_env = minetest.request_insecure_environment()
assert(insecure_env, "global_exchange needs to be trusted to run under mod security.")

local modpath = minetest.get_modpath(minetest.get_current_modname()) .. "/"

local exchange = assert(loadfile(modpath .. "exchange.lua"))(insecure_env).
   open_exchange(minetest.get_worldpath() .. "/global_exchange.db")

local formlib = assert(loadfile(modpath .. "formlib.lua"))()

minetest.register_on_shutdown(function()
   exchange:close()
end)

local function handle_setbalance_command(caller, name, newbalance)
   return exchange:set_balance(name, newbalance)
end

minetest.register_privilege("balance", {
   description = "Can use /setbalance",
   give_to_singleplayer = false
})

minetest.register_chatcommand("setbalance", {
   params      = "[<name>] <balance>",
   description = "set a player's trading balance",
   privs       = {balance=true},
   func = function(caller, param)
      local name, balancestr = string.match(param, "([^ ]+) ([0-9]+)")
      if not name or not balancestr then
         name = caller
         balancestr = string.match(param, "([0-9]+)")
         if not balancestr then
            return false, "Invalid parameters (see /help setbalance)"
         end
      end
      return handle_setbalance_command(caller, name, tonumber(balancestr))
   end,
})

assert(loadfile(modpath .. "atm.lua"))(exchange, formlib)
assert(loadfile(modpath .. "exchange_machine.lua"))(exchange, formlib)
assert(loadfile(modpath .. "digital_mailbox.lua"))(exchange, formlib)

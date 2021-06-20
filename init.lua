local mod_name = "wielded_light"

local update_interval = 0.2
local cleanup_interval = update_interval*3
local velocity_projection = update_interval * 1
local level_delta = 2
local max_light_level = 14
local shiny_items = {}

local active_lights = {}
local light_recalcs = {}
local tracked_entities = {}
local update_callbacks = {}
local update_player_callbacks = {}

local cat_id = 0
local cat_codes = {}
local function get_cat_code(cat)
	if not cat_codes[cat] then
		if cat_id >= 256 then
			error("Wielded item category limit exceeded, maximum 256 wield categories")
		end
		local code = string.format("%02x", cat_id)
		cat_id = cat_id+1
		cat_codes[cat] = code
	end
	return cat_codes[cat]
end

local function entity_still_exists(entity)
	return entity and (entity.obj:is_player() or entity.obj:get_entity_name() or false)
end

local function entity_pos(userdata, offset)
	if not offset then offset = { x=0, y=0, z=0 } end
	return wielded_light.get_light_position(
		vector.round(
			vector.add(
				vector.add(
					offset,
					userdata:get_pos()
				),
				vector.multiply(
					userdata:get_player_velocity(),
					velocity_projection
				)
			)
		)
	)
end

local function update_entity(entity)
	local pos = entity_pos(entity.obj, entity.offset)
	local pos_str = pos and minetest.pos_to_string(pos)
	if entity.pos and pos_str ~= entity.pos then
		for id,_ in pairs(entity.items) do
			remove_light(entity.pos, id)
		end
	end
	entity.pos = pos_str
	if pos then
		for id, item in pairs(entity.items) do
			if item.level > 0 then
				minetest.get_node_timer(pos):start(cleanup_interval)
				add_light(pos_str, id, item.level)
			else
				remove_light(pos_str, id)
			end
		end
	end
end

local function cleanup_timer_callback(pos, elapsed)
	local pos_str = minetest.pos_to_string(pos)
	local lights = active_lights[pos_str]
	if not lights then
		minetest.swap_node(pos, { name = "air" })
	else
		for id,_ in pairs(lights) do
			local uid = string.sub(id,3)
			local entity = tracked_entities[uid]
			if not entity_still_exists(entity) then
				remove_light(pos_str, id)
			end
		end
	end
end

local timer = 0
local function global_timer_callback(dtime)

	timer = timer + dtime;
	if timer < update_interval then
		return
	end
	timer = 0

	for _, player in pairs(minetest.get_connected_players()) do
		for _,callback in pairs(update_player_callbacks) do
			callback(player)
		end
	end

	for _,callback in pairs(update_callbacks) do
		callback()
	end

	-- Look at each tracked entity and update its position
	for uid, entity in pairs(tracked_entities) do
		if entity_still_exists(entity) then
			update_entity(entity)
		else
			tracked_entities[uid] = nil
		end
	end

	-- Recalculate light levels
	for pos,_ in pairs(light_recalcs) do
		recalc_light(pos)
	end
	light_recalcs = {}
end

function recalc_light(pos)
	if not active_lights[pos] then return end

	local any_light = false
	local max_light = 0
	for id, light_level in pairs(active_lights[pos]) do
		any_light = true
		if light_level > max_light then
			max_light = light_level
		end
	end
	local pos_vec = minetest.string_to_pos(pos)
	if not any_light then
		active_lights[pos] = nil
		minetest.swap_node(pos_vec, { name = "air" })
		return
	end
	if max_light == 0 then
		minetest.swap_node(pos_vec, { name = "air" })
		return
	end

	max_light = math.min(max_light, max_light_level)
	local old_value = 0
	local name = minetest.get_node(pos_vec).name
	if wielded_light.is_wielded_light(name) then
		old_value = wielded_light.level_of_wielded_light(name)
	end
	if old_value ~= max_light then
		minetest.swap_node(pos_vec, {
			name = wielded_light.wielded_light_of_level(max_light)
		})
		minetest.get_node_timer(pos_vec):start(cleanup_interval)
	end
end

function add_light(pos, id, light_level)
	if not active_lights[pos] then
		active_lights[pos] = {}
	end
	if active_lights[pos][id] ~= light_level then
		-- minetest.log("error", "add "..id.." "..pos.." "..tostring(light_level))
		active_lights[pos][id] = light_level
		light_recalcs[pos] = true
	end
end

function remove_light(pos, id)
	if not active_lights[pos] then return end
	-- minetest.log("error", "rem "..id.." "..pos)
	-- minetest.after(update_interval, function ()
	active_lights[pos][id] = nil
	light_recalcs[pos] = true
	-- end)
end

--- Shining API ---
wielded_light = {}

function wielded_light.register_lightstep(callback)
	table.insert(update_callbacks, callback)
end

function wielded_light.register_player_lightstep(callback)
	table.insert(update_player_callbacks, callback)
end

function wielded_light.wielded_light_of_level(light_level)
	return mod_name..":"..light_level
end

function wielded_light.level_of_wielded_light(node_name)
	return tonumber(node_name:sub(#mod_name+2))
end

function wielded_light.is_wielded_light(node_name)
	return node_name:sub(1, #mod_name) == mod_name
end

function wielded_light.is_lightable_node(node_pos)
	local name = minetest.get_node(node_pos).name
	if name == "air" then
		return true
	elseif wielded_light.is_wielded_light(name) then
		return true
	end
	return false
end

function wielded_light.get_light_position(pos)
	local around_vector = {
		{x=0, y=0, z=0},
		{x=0, y=1, z=0}, {x=0, y=-1, z=0},
		{x=1, y=0, z=0}, {x=-1, y=0, z=0},
		{x=0, y=0, z=1}, {x=0, y=0, z=1},
	}
	for _, around in ipairs(around_vector) do
		local light_pos = vector.add(pos, around)
		if wielded_light.is_lightable_node(light_pos) then
			return light_pos
		end
	end
end

function wielded_light.get_light_level(item_string)
	if not item_string or item_string == "" then
		return 0
	end

	local stack = ItemStack(item_string)
	local item_name = stack:get_name()

	local cached_light_level = shiny_items[item_name]
	if cached_light_level then
		return cached_light_level
	end

	local itemdef = stack:get_definition()
	if not itemdef then
		return 0
	end
	return math.min(math.max((itemdef.light_source or 0) - level_delta, 0), max_light_level)
	-- local light_level = math.min(math.max((itemdef.light_source or 0) - level_delta, 0), max_light_level)
	-- -- shiny_items[item_name] = light_level

	-- return light_level
end

function wielded_light.register_item_light(itemname, light_level)
	shiny_items[itemname] = light_level
end

function wielded_light.track_item_entity(userdata, cat, item)
	local light_level = wielded_light.get_light_level(item)
	if light_level <= 0 then return end

	local uid = tostring(userdata)
	local id = get_cat_code(cat)..uid
	if not tracked_entities[uid] then
		local pos = entity_pos(userdata)
		local pos_str = pos and minetest.pos_to_string(pos)
		if pos_str then
			add_light(pos_str, id, light_level)
		end
		tracked_entities[uid] = { obj=userdata, items={}, pos=pos_str }
	end
	tracked_entities[uid].items[id] = { level=light_level }
end

local player_height_offset = { x=0, y=1, z=0 }
function wielded_light.track_user_entity(userdata, cat, item)
	local uid = tostring(userdata)
	local id = get_cat_code(cat)..uid
	if not tracked_entities[uid] then
		tracked_entities[uid] = { obj=userdata, items={}, offset = player_height_offset }
	end
	local tracked_entity = tracked_entities[uid]
	local tracked_item = tracked_entity.items[id]

	if not tracked_item
	or tracked_item.item ~= item
	then
		local light_level = wielded_light.get_light_level(item)
		tracked_entity.items[id] = { level=light_level, item=item }
	end
end

-- Wielded item shining globalstep
minetest.register_globalstep(global_timer_callback)

-- Register helper nodes
for i=1, max_light_level do
	minetest.register_node(wielded_light.wielded_light_of_level(i), {
		drawtype = "airlike",
		groups = {not_in_creative_inventory = 1},
		walkable = false,
		paramtype = "light",
		sunlight_propagates = true,
		light_source = i,
		pointable = false,
		buildable_to = true,
		drop = {},
		on_timer = cleanup_timer_callback,
	})
end

-- Dropped item on_step override
-- https://github.com/minetest/minetest/issues/6909
local builtin_item = minetest.registered_entities["__builtin:item"]
local item = {
	on_step = function(self, dtime, ...)
		builtin_item.on_step(self, dtime, ...)
		if self.wielded_light then return end -- Already done, exit
		self.wielded_light = true
		local stack = ItemStack(self.itemstring)
		local item_name = stack:get_name()
		wielded_light.track_item_entity(self.object, "item", item_name)
	end
}

setmetatable(item, {__index = builtin_item})
minetest.register_entity(":__builtin:item", item)

wielded_light.register_player_lightstep(function (player)
	wielded_light.track_user_entity(player, "wield", player:get_wielded_item():get_name())
end)


---TEST
--wielded_light.register_item_light('default:dirt', 14)

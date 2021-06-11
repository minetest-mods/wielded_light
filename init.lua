local update_interval = 0.2
local level_delta = 2
local shiny_items = {}
local mod_name = "wielded_light"
local max_light_level = 14

--- Shining API ---
wielded_light = {}

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

	local light_level = math.min(math.max((itemdef.light_source or 0) - level_delta, 0), max_light_level)
	-- shiny_items[item_name] = light_level

	return light_level
end



function wielded_light.update_light(pos, light_level)
	local old_value = 0
	local timer
	local light_pos = wielded_light.get_light_position(pos)
	if not light_pos then
		return
	end

	local name = minetest.get_node(light_pos).name
	if wielded_light.is_wielded_light(name) then -- Update existing light node and timer
		old_value = wielded_light.level_of_wielded_light(name)
		if light_level <= old_value then
			timer = minetest.get_node_timer(light_pos)
			-- The timer is set to 3x update_interval
			-- This node was not updated the last interval and may
			-- is disabled before the next step
			-- Therefore the light should be re-set to avoid flicker
			if timer:get_elapsed() <= (update_interval * 1.5) then
				return
			end
		end
	end

	timer = timer or minetest.get_node_timer(light_pos)
	if light_level ~= old_value then
		minetest.swap_node(light_pos, { name = wielded_light.wielded_light_of_level(light_level) })
	end
	timer:start(update_interval*3)
end

function wielded_light.update_light_by_item(item, pos)
	local light_level = wielded_light.get_light_level(item)
	if light_level <= 0 then return end

	wielded_light.update_light(pos, light_level)
end

function wielded_light.register_item_light(itemname, light_level)
	shiny_items[itemname] = light_level
end


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
		on_timer = function(pos, elapsed)
			minetest.swap_node(pos, {name = "air"})
		end,
	})
end

-- Wielded item shining globalstep
local timer = 0
minetest.register_globalstep(function(dtime)
	timer = timer + dtime;
	if timer < update_interval then
		return
	end
	timer = 0

	for _, player in pairs(minetest.get_connected_players()) do
			
		local light_level = wielded_light.get_light_level(player:get_wielded_item())
		if light_level <= 0  then return end -- No light, exit

		-- predict where the player will be the next time we place the light
		-- assume that on average we're slightly past 1/2 of the next interval, hence 1.5
		-- (since the scheduling is a bit behind)
		-- experimentally this also works nicely
		local pos = vector.add (
			vector.add({x = 0, y = 1, z = 0}, vector.round(player:get_pos())),
			vector.round(vector.multiply(player:get_player_velocity(), update_interval * 1.5))
		)

		wielded_light.update_light(pos, light_level)
	end
end)


-- Dropped item on_step override
-- https://github.com/minetest/minetest/issues/6909
local builtin_item = minetest.registered_entities["__builtin:item"]
local item = {
	on_step = function(self, dtime, ...)
		builtin_item.on_step(self, dtime, ...)

		self.shining_timer = (self.shining_timer or 0) + dtime
		if self.shining_timer < update_interval then return end -- Too soon, exit
		self.shining_timer = 0
			
		local light_level = wielded_light.get_light_level(self.itemstring)
		if light_level <= 0  then return end -- No light, exit

		local pos = self.object:get_pos()
		if not pos then return end -- Invalid pos, exit

		wielded_light.update_light(vector.round(pos), light_level)
	end
}
setmetatable(item, {__index = builtin_item})
minetest.register_entity(":__builtin:item", item)


---TEST
--wielded_light.register_item_light('default:dirt', 14)


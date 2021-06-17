local update_interval = 0.2
local level_delta = 2
local shiny_items = {}

--- Shining API ---
wielded_light = {}

wielded_light.lightable_nodes = {}
wielded_light.lighting_nodes = {}

function wielded_light.update_light(pos, light_level)
	local around_vector = {
			{x=0, y=0, z=0},
			{x=0, y=1, z=0}, {x=0, y=-1, z=0},
			{x=1, y=0, z=0}, {x=-1, y=0, z=0},
			{x=0, y=0, z=1}, {x=0, y=0, z=1},
		}
	local update_node = false
	local timer
	local light_pos
	for _, around in ipairs(around_vector) do
		light_pos = vector.add(pos, around)
		local name = minetest.get_node(light_pos).name
		if wielded_light.lightable_nodes[name] and (minetest.get_node_light(light_pos) or 0) < light_level then
			update_node = wielded_light.lightable_nodes[name][light_level]
			break
		elseif wielded_light.lighting_nodes[name] then -- Update existing light node and timer
			local old_value = minetest.registered_nodes[name].light_source
			if light_level > old_value then
				update_node = wielded_light.lighting_nodes[name][light_level]
			else
				timer = minetest.get_node_timer(light_pos)
				local elapsed = timer:get_elapsed()
				if elapsed > (update_interval * 1.5) then
					-- The timer is set to 3x update_interval
					-- This node was not updated the last interval and may
					-- is disabled before the next step
					-- Therefore the light should be re-set to avoid flicker
					update_node = wielded_light.lighting_nodes[name][light_level]
				end
			end
			break
		end
	end
	if update_node then
		timer = timer or minetest.get_node_timer(light_pos)
		minetest.swap_node(light_pos, {name = update_node})
		timer:start(update_interval*3)
	end
end

function wielded_light.update_light_by_item(item, pos)
	local stack = ItemStack(item)
	local light_level = shiny_items[stack:get_name()]
	local itemdef = stack:get_definition()
	if not light_level and not itemdef then
		return
	end
	if itemdef and itemdef.floodable then
		local node = minetest.get_node(pos)
		if node then
			if minetest.registered_nodes[node.name] and (minetest.registered_nodes[node.name].liquidtype ~= "none") then
				return
			end
		end
	end

	light_level = light_level or ((itemdef.light_source or 0) - level_delta)

	if light_level > 0 then
		wielded_light.update_light(pos, light_level)
	end
end

function wielded_light.register_item_light(itemname, light_level)
	shiny_items[itemname] = light_level
end

local water_name = "default:water_source"
local water_def = minetest.registered_nodes["default:water_source"]
if minetest.get_modpath("hades_core") then
	water_name = "hades_core:water_source"
	water_def = minetest.registered_nodes["hades_core:water_source"]
end

-- Register helper nodes
wielded_light.lightable_nodes["air"] = {}
if water_def then
	wielded_light.lightable_nodes[water_name] = {}
end
for i=1, 14 do
	-- 14 air nodes
	local node_name = "wielded_light:"..i
	wielded_light.lightable_nodes["air"][i] = node_name
	wielded_light.lighting_nodes[node_name] = wielded_light.lightable_nodes["air"]
	minetest.register_node(node_name, {
		drawtype = "airlike",
		groups = {not_in_creative_inventory = 1},
		walkable = false,
		paramtype = "light",
		sunlight_propagates = true,
		light_source = i,
		pointable = false,
		buildable_to = true,
		drops = "",
		on_timer = function(pos, elapsed)
			minetest.swap_node(pos, {name = "air"})
		end,
	})

	--14 water nodes (only if default mod present)
	if water_def then
		local node_name = "wielded_light:water_"..i
		wielded_light.lightable_nodes[water_name][i] = node_name
		wielded_light.lighting_nodes[node_name] = wielded_light.lightable_nodes[water_name]
		minetest.register_node(node_name, {
			drawtype = "liquid",
			tiles = water_def.tiles,
			special_tiles = water_def.special_tiles,
			alpha = water_def.alpha,
			paramtype = "light",
			walkable = false,
			pointable = false,
			diggable = false,
			buildable_to = true,
			is_ground_content = false,
			drop = "",
			drowning = 1,
			liquidtype = "source",
			liquid_alternative_flowing = "wielded_light:water_"..i,
			liquid_alternative_source = "wielded_light:water_"..i,
			liquid_viscosity = 1,
			liquid_range = 0,
			post_effect_color = water_def.post_effect_color,
			groups = {not_in_creative_inventory = 1},
			sounds = water_def.sounds,
			light_source = i,
			on_timer = function(pos, elapsed)
				minetest.swap_node(pos, {name = water_name})
			end,
		})
	end
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
		-- predict where the player will be the next time we place the light
		-- assume that on average we're slightly past 1/2 of the next interval, hence 1.5
		-- (since the scheduling is a bit behind)
		-- experimentally this also works nicely
		local pos = vector.add (
			vector.add({x = 0, y = 1, z = 0}, vector.round(player:getpos())),
			vector.round(vector.multiply(player:get_player_velocity(), update_interval * 1.5))
		)

		wielded_light.update_light_by_item(player:get_wielded_item(), pos)
	end
end)


-- Dropped item on_step override
-- https://github.com/minetest/minetest/issues/6909
local builtin_item = minetest.registered_entities["__builtin:item"]
local item = {
	on_step = function(self, dtime, ...)
		builtin_item.on_step(self, dtime, ...)

		self.shining_timer = (self.shining_timer or 0) + dtime
		if self.shining_timer >= update_interval then
			self.shining_timer = 0
			local pos = self.object:get_pos()
			if pos then
				wielded_light.update_light_by_item(self.itemstring, pos)
			end
		end
	end
}
setmetatable(item, {__index = builtin_item})
minetest.register_entity(":__builtin:item", item)


---TEST
--wielded_light.register_item_light('default:dirt', 14)


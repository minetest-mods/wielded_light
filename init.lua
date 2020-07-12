local update_interval = 0.2
local level_delta = 2
local shiny_items = {}

local lightable_nodes = {}

--- Shining API ---
wielded_light = {}

local function deep_copy(input)
	if type(input) ~= "table" then
		return input
	end
	local output = {}
	for index, value in pairs(input) do
		output[index] = deep_copy(value)
	end
	return output
end

-- light_def = {
--	lightable_nodes = -- a string or a list of strings giving the node names of liquids to make lightable (required)
--	lit_by_floodable =  -- defaults to false, if true then items that are "floodable" (such as torches) will light this liquid when weilded
--}

function wielded_light.register_lightable_node(light_def)
	if (type(light_def.lightable_nodes) == "string") then
		light_def.lightable_nodes = {light_def.lightable_nodes}
	end

	for _, lightable_node_name in ipairs(light_def.lightable_nodes) do
		node_def = minetest.registered_nodes[lightable_node_name]
		assert(node_def, "[wielded_light] unable to find definition for " .. lightable_node_name ..
			" while registering lightable liquids")
			
		lit_node_name = "wielded_light:"..string.gsub(lightable_node_name, ":", "_")
		
		liquid = node_def.liquidtype == "source" or node_def.liquidtype == "flowing"
		
		lightable_def = {lit_name = lit_node_name, lit_by_floodable = light_def.lit_by_floodable}
		assert(not lightable_nodes[lightable_node_name], lightable_node_name .. " has already been registered with wielded_light")
		lightable_nodes[lightable_node_name] = lightable_def
		
		-- build the base helper node def
		copy_def = deep_copy(node_def)
		if liquid then
			--copy_def.liquidtype = nil -- wielded_light lit nodes don't work when they're liquid types, they get modified by the engine every second and it causes flicker.
			--copy_def.climbable = true
		end
		-- After an interval, turn back into the unlit node
		copy_def.on_timer = function(pos, elapsed)
			--minetest.chat_send_all("turning back into " .. lightable_node_name .. " " .. tostring(math.random(1,100)))
			minetest.swap_node(pos, {name = lightable_node_name})
		end
		copy_def.groups = copy_def.groups or {}
		copy_def.groups.not_in_creative_inventory = 1
		copy_def.drop = copy_def.drop or lightable_node_name -- if drop is undefined, set it to drop the unlit node type
		
		for i = 1, 14 do
			-- register helper nodes for lightable node
			copy_def.light_source = i
			copy_def.groups.wielded_light = i
			minetest.register_node(lit_node_name..i, copy_def)
			assert(not lightable_nodes[lit_node_name..i], lightable_node_name .. " has already been registered with wielded_light")
			lightable_nodes[lit_node_name..i] = lightable_def -- ensure the lightable def is available for every node it incorporates
		end
	end	
end

wielded_light.register_lightable_node({lightable_nodes = "air", lit_by_floodable = true})

-- Register aliases for the old helper nodes for air
for i=1, 14 do
	minetest.register_alias("wielded_light:"..i, "wielded_light:air"..i)
end

function wielded_light.update_light(pos, light_level, itemdef)
	local around_vector = {
			{x=0, y=0, z=0},
			{x=0, y=1, z=0}, {x=0, y=-1, z=0},
			{x=1, y=0, z=0}, {x=-1, y=0, z=0},
			{x=0, y=0, z=1}, {x=0, y=0, z=1},
		}
	for _, around in ipairs(around_vector) do
		local light_pos = vector.add(pos, around)
		local name = minetest.get_node(light_pos).name
		lightable_node_def = lightable_nodes[name]
		if lightable_node_def and (lightable_node_def.lit_by_floodable or not itemdef.floodable) then
			minetest.swap_node(light_pos, {name = lightable_node_def.lit_name..light_level})
			local timer = minetest.get_node_timer(light_pos)
			timer:start(update_interval*3)
			break
		end
	end
end

function wielded_light.update_light_by_item(item, pos)
	local stack = ItemStack(item)
	local light_level = shiny_items[stack:get_name()]
	local itemdef = stack:get_definition()
	if not light_level and not itemdef then
		return
	end

	light_level = light_level or ((itemdef.light_source or 0) - level_delta)

	if light_level > 0 then
		wielded_light.update_light(pos, light_level, itemdef)
	end
end

function wielded_light.register_item_light(itemname, light_level)
	shiny_items[itemname] = light_level
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
			vector.add({x = 0, y = 1, z = 0}, vector.round(player:get_pos())),
			vector.round(vector.multiply(player:get_player_velocity(), update_interval * 1.5))
		)

		wielded_light.update_light_by_item(player:get_wielded_item(), pos)
	end
end)


-- Dropped item on_step override
-- https://github.com/minetest/minetest/issues/6909
local builtin_item = minetest.registered_entities["__builtin:item"]
local item = {
	on_step = function(self, dtime, moveresult)
		builtin_item.on_step(self, dtime, moveresult)

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


if minetest.get_modpath("default") then
	wielded_light.register_lightable_node({lightable_nodes = {"default:water_source", "default:river_water_source"}})
end

---TEST
--wielded_light.register_item_light('default:dirt', 14)


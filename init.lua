local update_interval = 0.25
local level_delta = 3

for i=1, (14-level_delta) do
	minetest.register_node("wielded_light:"..i, {
		drawtype = "airlike",
		groups = {not_in_creative_inventory = 1},
		walkable = false,
		paramtype = "light",
		sunlight_propagates = true,
		light_source = i,
		pointable = false,
		buildable_to = true,
		drops = {},
		on_timer = function(pos, elapsed)
			minetest.swap_node(pos, {name = "air"})
		end,
	})
end

local timer = 0
minetest.register_globalstep(function(dtime)
	timer = timer + dtime;
	if timer < update_interval then
		return
	end
	timer = 0

	for _, player in pairs(minetest.get_connected_players()) do
		local wstack = player:get_wielded_item()
		local light_level = wstack:get_definition().light_source
		if light_level and light_level > level_delta then
			local pos = vector.add({x = 0, y = 1, z = 0}, vector.round(player:getpos()))
			local level = light_level-level_delta
			local name = minetest.get_node(pos).name
			if name == "air" and (minetest.get_node_light(pos) or 0) < level or -- New node
					name:sub(1,13) == "wielded_light" then -- Update existing light node and timer
				minetest.swap_node(pos, {name = "wielded_light:"..level})
				minetest.get_node_timer(pos):start(update_interval*2)
			end
		end
	end
end)

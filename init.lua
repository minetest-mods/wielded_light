local update_interval = 0.2
local level_delta = 2

wielded_light = {}


function wielded_light.update_light(pos, light_level)
	local do_update = false
	local old_value = 0
	local name = minetest.get_node(pos).name
	local timer

	if name == "air" and (minetest.get_node_light(pos) or 0) < light_level then
		do_update = true
	elseif name:sub(1,13) == "wielded_light" then -- Update existing light node and timer
		old_value = tonumber(name:sub(15))
		if light_level > old_value then
			do_update = true
		else
			timer = minetest.get_node_timer(pos)
			local elapsed = timer:get_elapsed()
			if elapsed > (update_interval * 1.5) then
				-- The timer is set to 3x update_interval
				-- This node was not updated the last interval and may
				-- is disabled before the next step
				-- Therefore the light should be re-set to avoid flicker
				do_update = true
			end
		end
	end
	if do_update then
		timer = timer or minetest.get_node_timer(pos)
		if light_level ~= old_value then
			minetest.swap_node(pos, {name = "wielded_light:"..light_level})
		end
		timer:start(update_interval*3)
	end
end


local shiny_items = {}
function wielded_light.register_item_light(itemname, light_level)
	shiny_items[itemname] = light_level
end


for i=1, 14 do
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

-- Wielded item shining globalstep
local timer = 0
minetest.register_globalstep(function(dtime)
	timer = timer + dtime;
	if timer < update_interval then
		return
	end
	timer = 0

	for _, player in pairs(minetest.get_connected_players()) do
		local wstack = player:get_wielded_item()
		local light_level = shiny_items[wstack:get_name()] or
				((wstack:get_definition().light_source or 0) - level_delta)
		if light_level > 0 then
			local pos = vector.add({x = 0, y = 1, z = 0}, vector.round(player:getpos()))
			wielded_light.update_light(pos, light_level)
		end
	end
end)


---TEST
--wielded_light.register_item_light('default:dirt', 14)

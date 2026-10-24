# Wielded Light

Idea taken from [`torches_wieldlight`](https://github.com/minetest-mods/torches), but written from scratch and usable for all shining items.

![Screenshot](https://github.com/bell07/minetest-wielded_light/raw/master/screenshot.png)

All bright nodes with light value > 2 lighten the player environment if wielded, with value fewer by 2. (Torch 13->11 for example)

Dependencies: none

License: [GPL-3.0-only](/LICENSES/GPL-3.0-only.txt) see [REUSE.toml](/REUSE.toml) for further details.

## API Reference

**Light updates:**

* `wielded_light.update_light(pos, light_level)` DEPRECATED
   * Does nothing. No replacement needed.
* `wielded_light.update_light_by_item(stack, pos)` DEPRECATED
   * Does nothing.
   * Use `wielded_light.track_item_entity`

**Light source registration:**

* `wielded_light.register_item_light(itemname, light_level, [floodable])`
   * Override or set custom light level to an item. This does not change the item/node definition, just the lighting in this mod.
   * Note: as per `lua_api.md`, "item" includes nodes, tools and craftitems.
   * `itemname` (string): item to register as light source
   * `light_level` (integer): value between 0 and 14
   * `floodable` (optional, boolean)
      * Defines whether the light source is ignored when used in a liquid node.
      * `nil` (default): inherits the vaulue from the Item Definition field `floodable`
* `wielded_light.register_lightable_node(node_name, nil, nil)`
   * In order to spawn light, it is necessary to swap the underlying node with a variant
     with a custom light level.
   * This function registers variants of `node_name` such that the surrounding area can be illuminated.
   * `node_name` (string): node name to register as a light source
      * e.g. liquids, air-like nodes, plants.
   * `nil`: Undefined behavior. Keep as `nil`.

**Lua entities (luaentity) and players:**

* `wielded_light.register_player_lightstep(function(player) end)`
   * Registers a callback which is called periodically for each player.
* `wielded_light.track_user_entity(obj, cat, item_name)`
   * Must be called on each server step, e.g. `wielded_light.register_player_lightstep`
   * `obj` (ObjectRef): a player object
   * `cat` (string): any unique string
   * `item_name` (string): which item to use as light source
* `wielded_light.track_item_entity(obj, cat, item_name)`
   * Adds a light source at the entity position and updates the light periodically.
   * Must be called exactly once for `obj`.
   * `obj` (ObjectRef): a luaentity
   * `cat` (string): any unique string
   * `item_name` (string): which item to use as light source

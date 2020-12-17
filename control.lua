TICKS_PER_UPDATE = settings.global["bluebuild-speed"].value
TIMEOUT_LENGTH = 60 * 60 * 2 --2 minutes

-- Find ghosts to place.  Then find buildings to destruct.
-- function runOnce()
-- 	--This format {player_index = {position, build_toggle, demo_toggle, build_active, demo_active, start_tick, last_tick, cache = {build_cache, demo_cache, upgrade_cache}}}
-- 	--Start_tick is used to determine if building should happen.  Last_tick is used to toggle active states.
-- 	global.blue = {}

-- 	-- global.blueBuildFirstTick = global.blueBuildFirstTick or {}
-- 	-- global.bluePositions = global.bluePosition or {}
-- 	-- global.blueBuildToggle = global.blueBuildToggle or {}
-- 	-- global.blueDemoToggle = global.blueDemoToggle or {}
-- 	-- global.blueLastDemo = global.blueLastDemo = {}
-- 	-- for n, p in pairs(game.players) do
-- 	-- 	initPlayer(p)
-- 	-- end
-- end

function initPlayer(player)
	player.print("Initializing BlueBuild+")
	global.blue[player.index] = {position = player.position, build_toggle = true, demo_toggle = true, build_active=true, demo_active = false, start_tick = game.tick, last_tick = game.tick}
	-- global.blueBuildToggle[player.index] = global.blueBuildToggle[player.index] or true
	-- global.blueDemoToggle[player.index] = global.blueDemoToggle[player.index] or true
	-- global.blueBuildFirstTick[player.index] = global.blueBuildFirstTick[player.index] or game.tick
	-- global.blueLastDemo[player.index] = game.tick	
end

function playerloop()
	for _, player in pairs(game.connected_players) do
		bluecheck(player)
	end
end

function bluecheck(player)
	local pos = player.position
	local index = player.index
	if not global.blue then global.blue = {} end
	if not global.blue[index] then initPlayer(player) end
	if player.permission_group and player.permission_group.name == "se-remote-view" then return end
	if global.blue[player.index].position and global.blue[player.index].position.x == pos.x and global.blue[player.index].position.y == pos.y then
		--We haven't moved.  Good, let's continue.
		--game.print("Player hasn't moved.")
		if game.tick >= global.blue[index].start_tick + TICKS_PER_UPDATE then		
			if global.blue[index].build_toggle and global.blue[index].build_active then
				-- Make magic happen.
				if bluebuild(player) == true then
					global.blue[index].last_tick = game.tick
					global.blue[index].start_tick = game.tick
					return
				end
				--Fulfill upgrade requests.
				if blueUpgrade(player) == true then
					global.blue[player.index].last_tick = game.tick
					global.blue[index].start_tick = game.tick
					return
				end
			end
			if global.blue[index].demo_toggle and global.blue[index].demo_active then
				-- Destructive magic happens here
				if bluedemo(player) == true and player.character then
					global.blue[index].last_tick = game.tick
					global.blue[index].start_tick = game.tick
					return
				end
			end
			--Still here?  Sleep for 6 ticks anyway.
			global.blue[index].start_tick = game.tick
		end
	else
		-- Player moved.  Reset progress.
		global.blue[index].position = player.position
		global.blue[index].start_tick = game.tick
		global.blue[index].cache = nil
		--global.bluePosition[player.index] = pos
		--global.blueBuildFirstTick[player.index] = game.tick
	end
	--Has a player used bluebuild within 5 minutes?  Turn off.
	if game.tick >= global.blue[index].last_tick + 5 * 60 * 60 then
		global.blue[index].build_active=false
		global.blue[index].demo_active=false
	end
end

function bluebuild(builder)
	local pos = builder.position
	local areaList = (global.blue[builder.index].cache and global.blue[builder.index].cache.build_cache) or builder.surface.find_entities_filtered{position = pos, radius = builder.reach_distance, type = {"entity-ghost", "tile-ghost"}, force=builder.force, limit=200 }

	--local tileList = builder.surface.find_entities_filtered{position = pos, radius = builder.reach_distance, type = "tile-ghost", force=builder.force }
	-- Merge the lists
	-- for key, value in pairs(tileList) do
		-- if not areaList then
			-- areaList = {}
		-- end
		-- table.insert(areaList, value)
	-- end
	-- game.print("Found " .. #areaList .. " ghosts in area.")
	for index, ghost in pairs(areaList) do
		if ghost == nil or not ghost.valid then
			table.remove(areaList, index)
			return false
		end
		--if builder.can_reach_entity(ghost) then
		-- game.print("Checking for items in inventory.")
		local materials = ghost.ghost_prototype.items_to_place_this
		local moduleList
		if ghost.type == "entity-ghost" then
			moduleList = ghost.item_requests --{"name"=..., "count"=...}
		end
		for __, item in pairs(materials) do
			if builder.get_item_count(item.name) >= item.count then
				if ghost.type == "tile-ghost" then
					ghost.revive{raise_revive=true}
					builder.remove_item({name=item.name, count=item.count})
					return true
				end
				local tmp, revive = ghost.revive{raise_revive = true}
				-- game.print("Placing item " .. revive.name .. ".")
				if revive and revive.valid then
					for module, modulecount in pairs(moduleList) do
					-- game.print("moduleList == " .. moduleItem.item )
						if builder.get_item_count(module) > 0 then
							local modStack = {name=module, count=math.min(builder.get_item_count(module), modulecount)}
							revive.insert(modStack)
							builder.remove_item(modStack)
						end
					end
				end

				--We look to see if the ghost got removed to determine if we deduct materials.  This accounts for the case where another mod deleted the entity we built.
				if not ghost.valid then
					-- game.print("Removing item from inventory.")

					-- Depreciated method of alerting other mods.
					--"revive" flag is just a way to signal to other mods that this was raised by script.
					--  script.raise_event(defines.events.on_put_item, {position=revive.position, player_index=builder.index, shift_build=false, built_by_moving=false, direction=revive.direction, revive=true})
					--  script.raise_event(defines.events.on_built_entity, {created_entity=revive, player_index=builder.index, stack tick=game.tick, name="on_built_entity", revive=true})

					builder.remove_item({name=item.name, count=item.count})
					table.remove(areaList, index)
					return true
				end
			end
		end
	end
	-- Are we still here?
	return false
end		

function bluedemo(builder)
	local pos = builder.position
	--local reachDistance = data.raw.player.player.reach_distance
	-- Reach distance must not be 0.  Just for you, Choumiko.  Now works with FAT Controller
	local reachDistance = math.max(math.min(builder.reach_distance, 128), 1)
	--local searchArea = {{pos.x - reachDistance, pos.y - reachDistance}, {pos.x + reachDistance, pos.y + reachDistance}}
	local areaList = builder.surface.find_entities_filtered{position = pos, radius = reachDistance, to_be_deconstructed=true, limit=100} --I may have greatly underestimated how many entities you can fit in a 14x14 block.
	--local areaListCleaned = {}
	
	-- if not global.blue[builder.index] then
	-- 	initPlayer(builder.index)
	-- end
	
	-- Clean areaList of entities not marked for decon
	for i = #areaList, 1, -1 do
		local ent = areaList[i]
		if not (ent and ent.valid and ent.to_be_deconstructed(game.forces.player) and builder.can_reach_entity(ent)) then
			table.remove(areaList, i)
		end
	end
	--game.print("Found " .. #areaListCleaned .. " demo targets in area.")
	--Now calculate mining time and destroy
	for index, ent in pairs(areaList) do
		if ent.name == "deconstructible-tile-proxy" then --In case we're trying to demo floor tiles.
			tile = ent.surface.get_tile(ent.position)
			--game.print(ent.prototype.mineable_properties)
			builder.mine_tile(tile)
			global.blue[builder.index].last_tick = game.tick
			return true
		end
		
		--Mining time is player... Nevermind, player.mining_power does not yet exist.  We'll just assume mining power of 2.5 (iron pickaxe)
		-- TODO: This is busted.  Everything is mining instantly!
		if game.tick > global.blue[builder.index].last_tick + ent.prototype.mineable_properties.mining_time * 60 then
			-- This might all be obsolete now thanks to player.mine_entity(entity)
			--global.blueLastDemo[builder.index] = game.tick
			if builder.mine_entity(ent) then
				global.blue[builder.index].last_tick = game.tick
				return true
			end	--Could not mine target for whatever reason.  Inventory probably full.
			--[[
			-- Add inventory of the destroyed
			-- game.print("Destroyed inventory: " .. serpent.line(ent.get_inventory(defines.inventory.item_main)))
			for inv, def in pairs(defines.inventory) do --]
				local inventory = ent.get_inventory(def)
				if inventory and inventory.valid then
					contents = inventory.get_contents()
					if contents then
						--game.print("Inventory " .. serpent.line(def) .. " contents: " .. serpent.line(contents))
						for key, value in pairs(contents) do
							local inserted = builder.insert({name=key, count=value})
							if inserted > 0 then
								ent.remove_item({name=key, count=inserted})
							end
							if inserted == 0 or not inserted == value then --Not enough inventory!
								builder.surface.create_entity({name="flying-text", position=builder.position, text="Inventory Full"})
								return true
							end
						end
					end
				end
			end
			--Add mining products
			local products = ent.prototype.mineable_properties.products			
			local inserted = 0
			if products then
				-- game.print("Products: " .. serpent.line(products))
				for key, value in pairs(products) do
					inserted = builder.insert({name=value.name, count=math.random(value.amount_min, value.amount_max)})
				end
			end
			-- Is the destroyed item a item-entity?
			if not isTile and ent.type == "item-entity" then
				inserted = builder.insert({name=ent.stack.name, count=ent.stack.count})
			end
			-- Was anything inserted?  If not, end here so we don't destroy the entity
			if inserted == 0 then
				builder.surface.create_entity({name="flying-text", position=builder.position, text="Inventory Full"})
				game.print(ent.name) -- Debug
				return true
			end
			script.raise_event(defines.events.on_preplayer_mined_item, {entity=ent, player_index=builder.index, name="on_preplayer_mined_item"})
			ent.destroy()
			return true
			]]
		end
	end
	return false
end

function blueUpgrade(builder)
	local pos = builder.position
	local reachDistance = math.max(math.min(builder.reach_distance, 128), 1)
	local areaList = builder.surface.find_entities_filtered{position = pos, radius = reachDistance, to_be_upgraded=true, limit=150}
	for _, target in pairs(areaList) do
		local itemsNeeded = target and target.valid and target.get_upgrade_target() and target.get_upgrade_target().items_to_place_this[1]
		local upgrade = target.get_upgrade_target()
		if itemsNeeded and builder.get_item_count(itemsNeeded.name) >= itemsNeeded.count then
			builder.surface.play_sound{position=target.position, path="entity-build/" .. upgrade.name}
			local underground
			if target.type == "underground-belt" then
				underground = target.belt_to_ground_type
			end
			local built = builder.surface.create_entity{position=target.position, name=upgrade.name, force=builder.force, direction=target.direction, fast_replace=true, player=builder, raise_built=true, type=underground}
			if built then
				builder.remove_item{name=itemsNeeded.name, count=itemsNeeded.count}
				return true
			end
		end
	end
end

--Reinventing the wheel
-- function distance(ent1, ent2)
-- 	return math.floor( math.sqrt( (ent1.position.x - ent2.position.x)^2 + (ent1.position.y - ent2.position.y)^2 ) )
-- end

-- function updateGhosts()
-- 	if not global.ghosts then
-- 		global.ghosts = {}
-- 	end
-- 	for __, surface in pairs(game.surfaces) do
-- 		-- type(surface) is string
-- 		if not global.ghosts[surface.name] then 
-- 			global.ghosts[surface.name] = {}
-- 		end
-- 		global.ghosts[surface.name] = game.surfaces[surface.name].find_entities_filtered{name="entity-ghost"}
-- 	end
-- end

--Toggle Bluebuild on
script.on_event(defines.events.on_built_entity, function(event)
	-- if not global.ghosts then
	-- 	global.ghosts = {}
	-- end
	if event.created_entity and (event.created_entity.name == "entity-ghost" or event.created_entity.name == "tile-ghost") then
		-- if not global.ghosts[event.created_entity.surface.name] then 
		-- 	global.ghosts[event.created_entity.surface.name] = {}
		-- end
		-- table.insert(global.ghosts[event.created_entity.surface.name], event.created_entity)
		global.blue[event.player_index].build_active=true
		global.blue[event.player_index].last_tick = game.tick
	end
end)

--Toggle bluedemo on
function demo_toggle(event)
	if event.player_index then
		global.blue[event.player_index].demo_active = true
		global.blue[event.player_index].last_tick = game.tick
	end
end

-- script.on_event(defines.events.on_player_joined_game, function(event)
-- 	initPlayer(game.players[event.player_index])
-- end)
	
script.on_event(defines.events.on_marked_for_deconstruction, demo_toggle)

script.on_event(defines.events.on_tick, function(event)
	playerloop()
	-- Update ghost list every 5 minutes.
	-- if (game.tick + 500) % (60 * 60 * 5) == 0 then
	-- 	updateGhosts()
	-- end
end)


script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
	if (event.setting == "bluebuild-speed") then
		TICKS_PER_UPDATE = settings.global["bluebuild-speed"].value
		if TICKS_PER_UPDATE > 0 then
		-- Overly complex, but who cares?
			tps = 60 / TICKS_PER_UPDATE
			if tps < 1 then
				game.print("BlueBuild+ updating at 1 tile per " .. 1 / tps .. " seconds")
			elseif tps == 1 then
				game.print("BlueBuild+ updating at 1 tile per second")
			else
				game.print("BlueBuild+ updating at " .. tps .. " tiles per second")
			end
		else
			game.print("BlueBuild+ updating as fast as possible")
		end
	end
end)

script.on_event('bluebuild-autobuild', function(event)
	global.blue[event.player_index].build_toggle = not global.blue[event.player_index].build_toggle
	if global.blue[event.player_index].build_toggle then str = "enabled" else str = "disabled" end
	game.players[event.player_index].print("BlueBuild+ AutoBuild " .. str .. ".")
	global.blue[event.player_index].build_active = true
	global.blue[event.player_index].start_tick = game.tick
end)

script.on_event('bluebuild-autodemo', function(event)
	global.blue[event.player_index].demo_toggle = not global.blue[event.player_index].demo_toggle
	if global.blue[event.player_index].demo_toggle then str = "enabled" else str = "disabled" end
	game.players[event.player_index].print("BlueBuild+ AutoDemo " .. str .. ".")
	global.blue[event.player_index].demo_active = true
	global.blue[event.player_index].start_tick = game.tick
end)

--script.on_init(runOnce)

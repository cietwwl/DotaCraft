-- The first Hero is free, only costs 5 supply and comes with a free Town Portal Scroll and a free skill point.
-- Additional Heroes require resources, and come with one skill point but do not have additional Town Portal Scrolls. 
-- To build a second Hero, you must upgrade your Town Hall to a Keep instead of a Town Hall. 
-- To build a third Hero you must have a third level Town Hall building such as a Castle.
-- You cannot train more than 3 Heroes, nor buy the same hero more than once
-- When a hero dies, the altar will gain the ability to respawn it for a cost

function BuildHero( event )
	local caster = event.caster
	local player = caster:GetPlayerOwner()
	local hero = player:GetAssignedHero()
	local playerID = player:GetPlayerID()
	local unit_name = event.Hero
	local origin = event.caster:GetAbsOrigin() + RandomVector(250)

	-- Get a random position to create the new_hero in
	local origin = caster:GetAbsOrigin() + RandomVector(150)

	-- handle_UnitOwner needs to be nil, else it will crash the game.
	local new_hero = CreateUnitByName(unit_name, origin, true, hero, nil, hero:GetTeamNumber())
	new_hero:SetPlayerID(playerID)
	new_hero:SetControllableByPlayer(playerID, true)
	new_hero:SetOwner(hero)
	
	if caster.flag then
		local position = caster.flag:GetAbsOrigin()
		Timers:CreateTimer(0.05, function() 
			FindClearSpaceForUnit(new_hero, new_hero:GetAbsOrigin(), true)
			new_hero:MoveToPosition(position) 
		end)
		print(new_hero:GetUnitName().." moving to position",position)
	end

	-- Add the hero to the table of heroes acquired by the player
	table.insert(player.heroes, new_hero)

	-- Swap the (hidden) finished hero ability for a passive version, to indicate it has been trained
	local ability = event.ability
	local ability_name = ability:GetAbilityName()
	
	-- Cut the _train and rank, add the _acquired suffix
	local new_ability_name = string.gsub(ability_name, "_train" , "")
	new_ability_name = string.sub(new_ability_name, 1 , string.len(new_ability_name) - 1).."_acquired"

	-- Swap and Disable on each altars
	for _,altar in pairs(player.altar_structures) do
		altar:AddAbility(new_ability_name)
		altar:SwapAbilities(ability_name, new_ability_name, false, true)
		altar:RemoveAbility(ability_name)
		local new_ability = altar:FindAbilityByName(new_ability_name)
		new_ability:SetLevel(new_ability:GetMaxLevel())
	end

end

function UpgradeAltarAbilities( event )
	local caster = event.caster
	local abilityOnProgress = event.ability
	local player = caster:GetPlayerOwner()

	-- Keep simple track of the abilities being queued, these can't be removed/upgraded else the channeling wont go off
	if not player.altar_queue then
		player.altar_queue = {}
	end

	-- Simple track of the current global rank
	if not player.AltarLevel then
		player.AltarLevel = 2
	else
		player.AltarLevel = player.AltarLevel + 1
	end

	table.insert(player.altar_queue, abilityOnProgress:GetAbilityName())
	print("ALTAR LEVEL "..player.AltarLevel.." QUEUE:")
	DeepPrintTable(player.altar_queue)

	-- On Each altar
	for _,altar in pairs(player.altar_structures) do
		for i=0,15 do
			local ability = altar:GetAbilityByIndex(i)
			if ability then
				local ability_name = ability:GetAbilityName()
				if string.find(ability_name, "_train") then
					if ability_name ~= abilityOnProgress:GetAbilityName() then	
						if player.AltarLevel == 4	then -- Disable completely
							ability:SetHidden(true)
							--altar:RemoveAbility(ability_name)
						else	

							local ability_len = string.len(ability_name)
							local rank = string.sub(ability_name, ability_len , ability_len)
							if rank ~= "0" then
								local new_ability_name = string.gsub(ability_name, rank , player.AltarLevel)

								-- If the ability has to be channeled (i.e. is queued), it cant be removed!
								if not tableContains(player.altar_queue, ability_name) then
									altar:AddAbility(new_ability_name)
									altar:SwapAbilities(ability_name, new_ability_name, false, true)
									altar:RemoveAbility(ability_name)

									local new_ability = altar:FindAbilityByName(new_ability_name) 
									new_ability:SetLevel(new_ability:GetMaxLevel())
									print("Swapped "..ability_name.." with "..new_ability:GetAbilityName())
								else
									ability:SetHidden(true)
									print("Table Contains "..ability_name.." set Hidden because the altar will be casting it later")
								end
							end
						end
					else
						-- Things go wrong if the ability being channeled is removed so just set it hidden
						ability:SetHidden(true)
					end
				end
			end			
		end

		-- Look to disable the upgraded abilities if the requirements arent met
		CheckAbilityRequirements(altar, player)

		local hero = altar:GetPlayerOwner():GetAssignedHero()
		local playerID = hero:GetPlayerID()
		FireGameEvent( 'ability_values_force_check', { player_ID = playerID })

		PrintAbilities(altar)
	end
end

function ReEnableAltarAbilities( event )
	local caster = event.caster
	local ability = event.ability
	local player = caster:GetPlayerOwner()

	 -- Remove the "item_" to compare
	local item_name = ability:GetAbilityName()
    local train_ability_name = string.gsub(item_name, "item_", "")
	print("ABILITY NAME : "..train_ability_name)

	-- Remove it from the altar queue
	local queue_element = getIndex(player.altar_queue, train_ability_name)
    table.remove(player.altar_queue, queue_element)

	-- This is the level at which all train abilities should end up
	player.AltarLevel = player.AltarLevel - 1

	print("ALTAR LEVEL "..player.AltarLevel.." QUEUE:")
	DeepPrintTable(player.altar_queue)

	print("--")
	-- On Each altar
	for _,altar in pairs(player.altar_structures) do
		for i=0,15 do
			local ability = altar:GetAbilityByIndex(i)
			if ability then
				local ability_name = ability:GetAbilityName()

				-- Gotta adjust back the abilities
				-- The hidden train ability was one in the queue
				if string.find(ability_name, "_train") then
				 	if ability:IsHidden() then

				 		-- The level which abilities have to be downgraded and set visible depends on the current AltarLevel
				 		-- There's some critical issues with different cancelling of the queue that have to be considered

						if not tableContains(player.altar_queue, ability_name) then

							-- Adjust the correct rank of this ability
							local ability_len = string.len(ability_name)
							local rank = tonumber(string.sub(ability_name, ability_len , ability_len))
							local adjusted_ability_name = string.gsub(ability_name, rank , tostring( player.AltarLevel))
							print(rank,ability_name,player.AltarLevel,adjusted_ability_name)

							local correct_ability = altar:FindAbilityByName(adjusted_ability_name)
							if correct_ability then
								correct_ability:SetHidden(false)
								print(adjusted_ability_name.." is now visible")
							else
								-- The ability has to be set to a new level that didn't exist originally
								print("Adding new adjusted ability "..adjusted_ability_name)
								altar:AddAbility(adjusted_ability_name)
								altar:SwapAbilities(ability_name, adjusted_ability_name, false, true)
								altar:RemoveAbility(ability_name)

								local new_adjusted_ability = altar:FindAbilityByName(adjusted_ability_name)
								new_adjusted_ability:SetLevel(new_adjusted_ability:GetMaxLevel())

							end
						else
							ability:SetHidden(true)
							print("Table Contains "..ability_name.." - Keep it hidden, its queued")
						end
					else
						-- If the ability is disabled, need to adjust
						if string.find(ability_name, "_disabled")  then
							ability_name = string.gsub(ability_name, "_disabled" , "")
							print("Adjusted ability name")
						end

						local ability_len = string.len(ability_name)
						local rank = string.sub(ability_name, ability_len , ability_len)
						print(ability_name,rank)
						if rank ~= "1" then

							local downgraded_ability_name = string.gsub(ability_name, rank , tostring( tonumber(rank) - 1))
							print("downgraded_ability_name: ", downgraded_ability_name)

							altar:AddAbility(downgraded_ability_name)
							altar:SwapAbilities(ability_name, downgraded_ability_name, false, true)
							altar:RemoveAbility(ability_name)
							altar:RemoveAbility(ability_name.."_disabled")

							local new_ability = altar:FindAbilityByName(downgraded_ability_name) 
							new_ability:SetLevel(new_ability:GetMaxLevel())
							print("Swapped "..ability_name.." with "..new_ability:GetAbilityName())
							print("--")
						else
							print("RANK 0 WAOW")
							print('--')
						end
					end
				end
			end
		end

		-- Look to disable the downgraded abilities if the requirements arent met
		local player = altar:GetPlayerOwner()
		CheckAbilityRequirements( structure, player )

		PrintAbilities(altar)
	end

end

-- Keep a player.altar after the player builds its first Altar
-- Clone the abilities of this building if possible, if its killed try to find another in the structures list
-- If no altar can be found, check the player.heroes table and decide which rank to apply
-- This can also include setting re-train abilities (because the heroes are dead) or passive version if the hero is still alive
function LinkAltar( event )
	local altar = event.caster
	local player = altar:GetPlayerOwner()

	-- If no altar is active, this will be the reference
	if not player.altar then
		player.altar = altar
		player.altar_structures = {}
	end

	-- Keep all altars in a separate structure list
	table.insert(player.altar_structures, altar)

	if altar ~= player.altar and IsValidEntity(player.altar) then
		print("Linking this Altar to "..player.altar:GetEntityIndex())
		CloneAltarAbilities( altar, player.altar )
	end

end

-- Copies the abilities on the main altar to the newly built altar
function CloneAltarAbilities( unit, source )

	-- First remove the train abilities on the unit
	for i=0,15 do
		local unit_ability = unit:GetAbilityByIndex(i)

		if unit_ability then
			local ability_name = unit_ability:GetAbilityName()
			if string.find(ability_name, "_train") then
				unit:RemoveAbility(ability_name)
			end
		end
	end

	-- Then copy over the abilities of the source
	for i=0,15 do
		local source_ability = source:GetAbilityByIndex(i)

		if source_ability then
			local ability_name = source_ability:GetAbilityName()
			if string.find(ability_name, "_train") or string.find(ability_name, "_acquired") then
				unit:AddAbility(ability_name)
				local ability = unit:FindAbilityByName(ability_name)
				if ability then 
					if source_ability:IsHidden() then
						ability:SetHidden(true)
					end
					ability:SetLevel(ability:GetMaxLevel())
				else
					print("Failed to add "..ability_name)
				end
			end
		end
	end
end
function FastReloadScript:StartScript()
end

function FastReloadScript:UpdateScript()
	local activity = ActivityMan:GetActivity()
	for player = Activity.PLAYER_1, Activity.MAXPLAYERCOUNT - 1 do
		if activity:PlayerActive(player) and activity:PlayerHuman(player) then
			local actor = activity:GetControlledActor(player)
			if actor and IsAHuman(actor) then
				actor = ToAHuman(actor)
				if actor.EquippedItem and IsHDFirearm(actor.EquippedItem) then
					local weapon = ToHDFirearm(actor.EquippedItem)
					if not weapon:NumberValueExists("FastReload") then
						weapon:SetNumberValue("FastReload", 1)
						weapon.ReloadTime = math.floor(weapon.ReloadTime / 5)
					end
				end
			end
		end
	end
end

function FastReloadScript:EndScript()
end

function FastReloadScript:PauseScript()
end

function FastReloadScript:CraftEnteredOrbit()
end

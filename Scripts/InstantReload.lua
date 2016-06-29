function InstantReloadScript:StartScript()
end

function InstantReloadScript:UpdateScript()
	local activity = ActivityMan:GetActivity()
	for player = Activity.PLAYER_1, Activity.MAXPLAYERCOUNT - 1 do
		if activity:PlayerActive(player) and activity:PlayerHuman(player) then
			local actor = activity:GetControlledActor(player)
			if actor and IsAHuman(actor) then
				actor = ToAHuman(actor)
				if actor.EquippedItem and IsHDFirearm(actor.EquippedItem) then
					local weapon = ToHDFirearm(actor.EquippedItem)
					if not weapon:NumberValueExists("InstantReload") then
						weapon:SetNumberValue("InstantReload", 1)
						weapon.ReloadTime = 0
					end
				end
			end
		end
	end
end

function InstantReloadScript:EndScript()
end

function InstantReloadScript:PauseScript()
end

function InstantReloadScript:CraftEnteredOrbit()
end

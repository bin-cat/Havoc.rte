function LongerSightRangeScript:StartScript()
end

function LongerSightRangeScript:UpdateScript()
	local activity = ActivityMan:GetActivity()
	for player = Activity.PLAYER_1, Activity.MAXPLAYERCOUNT - 1 do
		if activity:PlayerActive(player) and activity:PlayerHuman(player) then
			local actor = activity:GetControlledActor(player)
			if actor and IsAHuman(actor) then
				actor = ToAHuman(actor)
				if actor.EquippedItem and IsHDFirearm(actor.EquippedItem) then
					local weapon = ToHDFirearm(actor.EquippedItem)
					if not weapon:NumberValueExists("LongerSightRange") then
						weapon:SetNumberValue("LongerSightRange", 1)
						weapon.SharpLength = math.min(math.floor(weapon.SharpLength * 3), 600)
					end
				end
			end
		end
	end
end

function LongerSightRangeScript:EndScript()
end

function LongerSightRangeScript:PauseScript()
end

function LongerSightRangeScript:CraftEnteredOrbit()
end

dofile("Base.rte/Constants.lua")

function OldSkirmish:StartActivity()
	collectgarbage("collect")
	
	for player = Activity.PLAYER_1, Activity.MAXPLAYERCOUNT - 1 do
		if self:PlayerActive(player) and self:PlayerHuman(player) then
			-- Check if we already have a brain assigned
			if not self:GetPlayerBrain(player) then
				local foundBrain = MovableMan:GetUnassignedBrain(self:GetTeamOfPlayer(player))
				-- If we can't find an unassigned brain in the scene to give each player, then force to go into editing mode to place one
				if not foundBrain then
					self.ActivityState = Activity.EDITING
					-- Open all doors so we can do pathfinding through them with the brain placement
					MovableMan:OpenAllDoors(true, Activity.NOTEAM)
					AudioMan:ClearMusicQueue()
					AudioMan:PlayMusic("Base.rte/Music/dBSoundworks/ccambient4.ogg", -1, -1)
					self:SetLandingZone(Vector(player*SceneMan.SceneWidth/4, 0), player)
				else
					-- Set the found brain to be the selected actor at start
					self:SetPlayerBrain(foundBrain, player)
					self:SwitchToActor(foundBrain, player, self:GetTeamOfPlayer(player))
					self:SetLandingZone(self:GetPlayerBrain(player).Pos, player)
					-- Set the observation target to the brain, so that if/when it dies, the view flies to it in observation mode
					self:SetObservationTarget(self:GetPlayerBrain(player).Pos, player)
				end
			end
		end
	end
	
	-- Set all actors defined in the ini-file to sentry mode
	for actor in MovableMan.AddedActors do
		if actor.ClassName == "AHuman" or actor.ClassName == "ACrab" then
			actor.AIMode = Actor.AIMODE_SENTRY
		end
	end

	-- Count CPU teams
	self.CPUTeamCount = 0
	for team = 0, Activity.MAXTEAMCOUNT - 1 do
		if self:TeamActive(team) and self:TeamIsCPU(team) then
			self.CPUTeamCount = self.CPUTeamCount + 1
		end
	end
	
	-- Add a CPU team if we only have one team
	if self.CPUTeamCount == 0 then
		local activeTeams = 0
		for player = Activity.PLAYER_1, Activity.MAXPLAYERCOUNT - 1 do
			if self:PlayerHuman(player) then
				activeTeams = activeTeams + 1
			end
		end
		
		if activeTeams < 2 then
			local cputeam = -1;
			
			for player = Activity.PLAYER_1, Activity.MAXPLAYERCOUNT - 1 do
				if self:PlayerActive(player) and self:PlayerHuman(player) then
					cputeam = self:GetTeamOfPlayer(player) + 1
					if cputeam > Activity.TEAM_4 then
						cputeam = Activity.TEAM_1
					end
				end
			end
			
			self.CPUTeam = cputeam
			self.CPUTeamCount = 1
		end
	end
	
	-- Initialize the AI
	local CPUTeams = {};	
	self.AI = {}
	
	for team = 0, Activity.MAXTEAMCOUNT - 1 do
		if self:TeamActive(team) and self:TeamIsCPU(team) then
			table.insert(CPUTeams, team);
			
			self.AI[team] = {}
			self.AI[team].defeated = false;
			self.AI[team].SpawnTimer = Timer()
			self.AI[team].HuntTimer = Timer()
			self.AI[team].timeToSpawn = 8000 - 50 * self.Difficulty			-- Time before the first AI spawn: from 8s to 3s
			self.AI[team].baseSpawnTime = 8000 - 40 * self.Difficulty		-- From 8s to 4s
			self.AI[team].randomSpawnTime = 4000 - 20 * self.Difficulty		-- From 4s to 2s
			self.AI[team].digToBrainProbability = 0
			
			if self.Difficulty > 55 then
				self.AI[team].digToBrainProbability = self.Difficulty / 320
			end
			
			-- Select a tech for the CPU player
			self.AI[team].TechID = PresetMan:GetModuleID(self:GetTeamTech(team))
			
			-- Store data about player teams: self.AI[team].OnPlayerTeam[Act.Team] is true if "Act" is an enemy to the AI
			self.AI[team].OnPlayerTeam = {}
			for player = Activity.PLAYER_1, Activity.MAXPLAYERCOUNT - 1 do
				if self:PlayerActive(player) and self:PlayerHuman(player) then
					self.AI[team].OnPlayerTeam[self:GetTeamOfPlayer(player)] = true
				end
			end
			
			-- Switch to endless mode
			if self:GetStartingGold() > 100000 then
				self.endless = true
				self:SetTeamFunds(100000, team)
			else
				self:SetTeamFunds(80 * self.Difficulty + 2000, team)	-- AI team gold: from 2k to 10k
			end
		else
			self:SetTeamFunds(self:GetStartingGold(), team)
		end
		
		-- Set initial gold for human teams
		if self:TeamActive(team) and not self:TeamIsCPU(team) then
			self:SetTeamFunds(self:GetStartingGold(), Activity.TEAM_1)
		end
	end

	-- Store data about terrain and enemy actors in the LZ map, use it to pick safe landing zones
	self.LZmap = require("Activities/LandingZoneMap")
	self.LZmap:Initialize(CPUTeams)
	
	self.StartTimer = Timer()
	
	self.Fog = self:GetFogOfWarEnabled()
end


function OldSkirmish:EndActivity()
	-- Play sad music if no humans are left
	if self:HumanBrainCount() == 0 then
		AudioMan:ClearMusicQueue();
		AudioMan:PlayMusic("Base.rte/Music/dBSoundworks/udiedfinal.ogg", 2, -1.0);
		AudioMan:QueueSilence(10);
		AudioMan:QueueMusicStream("Base.rte/Music/dBSoundworks/ccambient4.ogg");		
	else
		-- But if humans are left, then play happy music!
		AudioMan:ClearMusicQueue();
		AudioMan:PlayMusic("Base.rte/Music/dBSoundworks/uwinfinal.ogg", 2, -1.0);
		AudioMan:QueueSilence(10);
		AudioMan:QueueMusicStream("Base.rte/Music/dBSoundworks/ccambient4.ogg");
	end
end


function OldSkirmish:UpdateActivity()
	if self.ActivityState == Activity.OVER then
		return
	end
	
	if self.ActivityState == Activity.EDITING then
		-- Game is in editing or other modes, so open all does and reset the game running timer
		MovableMan:OpenAllDoors(true, Activity.NOTEAM)
		self.StartTimer:Reset()
	else	
		-- Close all doors after placing brains so our fortresses are secure
		if not self.StartTimer:IsPastSimMS(500) then
			MovableMan:OpenAllDoors(false, Activity.NOTEAM)
			
			-- Make sure all actors are in sentry mode
			for Act in MovableMan.Actors do
				if Act.ClassName == "AHuman" or Act.ClassName == "ACrab" then
					Act.AIMode = Actor.AIMODE_SENTRY
				end
			end
			
			for team = 0, Activity.MAXTEAMCOUNT - 1 do
				if self:TeamActive(team) and self:TeamIsCPU(team) then
					if self.AI[team] then
						self.AI[team].SpawnTimer:Reset()
					end
				end
			end
			
			-- Add fog
			if self.Fog then
				self.Fog = false	-- only run once
				
				for player = Activity.PLAYER_1, Activity.MAXPLAYERCOUNT - 1 do
					if self:PlayerActive(player) and self:PlayerHuman(player) then
						SceneMan:MakeAllUnseen(Vector(25, 25), self:GetTeamOfPlayer(player))
					end
				end
				
				for team = 0, Activity.MAXTEAMCOUNT - 1 do
					if self:TeamActive(team) and self:TeamIsCPU(team) then
						SceneMan:MakeAllUnseen(Vector(65, 65), team)
					end
				end
				
				for Act in MovableMan.AddedActors do
					if Act.ClassName ~= "ADoor" then
						for ang = 0, math.pi*2, 0.15 do
							SceneMan:CastSeeRay(Act.Team, Act.EyePos, Vector(30+FrameMan.PlayerScreenWidth*0.5, 0):RadRotate(ang), Vector(), 1, 5)
						end
					end
				end
				
				for Act in MovableMan.Actors do
					if Act.ClassName ~= "ADoor" then
						for ang = 0, math.pi*2, 0.15 do
							SceneMan:CastSeeRay(Act.Team, Act.EyePos, Vector(30+FrameMan.PlayerScreenWidth*0.5, 0):RadRotate(ang), Vector(), 1, 5)
						end
					end
				end
			end
		end
		
		-- Clear all objective markers, they get re-added each frame
		self:ClearObjectivePoints()
		-- Keep track of which teams we have set objective points for already, since multiple players can be on the same team
		local setTeam = { [Activity.TEAM_1] = false, [Activity.TEAM_2] = false, [Activity.TEAM_3] = false, [Activity.TEAM_4] = false }
		local teamtally = 0
		local playertally = 0
		for player = Activity.PLAYER_1, Activity.MAXPLAYERCOUNT - 1 do
			if self:PlayerActive(player) and self:PlayerHuman(player) then
				if not self.StartTimer:IsPastRealMS(3000) then
					FrameMan:SetScreenText("Survive the assault!", player, 333, 5000, true)
				end
				-- The current player's team
				local team = self:GetTeamOfPlayer(player)
				
				-- If player brain is dead then try to find another, maybe he just entered craft
				if not MovableMan:IsActor(self:GetPlayerBrain(player)) then
					local newBrain = MovableMan:GetUnassignedBrain(self:GetTeamOfPlayer(player));
					if newBrain then
						self:SetPlayerBrain(newBrain, player)
						self:SwitchToActor(newBrain, player, self:GetTeamOfPlayer(player))
						self:SetLandingZone(self:GetPlayerBrain(player).Pos, player)
						self:SetObservationTarget(self:GetPlayerBrain(player).Pos, player)
					end
				end

				-- Check if any player's brain is dead and we could not find another
				if not MovableMan:IsActor(self:GetPlayerBrain(player)) then
					self:SetPlayerBrain(nil, player)
					self:ResetMessageTimer(player)
					FrameMan:ClearScreenText(player)
					FrameMan:SetScreenText("Your brain has been destroyed!", player, 333, -1, false)
				else
					playertally = playertally + 1
					if not setTeam[team] then
						-- Add objective points
						self:AddObjectivePoint("Protect!", self:GetPlayerBrain(player).AboveHUDPos, team, GameActivity.ARROWDOWN)
						for otherPlayer = Activity.PLAYER_1, Activity.MAXPLAYERCOUNT - 1 do
							if otherPlayer ~= player and self:PlayerActive(otherPlayer) and self:PlayerHuman(otherPlayer) and MovableMan:IsActor(self:GetPlayerBrain(otherPlayer)) then
								local otherTeam = self:GetTeamOfPlayer(otherPlayer)
								if otherTeam ~= team then
									self:AddObjectivePoint("Destroy!", self:GetPlayerBrain(otherPlayer).AboveHUDPos, team, GameActivity.ARROWDOWN)
								else
									self:AddObjectivePoint("Protect!", self:GetPlayerBrain(otherPlayer).AboveHUDPos, team, GameActivity.ARROWDOWN)
								end
							end
						end
						
						setTeam[team] = true
						teamtally = teamtally + 1
					end
				end
			end
		end
		
		-- Win/Lose Conditions player vs player
		if self.CPUTeamCount == 0 then
			if teamtally < 2 then
				for team = Activity.TEAM_1, Activity.TEAM_4 do
					if setTeam[team] then
						self.WinnerTeam = team
						break
					end
				end
				
				ActivityMan:EndActivity()
				return
			end
		else
			-- Win/Lose Conditions player vs AI
			if playertally < 1 then
				for team = 0, Activity.MAXTEAMCOUNT - 1 do
					if self:TeamActive(team) and self:TeamIsCPU(team) then
						self.WinnerTeam = team
						ActivityMan:EndActivity()
						return
					end
				end
			end
			
			-- Win/Lose conditions multiple CPU's
			if self.CPUTeamCount > 0 then
				local survivedAIs = 0;
				for team = Activity.TEAM_1, Activity.TEAM_4 do
					if self:TeamActive(team) and self:TeamIsCPU(team) then
						if not self.AI[team].defeated then
							survivedAIs = survivedAIs + 1
						end
					end
				end
				
				if survivedAIs == 0 then
					self.CPUTeamCount = 0
				end			
			end
			
			for team = 0, Activity.MAXTEAMCOUNT - 1 do
				if self:TeamActive(team) and self:TeamIsCPU(team) then
					self.LZmap:Update()	-- Update info about landing zones and player actors
					
					-- Check if any AI actors have reached their destination
					if self.AI[team].HuntTimer:IsPastSimMS(8000) then
						self.AI[team].HuntTimer:Reset()
						
						for Act in MovableMan.Actors do 
							if Act.Team == team and Act.AIMode ~= Actor.AIMODE_GOLDDIG and (Act.ClassName == "AHuman" or Act.ClassName == "ACrab") then
								if (Act.AIMode == Actor.AIMODE_GOTO and SceneMan:ShortestDistance(Act:GetLastAIWaypoint(), Act.Pos, false).Largest < 100) or 
									Act.AIMode == Actor.AIMODE_SENTRY or Act.Age > 80000
								then
									-- Destination reached: hunt for the brain
									Act.AIMode = Actor.AIMODE_BRAINHUNT
								end
							end
						end
					end
					
					-- The AI have money to buy units
					if self:GetTeamFunds(team) > 0 then
						if self.AI[team].SpawnTimer:IsPastSimMS(self.AI[team].timeToSpawn) then
							if self.AI[team].AttackPos then	-- Search for a LZ from where to attack the target
								if self.AI[team].DigToBrain then
									local easyPathLZx, easyPathLZobst, closeLZx, closeLZobst = self.LZmap:FindLZ(team, self.AI[team].AttackPos, 200)	-- Heavy digger
									if easyPathLZx then	-- Search done
										self.AI[team].SpawnTimer:Reset()
										self.AI[team].digToBrainProbability = self.AI[team].digToBrainProbability * 0.4
										self.AI[team].timeToSpawn = (self.AI[team].baseSpawnTime + math.random(self.AI[team].randomSpawnTime)) * rte.SpawnIntervalScale
										
										-- Search for another target
										self.AI[team].AttackTarget = nil
										self.AI[team].AttackPos = nil
										self.AI[team].DigToBrain = nil
									end
								else
									local easyPathLZx, easyPathLZobst, closeLZx, closeLZobst = self.LZmap:FindLZ(team, self.AI[team].AttackPos)
									if easyPathLZx then	-- Search done
										self.AI[team].SpawnTimer:Reset()
										if self.AI[team].digToBrainProbability > 0 then
											self.AI[team].digToBrainProbability = math.min(self.AI[team].digToBrainProbability+0.03, self.Difficulty/320)
										end
										
										local xPosLZ, obstacleHeight
										if closeLZobst < 25 and easyPathLZobst < 25 then
											if math.random() < 0.6 then
												xPosLZ = closeLZx
												obstacleHeight = closeLZobst
											else
												xPosLZ = easyPathLZx
												obstacleHeight = easyPathLZobst
											end
										elseif closeLZobst > 100 then
											xPosLZ = easyPathLZx
											obstacleHeight = easyPathLZobst
										else
											if math.random() < 0.4 then
												xPosLZ = closeLZx
												obstacleHeight = closeLZobst
											else
												xPosLZ = easyPathLZx
												obstacleHeight = easyPathLZobst
											end
										end
										
										if obstacleHeight > 200 and math.random() < 0.6 then
											if math.random() < self.Difficulty/111 then
												self.AI[team].timeToSpawn = (self.AI[team].baseSpawnTime + math.random(self.AI[team].randomSpawnTime)) * rte.SpawnIntervalScale
											else
												self.AI[team].timeToSpawn = 500
											end
											
											-- This target is very difficult to reach: cancel this attack and search for another target again soon
											self.AI[team].AttackTarget = nil
											self.AI[team].AttackPos = nil
										else
											self.AI[team].timeToSpawn = (self.AI[team].baseSpawnTime + math.random(self.AI[team].randomSpawnTime)) * rte.SpawnIntervalScale
											
											if obstacleHeight < 30 then
												self:CreateHeavyDrop(xPosLZ, self.AI[team].AttackPos, team)
											elseif obstacleHeight < 100 then
												self:CreateMediumDrop(xPosLZ, self.AI[team].AttackPos, team)
											elseif obstacleHeight < 200 then
												self:CreateLightDrop(xPosLZ, self.AI[team].AttackPos, team)
											else
												self:CreateScoutDrop(xPosLZ, self.AI[team].AttackPos, team)
												
												-- This target is very difficult to reach: change target for the next attack
												self.AI[team].AttackTarget = nil
												self.AI[team].AttackPos = nil
											end
											
											if not MovableMan:IsActor(self.AI[team].AttackTarget) or math.random() < 0.4 then
												-- Change target for the next attack
												self.AI[team].AttackTarget = nil
												self.AI[team].AttackPos = nil
											else
												self.AI[team].AttackPos = Vector(self.AI[team].AttackTarget.Pos.X, self.AI[team].AttackTarget.Pos.Y)
											end
										end
									end
								end
							else	-- Select a player actor as a target for the next attack
								local safePosX = self.LZmap:FindSafeLZ(team) or math.random(SceneMan.SceneWidth-1)
								if safePosX then
									if math.random() < self.AI[team].digToBrainProbability then	-- Try digging straight to the brain
										local TargetActors = {}
										for Act in MovableMan.Actors do
											if self.AI[team].OnPlayerTeam[Act.Team] and Act:IsInGroup("Brains") then
												local distance = 20 * (SceneMan:ShortestDistance(Vector(safePosX, Act.Pos.Y), Act.Pos, false).Largest / SceneMan.SceneWidth)
												table.insert(TargetActors, {Act=Act, score=self.LZmap:SurfaceProximity(Act.Pos)+distance})
											end
										end
										
										self.AI[team].AttackTarget = self:SelectTarget(TargetActors)
										if self.AI[team].AttackTarget then
											self.AI[team].DigToBrain = true
											self.AI[team].AttackPos = Vector(self.AI[team].AttackTarget.Pos.X, self.AI[team].AttackTarget.Pos.Y)
										else
											-- No target found
											self.AI[team].SpawnTimer:Reset()
											self.AI[team].timeToSpawn = 5000
											self.AI[team].digToBrainProbability = 0
										end
									else
										local TargetActors = {}
										for Act in MovableMan.Actors do
											if self.AI[team].OnPlayerTeam[Act.Team] and (Act.ClassName == "AHuman" or Act.ClassName == "ACrab" or Act.ClassName == "Actor") then
												local distance = 20 * (SceneMan:ShortestDistance(Vector(safePosX, Act.Pos.Y), Act.Pos, false).Largest / SceneMan.SceneWidth)
												table.insert(TargetActors, {Act=Act, score=self.LZmap:SurfaceProximity(Act.Pos)+distance})
											end
										end
										
										self.AI[team].AttackTarget = self:SelectTarget(TargetActors)
										if self.AI[team].AttackTarget then
											self.AI[team].AttackPos = Vector(self.AI[team].AttackTarget.Pos.X, self.AI[team].AttackTarget.Pos.Y)
										else
											-- No target found
											self.AI[team].SpawnTimer:Reset()
											self.AI[team].timeToSpawn = 5000
										end
									end
								else
									-- No safe LZ found yet
									self.AI[team].SpawnTimer:Reset()
									self.AI[team].timeToSpawn = 5000
								end
							end
						end
					else	-- The AI is out of gold
						if self.endless then
							self:SetTeamFunds(100000, team)
						else
							local enemyPresent = false
							local objectives = 0
							for Act in MovableMan.Actors do 
								if Act.Team == team and not Act:IsDead() then
									if Act.ClassName ~= "ADoor" then
										enemyPresent = true
										
										-- Add objective points
										if Act.ClassName == "AHuman" or Act.ClassName == "ACrab" then
											objectives = objectives + 1
											if objectives > 3 then
												break
											end
											
											for team = Activity.TEAM_1, Activity.TEAM_4 do
												self:AddObjectivePoint("Destroy!", Act.AboveHUDPos, team, GameActivity.ARROWDOWN)
											end
										end
									end
								end
							end
							
							-- No AI actors left, remove the CPU-Team
							if not enemyPresent then
								self.AI[team].defeated = true;
							end
						end
					end
				end
			end
		end
	end
end

-- Pick an actor semi-randomly, with a larger probablility for actors with a lower score
function OldSkirmish:SelectTarget(TargetActors)
	if #TargetActors > 1 then
		table.sort(TargetActors, function(A, B) return A.score < B.score end)	-- Actors closer to the surface first
		
		local temperature = 5	-- a higher temperature means less random selection
		local sum = 0
		local worstScore = TargetActors[#TargetActors].score
		
		-- normalize the score
		for i, Data in pairs(TargetActors) do
			TargetActors[i].chance = 1 - Data.score / worstScore
			sum = sum + math.exp(temperature*TargetActors[i].chance)
		end
		
		-- use Softmax to pick one of the n best LZs
		if sum > 0 then
			local pick = math.random() * sum
			sum = 0
			for _, Data in pairs(TargetActors) do
				sum = sum + math.exp(temperature*Data.chance)
				if sum >= pick then
					return Data.Act
				end
			end
		end
		
		return TargetActors[1].Act
	elseif #TargetActors == 1 then
		return TargetActors[1].Act
	end
end

function OldSkirmish:CreateHeavyDrop(xPosLZ, Destination, Team)
	local Craft = RandomACDropShip("Craft", self.AI[Team].TechID)	-- Pick a craft to deliver with
	if Craft then
		-- The max allowed weight of this craft plus cargo
		local craftMaxMass = Craft.MaxMass
		if craftMaxMass < 0 then
			craftMaxMass = math.huge
		elseif craftMaxMass < 1 then
			craftMaxMass = Craft.Mass + 400	-- MaxMass not defined
		end
		
		Craft.Team = Team
		Craft.Pos = Vector(xPosLZ, -30)	-- Set the spawn point of the craft
		
		local actorsInCargo
		if Craft.MaxPassengers < 2 then
			actorsInCargo = 1
		elseif Craft.MaxPassengers > 2 then
			actorsInCargo = math.random(2, Craft.MaxPassengers)
		else
			actorsInCargo = 2
		end

		for _ = 1, actorsInCargo do
			local Passenger
			if RangeRand(0, 105) < self.Difficulty then
				Passenger = self:CreateHeavyInfantry(Team)
			else
				Passenger = self:CreateRandomInfantry(Team)
			end
			
			if Passenger then
				if Destination then
					Passenger.AIMode = Actor.AIMODE_GOTO
					Passenger:AddAISceneWaypoint(Destination)
				end
				
				Craft:AddInventoryItem(Passenger)
				
				-- Stop adding actors when exceeding the weight limit
				if Craft.Mass > craftMaxMass then 
					break
				end
			end
		end
		
		-- Subtract the total value of the craft+cargo from the CPU team's funds
		self:ChangeTeamFunds(-Craft:GetTotalValue(self.AI[Team].TechID, 2), Team)
		
		-- Spawn the Craft onto the scene
		MovableMan:AddActor(Craft)
	end
end

function OldSkirmish:CreateMediumDrop(xPosLZ, Destination, Team)
	-- Pick a craft to deliver with
	local Craft, actorsInCargo
	if math.random() < 0.6 then
		Craft = RandomACDropShip("Craft", self.AI[Team].TechID)
		if Craft.MaxPassengers < 2 then
			actorsInCargo = 1
		elseif Craft.MaxPassengers > 2 then
			actorsInCargo = math.random(2, Craft.MaxPassengers)
		else
			actorsInCargo = 2
		end
	else
		Craft = RandomACRocket("Craft", self.AI[Team].TechID)
		actorsInCargo = Craft.MaxPassengers
	end
	
	if Craft then
		-- The max allowed weight of this craft plus cargo
		local craftMaxMass = Craft.MaxMass
		if craftMaxMass < 0 then
			craftMaxMass = math.huge
		elseif craftMaxMass < 1 then
			craftMaxMass = Craft.Mass + 400	-- MaxMass not defined
		end
		
		Craft.Team = Team
		Craft.Pos = Vector(xPosLZ, -30)	-- Set the spawn point of the craft
		
		for _ = 1, actorsInCargo do
			local Passenger
			if RangeRand(-5, 125) < self.Difficulty then
				Passenger = self:CreateMediumInfantry(Team)
			elseif math.random() < 0.65 then
				Passenger = self:CreateRandomInfantry(Team)
			else
				Passenger = self:CreateLightInfantry(Team)
			end
			
			if Passenger then
				if Destination then
					Passenger.AIMode = Actor.AIMODE_GOTO
					Passenger:AddAISceneWaypoint(Destination)
				end
				
				Craft:AddInventoryItem(Passenger)
				
				-- Stop adding actors when exceeding the weight limit
				if Craft.Mass > craftMaxMass then 
					break
				end
			end
		end
		
		-- Subtract the total value of the craft+cargo from the CPU team's funds
		self:ChangeTeamFunds(-Craft:GetTotalValue(self.AI[Team].TechID, 2), Team)
		
		-- Spawn the Craft onto the scene
		MovableMan:AddActor(Craft)
	end
end

function OldSkirmish:CreateLightDrop(xPosLZ, Destination, Team)
	-- Pick a craft to deliver with
	local Craft
	if math.random() < 0.6 then
		Craft = RandomACDropShip("Craft", self.AI[Team].TechID)
	else
		Craft = RandomACRocket("Craft", self.AI[Team].TechID)
	end
	
	if Craft then
		-- The max allowed weight of this craft plus cargo
		local craftMaxMass = Craft.MaxMass
		if craftMaxMass < 0 then
			craftMaxMass = math.huge
		elseif craftMaxMass < 1 then
			craftMaxMass = Craft.Mass + 400	-- MaxMass not defined
		end
		
		Craft.Team = Team
		Craft.Pos = Vector(xPosLZ, -30)	-- Set the spawn point of the craft
		
		for _ = 1, Craft.MaxPassengers do
			local Passenger
			if RangeRand(10, 200) < self.Difficulty then
				Passenger = self:CreateMediumInfantry(Team)
			else
				Passenger = self:CreateLightInfantry(Team)
			end
			
			if Passenger then
				if Destination then
					Passenger.AIMode = Actor.AIMODE_GOTO
					Passenger:AddAISceneWaypoint(Destination)
				end
				
				Craft:AddInventoryItem(Passenger)
				
				-- Stop adding actors when exceeding the weight limit
				if Craft.Mass > craftMaxMass then 
					break
				end
			end
		end
		
		-- Subtract the total value of the craft+cargo from the CPU team's funds
		self:ChangeTeamFunds(-Craft:GetTotalValue(self.AI[Team].TechID, 2), Team)
		
		-- Spawn the Craft onto the scene
		MovableMan:AddActor(Craft)
	end
end

function OldSkirmish:CreateScoutDrop(xPosLZ, Destination, Team)
	-- Pick a craft to deliver with
	local Craft
	if math.random() < 0.6 then
		Craft = RandomACDropShip("Craft", self.AI[Team].TechID)
	else
		Craft = RandomACRocket("Craft", self.AI[Team].TechID)
	end
	
	if Craft then
		-- The max allowed weight of this craft plus cargo
		local craftMaxMass = Craft.MaxMass
		if craftMaxMass < 0 then
			craftMaxMass = math.huge
		elseif craftMaxMass < 1 then
			craftMaxMass = Craft.Mass + 400	-- MaxMass not defined
		end
		
		Craft.Team = Team
		Craft.Pos = Vector(xPosLZ, -30)	-- Set the spawn point of the craft
		
		for _ = 1, Craft.MaxPassengers do
			local Passenger
			if math.random() < 0.3 then
				Passenger = self:CreateLightInfantry(Team)
			else
				Passenger = self:CreateScoutInfantry(Team)
			end
			
			if Passenger then
				if Destination then
					Passenger.AIMode = Actor.AIMODE_GOTO
					Passenger:AddAISceneWaypoint(Destination)
				end
				
				Craft:AddInventoryItem(Passenger)
				
				-- Stop adding actors when exceeding the weight limit
				if Craft.Mass > craftMaxMass then 
					break
				end
			end
		end
		
		-- Subtract the total value of the craft+cargo from the CPU team's funds
		self:ChangeTeamFunds(-Craft:GetTotalValue(self.AI[Team].TechID, 2), Team)
		
		-- Spawn the Craft onto the scene
		MovableMan:AddActor(Craft)
	end
end

-- Get any Actor from the CPU's native tech
function OldSkirmish:CreateRandomInfantry(Team)
	local	Passenger = RandomAHuman("Actors", self.AI[Team].TechID)
	if Passenger then
		Passenger:AddInventoryItem(RandomHDFirearm("Primary Weapons", self.AI[Team].TechID))
		Passenger:AddInventoryItem(RandomHDFirearm("Secondary Weapons", self.AI[Team].TechID))
		
		if math.random() < 0.4 then
			Passenger:AddInventoryItem(RandomTDExplosive("Grenades", self.AI[Team].TechID))
			if math.random() < 0.5 then
				Passenger:AddInventoryItem(RandomTDExplosive("Grenades", self.AI[Team].TechID))
			end
		end
		
		-- Set AI mode and team so it knows who and what to fight for!
		Passenger.AIMode = Actor.AIMODE_BRAINHUNT
		Passenger.Team = Team
		return Passenger
	end
end

function OldSkirmish:CreateLightInfantry(Team)
	local	Passenger = RandomAHuman("Light Infantry", self.AI[Team].TechID)
	if Passenger then
		Passenger:AddInventoryItem(RandomHDFirearm("Light Weapons", self.AI[Team].TechID))
		Passenger:AddInventoryItem(RandomHDFirearm("Secondary Weapons", self.AI[Team].TechID))
		
		if math.random() < 0.2 then
			Passenger:AddInventoryItem(RandomTDExplosive("Grenades", self.AI[Team].TechID))
		end
		
		-- Set AI mode and team so it knows who and what to fight for!
		Passenger.AIMode = Actor.AIMODE_BRAINHUNT
		Passenger.Team = Team
		return Passenger
	end
end

function OldSkirmish:CreateHeavyInfantry(Team)
	local	Passenger = RandomAHuman("Heavy Infantry", self.AI[Team].TechID)
	if Passenger then
		Passenger:AddInventoryItem(RandomHDFirearm("Heavy Weapons", self.AI[Team].TechID))
		Passenger:AddInventoryItem(RandomHDFirearm("Secondary Weapons", self.AI[Team].TechID))
		
		if math.random() < 0.6 then
			Passenger:AddInventoryItem(RandomTDExplosive("Grenades", self.AI[Team].TechID))
			Passenger:AddInventoryItem(RandomTDExplosive("Grenades", self.AI[Team].TechID))
			if math.random() < 0.4 then
				Passenger:AddInventoryItem(RandomTDExplosive("Grenades", self.AI[Team].TechID))
			end
		end
		
		-- Set AI mode and team so it knows who and what to fight for!
		Passenger.AIMode = Actor.AIMODE_BRAINHUNT
		Passenger.Team = Team
		return Passenger
	end
end

function OldSkirmish:CreateMediumInfantry(Team)
	local	Passenger = RandomAHuman("Heavy Infantry", self.AI[Team].TechID)
	if Passenger then
		Passenger:AddInventoryItem(RandomHDFirearm("Light Weapons", self.AI[Team].TechID))
		Passenger:AddInventoryItem(RandomHDFirearm("Secondary Weapons", self.AI[Team].TechID))
		
		-- Set AI mode and team so it knows who and what to fight for!
		Passenger.AIMode = Actor.AIMODE_BRAINHUNT
		Passenger.Team = Team
		return Passenger
	end
end

function OldSkirmish:CreateScoutInfantry(Team)
	local	Passenger = RandomAHuman("Light Infantry", self.AI[Team].TechID)
	if Passenger then
		Passenger:AddInventoryItem(RandomHDFirearm("Secondary Weapons", self.AI[Team].TechID))
		
		if math.random() < 0.6 then
			Passenger:AddInventoryItem(RandomTDExplosive("Grenades", self.AI[Team].TechID))
		else
			Passenger:AddInventoryItem(RandomHDFirearm("Secondary Weapons", self.AI[Team].TechID))
		end
		
		-- Set AI mode and team so it knows who and what to fight for!
		Passenger.AIMode = Actor.AIMODE_BRAINHUNT
		Passenger.Team = Team
		return Passenger
	end
end

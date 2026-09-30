--[[
	RoundService
	============
	Runs the match loop, forever:

	  LOBBY    Count down LobbyTime. The timer stays full until there are
	           at least MinPlayers players in the server.
	  INTRO    Load a map, pick the killer(s), spawn everyone and freeze
	           them for IntroTime seconds.
	  INROUND  Unfreeze. The round ends when:
	             - the timer runs out            -> Survivors win
	             - every survivor is dead        -> Killer wins
	             - every killer is dead or left  -> Survivors win
	  LMS      When one survivor is left (and the round started with 2+),
	           the timer is reset to LastManStandingTime.
	  ENDED    Announce the winner, wait EndTime, send everyone back to the
	           lobby, delete the map. Then the loop starts again.

	The current stage and timer are stored as attributes on
	ReplicatedStorage ("RoundState", "TimeLeft"). Attributes set by the
	server copy to every client automatically, including players who join
	mid-round, which is why we use them instead of remote events here.

	Each player in a match gets two attributes:
	  "Role"  = "Killer" or "Survivor"
	  "Alive" = true / false
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local RoundState = require(ReplicatedStorage.Shared.RoundState)
local Networker = require(ReplicatedStorage.Packages.Networker)
local MapService = require(script.Parent.MapService)

type Role = "Killer" | "Survivor"
type Winner = "Survivors" | "Killers"

-- Everything about the match currently being played.
-- A fresh one is made every round, so nothing leaks between rounds.
type Match = {
	participants: { Player }, -- everyone who started the match
	killers: { [Player]: true }, -- killers still alive
	survivors: { [Player]: true }, -- survivors still alive
	hadKillers: boolean, -- false only when testing alone
	startingSurvivors: number,
	inLastManStanding: boolean,
	winner: Winner?, -- set the moment someone wins; the round loop sees it and stops
	deadline: number, -- os.clock() time when the round timer hits 0
	connections: { RBXScriptConnection },
}

-- TEMPORARY: colours so you can see who's who while testing.
-- Removed once characters have real models (step 3).
local ROLE_COLORS: { [Role]: Color3 } = {
	Killer = Color3.fromRGB(220, 40, 40),
	Survivor = Color3.fromRGB(60, 140, 255),
}

local random = Random.new()

local RoundService = {}

RoundService.state = RoundState.Lobby :: RoundState.State
RoundService.match = nil :: Match?

-- Helpers ----------------------------------------------------------------

local function debugPrint(...: any)
	if Config.Debug.Enabled then
		print("[RoundService]", ...)
	end
end

-- Counts the entries in a { [key]: true } table (# only works on lists).
local function count(set: { [any]: any }): number
	local n = 0
	for _ in set do
		n += 1
	end
	return n
end

-- Shuffles a list in place (Fisher-Yates) and returns it.
local function shuffle<T>(list: { T }): { T }
	for i = #list, 2, -1 do
		local j = random:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

-- Lifecycle --------------------------------------------------------------

function RoundService:Init()
	-- Server -> client messages (announcements). Clients can't call anything yet,
	-- so there's no whitelist.
	self.network = Networker.server.new("RoundService", self)

	self:_setState(RoundState.Lobby)
	self:_setTimeLeft(Config.Round.LobbyTime)
end

function RoundService:Start()
	-- A player leaving counts as them dying.
	Players.PlayerRemoving:Connect(function(player)
		self:_eliminate(player)
	end)

	-- Start() runs in its own thread (see Loader), so looping forever is fine.
	while true do
		self:_runLobby()
		self:_runMatch()
	end
end

-- Stages -----------------------------------------------------------------

function RoundService:_runLobby()
	self:_setState(RoundState.Lobby)

	local timeLeft = Config.Round.LobbyTime
	while timeLeft > 0 do
		local waiting = #Players:GetPlayers() < Config.Round.MinPlayers
		if waiting then
			-- Not enough players: keep the timer full until more join.
			timeLeft = Config.Round.LobbyTime
		end

		ReplicatedStorage:SetAttribute("WaitingForPlayers", waiting)
		self:_setTimeLeft(timeLeft)
		task.wait(1)

		if not waiting then
			timeLeft -= 1
		end
	end

	ReplicatedStorage:SetAttribute("WaitingForPlayers", false)
end

function RoundService:_runMatch()
	local players = Players:GetPlayers()
	if #players < Config.Round.MinPlayers then
		return -- someone left right as the timer ended; back to the lobby
	end

	if not MapService:LoadRandomMap() then
		task.wait(5) -- no maps set up; wait a bit so the warning doesn't spam
		return
	end

	-- 1. Pick roles. Always leave at least one survivor, so when testing
	--    alone you're a survivor with no killer.
	shuffle(players)
	local killerCount = math.clamp(Config.Round.KillerCount, 0, #players - 1)

	local match: Match = {
		participants = players,
		killers = {},
		survivors = {},
		hadKillers = killerCount > 0,
		startingSurvivors = #players - killerCount,
		inLastManStanding = false,
		winner = nil,
		deadline = 0,
		connections = {},
	}
	self.match = match

	-- Fill in both teams BEFORE spawning anyone. Spawning waits for characters
	-- to load, and if someone left mid-way we'd otherwise check a half-built team.
	for i, player in players do
		if i <= killerCount then
			match.killers[player] = true
		else
			match.survivors[player] = true
		end
	end

	-- 2. Spawn everyone, frozen.
	self:_setState(RoundState.Intro)
	self:_setTimeLeft(Config.Round.IntroTime)

	local killerSpawns = shuffle(MapService:GetSpawns("Killer"))
	local survivorSpawns = shuffle(MapService:GetSpawns("Survivor"))
	local killerIndex, survivorIndex = 0, 0

	for _, player in players do
		if match.killers[player] then
			killerIndex += 1
			-- % wraps around, so if there are more players than spawn parts,
			-- players share spawns instead of erroring.
			local spawnCFrame = killerSpawns[(killerIndex - 1) % #killerSpawns + 1]
			self:_spawnPlayer(match, player, "Killer", spawnCFrame)
		elseif match.survivors[player] then
			survivorIndex += 1
			local spawnCFrame = survivorSpawns[(survivorIndex - 1) % #survivorSpawns + 1]
			self:_spawnPlayer(match, player, "Survivor", spawnCFrame)
		end
	end

	-- 3. Intro.
	local killerNames = {}
	for killer in match.killers do
		table.insert(killerNames, killer.DisplayName)
	end
	if #killerNames > 0 then
		self.network:fireAll("Announce", `The killer is {table.concat(killerNames, " and ")}!`)
	else
		self.network:fireAll("Announce", "Solo test: no killer this round")
	end

	task.wait(Config.Round.IntroTime)
	self:_setFrozen(match, false)

	-- 4. The round itself.
	self:_setState(RoundState.InRound)
	match.deadline = os.clock() + Config.Round.RoundTime
	self:_checkWinConditions(match) -- someone may have left during the intro

	-- We check 10 times a second so a win ends the round almost instantly.
	-- LMS can move the deadline, which is why we re-read it every loop.
	while not match.winner do
		local remaining = math.max(0, math.ceil(match.deadline - os.clock()))
		self:_setTimeLeft(remaining)

		if remaining <= 0 then
			match.winner = "Survivors" -- they survived the whole round
			break
		end
		task.wait(0.1)
	end

	-- 5. End.
	self:_endMatch(match)
end

function RoundService:_endMatch(match: Match)
	self:_setState(RoundState.Ended)
	self:_setTimeLeft(Config.Round.EndTime)

	local message = if match.winner == "Killers" then "The killer wins!" else "Survivors win!"
	self.network:fireAll("Announce", message)
	debugPrint("Winner:", match.winner)

	task.wait(Config.Round.EndTime)

	-- Stop listening for deaths in this match.
	for _, connection in match.connections do
		connection:Disconnect()
	end

	-- Send everyone who's still in the server back to the lobby.
	-- LoadCharacterAsync respawns them at the lobby's SpawnLocation.
	for _, player in match.participants do
		if player.Parent then
			player:SetAttribute("Role", nil)
			player:SetAttribute("Alive", nil)
			pcall(player.LoadCharacterAsync, player)
		end
	end

	self.match = nil
	MapService:Unload()
end

-- Players ----------------------------------------------------------------

function RoundService:_spawnPlayer(match: Match, player: Player, role: Role, spawnCFrame: CFrame)
	player:SetAttribute("Role", role)
	player:SetAttribute("Alive", true)

	-- LoadCharacterAsync gives the player a brand new character (and waits for it).
	-- pcall because it errors if the player left while we were busy.
	local ok = pcall(player.LoadCharacterAsync, player)
	if not ok or self.match ~= match or not player.Parent then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not humanoid or not root then
		warn(`[RoundService] {player.Name}'s character didn't load properly`)
		self:_eliminate(player)
		return
	end

	-- Move them to their spawn (3 studs up so they don't clip into the floor)
	-- and freeze them for the intro.
	character:PivotTo(spawnCFrame + Vector3.new(0, 3, 0))
	root.Anchored = true

	-- TEMPORARY role colour.
	local highlight = Instance.new("Highlight")
	highlight.FillColor = ROLE_COLORS[role]
	highlight.FillTransparency = 0.5
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded -- not visible through walls
	highlight.Parent = character

	table.insert(
		match.connections,
		humanoid.Died:Connect(function()
			self:_eliminate(player)
		end)
	)
end

function RoundService:_setFrozen(match: Match, frozen: boolean)
	for _, player in match.participants do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.Anchored = frozen
		end
	end
end

-- Removes a player from the match (they died or left).
-- Safe to call more than once for the same player.
function RoundService:_eliminate(player: Player)
	local match = self.match
	if not match or not (match.killers[player] or match.survivors[player]) then
		return
	end

	match.killers[player] = nil
	match.survivors[player] = nil
	if player.Parent then
		player:SetAttribute("Alive", false)
	end

	debugPrint(player.Name, "was eliminated")
	self:_checkWinConditions(match)
end

-- Win conditions ---------------------------------------------------------

function RoundService:_checkWinConditions(match: Match)
	if match.winner then
		return
	end

	local killersLeft = count(match.killers)
	local survivorsLeft = count(match.survivors)

	if match.hadKillers and killersLeft == 0 then
		match.winner = "Survivors"
	elseif survivorsLeft == 0 then
		match.winner = "Killers"
	elseif
		survivorsLeft == 1
		and match.hadKillers
		and match.startingSurvivors >= 2
		and not match.inLastManStanding
		and self.state == RoundState.InRound
	then
		local lastSurvivor = next(match.survivors)
		if lastSurvivor then
			self:_startLastManStanding(match, lastSurvivor)
		end
	end
end

function RoundService:_startLastManStanding(match: Match, lastSurvivor: Player)
	match.inLastManStanding = true
	self:_setState(RoundState.LastManStanding)
	match.deadline = os.clock() + self:_getLastManStandingTime(match, lastSurvivor)

	self.network:fireAll("Announce", `{lastSurvivor.DisplayName} is the last one standing!`)
end

-- How long LMS lasts. Later (step 3) this returns SpecialLastManStandingTime
-- for special killer-vs-survivor matchups.
function RoundService:_getLastManStandingTime(_match: Match, _lastSurvivor: Player): number
	return Config.Round.LastManStandingTime
end

-- Replicated state -------------------------------------------------------

function RoundService:_setState(state: RoundState.State)
	self.state = state
	ReplicatedStorage:SetAttribute("RoundState", state)
	debugPrint("State ->", state)
end

function RoundService:_setTimeLeft(seconds: number)
	-- Only update when the number actually changes, so clients aren't
	-- sent the same value 10 times a second.
	if ReplicatedStorage:GetAttribute("TimeLeft") ~= seconds then
		ReplicatedStorage:SetAttribute("TimeLeft", seconds)
	end
end

return RoundService

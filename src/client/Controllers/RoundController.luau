--[[
	RoundController
	===============
	Shows the round state on screen. This is a TEMPORARY debug label so you
	can watch the round loop work while testing. The real HUD comes in step 6.

	It doesn't ask the server for anything. It just watches the attributes
	RoundService sets on ReplicatedStorage and redraws when they change.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local RoundState = require(ReplicatedStorage.Shared.RoundState)
local Networker = require(ReplicatedStorage.Packages.Networker)

local player = Players.LocalPlayer

-- What to show for each stage.
local STATE_TEXT: { [string]: string } = {
	[RoundState.Lobby] = "Intermission",
	[RoundState.Intro] = "Get ready...",
	[RoundState.InRound] = "Survive!",
	[RoundState.LastManStanding] = "LAST MAN STANDING",
	[RoundState.Ended] = "Round over",
}

local RoundController = {}

RoundController.statusLabel = nil :: TextLabel?
RoundController.announceLabel = nil :: TextLabel?
RoundController.announceToken = 0

-- Turns 75 into "1:15".
local function formatTime(seconds: number): string
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function makeLabel(parent: Instance, yOffset: number, height: number): TextLabel
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, yOffset)
	label.Size = UDim2.fromOffset(420, height)
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.BackgroundTransparency = 0.4
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 20
	label.Text = ""
	label.Parent = parent
	return label
end

function RoundController:Init()
	-- Connect to RoundService so it can call Announce() on us.
	self.network = Networker.client.new("RoundService", self)

	local gui = Instance.new("ScreenGui")
	gui.Name = "RoundDebug"
	gui.ResetOnSpawn = false -- keep it when the character respawns
	gui.Parent = player:WaitForChild("PlayerGui")

	self.statusLabel = makeLabel(gui, 10, 40)
	local announceLabel = makeLabel(gui, 56, 34)
	announceLabel.Visible = false
	self.announceLabel = announceLabel
end

function RoundController:Start()
	local function refresh()
		self:_refresh()
	end

	-- Redraw whenever anything we show changes.
	ReplicatedStorage:GetAttributeChangedSignal("RoundState"):Connect(refresh)
	ReplicatedStorage:GetAttributeChangedSignal("TimeLeft"):Connect(refresh)
	ReplicatedStorage:GetAttributeChangedSignal("WaitingForPlayers"):Connect(refresh)
	player:GetAttributeChangedSignal("Role"):Connect(refresh)
	player:GetAttributeChangedSignal("Alive"):Connect(refresh)
	Players.PlayerAdded:Connect(refresh)
	Players.PlayerRemoving:Connect(refresh)

	refresh()
end

function RoundController:_refresh()
	local label = self.statusLabel
	if not label then
		return
	end

	local state = ReplicatedStorage:GetAttribute("RoundState") or RoundState.Lobby
	local timeLeft = ReplicatedStorage:GetAttribute("TimeLeft") or 0
	local waiting = ReplicatedStorage:GetAttribute("WaitingForPlayers")

	local text
	if state == RoundState.Lobby and waiting then
		text = `Waiting for players ({#Players:GetPlayers()}/{Config.Round.MinPlayers})`
	else
		text = `{STATE_TEXT[state] or state}   {formatTime(timeLeft)}`
	end

	local role = player:GetAttribute("Role")
	if role then
		local status = if player:GetAttribute("Alive") == false then "dead" else role
		text ..= `   |   You: {status}`
	end

	label.Text = text
end

-- Called by the server: network:fireAll("Announce", message)
function RoundController:Announce(message: string)
	print(`[Round] {message}`)

	local label = self.announceLabel
	if not label then
		return
	end
	label.Text = message
	label.Visible = true

	-- Hide it after 4 seconds, unless a newer announcement replaced it.
	self.announceToken += 1
	local token = self.announceToken
	task.delay(4, function()
		if self.announceToken == token then
			label.Visible = false
		end
	end)
end

return RoundController

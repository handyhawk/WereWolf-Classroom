--[[
	RoundController
	===============
	Shows the round timer on screen.

	YOU design the UI in Studio; this script only changes the TEXT.
	Build a ScreenGui in StarterGui like this (only the NAMES matter; you can
	put the labels inside any frames/images you like, as deep as you want):

	  StarterGui
	    RoundHUD                 <- ScreenGui (set ResetOnSpawn = false)
	      ...your frames, ImageLabels, decorations...
	        TimeText             <- TextLabel   REQUIRED  shows "3:42"
	        StateText            <- TextLabel   optional  shows "Survive!"
	        AnnouncementText     <- TextLabel   optional  shows "The killer is ..."

	Fonts, colours, sizes, images, positions: all yours. The script never
	touches them. It only sets .Text (and .Visible on AnnouncementText, which
	is hidden until there's an announcement).

	If there's no RoundHUD yet, a plain built-in one is used so you can still
	test. As soon as your RoundHUD appears, it takes over.

	It doesn't ask the server for anything. It watches the attributes
	RoundService sets on ReplicatedStorage and redraws when they change.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local RoundState = require(ReplicatedStorage.Shared.RoundState)
local Networker = require(ReplicatedStorage.Packages.Networker)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- The name of your ScreenGui in StarterGui.
local HUD_NAME = "RoundHUD"

-- The words shown in StateText for each stage. Change them freely.
local STATE_TEXT: { [string]: string } = {
	[RoundState.Lobby] = "Intermission",
	[RoundState.Intro] = "Get ready...",
	[RoundState.InRound] = "Survive!",
	[RoundState.LastManStanding] = "LAST MAN STANDING",
	[RoundState.Ended] = "Round over",
}

-- How long an announcement stays on screen, in seconds.
local ANNOUNCEMENT_TIME = 4

type Hud = {
	gui: ScreenGui,
	timeText: TextLabel,
	stateText: TextLabel?,
	announceText: TextLabel?,
}

local RoundController = {}

RoundController.hud = nil :: Hud?
RoundController.defaultGui = nil :: ScreenGui?
RoundController.warnedFor = nil :: Instance?
RoundController.announceToken = 0

-- Turns 75 into "1:15".
local function formatTime(seconds: number): string
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- Searches the whole ScreenGui (true = look inside every frame) for a
-- TextLabel with this name. Returns nil if there isn't one.
local function findLabel(gui: Instance, name: string): TextLabel?
	local found = gui:FindFirstChild(name, true)
	if found and found:IsA("TextLabel") then
		return found
	end
	return nil
end

-- A plain fallback HUD, used only until you make your own RoundHUD.
local function createDefaultHud(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoundHUD_Default"
	gui.ResetOnSpawn = false

	local function makeLabel(name: string, yOffset: number, height: number, textSize: number): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 0, yOffset)
		label.Size = UDim2.fromOffset(300, height)
		label.BackgroundColor3 = Color3.new(0, 0, 0)
		label.BackgroundTransparency = 0.4
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextSize = textSize
		label.Text = ""
		label.Parent = gui
		return label
	end

	makeLabel("TimeText", 10, 44, 30)
	makeLabel("StateText", 56, 26, 16)
	makeLabel("AnnouncementText", 90, 30, 18).Visible = false

	-- Not parented yet: the caller remembers it first, then puts it on screen.
	return gui
end

function RoundController:Init()
	-- Connect to RoundService so it can call Announce() on us.
	self.network = Networker.client.new("RoundService", self)
end

function RoundController:Start()
	local function refresh()
		self:_refresh()
	end

	-- Redraw whenever the round changes.
	ReplicatedStorage:GetAttributeChangedSignal("RoundState"):Connect(refresh)
	ReplicatedStorage:GetAttributeChangedSignal("TimeLeft"):Connect(refresh)
	ReplicatedStorage:GetAttributeChangedSignal("WaitingForPlayers"):Connect(refresh)
	Players.PlayerAdded:Connect(refresh)
	Players.PlayerRemoving:Connect(refresh)

	-- Your RoundHUD is copied into PlayerGui when your character spawns,
	-- which can be after this script starts. Redraw when it shows up.
	playerGui.ChildAdded:Connect(refresh)

	refresh()
end

-- Returns the labels to draw into: your RoundHUD if it exists, otherwise
-- the built-in default. Called on every redraw, so if your RoundHUD appears
-- later (or gets recreated), we switch to it automatically.
function RoundController:_getHud(): Hud?
	local custom = playerGui:FindFirstChild(HUD_NAME)
	local gui: ScreenGui? = if custom and custom:IsA("ScreenGui") then custom else nil

	if gui then
		-- Your HUD exists, so the default one isn't needed any more.
		if self.defaultGui then
			self.defaultGui:Destroy()
			self.defaultGui = nil
		end
	else
		if not self.defaultGui then
			-- Remember it BEFORE parenting. Parenting fires ChildAdded, which
			-- redraws, and that redraw must see that the default already exists
			-- (otherwise it would make another one, forever).
			local default = createDefaultHud()
			self.defaultGui = default
			default.Parent = playerGui
		end
		gui = self.defaultGui
	end
	assert(gui, "unreachable")

	-- Same HUD as last time: reuse the labels we already found.
	if self.hud and self.hud.gui == gui then
		return self.hud
	end

	local timeText = findLabel(gui, "TimeText")
	if not timeText then
		if self.warnedFor ~= gui then
			self.warnedFor = gui
			warn(`[RoundController] {gui.Name} needs a TextLabel named "TimeText" somewhere inside it`)
		end
		return nil
	end

	local announceText = findLabel(gui, "AnnouncementText")
	if announceText then
		announceText.Visible = false
	end

	self.hud = {
		gui = gui,
		timeText = timeText,
		stateText = findLabel(gui, "StateText"),
		announceText = announceText,
	}
	return self.hud
end

function RoundController:_refresh()
	local hud = self:_getHud()
	if not hud then
		return
	end

	local state = ReplicatedStorage:GetAttribute("RoundState") or RoundState.Lobby
	local timeLeft = ReplicatedStorage:GetAttribute("TimeLeft") or 0
	local waiting = state == RoundState.Lobby and ReplicatedStorage:GetAttribute("WaitingForPlayers")

	if waiting then
		hud.timeText.Text = "--:--"
	else
		hud.timeText.Text = formatTime(timeLeft)
	end

	if hud.stateText then
		if waiting then
			hud.stateText.Text = `Waiting for players ({#Players:GetPlayers()}/{Config.Round.MinPlayers})`
		else
			hud.stateText.Text = STATE_TEXT[state] or state
		end
	end
end

-- Called by the server: network:fireAll("Announce", message)
function RoundController:Announce(message: string)
	print(`[Round] {message}`)

	local hud = self:_getHud()
	local label = hud and hud.announceText
	if not label then
		return -- no AnnouncementText in your HUD, that's fine
	end

	label.Text = message
	label.Visible = true

	-- Hide it again later, unless a newer announcement replaced it.
	self.announceToken += 1
	local token = self.announceToken
	task.delay(ANNOUNCEMENT_TIME, function()
		if self.announceToken == token then
			label.Visible = false
		end
	end)
end

return RoundController

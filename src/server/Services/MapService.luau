--[[
	MapService
	==========
	Loads a random map for each round and removes it afterwards.

	How to add a map (in Studio):
	  ServerStorage
	    Maps              <- Folder
	      TestMap         <- Model (any name, this is the map)
	        Spawns        <- Folder
	          Killer      <- Part (one or more)
	          Survivor    <- Part (one or more)
	        ...floor, walls, props...

	Build the map away from the lobby (e.g. 500 studs to the side), because
	it's copied into the game at the exact position you built it.
	You don't need to hide the spawn parts yourself; this script does it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

export type Role = "Killer" | "Survivor"

local MapService = {}

-- The map currently in the game (nil while in the lobby).
MapService.currentMap = nil :: Model?
-- Remembered so we don't pick the same map twice in a row.
MapService.lastMapName = nil :: string?

local random = Random.new()

-- Returns every map Model inside ServerStorage > Maps.
function MapService:_getMapTemplates(): { Model }
	local folder = ServerStorage:FindFirstChild("Maps")
	local maps: { Model } = {}
	if not folder then
		return maps
	end

	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			table.insert(maps, child)
		end
	end
	return maps
end

--- Copies a random map into Workspace and returns it.
--- Returns nil (with a warning) if there are no maps set up.
function MapService:LoadRandomMap(): Model?
	self:Unload()

	local templates = self:_getMapTemplates()
	if #templates == 0 then
		warn("[MapService] No maps found. Add a Model to ServerStorage > Maps (see MapService for the layout).")
		return nil
	end

	-- If there's more than one map, remove last round's map from the choices.
	local choices = templates
	if #templates > 1 and self.lastMapName then
		choices = {}
		for _, template in templates do
			if template.Name ~= self.lastMapName then
				table.insert(choices, template)
			end
		end
	end

	local template = choices[random:NextInteger(1, #choices)]
	local map = template:Clone()

	-- Make spawn parts invisible and non-solid, in case they weren't set up that way.
	local spawns = map:FindFirstChild("Spawns")
	if spawns then
		for _, part in spawns:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = false
				part.Transparency = 1
			end
		end
	end

	map.Parent = workspace

	self.currentMap = map
	self.lastMapName = template.Name
	-- Clients can read this later to show the map name.
	ReplicatedStorage:SetAttribute("MapName", template.Name)

	return map
end

--- Returns the spawn positions for a role on the current map.
--- Always returns at least one position, so callers never have to handle "none".
function MapService:GetSpawns(role: Role): { CFrame }
	local map = self.currentMap
	if not map then
		warn("[MapService] GetSpawns was called but no map is loaded")
		return { CFrame.new(0, 10, 0) }
	end

	local result: { CFrame } = {}
	local spawns = map:FindFirstChild("Spawns")
	if spawns then
		for _, part in spawns:GetChildren() do
			if part:IsA("BasePart") and part.Name == role then
				table.insert(result, part.CFrame)
			end
		end
	end

	if #result == 0 then
		warn(`[MapService] Map "{map.Name}" has no "{role}" parts in its Spawns folder, using the map's centre instead`)
		table.insert(result, map:GetPivot())
	end

	return result
end

--- Removes the current map from the game.
function MapService:Unload()
	if self.currentMap then
		self.currentMap:Destroy()
		self.currentMap = nil
		ReplicatedStorage:SetAttribute("MapName", nil)
	end
end

return MapService

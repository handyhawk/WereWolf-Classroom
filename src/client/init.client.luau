--[[
	Client entry point
	==================
	The ONLY LocalScript for the player. It waits until the server says it's
	ready, then starts every Controller in the Controllers folder.

	A "Controller" is a ModuleScript that runs on the player's device and
	handles one thing they see or do (HUD, input, camera, sounds...).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader = require(ReplicatedStorage.Shared.Loader)

-- If the server hasn't finished loading yet, pause here until it has.
if not ReplicatedStorage:GetAttribute("ServerReady") then
	ReplicatedStorage:GetAttributeChangedSignal("ServerReady"):Wait()
end

Loader.Load(script.Controllers)

print("[Client] All controllers loaded")

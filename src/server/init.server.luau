--[[
	Server entry point
	==================
	The ONLY Script on the server. Its job is to start every Service
	in the Services folder, then tell clients the server is ready.

	A "Service" is a ModuleScript that runs on the server and owns one
	system of the game (rounds, maps, characters...).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader = require(ReplicatedStorage.Shared.Loader)

Loader.Load(script.Services)

-- Clients wait for this attribute before starting, so every Service has
-- created its remotes before any client tries to use them.
ReplicatedStorage:SetAttribute("ServerReady", true)

print("[Server] All services loaded")

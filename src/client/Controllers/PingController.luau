--[[
	PingController (test controller)
	================================
	The client half of PingService. Delete both once we have real systems.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networker = require(ReplicatedStorage.Packages.Networker)

local PingController = {}

function PingController:Init()
	-- Connects to the server's "PingService" channel. Passing `self` means
	-- that when the server fires "ShowMessage", Networker calls
	-- PingController:ShowMessage(...) for us.
	self.network = Networker.client.new("PingService", self)
end

function PingController:Start()
	-- fetch = ask the server and WAIT for its answer (like a function call).
	-- fire  = send and don't wait (we'll use it for things like "use ability").
	local reply = self.network:fetch("Ping")
	print(`[PingController] Server replied: {reply}`)
end

-- Called by the server via network:fire(player, "ShowMessage", text).
function PingController:ShowMessage(text: string)
	print(`[PingController] Message from server: {text}`)
end

return PingController

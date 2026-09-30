--[[
	PingService (test service)
	==========================
	A tiny example that proves the foundation works end to end:
	  - the Loader finds and starts it
	  - a client can ask the server something and get an answer back
	  - the server can send a message to one client

	Every future Service follows this same shape. Once the round system
	exists, you can delete this file together with PingController.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networker = require(ReplicatedStorage.Packages.Networker)

local PingService = {}

function PingService:Init()
	-- Creates this service's remote channel, named "PingService".
	-- The list at the end is a whitelist: clients may ONLY call these
	-- functions. Any other name they send gets rejected.
	self.network = Networker.server.new("PingService", self, {
		self.Ping,
	})
end

function PingService:Start()
	print("[PingService] Started")
end

-- A client calls this with network:fetch("Ping").
-- Networker always passes the player who called it as the first argument,
-- so the server knows who is asking. Never trust a player the client
-- claims to be. Use this argument.
function PingService:Ping(player: Player): string
	print(`[PingService] {player.Name} pinged the server`)

	-- Server -> client: call ShowMessage on this player's PingController.
	self.network:fire(player, "ShowMessage", `Hello {player.Name}, the server can talk to you!`)

	-- Whatever we return goes back to the client as fetch's result.
	return "pong"
end

return PingService

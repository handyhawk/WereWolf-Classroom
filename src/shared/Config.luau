--!strict
--[[
	Config
	======
	All the game's tuning numbers in one place. When you want to change how
	long a round lasts, you change it here instead of hunting through scripts.

	It lives in ReplicatedStorage, so both the server and clients can read it
	(e.g. the client UI can show the round length).

	Don't put secrets here: exploiters can read everything in ReplicatedStorage.
]]

local Config = {
	Round = {
		-- Players needed before the lobby timer starts counting down.
		-- Set this to 1 when you want to test alone in Studio.
		MinPlayers = 2,

		-- How many killers each round.
		KillerCount = 1,

		-- Times are in seconds.
		LobbyTime = 30,
		IntroTime = 5,
		RoundTime = 240,
		LastManStandingTime = 90,
	},

	Debug = {
		-- Extra print() output while developing. Turn off before publishing.
		Enabled = true,
	},
}

-- table.freeze makes a table read-only. If any script tries to do
-- `Config.Round.RoundTime = 5`, it errors instead of silently changing the
-- game for everyone. We freeze every nested table too.
local function deepFreeze(t: { [any]: any })
	for _, value in t do
		if typeof(value) == "table" and not table.isfrozen(value) then
			deepFreeze(value)
		end
	end
	table.freeze(t)
end

deepFreeze(Config)

return Config

--!strict
--[[
	RoundState
	==========
	The names of every stage a match goes through, in order:

	  Lobby -> Intro -> InRound -> (LastManStanding) -> Ended -> Lobby ...

	Both server and client use these instead of typing "InRound" by hand.
	If you mistype one (RoundState.InRond), you get an error straight away
	instead of a bug where a check silently never matches.
]]

export type State = "Lobby" | "Intro" | "InRound" | "LastManStanding" | "Ended"

local RoundState = {
	Lobby = "Lobby" :: State,
	Intro = "Intro" :: State,
	InRound = "InRound" :: State,
	LastManStanding = "LastManStanding" :: State,
	Ended = "Ended" :: State,
}

-- Reading a name that doesn't exist throws an error (the typo protection).
setmetatable(RoundState, {
	__index = function(_, key)
		error(`RoundState.{tostring(key)} does not exist`, 2)
	end,
})

table.freeze(RoundState)

return RoundState

--!strict
--[[
	Loader
	======
	Finds every ModuleScript inside a folder and boots them in two phases.

	  Phase 1 - Init()
	    Runs one module at a time. Use it to set up the module's OWN stuff
	    (variables, remotes). Don't talk to other modules here, because they
	    might not have run their Init yet.

	  Phase 2 - Start()
	    Runs only after EVERY module has finished Init. Now it's safe to use
	    other modules, connect events and start loops. Each Start runs in its
	    own thread, so one slow or broken module can't block the others.

	Both functions are optional. A module without them is still required,
	so it can be used as a plain library.

	Rules for what gets loaded:
	  - ModuleScripts directly in the folder, or inside sub-Folders, are loaded.
	  - A ModuleScript placed INSIDE another ModuleScript is treated as that
	    module's private helper and is NOT loaded automatically.
]]

export type Module = {
	Init: ((self: any) -> ())?,
	Start: ((self: any) -> ())?,
	[any]: any,
}

type Entry = {
	name: string,
	module: Module,
}

local Loader = {}

-- Walks the folder tree and collects ModuleScripts (see rules above).
local function collectModuleScripts(parent: Instance, found: { ModuleScript })
	for _, child in parent:GetChildren() do
		if child:IsA("ModuleScript") then
			table.insert(found, child)
		elseif child:IsA("Folder") then
			collectModuleScripts(child, found)
		end
	end
end

-- Calls module[methodName] safely. If it errors, we print the full error
-- with a traceback (so you can find the line) instead of crashing the loader.
-- Returns false if it errored.
local function safeCall(entry: Entry, methodName: string): boolean
	local method = entry.module[methodName]
	if typeof(method) ~= "function" then
		return true
	end

	local ok, err = xpcall(method, debug.traceback, entry.module)
	if not ok then
		warn(`[Loader] {entry.name}:{methodName}() failed:\n{err}`)
	end
	return ok
end

--- Requires, Inits and Starts every module in `parent`.
--- Returns the loaded modules by name, in case the caller wants them.
function Loader.Load(parent: Instance): { [string]: Module }
	local moduleScripts: { ModuleScript } = {}
	collectModuleScripts(parent, moduleScripts)

	-- Sort by name so the load order is the same every time you press Play.
	table.sort(moduleScripts, function(a, b)
		return a.Name < b.Name
	end)

	-- Step 1: require everything.
	local entries: { Entry } = {}
	local byName: { [string]: Module } = {}

	for _, moduleScript in moduleScripts do
		local ok, result = pcall(require, moduleScript)

		if not ok then
			warn(`[Loader] Could not require {moduleScript:GetFullName()}:\n{result}`)
		elseif typeof(result) ~= "table" then
			warn(`[Loader] {moduleScript:GetFullName()} must return a table, skipping it`)
		elseif byName[moduleScript.Name] then
			warn(`[Loader] Two modules are named "{moduleScript.Name}", skipping the second one`)
		else
			table.insert(entries, { name = moduleScript.Name, module = result })
			byName[moduleScript.Name] = result
		end
	end

	-- Step 2: Init, one after another.
	-- If a module's Init breaks, we remember it and don't Start it, because
	-- its Start would probably just cause more confusing errors.
	local readyToStart: { Entry } = {}
	for _, entry in entries do
		if safeCall(entry, "Init") then
			table.insert(readyToStart, entry)
		end
	end

	-- Step 3: Start, each in its own thread.
	for _, entry in readyToStart do
		task.spawn(safeCall, entry, "Start")
	end

	return byName
end

return Loader

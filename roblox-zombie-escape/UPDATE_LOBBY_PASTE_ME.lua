-- ZOMBIE ESCAPE: LOBBY UPDATE (paste in Studio Command Bar after the first installer)
local SSS = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")
local SPS = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")
local modules = SSS:WaitForChild("Modules")

local function put(parent, className, name, source)
	local old = parent:FindFirstChild(name)
	if old then old:Destroy() end
	local s = Instance.new(className)
	s.Name = name
	s.Source = source
	s.Parent = parent
end

local function patch(script, find, replace)
	assert(script.Source:find(find, 1, true), "patch target not found in " .. script.Name)
	local a, b = script.Source:find(find, 1, true)
	script.Source = script.Source:sub(1, a - 1) .. replace .. script.Source:sub(b + 1)
end

put(RS, "ModuleScript", "Config", [=====[
-- ModuleScript: ReplicatedStorage/Config
-- All game tuning lives here.
return {
	-- Lobby / party settings
	-- GamePlaceId = 0  -> single-place mode: lobby and game arena are in the same place (good for testing in Studio)
	-- GamePlaceId = <id of your published game place> -> lobby teleports each party to its own PRIVATE server
	GamePlaceId = 0,
	LobbyPlaceId = 0, -- optional: place players return to after escaping / if they join the game place directly
	PartyMax = 4,
	LobbyRooms = 4,
	StartCountdown = 5,
	LobbyHeight = 500, -- lobby platform height (single-place mode keeps it far above the arena)

	MapSize = 400,
	GridStep = 120,

	StartReserve = 36,
	MaxReserve = 180,
	AmmoPickup = 24,
	MedkitHeal = 50,
	KeysNeeded = 3,
	LootRespawn = 90,

	ZombieMax = 30,
	ZombieSpawnInterval = 3,
	ZombiesPerHouse = 2,
	ZombieHealth = 60,
	ZombieSpeed = 11,
	ZombieDamage = 12,
	ZombieAttackCooldown = 1,
	ZombieAttackRange = 5,
	ZombieDetectRange = 70,
	ZombieMinSpawnDistance = 60,
	ZombieAmmoDropChance = 0.15,

	-- name, weight (Pistol is given at spawn, so it is not in the loot table)
	LootTable = {
		{ "Ammo", 40 },
		{ "Medkit", 20 },
		{ "Shotgun", 22 },
		{ "Rifle", 18 },
	},

	Weapons = {
		Pistol = {
			Damage = 20, FireRate = 0.35, MagSize = 12, Range = 250, Pellets = 1,
			Spread = 0.01, ReloadTime = 1.2, Auto = false,
			HandleSize = Vector3.new(0.4, 0.8, 1.6), Color = Color3.fromRGB(60, 60, 60),
		},
		Rifle = {
			Damage = 24, FireRate = 0.11, MagSize = 30, Range = 400, Pellets = 1,
			Spread = 0.025, ReloadTime = 2, Auto = true,
			HandleSize = Vector3.new(0.4, 0.7, 3), Color = Color3.fromRGB(40, 70, 40),
		},
		Shotgun = {
			Damage = 12, FireRate = 0.9, MagSize = 6, Range = 80, Pellets = 8,
			Spread = 0.08, ReloadTime = 2.5, Auto = false,
			HandleSize = Vector3.new(0.5, 0.7, 2.8), Color = Color3.fromRGB(110, 70, 30),
		},
	},
}
]=====])

put(modules, "ModuleScript", "LobbyService", [=====[
-- ModuleScript: ServerScriptService/Modules/LobbyService
-- Lobby with private party rooms (max Config.PartyMax players each).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.RemoteHub)

local Lobby = {}
Lobby.onEnterGame = nil -- set by GameManager (single-place mode)
Lobby.spawnCFrame = CFrame.new(0, Config.LobbyHeight + 4, 45)

local rooms = {}

local function notify(player: Player, text: string)
	Remotes.Notify:FireClient(player, text)
end

local function part(parent, name, size, position, color, material, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = position
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.Anchored = true
	p.Parent = parent
	return p
end

local function refresh(room)
	for i = #room.members, 1, -1 do
		if room.members[i].Parent == nil then
			table.remove(room.members, i)
		end
	end
	if #room.members == 0 then
		room.host = nil
	elseif not table.find(room.members, room.host) then
		room.host = room.members[1]
	end

	local names = {}
	for _, p in room.members do
		table.insert(names, (p == room.host and "* " or "") .. p.DisplayName)
	end
	local status = room.locked and "STARTING..." or (#room.members == 0 and "Empty - step up to join" or table.concat(names, "\n"))
	room.label.Text = ("PRIVATE PARTY %d  [%d/%d]\n%s"):format(room.index, #room.members, Config.PartyMax, status)
end

local function roomOf(player: Player)
	for _, room in rooms do
		if table.find(room.members, player) then
			return room
		end
	end
	return nil
end

local function leave(player: Player)
	local room = roomOf(player)
	if room then
		table.remove(room.members, table.find(room.members, player))
		refresh(room)
	end
end

local function join(player: Player, room)
	if room.locked then
		notify(player, "That party is already starting")
		return
	end
	if #room.members >= Config.PartyMax then
		notify(player, "Party is full (" .. Config.PartyMax .. "/" .. Config.PartyMax .. ")")
		return
	end
	leave(player)
	table.insert(room.members, player)
	refresh(room)
	notify(player, ("Joined party %d. The host (*) presses START."):format(room.index))
end

local function launch(members)
	if Config.GamePlaceId == 0 then
		-- single-place mode: move the party into the arena
		for _, player in members do
			local char = player.Character
			if char then
				player:SetAttribute("InGame", true)
				char:PivotTo(CFrame.new(math.random(-6, 6), 5, math.random(-6, 6)))
				if Lobby.onEnterGame then
					Lobby.onEnterGame(player)
				end
			end
		end
	else
		-- real private server for this party only
		local ok, err = pcall(function()
			local code = TeleportService:ReserveServer(Config.GamePlaceId)
			local options = Instance.new("TeleportOptions")
			options.ReservedServerAccessCode = code
			TeleportService:TeleportAsync(Config.GamePlaceId, members, options)
		end)
		if not ok then
			warn("Teleport failed: " .. tostring(err))
			for _, player in members do
				notify(player, "Teleport failed - check GamePlaceId and that the game is published")
			end
		end
	end
end

local function startRoom(room)
	if room.locked or #room.members == 0 then
		return
	end
	room.locked = true
	for t = Config.StartCountdown, 1, -1 do
		for _, p in room.members do
			notify(p, "Game starts in " .. t)
		end
		room.label.Text = ("PRIVATE PARTY %d\nStarting in %d..."):format(room.index, t)
		task.wait(1)
	end

	local members = {}
	for _, p in room.members do
		if p.Parent then
			table.insert(members, p)
		end
	end
	room.members = {}
	room.host = nil
	if #members > 0 then
		launch(members)
	end
	room.locked = false
	refresh(room)
end

function Lobby.build()
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	folder.Parent = workspace

	local y = Config.LobbyHeight
	part(folder, "LobbyFloor", Vector3.new(160, 2, 160), Vector3.new(0, y, 0), Color3.fromRGB(35, 35, 45), Enum.Material.Concrete)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(0, y + 1.5, 45)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(80, 120, 200)
	spawn.Parent = folder

	local title = part(folder, "Title", Vector3.new(1, 1, 1), Vector3.new(0, y + 25, 60), Color3.new(0, 0, 0), nil, 1)
	title.CanCollide = false
	local tg = Instance.new("BillboardGui")
	tg.Size = UDim2.fromOffset(500, 100)
	tg.AlwaysOnTop = true
	tg.Adornee = title
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.Text = "ZOMBIE ESCAPE\nPick a private party (max " .. Config.PartyMax .. ")"
	tl.TextScaled = true
	tl.Font = Enum.Font.GothamBlack
	tl.TextColor3 = Color3.fromRGB(255, 80, 80)
	tl.Parent = tg
	tg.Parent = title

	local n = Config.LobbyRooms
	for i = 1, n do
		local x = (i - (n + 1) / 2) * 34
		local room = { index = i, members = {}, host = nil, locked = false }
		rooms[i] = room

		local pad = part(folder, "Pad" .. i, Vector3.new(20, 1, 20), Vector3.new(x, y + 1.5, -30), Color3.fromRGB(60, 200, 120), Enum.Material.Neon, 0.3)
		local glass = Color3.fromRGB(150, 200, 255)
		part(folder, "WallBack" .. i, Vector3.new(20, 12, 1), Vector3.new(x, y + 7, -40), glass, Enum.Material.Glass, 0.6)
		part(folder, "WallL" .. i, Vector3.new(1, 12, 20), Vector3.new(x - 10, y + 7, -30), glass, Enum.Material.Glass, 0.6)
		part(folder, "WallR" .. i, Vector3.new(1, 12, 20), Vector3.new(x + 10, y + 7, -30), glass, Enum.Material.Glass, 0.6)

		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(260, 110)
		gui.StudsOffset = Vector3.new(0, 10, 0)
		gui.AlwaysOnTop = true
		gui.Adornee = pad
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 0.4
		label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Parent = gui
		gui.Parent = pad
		room.label = label

		local joinPrompt = Instance.new("ProximityPrompt")
		joinPrompt.ActionText = "Join / Leave"
		joinPrompt.ObjectText = "Private Party " .. i
		joinPrompt.HoldDuration = 0
		joinPrompt.MaxActivationDistance = 12
		joinPrompt.RequiresLineOfSight = false
		joinPrompt.Parent = pad
		joinPrompt.Triggered:Connect(function(player)
			if roomOf(player) == room then
				leave(player)
				notify(player, "Left the party")
			else
				join(player, room)
				if #room.members >= Config.PartyMax then
					task.spawn(startRoom, room)
				end
			end
		end)

		local button = part(folder, "Start" .. i, Vector3.new(4, 1, 4), Vector3.new(x, y + 1.5, -12), Color3.fromRGB(255, 150, 40), Enum.Material.Neon)
		local startPrompt = Instance.new("ProximityPrompt")
		startPrompt.ActionText = "START GAME"
		startPrompt.ObjectText = "Host only"
		startPrompt.HoldDuration = 0.5
		startPrompt.MaxActivationDistance = 10
		startPrompt.RequiresLineOfSight = false
		startPrompt.Parent = button
		startPrompt.Triggered:Connect(function(player)
			if room.host ~= player then
				notify(player, "Only the party host (*) can start")
				return
			end
			startRoom(room)
		end)

		refresh(room)
	end

	Players.PlayerRemoving:Connect(leave)
	return spawn
end

return Lobby
]=====])

put(SSS, "Script", "GameManager", [=====[
-- Script: ServerScriptService/GameManager
-- Entry point. Modes (decided by Config.GamePlaceId):
--   "Both"  : GamePlaceId == 0, lobby + arena in one place (Studio testing)
--   "Lobby" : this place is the lobby; parties are teleported to the game place
--   "Game"  : this place is the game place (private server for one party)
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.RemoteHub)

local Modules = script.Parent:WaitForChild("Modules")
local MapBuilder = require(Modules.MapBuilder)
local LootService = require(Modules.LootService)
local ZombieService = require(Modules.ZombieService)
local WeaponService = require(Modules.WeaponService)
local WeaponFactory = require(Modules.WeaponFactory)
local LobbyService = require(Modules.LobbyService)

local mode
if Config.GamePlaceId == 0 then
	mode = "Both"
elseif game.PlaceId == Config.GamePlaceId then
	mode = "Game"
else
	mode = "Lobby"
end

-- remove template leftovers
for _, name in { "Baseplate", "SpawnLocation" } do
	local old = workspace:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end

-- night atmosphere
Lighting.ClockTime = 0
Lighting.Brightness = 0.6
Lighting.Ambient = Color3.fromRGB(25, 25, 40)
Lighting.OutdoorAmbient = Color3.fromRGB(25, 25, 40)
Lighting.FogColor = Color3.fromRGB(10, 10, 15)
Lighting.FogStart = 60
Lighting.FogEnd = 300
if mode ~= "Game" then
	Lighting.FogEnd = 100000 -- no fog in the lobby
end

local function clearTools(player: Player)
	for _, container in { player:FindFirstChild("Backpack"), player.Character } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") then
					child:Destroy()
				end
			end
		end
	end
end

local function resetRun(player: Player)
	player:SetAttribute("Reserve", Config.StartReserve)
	for key in player:GetAttributes() do
		if string.sub(key, 1, 4) == "Key_" then
			player:SetAttribute(key, nil)
		end
	end
	player:SetAttribute("Keys", 0)
end

local function enterGame(player: Player)
	player:SetAttribute("InGame", true)
	resetRun(player)
	clearTools(player)
	local pistol = WeaponFactory.create("Pistol")
	pistol.Parent = player:WaitForChild("Backpack")
	Remotes.Notify:FireClient(player, "Find " .. Config.KeysNeeded .. " keycards in the houses, then reach the ESCAPE zone!")
end

local map
if mode ~= "Game" then
	LobbyService.build()
	LobbyService.onEnterGame = enterGame
end
if mode ~= "Lobby" then
	map = MapBuilder.build()
	if mode == "Both" then
		map.spawn.Enabled = false -- players spawn in the lobby
	end
	LootService.start(map)
	ZombieService.onKilled = function(position)
		LootService.drop(position, "Ammo")
	end
	ZombieService.start(map)
	WeaponService.start()
end

-- players -----------------------------------------------------------------
local function bounceToLobby(player: Player)
	if Config.LobbyPlaceId ~= 0 then
		pcall(function()
			TeleportService:Teleport(Config.LobbyPlaceId, player)
		end)
	else
		player:Kick("Join the game through the lobby.")
	end
end

local function onPlayer(player: Player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	for _, name in { "Kills", "Escapes" } do
		local v = Instance.new("IntValue")
		v.Name = name
		v.Parent = stats
	end
	stats.Parent = player

	if mode == "Game" and game.PrivateServerId == "" and not RunService:IsStudio() then
		bounceToLobby(player)
		return
	end

	player.CharacterAdded:Connect(function()
		if mode == "Game" then
			enterGame(player)
		else
			player:SetAttribute("InGame", false) -- respawned in the lobby
			resetRun(player)
		end
	end)
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayer, p)
end

-- escape zone -------------------------------------------------------------
if map then
	local lastWarn = {}
	map.escapeZone.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player or not player:GetAttribute("InGame") then
			return
		end
		local hum = character:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then
			return
		end

		local keys = player:GetAttribute("Keys") or 0
		if keys >= Config.KeysNeeded then
			player.leaderstats.Escapes.Value += 1
			resetRun(player)
			if mode == "Both" then
				Remotes.Notify:FireClient(player, "YOU ESCAPED! Back to the lobby.")
				clearTools(player)
				player:SetAttribute("InGame", false)
				character:PivotTo(LobbyService.spawnCFrame)
			elseif Config.LobbyPlaceId ~= 0 then
				Remotes.Notify:FireClient(player, "YOU ESCAPED! Returning to the lobby...")
				player:SetAttribute("InGame", false)
				task.delay(4, bounceToLobby, player)
			else
				Remotes.Notify:FireClient(player, "YOU ESCAPED! Back to the start for another run.")
				character:PivotTo(CFrame.new(0, 5, 0))
			end
		elseif os.clock() - (lastWarn[player] or 0) > 4 then
			lastWarn[player] = os.clock()
			Remotes.Notify:FireClient(player, ("Need %d more keycard(s)"):format(Config.KeysNeeded - keys))
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastWarn[player] = nil
	end)
end
]=====])

local zs = modules:WaitForChild("ZombieService")
patch(zs, [[if hrp and hum and hum.Health > 0 then]], [[if hrp and hum and hum.Health > 0 and player:GetAttribute("InGame") then]])
patch(zs, [[if hrp and (Vector3.new(x, 0, z)]], [[if hrp and player:GetAttribute("InGame") and (Vector3.new(x, 0, z)]])
patch(zs, [[if count < Config.ZombieMax and #Players:GetPlayers() > 0 then]], [[local active = 0
			for _, pl in Players:GetPlayers() do
				if pl:GetAttribute("InGame") then
					active += 1
				end
			end
			if count < Config.ZombieMax and active > 0 then]])

local hud = SPS:WaitForChild("HUD")
patch(hud, [[RunService.Heartbeat:Connect(function()
	local char = player.Character]], [[RunService.Heartbeat:Connect(function()
	local inGame = player:GetAttribute("InGame") == true
	ammo.Visible = inGame
	keys.Visible = inGame
	local char = player.Character]])

print("Lobby update installed! Press Play.")

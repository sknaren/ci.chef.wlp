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

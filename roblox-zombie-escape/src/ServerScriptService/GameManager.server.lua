-- Script: ServerScriptService/GameManager
-- Entry point. Boots the map, loot, zombies, weapons and handles players.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.RemoteHub)

local Modules = script.Parent:WaitForChild("Modules")
local MapBuilder = require(Modules.MapBuilder)
local LootService = require(Modules.LootService)
local ZombieService = require(Modules.ZombieService)
local WeaponService = require(Modules.WeaponService)
local WeaponFactory = require(Modules.WeaponFactory)

-- remove template leftovers so they don't overlap the generated map
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

local map = MapBuilder.build()
LootService.start(map)
ZombieService.onKilled = function(position)
	LootService.drop(position, "Ammo")
end
ZombieService.start(map)
WeaponService.start()

local function setupCharacter(player: Player, character: Model)
	player:SetAttribute("Reserve", Config.StartReserve)
	for key in player:GetAttributes() do
		if string.sub(key, 1, 4) == "Key_" then
			player:SetAttribute(key, nil)
		end
	end
	player:SetAttribute("Keys", 0)

	local pistol = WeaponFactory.create("Pistol")
	pistol.Parent = player:WaitForChild("Backpack")
	Remotes.Notify:FireClient(player, "Find " .. Config.KeysNeeded .. " keycards in the houses, then reach the ESCAPE zone!")
end

Players.PlayerAdded:Connect(function(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	for _, name in { "Kills", "Escapes" } do
		local v = Instance.new("IntValue")
		v.Name = name
		v.Parent = stats
	end
	stats.Parent = player

	player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)
end)

-- escape zone
local lastWarn = {}
map.escapeZone.Touched:Connect(function(hit)
	local character = hit.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return
	end

	local keys = player:GetAttribute("Keys") or 0
	if keys >= Config.KeysNeeded then
		player.leaderstats.Escapes.Value += 1
		player:SetAttribute("Keys", 0)
		for key in player:GetAttributes() do
			if string.sub(key, 1, 4) == "Key_" then
				player:SetAttribute(key, nil)
			end
		end
		Remotes.Notify:FireClient(player, "YOU ESCAPED! Back to the start for another run.")
		character:PivotTo(CFrame.new(0, 5, 0))
	elseif os.clock() - (lastWarn[player] or 0) > 4 then
		lastWarn[player] = os.clock()
		Remotes.Notify:FireClient(player, ("Need %d more keycard(s)"):format(Config.KeysNeeded - keys))
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastWarn[player] = nil
end)

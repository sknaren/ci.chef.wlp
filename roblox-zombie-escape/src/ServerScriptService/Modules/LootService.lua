-- ModuleScript: ServerScriptService/Modules/LootService
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.RemoteHub)
local WeaponFactory = require(script.Parent.WeaponFactory)

local LootService = {}

local COLORS = {
	Ammo = Color3.fromRGB(255, 210, 60),
	Medkit = Color3.fromRGB(255, 255, 255),
	Pistol = Color3.fromRGB(120, 120, 120),
	Rifle = Color3.fromRGB(70, 140, 70),
	Shotgun = Color3.fromRGB(170, 110, 50),
	Key = Color3.fromRGB(70, 160, 255),
}

local lootFolder

local function hasTool(player: Player, name: string): boolean
	local char = player.Character
	return player.Backpack:FindFirstChild(name) ~= nil or (char ~= nil and char:FindFirstChild(name) ~= nil)
end

local function notify(player: Player, text: string)
	Remotes.Notify:FireClient(player, text)
end

local function countKeys(player: Player)
	local n = 0
	for key, value in player:GetAttributes() do
		if string.sub(key, 1, 4) == "Key_" and value then
			n += 1
		end
	end
	player:SetAttribute("Keys", n)
end

-- returns true when the pickup was consumed
local function give(player: Player, kind: string, keyId: number?): boolean
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return false
	end

	if kind == "Ammo" then
		local reserve = player:GetAttribute("Reserve") or 0
		if reserve >= Config.MaxReserve then
			notify(player, "Ammo full")
			return false
		end
		player:SetAttribute("Reserve", math.min(Config.MaxReserve, reserve + Config.AmmoPickup))
		notify(player, "+" .. Config.AmmoPickup .. " ammo")
		return true
	elseif kind == "Medkit" then
		if hum.Health >= hum.MaxHealth then
			notify(player, "Health full")
			return false
		end
		hum.Health = math.min(hum.MaxHealth, hum.Health + Config.MedkitHeal)
		notify(player, "+" .. Config.MedkitHeal .. " health")
		return true
	elseif kind == "Key" then
		local attr = "Key_" .. tostring(keyId)
		if player:GetAttribute(attr) then
			notify(player, "You already have this keycard")
			return false
		end
		player:SetAttribute(attr, true)
		countKeys(player)
		notify(player, ("Keycard %d/%d"):format(player:GetAttribute("Keys"), Config.KeysNeeded))
		return true
	elseif Config.Weapons[kind] then
		if hasTool(player, kind) then
			player:SetAttribute("Reserve", math.min(Config.MaxReserve, (player:GetAttribute("Reserve") or 0) + Config.Weapons[kind].MagSize))
			notify(player, "Already have " .. kind .. " (+ammo)")
		else
			local tool = WeaponFactory.create(kind)
			tool.Parent = player.Backpack
			notify(player, "Picked up " .. kind)
		end
		return true
	end
	return false
end

-- respawns: true = reappears after Config.LootRespawn, false = removed after 60s
function LootService.createLoot(position: Vector3, kind: string, respawns: boolean, keyId: number?)
	local item = Instance.new("Part")
	item.Name = "Loot_" .. kind
	item.Size = Vector3.new(1.6, 1.6, 1.6)
	item.Position = position
	item.Color = COLORS[kind] or Color3.new(1, 1, 1)
	item.Material = Enum.Material.Neon
	item.Anchored = true
	item.CanCollide = false
	item.Parent = lootFolder

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 26)
	gui.StudsOffset = Vector3.new(0, 2, 0)
	gui.MaxDistance = 40
	gui.Adornee = item
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = kind == "Key" and "Keycard" or kind
	text.TextColor3 = item.Color
	text.TextStrokeTransparency = 0.3
	text.TextScaled = true
	text.Font = Enum.Font.GothamBold
	text.Parent = gui
	gui.Parent = item

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Take"
	prompt.ObjectText = kind == "Key" and "Keycard" or kind
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = item

	prompt.Triggered:Connect(function(player)
		if not prompt.Enabled then
			return
		end
		if give(player, kind, keyId) then
			if respawns then
				prompt.Enabled = false
				item.Transparency = 1
				gui.Enabled = false
				task.delay(Config.LootRespawn, function()
					if item.Parent then
						prompt.Enabled = true
						item.Transparency = 0
						gui.Enabled = true
					end
				end)
			else
				item:Destroy()
			end
		end
	end)

	if not respawns then
		Debris:AddItem(item, 60)
	end
	return item
end

local function rollKind(): string
	local total = 0
	for _, entry in Config.LootTable do
		total += entry[2]
	end
	local roll = math.random() * total
	for _, entry in Config.LootTable do
		roll -= entry[2]
		if roll <= 0 then
			return entry[1]
		end
	end
	return "Ammo"
end

function LootService.start(map)
	lootFolder = Instance.new("Folder")
	lootFolder.Name = "Loot"
	lootFolder.Parent = workspace

	-- regular loot in every house
	for _, house in map.houses do
		for _, spot in house.lootSpots do
			LootService.createLoot(spot, rollKind(), true)
		end
	end

	-- keycards in randomly chosen houses
	local order = {}
	for i = 1, #map.houses do
		order[i] = i
	end
	for i = #order, 2, -1 do
		local j = math.random(i)
		order[i], order[j] = order[j], order[i]
	end
	for k = 1, math.min(Config.KeysNeeded, #order) do
		local house = map.houses[order[k]]
		LootService.createLoot(house.keySpot, "Key", true, k)
	end
end

-- used by ZombieService for drops
function LootService.drop(position: Vector3, kind: string)
	LootService.createLoot(position + Vector3.new(0, 1.5, 0), kind, false)
end

return LootService

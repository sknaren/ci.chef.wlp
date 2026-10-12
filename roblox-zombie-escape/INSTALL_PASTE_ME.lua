-- ZOMBIE ESCAPE ONE-PASTE INSTALLER
-- Roblox Studio: View > Command Bar (enable it), paste this WHOLE file, press Enter. Then press Play.
local SSS = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")
local SP = game:GetService("StarterPlayer")
local SPS = SP:FindFirstChild("StarterPlayerScripts") or SP:WaitForChild("StarterPlayerScripts")

local modules = SSS:FindFirstChild("Modules") or Instance.new("Folder")
modules.Name = "Modules"
modules.Parent = SSS

local parents = { ReplicatedStorage = RS, ServerScriptService = SSS, Modules = modules, StarterPlayerScripts = SPS }

local function add(parentKey, className, name, source)
	local parent = parents[parentKey]
	local old = parent:FindFirstChild(name)
	if old then old:Destroy() end
	local s = Instance.new(className)
	s.Name = name
	s.Source = source
	s.Parent = parent
end

add("ReplicatedStorage", "ModuleScript", "Config", [=====[
-- ModuleScript: ReplicatedStorage/Config
-- All game tuning lives here.
return {
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

add("ReplicatedStorage", "ModuleScript", "RemoteHub", [=====[
-- ModuleScript: ReplicatedStorage/RemoteHub
-- Creates (server) / waits for (client) every RemoteEvent used by the game.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NAMES = { "Fire", "Reload", "Tracer", "Notify", "HitMarker" }

local folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "RemoteEvents"
		folder.Parent = ReplicatedStorage
	end
	for _, name in NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("RemoteEvents")
end

local hub = {}
for _, name in NAMES do
	hub[name] = folder:WaitForChild(name)
end
return hub
]=====])

add("Modules", "ModuleScript", "WeaponFactory", [=====[
-- ModuleScript: ServerScriptService/Modules/WeaponFactory
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config)

local Factory = {}

function Factory.create(name: string): Tool?
	local stats = Config.Weapons[name]
	if not stats then
		return nil
	end

	local tool = Instance.new("Tool")
	tool.Name = name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = name

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = stats.HandleSize
	handle.Color = stats.Color
	handle.Material = Enum.Material.Metal
	handle.Parent = tool

	tool:SetAttribute("IsGun", true)
	tool:SetAttribute("Mag", stats.MagSize)
	tool:SetAttribute("MagSize", stats.MagSize)
	tool:SetAttribute("FireRate", stats.FireRate)
	tool:SetAttribute("Auto", stats.Auto)
	tool:SetAttribute("Reloading", false)
	return tool
end

return Factory
]=====])

add("Modules", "ModuleScript", "MapBuilder", [=====[
-- ModuleScript: ServerScriptService/Modules/MapBuilder
-- Builds a night-time town: ground, fence, 7 houses, spawn pad and escape zone.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config)

local MapBuilder = {}

local function part(parent, name, size, position, color, material, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = position
	p.Color = color
	p.Material = material or Enum.Material.Concrete
	p.Transparency = transparency or 0
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function buildHouse(parent, index, cx, cz)
	local model = Instance.new("Model")
	model.Name = "House" .. index
	local wall = Color3.fromRGB(120 + math.random(-20, 20), 105, 90)
	local H, T, S = 12, 1, 30 -- height, thickness, side length
	local half = S / 2
	local door = 7

	part(model, "Floor", Vector3.new(S, 0.4, S), Vector3.new(cx, 0.2, cz), Color3.fromRGB(70, 55, 40), Enum.Material.WoodPlanks)
	part(model, "Back", Vector3.new(S, H, T), Vector3.new(cx, H / 2, cz - half), wall)
	part(model, "Left", Vector3.new(T, H, S), Vector3.new(cx - half, H / 2, cz), wall)
	part(model, "Right", Vector3.new(T, H, S), Vector3.new(cx + half, H / 2, cz), wall)
	local seg = (S - door) / 2
	part(model, "FrontL", Vector3.new(seg, H, T), Vector3.new(cx - door / 2 - seg / 2, H / 2, cz + half), wall)
	part(model, "FrontR", Vector3.new(seg, H, T), Vector3.new(cx + door / 2 + seg / 2, H / 2, cz + half), wall)
	part(model, "Lintel", Vector3.new(door, 4, T), Vector3.new(cx, H - 2, cz + half), wall)
	part(model, "Roof", Vector3.new(S + 2, 1, S + 2), Vector3.new(cx, H + 0.5, cz), Color3.fromRGB(60, 35, 35))

	local lamp = part(model, "Lamp", Vector3.new(2, 0.3, 2), Vector3.new(cx, H - 0.2, cz), Color3.fromRGB(255, 220, 150), Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Range = 26
	light.Brightness = 1.2
	light.Color = Color3.fromRGB(255, 220, 160)
	light.Parent = lamp

	-- a few crates for cover
	for i = 1, 3 do
		local ox = math.random(-9, 9)
		local oz = math.random(-9, 5)
		part(model, "Crate" .. i, Vector3.new(3, 3, 3), Vector3.new(cx + ox, 1.9, cz + oz), Color3.fromRGB(130, 90, 50), Enum.Material.Wood)
	end

	model.Parent = parent

	local lootSpots = {
		Vector3.new(cx - 9, 1.5, cz - 9),
		Vector3.new(cx + 9, 1.5, cz - 9),
		Vector3.new(cx - 9, 1.5, cz + 6),
		Vector3.new(cx + 9, 1.5, cz + 6),
	}
	return {
		model = model,
		center = Vector3.new(cx, 0, cz),
		lootSpots = lootSpots,
		keySpot = Vector3.new(cx, 1.5, cz - 12),
		zombieSpots = { Vector3.new(cx - 5, 3.5, cz), Vector3.new(cx + 5, 3.5, cz - 5) },
	}
end

function MapBuilder.build()
	local map = Instance.new("Folder")
	map.Name = "Map"
	map.Parent = workspace

	local size = Config.MapSize
	local ground = part(map, "Ground", Vector3.new(size, 1, size), Vector3.new(0, -0.5, 0), Color3.fromRGB(45, 70, 40), Enum.Material.Grass)

	-- invisible-ish fence
	local fenceH = 40
	for _, f in {
		{ Vector3.new(size, fenceH, 2), Vector3.new(0, fenceH / 2, -size / 2) },
		{ Vector3.new(size, fenceH, 2), Vector3.new(0, fenceH / 2, size / 2) },
		{ Vector3.new(2, fenceH, size), Vector3.new(-size / 2, fenceH / 2, 0) },
		{ Vector3.new(2, fenceH, size), Vector3.new(size / 2, fenceH / 2, 0) },
	} do
		part(map, "Fence", f[1], f[2], Color3.fromRGB(20, 20, 20), Enum.Material.Metal, 0.6)
	end

	-- spawn pad (centre)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.Position = Vector3.new(0, 0.5, 0)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 3
	spawn.Color = Color3.fromRGB(80, 120, 200)
	spawn.Parent = map

	-- 3x3 grid: centre = spawn, one corner = escape, remaining 7 = houses
	local step = Config.GridStep
	local houses = {}
	local escapeCell = Vector2.new(1, 1)
	local n = 0
	for gx = -1, 1 do
		for gz = -1, 1 do
			if not (gx == 0 and gz == 0) and not (gx == escapeCell.X and gz == escapeCell.Y) then
				n += 1
				local jx, jz = math.random(-8, 8), math.random(-8, 8)
				table.insert(houses, buildHouse(map, n, gx * step + jx, gz * step + jz))
			end
		end
	end

	local escapePos = Vector3.new(escapeCell.X * step, 0, escapeCell.Y * step)
	local pad = part(map, "EscapeZone", Vector3.new(30, 1, 30), escapePos + Vector3.new(0, 0.5, 0), Color3.fromRGB(60, 255, 120), Enum.Material.Neon, 0.4)
	pad.CanCollide = false
	local beam = part(map, "EscapeBeam", Vector3.new(6, 60, 6), escapePos + Vector3.new(0, 30, 0), Color3.fromRGB(60, 255, 120), Enum.Material.Neon, 0.7)
	beam.CanCollide = false
	local sign = Instance.new("BillboardGui")
	sign.Size = UDim2.fromOffset(200, 50)
	sign.StudsOffset = Vector3.new(0, 70, 0)
	sign.AlwaysOnTop = true
	sign.Adornee = beam
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "ESCAPE"
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = Color3.fromRGB(60, 255, 120)
	label.Parent = sign
	sign.Parent = beam

	return {
		folder = map,
		ground = ground,
		spawn = spawn,
		houses = houses,
		escapeZone = pad,
		escapePos = escapePos,
	}
end

return MapBuilder
]=====])

add("Modules", "ModuleScript", "LootService", [=====[
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
]=====])

add("Modules", "ModuleScript", "ZombieService", [=====[
-- ModuleScript: ServerScriptService/Modules/ZombieService
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Config)

local ZombieService = {}
ZombieService.onKilled = nil -- optional callback(position)

local zombies = {} -- [model] = state
local zombieFolder
local mapData

local function newPart(model, name, size, offset, base, color, collide)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = base * offset
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = collide
	p.Massless = not collide
	p.Parent = model
	return p
end

function ZombieService.spawnZombie(position: Vector3)
	local base = CFrame.new(position.X, 3.1, position.Z) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	local skin = Color3.fromRGB(90, 130 + math.random(-20, 20), 80)

	local model = Instance.new("Model")
	model.Name = "Zombie"

	local root = newPart(model, "HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(), base, Color3.fromRGB(70, 90, 110), true)
	local head = newPart(model, "Head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 1.6, 0), base, skin, false)
	local parts = {
		head,
		newPart(model, "LeftArm", Vector3.new(0.8, 0.8, 2.2), CFrame.new(-1.4, 0.4, -1.1), base, skin, false),
		newPart(model, "RightArm", Vector3.new(0.8, 0.8, 2.2), CFrame.new(1.4, 0.4, -1.1), base, skin, false),
		newPart(model, "LeftLeg", Vector3.new(0.9, 2, 0.9), CFrame.new(-0.5, -2, 0), base, Color3.fromRGB(50, 50, 70), false),
		newPart(model, "RightLeg", Vector3.new(0.9, 2, 0.9), CFrame.new(0.5, -2, 0), base, Color3.fromRGB(50, 50, 70), false),
	}
	for _, p in parts do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
	end

	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.HipHeight = 2
	hum.MaxHealth = Config.ZombieHealth
	hum.Health = Config.ZombieHealth
	hum.WalkSpeed = Config.ZombieSpeed + math.random(-2, 2)
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.Parent = model

	model.PrimaryPart = root
	CollectionService:AddTag(model, "Zombie")
	model.Parent = zombieFolder
	root:SetNetworkOwner(nil)

	zombies[model] = { humanoid = hum, root = root, lastAttack = 0, nextWander = 0 }

	hum.Died:Connect(function()
		zombies[model] = nil
		local uid = model:GetAttribute("LastAttacker")
		local killer = uid and Players:GetPlayerByUserId(uid)
		local stats = killer and killer:FindFirstChild("leaderstats")
		if stats then
			stats.Kills.Value += 1
		end
		if ZombieService.onKilled and math.random() < Config.ZombieAmmoDropChance then
			ZombieService.onKilled(root.Position)
		end
		Debris:AddItem(model, 3)
	end)
	return model
end

local function nearestPlayer(position: Vector3)
	local best, bestDist, bestHum
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 then
			local d = (hrp.Position - position).Magnitude
			if not bestDist or d < bestDist then
				best, bestDist, bestHum = hrp, d, hum
			end
		end
	end
	return best, bestDist, bestHum
end

local function insideHouse(x: number, z: number): boolean
	for _, h in mapData.houses do
		if math.abs(x - h.center.X) < 20 and math.abs(z - h.center.Z) < 20 then
			return true
		end
	end
	return math.abs(x - mapData.escapePos.X) < 20 and math.abs(z - mapData.escapePos.Z) < 20
end

local function randomSpawnPoint(): Vector3?
	local half = Config.MapSize / 2 - 10
	for _ = 1, 12 do
		local x, z = math.random(-half, half), math.random(-half, half)
		if not insideHouse(x, z) then
			local ok = true
			for _, player in Players:GetPlayers() do
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if hrp and (Vector3.new(x, 0, z) - Vector3.new(hrp.Position.X, 0, hrp.Position.Z)).Magnitude < Config.ZombieMinSpawnDistance then
					ok = false
					break
				end
			end
			if ok then
				return Vector3.new(x, 0, z)
			end
		end
	end
	return nil
end

local function think()
	local now = os.clock()
	local half = Config.MapSize / 2 - 10
	for model, z in zombies do
		if z.humanoid.Health <= 0 or not model.Parent then
			zombies[model] = nil
			continue
		end
		local pos = z.root.Position
		local targetRoot, dist, targetHum = nearestPlayer(pos)
		if targetRoot and dist <= Config.ZombieDetectRange then
			z.humanoid:MoveTo(targetRoot.Position)
			if dist <= Config.ZombieAttackRange and now - z.lastAttack >= Config.ZombieAttackCooldown then
				z.lastAttack = now
				targetHum:TakeDamage(Config.ZombieDamage)
			end
			-- hop over crates / low obstacles
			if targetRoot.Position.Y - pos.Y > 2 or z.root.AssemblyLinearVelocity.Magnitude < 1 then
				z.humanoid.Jump = true
			end
		elseif now >= z.nextWander then
			z.nextWander = now + 4 + math.random() * 4
			local target = pos + Vector3.new(math.random(-30, 30), 0, math.random(-30, 30))
			z.humanoid:MoveTo(Vector3.new(math.clamp(target.X, -half, half), 0, math.clamp(target.Z, -half, half)))
		end
	end
end

function ZombieService.start(map)
	mapData = map
	zombieFolder = Instance.new("Folder")
	zombieFolder.Name = "Zombies"
	zombieFolder.Parent = workspace

	for _, house in map.houses do
		for i = 1, math.min(Config.ZombiesPerHouse, #house.zombieSpots) do
			ZombieService.spawnZombie(house.zombieSpots[i])
		end
	end

	task.spawn(function()
		while true do
			task.wait(Config.ZombieSpawnInterval)
			local count = 0
			for _ in zombies do
				count += 1
			end
			if count < Config.ZombieMax and #Players:GetPlayers() > 0 then
				local point = randomSpawnPoint()
				if point then
					ZombieService.spawnZombie(point)
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.3)
			think()
		end
	end)
end

return ZombieService
]=====])

add("Modules", "ModuleScript", "WeaponService", [=====[
-- ModuleScript: ServerScriptService/Modules/WeaponService
-- Server-authoritative shooting and reloading.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.RemoteHub)

local WeaponService = {}

local lastShot = {} -- [tool] = os.clock()

local function validTool(player: Player, tool: any)
	if typeof(tool) ~= "Instance" or not tool:IsA("Tool") then
		return nil
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not hum or hum.Health <= 0 or tool.Parent ~= char then
		return nil
	end
	local stats = Config.Weapons[tool.Name]
	if not stats or not tool:GetAttribute("IsGun") then
		return nil
	end
	return stats, char
end

local function characterList()
	local list = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	return list
end

local function onFire(player: Player, tool: any, aimPos: any)
	if typeof(aimPos) ~= "Vector3" then
		return
	end
	local stats, char = validTool(player, tool)
	if not stats then
		return
	end
	if tool:GetAttribute("Reloading") or (tool:GetAttribute("Mag") or 0) <= 0 then
		return
	end
	local now = os.clock()
	if now - (lastShot[tool] or 0) < stats.FireRate * 0.9 then
		return
	end
	lastShot[tool] = now
	tool:SetAttribute("Mag", tool:GetAttribute("Mag") - 1)

	local head = char:FindFirstChild("Head")
	if not head then
		return
	end
	local origin = head.Position
	local offset = aimPos - origin
	if offset.Magnitude < 0.1 then
		return
	end
	local baseCF = CFrame.lookAt(origin, aimPos)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = characterList() -- no friendly fire

	local handle = tool:FindFirstChild("Handle")
	local muzzle = handle and handle.Position or origin
	local hitSomething = false

	for _ = 1, stats.Pellets do
		local dir = (baseCF * CFrame.Angles(
			(math.random() * 2 - 1) * stats.Spread,
			(math.random() * 2 - 1) * stats.Spread,
			0
		)).LookVector
		local result = workspace:Raycast(origin, dir * stats.Range, params)
		local endPos = result and result.Position or origin + dir * stats.Range

		if result then
			local model = result.Instance:FindFirstAncestorOfClass("Model")
			local hum = model and model:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 and CollectionService:HasTag(model, "Zombie") then
				local damage = stats.Damage
				if result.Instance.Name == "Head" then
					damage *= 2
				end
				model:SetAttribute("LastAttacker", player.UserId)
				hum:TakeDamage(damage)
				hitSomething = true
			end
		end
		Remotes.Tracer:FireAllClients(muzzle, endPos)
	end
	if hitSomething then
		Remotes.HitMarker:FireClient(player)
	end
end

local function onReload(player: Player, tool: any)
	local stats = validTool(player, tool)
	if not stats or tool:GetAttribute("Reloading") then
		return
	end
	local reserve = player:GetAttribute("Reserve") or 0
	local mag = tool:GetAttribute("Mag") or 0
	if mag >= stats.MagSize or reserve <= 0 then
		return
	end

	tool:SetAttribute("Reloading", true)
	task.wait(stats.ReloadTime)
	if tool.Parent and player.Parent then
		reserve = player:GetAttribute("Reserve") or 0
		mag = tool:GetAttribute("Mag") or 0
		local take = math.min(stats.MagSize - mag, reserve)
		tool:SetAttribute("Mag", mag + take)
		player:SetAttribute("Reserve", reserve - take)
	end
	tool:SetAttribute("Reloading", false)
end

function WeaponService.start()
	Remotes.Fire.OnServerEvent:Connect(onFire)
	Remotes.Reload.OnServerEvent:Connect(onReload)
end

return WeaponService
]=====])

add("ServerScriptService", "Script", "GameManager", [=====[
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
]=====])

add("StarterPlayerScripts", "LocalScript", "GunClient", [=====[
-- LocalScript: StarterPlayer/StarterPlayerScripts/GunClient
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local Remotes = require(ReplicatedStorage:WaitForChild("RemoteHub"))

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local equipped: Tool? = nil
local firing = false
local connected = {}

local function fireLoop(tool: Tool)
	if firing then
		return
	end
	firing = true
	while firing and equipped == tool do
		if (tool:GetAttribute("Mag") or 0) <= 0 then
			Remotes.Reload:FireServer(tool)
			break
		end
		if not tool:GetAttribute("Reloading") then
			Remotes.Fire:FireServer(tool, mouse.Hit.Position)
		end
		if not tool:GetAttribute("Auto") then
			break
		end
		task.wait(tool:GetAttribute("FireRate") or 0.2)
	end
	firing = false
end

local function onCharacter(character: Model)
	equipped = nil
	firing = false
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("IsGun") then
			equipped = child
			if not connected[child] then
				connected[child] = true
				child.Activated:Connect(function()
					task.spawn(fireLoop, child)
				end)
				child.Deactivated:Connect(function()
					firing = false
				end)
			end
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child == equipped then
			equipped = nil
			firing = false
		end
	end)
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	onCharacter(player.Character)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.R and equipped then
		Remotes.Reload:FireServer(equipped)
	end
end)

-- bullet tracers
Remotes.Tracer.OnClientEvent:Connect(function(from: Vector3, to: Vector3)
	local dist = (to - from).Magnitude
	if dist < 1 then
		return
	end
	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(255, 230, 120)
	beam.Size = Vector3.new(0.12, 0.12, dist)
	beam.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -dist / 2)
	beam.Parent = workspace
	Debris:AddItem(beam, 0.06)
end)
]=====])

add("StarterPlayerScripts", "LocalScript", "HUD", [=====[
-- LocalScript: StarterPlayer/StarterPlayerScripts/HUD
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("RemoteHub"))

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "ZombieHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local function label(name, size, position, anchor, textSize, color)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = position
	l.AnchorPoint = anchor
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = textSize
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.4
	l.Text = ""
	l.Parent = gui
	return l
end

local ammo = label("Ammo", UDim2.fromOffset(260, 50), UDim2.new(1, -20, 1, -20), Vector2.new(1, 1), 36, Color3.new(1, 1, 1))
ammo.TextXAlignment = Enum.TextXAlignment.Right
local keys = label("Keys", UDim2.fromOffset(300, 30), UDim2.new(0.5, 0, 0, 12), Vector2.new(0.5, 0), 22, Color3.fromRGB(90, 170, 255))
local message = label("Message", UDim2.fromOffset(700, 40), UDim2.new(0.5, 0, 0.2, 0), Vector2.new(0.5, 0.5), 26, Color3.fromRGB(255, 240, 180))
message.TextTransparency = 1
message.TextStrokeTransparency = 1

local hit = label("Hit", UDim2.fromOffset(40, 40), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), 36, Color3.fromRGB(255, 70, 70))
hit.Text = "X"
hit.TextTransparency = 1
hit.TextStrokeTransparency = 1

RunService.Heartbeat:Connect(function()
	local char = player.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	if tool and tool:GetAttribute("IsGun") then
		local suffix = tool:GetAttribute("Reloading") and " (reloading)" or ""
		ammo.Text = ("%s  %d / %d%s"):format(tool.Name, tool:GetAttribute("Mag") or 0, player:GetAttribute("Reserve") or 0, suffix)
	else
		ammo.Text = ("Reserve ammo: %d"):format(player:GetAttribute("Reserve") or 0)
	end
	keys.Text = ("Keycards %d / %d"):format(player:GetAttribute("Keys") or 0, Config.KeysNeeded)
end)

local token = 0
Remotes.Notify.OnClientEvent:Connect(function(text: string)
	token += 1
	local mine = token
	message.Text = text
	message.TextTransparency = 0
	message.TextStrokeTransparency = 0.4
	task.delay(3.5, function()
		if token == mine then
			TweenService:Create(message, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end)

Remotes.HitMarker.OnClientEvent:Connect(function()
	hit.TextTransparency = 0
	hit.TextStrokeTransparency = 0.4
	TweenService:Create(hit, TweenInfo.new(0.25), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
end)
]=====])

print("Zombie Escape installed! Delete the Baseplate is automatic. Press Play.")

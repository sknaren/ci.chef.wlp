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
		if hrp and hum and hum.Health > 0 and player:GetAttribute("InGame") then
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
				if hrp and player:GetAttribute("InGame") and (Vector3.new(x, 0, z) - Vector3.new(hrp.Position.X, 0, hrp.Position.Z)).Magnitude < Config.ZombieMinSpawnDistance then
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
			local active = 0
			for _, pl in Players:GetPlayers() do
				if pl:GetAttribute("InGame") then
					active += 1
				end
			end
			if count < Config.ZombieMax and active > 0 then
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

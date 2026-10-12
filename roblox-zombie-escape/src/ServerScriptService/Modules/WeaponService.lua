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

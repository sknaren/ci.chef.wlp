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

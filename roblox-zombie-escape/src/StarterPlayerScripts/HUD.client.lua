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
	local inGame = player:GetAttribute("InGame") == true
	ammo.Visible = inGame
	keys.Visible = inGame
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

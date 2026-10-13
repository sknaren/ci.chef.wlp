-- ClientMain  (LocalScript in StarterPlayer > StarterPlayerScripts)
-- HUD, per-arena day/night lighting, weapon firing, heal (H), sprint (Shift), sneak (C), dismount (E).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local plr = Players.LocalPlayer
local R_Msg, R_Status = RS:WaitForChild("Msg"), RS:WaitForChild("Status")
local R_Fire, R_Heal = RS:WaitForChild("Fire"), RS:WaitForChild("Heal")

local DAY, NIGHT = 120, 180
local CYCLE = DAY + NIGHT
local function lerp(a, b, t) return a + (b - a) * t end
local function darkness(t)
	if t < 10 then return 1 - t / 10 end
	if t < DAY - 10 then return 0 end
	if t < DAY + 10 then return (t - (DAY - 10)) / 20 end
	return 1
end

-------------------------------------------------------------------- HUD
local gui = Instance.new("ScreenGui")
gui.Name = "HUD"
gui.ResetOnSpawn = false
gui.Parent = plr:WaitForChild("PlayerGui")

local function label(pos, size, anchor)
	local l = Instance.new("TextLabel")
	l.AnchorPoint = anchor or Vector2.new(0, 0)
	l.Position = pos
	l.Size = size
	l.BackgroundColor3 = Color3.new(0, 0, 0)
	l.BackgroundTransparency = 0.4
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.Parent = gui
	return l
end
local clock = label(UDim2.fromScale(0.5, 0.02), UDim2.fromOffset(380, 36), Vector2.new(0.5, 0))
local stats = label(UDim2.fromScale(0.02, 0.97), UDim2.fromOffset(300, 70), Vector2.new(0, 1))
local toast = label(UDim2.fromScale(0.5, 0.22), UDim2.fromOffset(460, 40), Vector2.new(0.5, 0))
local help = label(UDim2.fromScale(0.98, 0.97), UDim2.fromOffset(300, 90), Vector2.new(1, 1))
help.TextSize = 14
help.TextScaled = false
help.TextWrapped = true
help.Text = "E: open / ride / get off\nShift run | C sneak | H heal\n1 pistol  2 bat | Click: shoot\nNoise attracts zombies!"
clock.Visible, toast.Visible, stats.Visible = false, false, false
stats.TextScaled = false
stats.TextSize = 18
stats.TextXAlignment = Enum.TextXAlignment.Left

local toastId = 0
R_Msg.OnClientEvent:Connect(function(text, color)
	toastId += 1
	local my = toastId
	toast.Text = text
	toast.TextColor3 = Color3.fromHex(color)
	toast.Visible = true
	task.delay(2.5, function() if my == toastId then toast.Visible = false end end)
end)

-------------------------------------------------------------------- day / night (each arena has its own clock)
local state
R_Status.OnClientEvent:Connect(function(d)
	state = d.active and d or nil
	clock.Visible = d.active
	stats.Visible = d.active
	if not d.active then
		Lighting.ClockTime, Lighting.Brightness, Lighting.FogEnd = 14, 2, 100000
		Lighting.Ambient, Lighting.OutdoorAmbient = Color3.fromRGB(70, 70, 70), Color3.fromRGB(127, 127, 127)
	end
end)

RunService.RenderStepped:Connect(function(dt)
	if not state then return end
	state.time = (state.time + dt) % CYCLE
	local t = state.time
	local dark = darkness(t)
	local clockTime
	if t < DAY then clockTime = 6 + 12 * (t / DAY) else clockTime = (18 + 12 * ((t - DAY) / NIGHT)) % 24 end
	Lighting.ClockTime = clockTime
	Lighting.Brightness = lerp(2.2, 0.15, dark)
	Lighting.FogStart = 0
	Lighting.FogEnd = lerp(2500, 260, dark)
	Lighting.FogColor = Color3.new(0.53, 0.72, 0.91):Lerp(Color3.new(0.01, 0.02, 0.05), dark)
	Lighting.Ambient = Color3.fromRGB(70, 70, 70):Lerp(Color3.fromRGB(8, 10, 18), dark)
	Lighting.OutdoorAmbient = Color3.fromRGB(127, 127, 127):Lerp(Color3.fromRGB(14, 18, 34), dark)
	local left = math.ceil(t < DAY and DAY - t or CYCLE - t)
	clock.Text = ("DAY %d  -  %s  %d:%02d"):format(state.day, t < DAY and "DAYTIME" or "NIGHT", left // 60, left % 60)
	clock.TextColor3 = t < DAY and Color3.fromRGB(242, 177, 52) or Color3.fromRGB(143, 168, 255)
	local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
	stats.Text = ("HP %d   Ammo %d\nMedkits %d   Food %d   Kills %d"):format(
		hum and hum.Health or 0, plr:GetAttribute("Ammo") or 0, plr:GetAttribute("Medkits") or 0, plr:GetAttribute("Food") or 0, state.kills or 0)
end)

-------------------------------------------------------------------- weapons / movement
local mouse = plr:GetMouse()
local function hookTool(tool)
	if not tool:IsA("Tool") or (tool.Name ~= "Pistol" and tool.Name ~= "Bat") then return end
	tool.Activated:Connect(function() R_Fire:FireServer(tool.Name, mouse.Hit.Position) end)
end
local function hookCharacter(char)
	char.ChildAdded:Connect(hookTool)
	for _, c in char:GetChildren() do hookTool(c) end
end
plr.CharacterAdded:Connect(hookCharacter)
if plr.Character then hookCharacter(plr.Character) end
plr.ChildAdded:Connect(function(c) if c:IsA("Backpack") then c.ChildAdded:Connect(hookTool) end end)
local bp = plr:FindFirstChildOfClass("Backpack")
if bp then bp.ChildAdded:Connect(hookTool) end

local function setSpeed()
	local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	if UIS:IsKeyDown(Enum.KeyCode.C) then hum.WalkSpeed = 6
	elseif UIS:IsKeyDown(Enum.KeyCode.LeftShift) then hum.WalkSpeed = 26
	else hum.WalkSpeed = 16 end
end
UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.H then R_Heal:FireServer() end
	if input.KeyCode == Enum.KeyCode.E then
		local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then hum.Sit = false; hum.Jump = true end
	end
	setSpeed()
end)
UIS.InputEnded:Connect(setSpeed)

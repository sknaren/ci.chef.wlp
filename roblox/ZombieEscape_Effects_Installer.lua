-- Zombie Escape: 3D / visual effects installer.
-- Paste into the Roblox Studio command bar AFTER the main Zombie Escape installer, then press Play.
-- Installs:
--   ServerScriptService.EffectsServer          (Script)       lighting, lobby holograms, pickup beams, zombie eyes, flicker
--   StarterPlayerScripts.Effects               (LocalScript)  muzzle flash, tracers, impacts, shells, camera shake,
--                                                             blood, damage vignette, hit markers, pickup popups, dust
-- Safe to run more than once: existing copies are replaced.

local SSS = game:GetService("ServerScriptService")
local SPS = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")

local function put(parent, className, name, source)
	local old = parent:FindFirstChild(name)
	if old then old:Destroy() end
	local s = Instance.new(className)
	s.Name = name
	s.Source = source
	s.Parent = parent
end

put(SSS, "Script", "EffectsServer", [=====[
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

-- ---------------------------------------------------------------- helpers
local anims = {}
local clock = 0

local function animate(fn)
	table.insert(anims, fn)
end

RunService.Heartbeat:Connect(function(dt)
	clock += dt
	for i = #anims, 1, -1 do
		if not anims[i](clock) then
			table.remove(anims, i)
		end
	end
end)

local function ensure(className, name, props)
	local inst = Lighting:FindFirstChild(name)
	if not inst then
		inst = Instance.new(className)
		inst.Name = name
		inst.Parent = Lighting
	end
	for k, v in props do
		inst[k] = v
	end
	return inst
end

local function newLight(className, parent, props)
	local l = Instance.new(className)
	l:SetAttribute("FX", true)
	for k, v in props do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e:SetAttribute("FX", true)
	e.Texture = SPARKLE
	for k, v in props do
		e[k] = v
	end
	e.Parent = parent
	return e
end

local function neonPart(parent, size, color, shape)
	local p = Instance.new("Part")
	p:SetAttribute("FX", true)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local function inRig(inst)
	local cur = inst.Parent
	while cur and cur ~= workspace do
		if cur:IsA("Tool") or (cur:IsA("Model") and cur:FindFirstChildOfClass("Humanoid")) then
			return true
		end
		cur = cur.Parent
	end
	return false
end

-- ---------------------------------------------------------------- atmosphere
task.wait(1) -- let GameManager set its own Lighting values first

ensure("Atmosphere", "FXAtmosphere", {
	Density = 0.38, Offset = 0.1, Haze = 2.2, Glare = 0,
	Color = Color3.fromRGB(70, 80, 110), Decay = Color3.fromRGB(20, 20, 35),
})
ensure("BloomEffect", "FXBloom", { Intensity = 0.9, Size = 28, Threshold = 0.9 })
ensure("ColorCorrectionEffect", "FXColor", {
	Contrast = 0.15, Saturation = -0.1, Brightness = 0.02, TintColor = Color3.fromRGB(200, 215, 255),
})
ensure("SunRaysEffect", "FXRays", { Intensity = 0.08, Spread = 0.8 })
ensure("DepthOfFieldEffect", "FXDof", { FarIntensity = 0.25, NearIntensity = 0, FocusDistance = 60, InFocusRadius = 60 })
Lighting.GlobalShadows = true
Lighting.ShadowSoftness = 0.3
Lighting.EnvironmentDiffuseScale = 0.6
Lighting.EnvironmentSpecularScale = 0.8

-- ---------------------------------------------------------------- lobby
local function decorateLobby(folder)
	local floor = folder:FindFirstChild("LobbyFloor")
	local y = floor and floor.Position.Y or 500

	-- floating dust over the whole lobby
	local dust = Instance.new("Part")
	dust:SetAttribute("FX", true)
	dust.Anchored, dust.CanCollide, dust.CanQuery, dust.CanTouch = true, false, false, false
	dust.Transparency = 1
	dust.Size = Vector3.new(160, 40, 160)
	dust.Position = Vector3.new(0, y + 20, 0)
	dust.Parent = folder
	emitter(dust, {
		Shape = Enum.ParticleEmitterShape.Box, Rate = 25, Lifetime = NumberRange.new(6, 9),
		Speed = NumberRange.new(0.5, 1.5), Size = NumberSequence.new(0.3), LightEmission = 0.6,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.6), NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new(Color3.fromRGB(180, 200, 255)), SpreadAngle = Vector2.new(180, 180),
	})

	-- colour-cycling neon border around the floor
	if floor then
		local strips = {}
		for _, d in { { 0, -80, 160, 0.8 }, { 0, 80, 160, 0.8 }, { -80, 0, 0.8, 160 }, { 80, 0, 0.8, 160 } } do
			local s = neonPart(folder, Vector3.new(d[3], 0.3, d[4]), Color3.fromRGB(80, 120, 255))
			s.Position = Vector3.new(d[1], y + 1.1, d[2])
			table.insert(strips, s)
		end
		animate(function(t)
			if not floor.Parent then return false end
			for i, s in strips do
				s.Color = Color3.fromHSV((t * 0.06 + i * 0.08) % 1, 0.75, 1)
			end
			return true
		end)
	end

	-- title: red glow + orbiting neon cubes
	local title = folder:FindFirstChild("Title")
	if title then
		newLight("PointLight", title, { Color = Color3.fromRGB(255, 60, 60), Brightness = 3, Range = 40 })
		local cubes = {}
		for i = 1, 10 do
			cubes[i] = neonPart(folder, Vector3.one * 1.6, Color3.fromRGB(255, 70, 70))
		end
		local tilt = CFrame.fromEulerAnglesXYZ(0, 0, 0.35)
		animate(function(t)
			if not title.Parent then
				for _, c in cubes do c:Destroy() end
				return false
			end
			for i, c in cubes do
				local a = t * 0.9 + i * (math.pi * 2 / #cubes)
				c.CFrame = CFrame.new(title.Position + tilt:VectorToWorldSpace(Vector3.new(math.cos(a) * 16, 0, math.sin(a) * 16)))
					* CFrame.Angles(t, a, 0)
			end
			return true
		end)
	end

	-- party pads: light column, orbiting orbs, sparkles, breathing glow
	for _, obj in folder:GetChildren() do
		local idx = obj.Name:match("^Pad(%d+)$")
		if idx and obj:IsA("BasePart") then
			local phase = tonumber(idx) * 1.3
			local light = newLight("PointLight", obj, { Color = Color3.fromRGB(60, 255, 140), Brightness = 2, Range = 26 })
			emitter(obj, {
				Rate = 14, Lifetime = NumberRange.new(2, 3), Speed = NumberRange.new(3, 6),
				Size = NumberSequence.new(0.4, 0), LightEmission = 1, SpreadAngle = Vector2.new(10, 10),
				Color = ColorSequence.new(Color3.fromRGB(120, 255, 180)), EmissionDirection = Enum.NormalId.Top,
			})
			local column = neonPart(folder, Vector3.new(14, 18, 18), Color3.fromRGB(60, 255, 140), Enum.PartType.Cylinder)
			column.Transparency = 0.88
			column.CFrame = CFrame.new(obj.Position + Vector3.new(0, 7.5, 0)) * CFrame.Angles(0, 0, math.pi / 2)
			local orbs = {}
			for i = 1, 3 do
				orbs[i] = neonPart(folder, Vector3.one * 1.2, Color3.fromRGB(150, 255, 200), Enum.PartType.Ball)
			end
			animate(function(t)
				if not obj.Parent then
					column:Destroy()
					for _, o in orbs do o:Destroy() end
					return false
				end
				obj.Transparency = 0.3 + 0.12 * math.sin(t * 2 + phase)
				light.Brightness = 2 + math.sin(t * 2 + phase)
				for i, o in orbs do
					local a = t * 1.4 + i * (math.pi * 2 / 3) + phase
					o.Position = obj.Position + Vector3.new(math.cos(a) * 7, 3 + math.sin(t * 2 + i) * 1.2, math.sin(a) * 7)
				end
				return true
			end)
		end

		if obj.Name:match("^Start%d+$") and obj:IsA("BasePart") then
			local light = newLight("PointLight", obj, { Color = Color3.fromRGB(255, 150, 40), Brightness = 2, Range = 16 })
			emitter(obj, {
				Rate = 8, Lifetime = NumberRange.new(1, 1.5), Speed = NumberRange.new(2, 4),
				Size = NumberSequence.new(0.3, 0), LightEmission = 1, SpreadAngle = Vector2.new(15, 15),
				Color = ColorSequence.new(Color3.fromRGB(255, 190, 90)), EmissionDirection = Enum.NormalId.Top,
			})
			animate(function(t)
				if not obj.Parent then return false end
				light.Brightness = 2 + math.sin(t * 5)
				return true
			end)
		end
	end
end

task.spawn(function()
	local lobby = workspace:WaitForChild("Lobby", 15)
	if lobby then
		task.wait(0.5)
		decorateLobby(lobby)
	end
end)

-- ---------------------------------------------------------------- pickups & escape zone
local GOLD = Color3.fromRGB(255, 215, 70)
local ROLES = {
	{ match = "escape", color = Color3.fromRGB(80, 255, 140), big = true },
	{ match = "key", color = GOLD },
	{ match = "ammo", color = Color3.fromRGB(255, 200, 60) },
	{ match = "medkit", color = Color3.fromRGB(80, 255, 120) },
	{ match = "shotgun", color = Color3.fromRGB(255, 140, 40) },
	{ match = "rifle", color = Color3.fromRGB(80, 170, 255) },
}

local function hasDoneAncestor(inst)
	local cur = inst
	while cur and cur ~= workspace do
		if cur:GetAttribute("FXDone") then return true end
		cur = cur.Parent
	end
	return false
end

local function decoratePickup(inst, def)
	if not inst.Parent or inst:GetAttribute("FX") or hasDoneAncestor(inst) or inRig(inst) then return end
	local lobby = workspace:FindFirstChild("Lobby")
	if lobby and inst:IsDescendantOf(lobby) then return end
	local target = inst
	if inst:IsA("Model") then
		target = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
	end
	if not target or not target:IsA("BasePart") then return end
	inst:SetAttribute("FXDone", true)

	local color = def.color
	local height = def.big and 90 or 12
	local a0 = Instance.new("Attachment")
	a0:SetAttribute("FX", true)
	a0.Parent = target
	local a1 = Instance.new("Attachment")
	a1:SetAttribute("FX", true)
	a1.Parent = target
	a1.WorldPosition = target.Position + Vector3.new(0, height, 0)

	local beam = Instance.new("Beam")
	beam:SetAttribute("FX", true)
	beam.Attachment0, beam.Attachment1 = a0, a1
	beam.Color = ColorSequence.new(color)
	beam.Width0 = def.big and 14 or 1.4
	beam.Width1 = def.big and 3 or 0.2
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	beam.Parent = target

	local emitterProps = {
		Rate = def.big and 40 or 10, Lifetime = NumberRange.new(1.5, 2.5), Speed = NumberRange.new(2, 6),
		Size = NumberSequence.new(def.big and 1.2 or 0.35, 0), LightEmission = 1, SpreadAngle = Vector2.new(12, 12),
		Color = ColorSequence.new(color), EmissionDirection = Enum.NormalId.Top,
	}
	if def.big then
		emitterProps.Shape = Enum.ParticleEmitterShape.Box
		emitterProps.Speed = NumberRange.new(8, 16)
	end
	emitter(target, emitterProps)

	local light = newLight("PointLight", target, { Color = color, Brightness = 2, Range = def.big and 60 or 16 })
	local phase = math.random() * 6
	animate(function(t)
		if not target.Parent or not light.Parent then return false end
		light.Brightness = (def.big and 3 or 2) + math.sin(t * 3 + phase) * 1.2
		return true
	end)
end

-- ---------------------------------------------------------------- zombies & ambient light flicker
local flickers = {}

local function zombieFX(hum)
	local model = hum.Parent
	if not model or not model:IsA("Model") or Players:GetPlayerFromCharacter(model) then return end
	task.spawn(function()
		local head = model:WaitForChild("Head", 3)
		local root = model:WaitForChild("HumanoidRootPart", 3)
		if head then
			newLight("PointLight", head, { Color = Color3.fromRGB(255, 40, 40), Brightness = 1.5, Range = 9 })
		end
		if root then
			emitter(root, {
				Texture = SMOKE, Rate = 8, Lifetime = NumberRange.new(1, 1.5), Speed = NumberRange.new(1, 2),
				Size = NumberSequence.new(2, 4), LightEmission = 0,
				Transparency = NumberSequence.new(0.6, 1), Color = ColorSequence.new(Color3.fromRGB(60, 15, 15)),
				Acceleration = Vector3.new(0, 2, 0),
			})
		end
	end)
end

local function consider(inst)
	if inst:GetAttribute("FX") then return end
	if inst:IsA("Humanoid") then
		zombieFX(inst)
	elseif inst:IsA("PointLight") or inst:IsA("SpotLight") or inst:IsA("SurfaceLight") then
		if #flickers < 150 and not inRig(inst) then
			table.insert(flickers, inst)
		end
	elseif inst:IsA("BasePart") or inst:IsA("Model") then
		local lname = inst.Name:lower()
		for _, def in ROLES do
			if lname:find(def.match, 1, true) then
				task.delay(0.3, decoratePickup, inst, def)
				break
			end
		end
	end
end

workspace.DescendantAdded:Connect(consider)
task.spawn(function()
	for i, d in workspace:GetDescendants() do
		consider(d)
		if i % 2000 == 0 then task.wait() end
	end
end)

task.spawn(function()
	while true do
		task.wait(0.12)
		for i = #flickers, 1, -1 do
			local l = flickers[i]
			if not l.Parent then
				table.remove(flickers, i)
			elseif math.random() < 0.02 then
				l.Enabled = false
				task.delay(0.05 + math.random() * 0.12, function()
					if l.Parent then l.Enabled = true end
				end)
			end
		end
	end
end)
]=====])

put(SPS, "LocalScript", "Effects", [=====[
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local fxFolder = Instance.new("Folder")
fxFolder.Name = "FXLocal"
fxFolder.Parent = workspace

local function tween(inst, time, props, style)
	TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

-- ---------------------------------------------------------------- particle presets
local SPARK = {
	Texture = SPARKLE, Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 120, 30)),
	LightEmission = 1, Size = NumberSequence.new(0.35, 0), Transparency = NumberSequence.new(0, 1),
	Lifetime = NumberRange.new(0.15, 0.4), Speed = NumberRange.new(15, 35), SpreadAngle = Vector2.new(35, 35),
	Acceleration = Vector3.new(0, -60, 0), Drag = 2,
}
local BLOOD = {
	Texture = SMOKE, Color = ColorSequence.new(Color3.fromRGB(150, 10, 10), Color3.fromRGB(70, 0, 0)),
	LightEmission = 0, Size = NumberSequence.new(0.6, 0.15), Transparency = NumberSequence.new(0.1, 1),
	Lifetime = NumberRange.new(0.4, 0.9), Speed = NumberRange.new(10, 28), SpreadAngle = Vector2.new(50, 50),
	Acceleration = Vector3.new(0, -70, 0), Drag = 1,
}
local BLOOD_RADIAL = table.clone(BLOOD)
BLOOD_RADIAL.SpreadAngle = Vector2.new(180, 180)
BLOOD_RADIAL.Size = NumberSequence.new(1, 0.2)
local PUFF = {
	Texture = SMOKE, Color = ColorSequence.new(Color3.fromRGB(110, 110, 110)), LightEmission = 0,
	Size = NumberSequence.new(1, 4), Transparency = NumberSequence.new(0.5, 1), Lifetime = NumberRange.new(0.6, 1.2),
	Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(40, 40), Rotation = NumberRange.new(0, 360),
	RotSpeed = NumberRange.new(-60, 60),
}

-- Emits a one-off particle burst at pos, shooting along normal.
local function burst(pos, normal, props, count, life)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Transparency = 1
	p.Size = Vector3.one * 0.2
	local up = math.abs(normal.Y) > 0.99 and Vector3.xAxis or Vector3.yAxis
	p.CFrame = CFrame.lookAt(pos, pos + normal, up) * CFrame.Angles(-math.pi / 2, 0, 0)
	p.Parent = fxFolder
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.Rate = 0
	for k, v in props do
		e[k] = v
	end
	e.Parent = p
	e:Emit(count)
	Debris:AddItem(p, life or 1.2)
end

-- ---------------------------------------------------------------- camera shake / recoil
local shake, kick = 0, 0

local function addShake(amount, recoil)
	shake = math.min(shake + amount, 3)
	kick = math.min(kick + (recoil or 0), 4)
end

RunService:BindToRenderStep("FXCameraShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if shake > 0.005 or kick > 0.005 then
		local rx = (math.random() - 0.5) * shake * 0.02 + kick * 0.012
		local ry = (math.random() - 0.5) * shake * 0.02
		local rz = (math.random() - 0.5) * shake * 0.01
		camera.CFrame = camera.CFrame * CFrame.Angles(rx, ry, rz)
	end
	shake *= math.exp(-dt * 9)
	kick *= math.exp(-dt * 14)
end)

-- ---------------------------------------------------------------- GUI layer
local gui = Instance.new("ScreenGui")
gui.Name = "FXGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 10
gui.Parent = player:WaitForChild("PlayerGui")

-- red edge vignette (fades with GroupTransparency)
local vignette = Instance.new("CanvasGroup")
vignette.Size = UDim2.fromScale(1, 1)
vignette.BackgroundTransparency = 1
vignette.GroupTransparency = 1
vignette.Parent = gui
for _, d in {
	{ UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.3), 90 },
	{ UDim2.fromScale(0, 0.7), UDim2.fromScale(1, 0.3), 270 },
	{ UDim2.fromScale(0, 0), UDim2.fromScale(0.25, 1), 0 },
	{ UDim2.fromScale(0.75, 0), UDim2.fromScale(0.25, 1), 180 },
} do
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.fromRGB(190, 0, 0)
	f.Position, f.Size = d[1], d[2]
	local g = Instance.new("UIGradient")
	g.Rotation = d[3]
	g.Transparency = NumberSequence.new(0, 1)
	g.Parent = f
	f.Parent = vignette
end

local function flash(color, startTransparency, duration)
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.BackgroundTransparency = startTransparency
	f.Parent = gui
	tween(f, duration, { BackgroundTransparency = 1 })
	Debris:AddItem(f, duration + 0.1)
end

local function popup(text, color)
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromScale(0.5, 0.35)
	l.Size = UDim2.fromOffset(500, 60)
	l.BackgroundTransparency = 1
	l.Text = text
	l.Font = Enum.Font.GothamBlack
	l.TextSize = 40
	l.TextColor3 = color
	l.TextStrokeTransparency = 0
	l.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0.5
	scale.Parent = l
	tween(scale, 0.25, { Scale = 1.1 }, Enum.EasingStyle.Back)
	task.delay(0.9, function()
		tween(l, 0.6, { Position = UDim2.fromScale(0.5, 0.28), TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
	Debris:AddItem(l, 1.7)
end

local function hitMarker()
	local loc = UserInputService:GetMouseLocation()
	local g = Instance.new("CanvasGroup")
	g.AnchorPoint = Vector2.new(0.5, 0.5)
	g.Position = UDim2.fromOffset(loc.X, loc.Y)
	g.Size = UDim2.fromOffset(28, 28)
	g.BackgroundTransparency = 1
	g.Parent = gui
	for _, rot in { 45, -45 } do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromOffset(3, 22)
		bar.Rotation = rot
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
		bar.Parent = g
	end
	tween(g, 0.25, { GroupTransparency = 1, Size = UDim2.fromOffset(40, 40) })
	Debris:AddItem(g, 0.3)
end

-- ---------------------------------------------------------------- weapon effects
local function enemyOf(inst)
	local m = inst:FindFirstAncestorOfClass("Model")
	if m and m:FindFirstChildOfClass("Humanoid") and not Players:GetPlayerFromCharacter(m) then
		return m
	end
	return nil
end

local function muzzleFlash(pos, dir)
	local f = Instance.new("Part")
	f.Anchored, f.CanCollide, f.CanQuery, f.CanTouch, f.CastShadow = true, false, false, false, false
	f.Shape = Enum.PartType.Ball
	f.Material = Enum.Material.Neon
	f.Color = Color3.fromRGB(255, 200, 90)
	f.Size = Vector3.one * 0.5
	f.Position = pos
	f.Parent = fxFolder
	local l = Instance.new("PointLight")
	l.Color = Color3.fromRGB(255, 180, 80)
	l.Brightness = 6
	l.Range = 16
	l.Parent = f
	tween(f, 0.07, { Size = Vector3.one * 1.6, Transparency = 1 })
	tween(l, 0.09, { Brightness = 0 })
	Debris:AddItem(f, 0.2)
	burst(pos, dir, SPARK, 6, 0.6)
end

local function tracer(a, b)
	local dist = (b - a).Magnitude
	if dist < 1 then return end
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 225, 140)
	p.Size = Vector3.new(0.12, 0.12, dist)
	p.CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -dist / 2)
	p.Parent = fxFolder
	tween(p, 0.14, { Transparency = 1, Size = Vector3.new(0.02, 0.02, dist) })
	Debris:AddItem(p, 0.2)
end

local function impact(pos, normal, isEnemy)
	if isEnemy then
		burst(pos, normal, BLOOD, 12, 1.2)
	else
		burst(pos, normal, SPARK, 10, 0.8)
		burst(pos, normal, PUFF, 2, 1.5)
	end
end

local function ejectShell(handle)
	local s = Instance.new("Part")
	s.Size = Vector3.new(0.12, 0.12, 0.3)
	s.Material = Enum.Material.Metal
	s.Color = Color3.fromRGB(215, 170, 60)
	s.CanCollide, s.CanTouch, s.CanQuery = false, false, false
	s.CFrame = handle.CFrame
	s.Parent = fxFolder
	s.AssemblyLinearVelocity = camera.CFrame.RightVector * (6 + math.random() * 3) + Vector3.new(math.random() * 2, 6 + math.random() * 3, 0)
	s.AssemblyAngularVelocity = Vector3.new(math.random() * 30, math.random() * 30, math.random() * 30)
	task.delay(0.15, function()
		if s.Parent then s.CanCollide = true end
	end)
	Debris:AddItem(s, 2)
end

local function doShot(tool)
	local cfg = Config.Weapons[tool.Name]
	local handle = tool:FindFirstChild("Handle")
	local char = player.Character
	if not cfg or not handle or not char then return end
	for _, key in { "Ammo", "Mag", "Magazine" } do
		local v = tool:GetAttribute(key)
		if type(v) == "number" and v <= 0 then return end
	end
	if tool:GetAttribute("Reloading") == true then return end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char, fxFolder }
	params.RespectCanCollide = true

	local loc = UserInputService:GetMouseLocation()
	local mray = camera:ViewportPointToRay(loc.X, loc.Y)
	local aimHit = workspace:Raycast(mray.Origin, mray.Direction * 1000, params)
	local target = aimHit and aimHit.Position or (mray.Origin + mray.Direction * 1000)

	local toTarget = target - handle.Position
	if toTarget.Magnitude < 0.5 then return end
	local muzzle = handle.Position + toTarget.Unit * (handle.Size.Z * 0.5)
	local baseDir = (target - muzzle).Unit

	muzzleFlash(muzzle, baseDir)
	ejectShell(handle)

	local hitEnemy = false
	local spread = cfg.Spread or 0
	for _ = 1, cfg.Pellets or 1 do
		local dir = baseDir
		if spread > 0 then
			local cf = CFrame.lookAt(Vector3.zero, baseDir) * CFrame.Angles((math.random() - 0.5) * 2 * spread, (math.random() - 0.5) * 2 * spread, 0)
			dir = cf.LookVector
		end
		local res = workspace:Raycast(muzzle, dir * cfg.Range, params)
		tracer(muzzle, res and res.Position or (muzzle + dir * cfg.Range))
		if res then
			local enemy = enemyOf(res.Instance) ~= nil
			impact(res.Position, res.Normal, enemy)
			hitEnemy = hitEnemy or enemy
		end
	end
	if hitEnemy then hitMarker() end

	if (cfg.Pellets or 1) > 1 then
		addShake(1.2, 2.2)
	elseif cfg.Auto then
		addShake(0.4, 0.5)
	else
		addShake(0.7, 1.1)
	end
end

local hooked = setmetatable({}, { __mode = "k" })

local function hookTool(tool)
	if hooked[tool] or not Config.Weapons[tool.Name] then return end
	hooked[tool] = true
	local held = false
	tool.Activated:Connect(function()
		held = true
		local cfg = Config.Weapons[tool.Name]
		doShot(tool)
		if cfg.Auto then
			task.spawn(function()
				while held and tool.Parent == player.Character do
					task.wait(cfg.FireRate)
					if held and tool.Parent == player.Character then
						doShot(tool)
					end
				end
			end)
		end
	end)
	tool.Deactivated:Connect(function() held = false end)
	tool.Unequipped:Connect(function() held = false end)
end

local function watch(container)
	for _, c in container:GetChildren() do
		if c:IsA("Tool") then hookTool(c) end
	end
	container.ChildAdded:Connect(function(c)
		if c:IsA("Tool") then hookTool(c) end
	end)
end

local backpack = player:FindFirstChildOfClass("Backpack")
if backpack then watch(backpack) end
player.ChildAdded:Connect(function(c)
	if c:IsA("Backpack") then watch(c) end
end)

-- ---------------------------------------------------------------- zombie hit / death reactions
local function highlightFlash(model, color, duration)
	local h = Instance.new("Highlight")
	h.FillColor = color
	h.OutlineColor = color
	h.FillTransparency = 0.3
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = model
	tween(h, duration, { FillTransparency = 1, OutlineTransparency = 1 })
	Debris:AddItem(h, duration + 0.1)
end

local trackedHumanoids = setmetatable({}, { __mode = "k" })

local function trackHumanoid(hum)
	local model = hum.Parent
	if trackedHumanoids[hum] or not model or not model:IsA("Model") or Players:GetPlayerFromCharacter(model) then return end
	trackedHumanoids[hum] = true
	local last = hum.Health
	hum.HealthChanged:Connect(function(h)
		if h < last and h > 0 then
			highlightFlash(model, Color3.fromRGB(255, 40, 40), 0.18)
		end
		last = h
	end)
	hum.Died:Connect(function()
		local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
		if root then
			burst(root.Position, Vector3.yAxis, BLOOD_RADIAL, 40, 1.4)
			burst(root.Position, Vector3.yAxis, PUFF, 6, 1.6)
		end
		highlightFlash(model, Color3.fromRGB(255, 0, 0), 0.5)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				tween(d, 0.9, { Transparency = 1 })
			end
		end
	end)
end

workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Humanoid") then trackHumanoid(d) end
end)
task.spawn(function()
	for i, d in workspace:GetDescendants() do
		if d:IsA("Humanoid") then trackHumanoid(d) end
		if i % 2000 == 0 then task.wait() end
	end
end)

-- ---------------------------------------------------------------- own health: damage flash, heal flash, low-health look
local healthFrac, flashAmt, lowAmt = 1, 0, 0

local lowCC = Instance.new("ColorCorrectionEffect")
lowCC.Name = "FXLowHealth"
lowCC.Parent = Lighting

local function onCharacter(char)
	local hum = char:WaitForChild("Humanoid")
	local last = hum.Health
	healthFrac = hum.Health / math.max(hum.MaxHealth, 1)
	hum.HealthChanged:Connect(function(h)
		healthFrac = h / math.max(hum.MaxHealth, 1)
		if h < last then
			flashAmt = math.max(flashAmt, math.clamp(0.4 + (last - h) / 30, 0, 1))
			addShake(1.6, 0)
		elseif h > last + 9 then
			flash(Color3.fromRGB(80, 255, 120), 0.7, 0.6)
		end
		last = h
	end)
end

if player.Character then task.spawn(onCharacter, player.Character) end
player.CharacterAdded:Connect(onCharacter)

RunService.RenderStepped:Connect(function(dt)
	flashAmt *= math.exp(-dt * 3)
	local target = healthFrac < 0.35 and (0.35 - healthFrac) / 0.35 or 0
	lowAmt += (target - lowAmt) * math.min(1, dt * 4)
	local pulse = lowAmt * (0.55 + 0.25 * math.sin(os.clock() * 6))
	local intensity = math.clamp(math.max(flashAmt, pulse), 0, 1)
	vignette.GroupTransparency = 1 - intensity * 0.85
	lowCC.Saturation = -0.7 * lowAmt
	lowCC.TintColor = Color3.new(1, 1 - 0.35 * lowAmt, 1 - 0.35 * lowAmt)
end)

-- ---------------------------------------------------------------- pickup / escape feedback
local lastKeys = player:GetAttribute("Keys") or 0
player:GetAttributeChangedSignal("Keys"):Connect(function()
	local k = player:GetAttribute("Keys") or 0
	if k > lastKeys then
		flash(Color3.fromRGB(255, 215, 70), 0.6, 0.7)
		popup(("KEYCARD  %d / %d"):format(k, Config.KeysNeeded), Color3.fromRGB(255, 215, 70))
	end
	lastKeys = k
end)

local lastReserve = player:GetAttribute("Reserve")
player:GetAttributeChangedSignal("Reserve"):Connect(function()
	local r = player:GetAttribute("Reserve") or 0
	if lastReserve and r > lastReserve and r - lastReserve <= Config.AmmoPickup then
		flash(Color3.fromRGB(255, 200, 60), 0.85, 0.4)
		popup("+AMMO", Color3.fromRGB(255, 200, 60))
	end
	lastReserve = r
end)

task.spawn(function()
	local stats = player:WaitForChild("leaderstats", 30)
	local escapes = stats and stats:WaitForChild("Escapes", 30)
	if not escapes then return end
	local last = escapes.Value
	escapes.Changed:Connect(function(v)
		if v > last then
			flash(Color3.fromRGB(220, 255, 230), 0.1, 1.5)
			popup("YOU ESCAPED!", Color3.fromRGB(80, 255, 140))
		end
		last = v
	end)
end)

-- ---------------------------------------------------------------- drifting dust around the camera
local dust = Instance.new("Part")
dust.Anchored, dust.CanCollide, dust.CanQuery, dust.CanTouch = true, false, false, false
dust.Transparency = 1
dust.Size = Vector3.new(80, 40, 80)
dust.Parent = fxFolder
local dustEmitter = Instance.new("ParticleEmitter")
dustEmitter.Texture = SPARKLE
dustEmitter.Shape = Enum.ParticleEmitterShape.Box
dustEmitter.Rate = 30
dustEmitter.Lifetime = NumberRange.new(6, 9)
dustEmitter.Speed = NumberRange.new(0.5, 1.5)
dustEmitter.Size = NumberSequence.new(0.15, 0.25)
dustEmitter.LightEmission = 0.3
dustEmitter.SpreadAngle = Vector2.new(180, 180)
dustEmitter.Acceleration = Vector3.new(0.5, 0.2, 0.3)
dustEmitter.Color = ColorSequence.new(Color3.fromRGB(190, 200, 220))
dustEmitter.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.6), NumberSequenceKeypoint.new(1, 1),
})
dustEmitter.Parent = dust

RunService.RenderStepped:Connect(function()
	dust.Position = camera.CFrame.Position
end)
]=====])

print("Zombie Escape effects installed. Press Play to see them.")

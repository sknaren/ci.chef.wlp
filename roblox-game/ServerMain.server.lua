-- ServerMain  (Script in ServerScriptService)
-- Dead Hours: lobby with 4 doors (1-5 players each), one independent arena per door,
-- houses with roofs, doors + cupboards (E), loot in ~55% of houses, a bike (E),
-- day = 2 min / night = 3 min, zombies attracted by noise (much more at night).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

Players.CharacterAutoLoads = false

-------------------------------------------------------------------- config
local DAY, NIGHT = 120, 180
local CYCLE = DAY + NIGHT
local HALF = 200 -- arena half-size (studs)
local LOBBY = Vector3.new(0, 500, 0)

-- Paste Roblox audio asset ids here (Creator Store > Audio), e.g. "rbxassetid://123456".
-- Empty string = that sound is skipped.
local SOUND = { Gun = "", Door = "", DoorBreak = "", Cupboard = "", Pickup = "", Groan = "", Engine = "", Hurt = "", Bat = "" }

-------------------------------------------------------------------- helpers
local function remote(name)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = RS
	return r
end
local R_Msg, R_Status, R_Fire, R_Heal = remote("Msg"), remote("Status"), remote("Fire"), remote("Heal")

local function lerp(a, b, t) return a + (b - a) * t end
local function darkness(t)
	if t < 10 then return 1 - t / 10 end
	if t < DAY - 10 then return 0 end
	if t < DAY + 10 then return (t - (DAY - 10)) / 20 end
	return 1
end

local function mk(parent, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then for k, v in props do p[k] = v end end
	p.Parent = parent
	return p
end

local function playSound(id, parent, vol, speed, maxDist)
	if id == "" then return end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = vol or 1
	s.PlaybackSpeed = speed or 1
	s.RollOffMaxDistance = maxDist or 150
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 6)
end

local function msg(plr, text, color)
	R_Msg:FireClient(plr, text, color or "#ffffff")
end

local function hingeDoor(part, hingeCF, angle)
	local rel = hingeCF:ToObjectSpace(part.CFrame)
	return { closed = part.CFrame, open = hingeCF * CFrame.Angles(0, angle, 0) * rel }
end

-------------------------------------------------------------------- lobby
local lobby = Instance.new("Folder")
lobby.Name = "Lobby"
lobby.Parent = workspace
mk(lobby, Vector3.new(120, 2, 110), CFrame.new(LOBBY - Vector3.new(0, 1, 30)), Color3.fromRGB(50, 52, 60), Enum.Material.Concrete)
local spawnLoc = Instance.new("SpawnLocation")
spawnLoc.Anchored = true
spawnLoc.Size = Vector3.new(10, 1, 10)
spawnLoc.Position = LOBBY + Vector3.new(0, 0.6, 20)
spawnLoc.Neutral = true
spawnLoc.Transparency = 0.6
spawnLoc.Parent = lobby
mk(lobby, Vector3.new(120, 30, 2), CFrame.new(LOBBY + Vector3.new(0, 15, 25)), Color3.fromRGB(70, 74, 86), nil, { Transparency = 0.6 })
mk(lobby, Vector3.new(2, 30, 110), CFrame.new(LOBBY + Vector3.new(-60, 15, -30)), Color3.fromRGB(70, 74, 86), nil, { Transparency = 0.6 })
mk(lobby, Vector3.new(2, 30, 110), CFrame.new(LOBBY + Vector3.new(60, 15, -30)), Color3.fromRGB(70, 74, 86), nil, { Transparency = 0.6 })

local DOOR_COLORS = { Color3.fromRGB(224, 90, 71), Color3.fromRGB(74, 168, 232), Color3.fromRGB(87, 194, 107), Color3.fromRGB(232, 177, 58) }
local doors = {}

local function billboard(adornee, text, size, offset)
	local g = Instance.new("BillboardGui")
	g.Size = size
	g.StudsOffset = offset or Vector3.new(0, 0, 0)
	g.AlwaysOnTop = true
	g.Adornee = adornee
	g.Parent = adornee
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 0.35
	l.BackgroundColor3 = Color3.new(0, 0, 0)
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextScaled = true
	l.Font = Enum.Font.GothamBold
	l.Text = text
	l.Parent = g
	return l
end

local function refreshDoor(d)
	local n = #d.players
	if d.arena then
		d.label.Text = ("DOOR %d  -  GAME IN PROGRESS"):format(d.id)
	elseif n == 0 then
		d.label.Text = ("DOOR %d  0/5  (E to enter)"):format(d.id)
	else
		d.label.Text = ("DOOR %d  %d/5  starts in %ds"):format(d.id, n, d.countdown or 0)
	end
end

local function leaveDoor(plr)
	for _, d in doors do
		local i = table.find(d.players, plr)
		if i then
			table.remove(d.players, i)
			d.countdown = nil
			refreshDoor(d)
		end
	end
	plr:SetAttribute("Door", nil)
end

for i = 1, 4 do
	local x = (i - 2.5) * 26
	local col = DOOR_COLORS[i]
	local frame = mk(lobby, Vector3.new(16, 14, 2), CFrame.new(LOBBY + Vector3.new(x, 7, -70)), col, Enum.Material.Neon)
	local pad = mk(lobby, Vector3.new(16, 0.4, 10), CFrame.new(LOBBY + Vector3.new(x, 0.2, -63)), col, Enum.Material.Neon, { Transparency = 0.5 })
	local d = { id = i, players = {}, x = x }
	d.label = billboard(frame, "", UDim2.fromOffset(300, 60), Vector3.new(0, 9, 0))
	-- waiting room behind the door
	local room = CFrame.new(LOBBY + Vector3.new(x, 0, -95))
	mk(lobby, Vector3.new(20, 1, 20), room * CFrame.new(0, -0.5, 0), col, Enum.Material.Slate)
	d.roomCF = room * CFrame.new(0, 4, 0)
	d.exitCF = CFrame.new(LOBBY + Vector3.new(x, 4, -55))
	local enter = Instance.new("ProximityPrompt")
	enter.ActionText = "Enter Door " .. i
	enter.ObjectText = "Squad of 1-5"
	enter.KeyboardKeyCode = Enum.KeyCode.E
	enter.MaxActivationDistance = 14
	enter.RequiresLineOfSight = false
	enter.Parent = pad
	local leave = Instance.new("ProximityPrompt")
	leave.ActionText = "Leave Door " .. i
	leave.KeyboardKeyCode = Enum.KeyCode.E
	leave.MaxActivationDistance = 40
	leave.RequiresLineOfSight = false
	local leavePart = mk(lobby, Vector3.new(4, 1, 4), room * CFrame.new(0, 0.5, 6), Color3.new(1, 1, 1), Enum.Material.Neon, { Transparency = 0.7 })
	leave.Parent = leavePart
	enter.Triggered:Connect(function(plr)
		if d.arena then return msg(plr, "A game is already running at this door", "#ff9a5a") end
		if #d.players >= 5 then return msg(plr, "Door is full (5/5)", "#ff7766") end
		if plr:GetAttribute("Door") then return end
		local char = plr.Character
		if not char then return end
		table.insert(d.players, plr)
		plr:SetAttribute("Door", i)
		d.countdown = 20 -- restarts whenever somebody joins
		char:PivotTo(d.roomCF * CFrame.new(math.random(-6, 6), 0, math.random(-6, 6)))
		refreshDoor(d)
	end)
	leave.Triggered:Connect(function(plr)
		if plr:GetAttribute("Door") ~= i then return end
		leaveDoor(plr)
		if plr.Character then plr.Character:PivotTo(d.exitCF) end
	end)
	doors[i] = d
	refreshDoor(d)
end

-------------------------------------------------------------------- arenas
local arenas = {}
local ZOMBIE_VISION_DAY, ZOMBIE_VISION_NIGHT = 70, 32

local function arenaPlayers(a)
	local list = {}
	for _, p in a.players do
		local c = p.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		if h and h.Health > 0 and c:FindFirstChild("HumanoidRootPart") then table.insert(list, p) end
	end
	return list
end

-- noise: zombies within radius * hearing (0.45 by day .. 1.3 at night) go to the sound
local function noise(a, pos, radius)
	local hear = lerp(0.45, 1.3, darkness(a.time))
	for _, z in a.zombies do
		if z.hum.Health > 0 and z.state ~= "chase" then
			if (z.hrp.Position - pos).Magnitude < radius * hear then
				z.state = "investigate"
				z.goal = pos + Vector3.new(math.random(-6, 6), 0, math.random(-6, 6))
			end
		end
	end
end

local function houseAt(a, p)
	for _, h in a.houses do
		local l = h.cf:PointToObjectSpace(p)
		if math.abs(l.X) < 8 and math.abs(l.Z) < 7 then return h end
	end
end

local function steerPoint(a, from, to)
	local ht, hf = houseAt(a, to), houseAt(a, from)
	if ht and ht ~= hf then
		if (from - ht.doorOut).Magnitude < 5 then return ht.doorIn end
		return ht.doorOut
	end
	if hf and hf ~= ht then
		if (from - hf.doorIn).Magnitude < 5 then return hf.doorOut end
		return hf.doorIn
	end
	return to
end

-------------------------------------------------------------------- house + cupboards
local LOOT = {
	{ id = "Ammo", amount = 12, w = 42, color = Color3.fromRGB(227, 179, 65), text = "+12 Ammo" },
	{ id = "Ammo", amount = 24, w = 10, color = Color3.fromRGB(227, 179, 65), text = "+24 Ammo" },
	{ id = "Medkits", amount = 1, w = 20, color = Color3.fromRGB(230, 40, 40), text = "Medkit" },
	{ id = "Food", amount = 1, w = 25, color = Color3.fromRGB(150, 215, 120), text = "Canned food" },
}
local function rollLoot()
	local total = 0
	for _, l in LOOT do total += l.w end
	local r = math.random() * total
	for _, l in LOOT do
		r -= l.w
		if r <= 0 then return l end
	end
	return LOOT[1]
end

local function buildCupboard(a, cf, w, h, d, name, loot)
	local wood = Color3.fromRGB(122, 82, 50)
	local body = mk(a.folder, Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), wood, Enum.Material.Wood)
	mk(a.folder, Vector3.new(w - 0.6, h - 0.6, 0.2), cf * CFrame.new(0, h / 2, d / 2 + 0.05), Color3.fromRGB(35, 22, 12), Enum.Material.Wood)
	local fz = d / 2 + 0.25
	local dl = mk(a.folder, Vector3.new(w / 2, h - 0.4, 0.3), cf * CFrame.new(-w / 4, h / 2, fz), Color3.fromRGB(160, 110, 66), Enum.Material.Wood)
	local dr = mk(a.folder, Vector3.new(w / 2, h - 0.4, 0.3), cf * CFrame.new(w / 4, h / 2, fz), Color3.fromRGB(160, 110, 66), Enum.Material.Wood)
	local left = hingeDoor(dl, cf * CFrame.new(-w / 2, h / 2, fz), math.rad(-100))
	local right = hingeDoor(dr, cf * CFrame.new(w / 2, h / 2, fz), math.rad(100))
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 9
	prompt.Parent = body
	local state = { open = false, looted = false, busy = false }
	local info = TweenInfo.new(0.55, Enum.EasingStyle.Quad)
	prompt.Triggered:Connect(function(plr)
		if state.busy then return end
		state.busy = true
		if not state.open then
			playSound(SOUND.Cupboard, body, 0.8)
			TweenService:Create(dl, info, { CFrame = left.open }):Play()
			TweenService:Create(dr, info, { CFrame = right.open }):Play()
			noise(a, body.Position, 20)
			task.wait(0.6)
			state.open = true
			prompt.ActionText = "Close"
			if not state.looted then
				state.looted = true
				if #loot == 0 then
					msg(plr, "Empty...", "#aaaaaa")
				else
					for idx, item in loot do
						task.delay((idx - 1) * 0.3, function()
							local orb = mk(a.folder, Vector3.new(0.8, 0.8, 0.8), CFrame.new(body.Position + Vector3.new(0, h / 2, d)), item.color, Enum.Material.Neon, { CanCollide = false })
							TweenService:Create(orb, TweenInfo.new(0.9), { CFrame = orb.CFrame + Vector3.new(0, 4, 0), Transparency = 1 }):Play()
							Debris:AddItem(orb, 1)
							task.wait(0.6)
							playSound(SOUND.Pickup, body, 0.7)
							plr:SetAttribute(item.id, (plr:GetAttribute(item.id) or 0) + item.amount)
							msg(plr, item.text, "#" .. item.color:ToHex())
						end)
					end
				end
			end
		else
			playSound(SOUND.Cupboard, body, 0.8, 0.8)
			TweenService:Create(dl, info, { CFrame = left.closed }):Play()
			TweenService:Create(dr, info, { CFrame = right.closed }):Play()
			task.wait(0.6)
			state.open = false
			prompt.ActionText = "Open"
		end
		state.busy = false
	end)
end

local function buildHouse(a, cf, hasLoot)
	local W, D, H, T = 16, 14, 10, 1
	local wall = Color3.fromRGB(201, 183, 156)
	local function L(x, y, z) return cf * CFrame.new(x, y, z) end
	local function solid(size, c, color, mat)
		return mk(a.solid, size, c, color or wall, mat or Enum.Material.Brick)
	end
	mk(a.folder, Vector3.new(W, 1, D), L(0, 0.5, 0), Color3.fromRGB(107, 74, 43), Enum.Material.WoodPlanks)
	solid(Vector3.new(W, H, T), L(0, 1 + H / 2, -D / 2 + T / 2))
	solid(Vector3.new(T, H, D), L(-W / 2 + T / 2, 1 + H / 2, 0))
	solid(Vector3.new(T, H, D), L(W / 2 - T / 2, 1 + H / 2, 0))
	solid(Vector3.new(9.5, H, T), L(-3.25, 1 + H / 2, D / 2 - T / 2))
	solid(Vector3.new(1.5, H, T), L(7.25, 1 + H / 2, D / 2 - T / 2))
	solid(Vector3.new(5, H - 8, T), L(4, 1 + 8 + (H - 8) / 2, D / 2 - T / 2))
	mk(a.solid, Vector3.new(W, 0.5, D), L(0, H + 0.75, 0), Color3.fromRGB(232, 226, 210), Enum.Material.SmoothPlastic) -- ceiling
	-- gabled roof (two slabs)
	local rise, half = 5, D / 2 + 1.5
	local len = math.sqrt(half * half + rise * rise) + 0.4
	local ang = math.atan2(rise, half)
	local roofColor = Color3.fromRGB(138, 59, 42)
	mk(a.solid, Vector3.new(W + 3, 0.6, len), L(0, 1 + H + rise / 2, -half / 2) * CFrame.Angles(-ang, 0, 0), roofColor, Enum.Material.Slate)
	mk(a.solid, Vector3.new(W + 3, 0.6, len), L(0, 1 + H + rise / 2, half / 2) * CFrame.Angles(ang, 0, 0), roofColor, Enum.Material.Slate)
	-- windows
	local glass = Color3.fromRGB(120, 170, 220)
	for _, w in { { -4, D / 2 - T / 2, 5, 3, T + 0.2 }, { 0, -D / 2 + T / 2, 5, 3, T + 0.2 } } do
		mk(a.folder, Vector3.new(w[3], w[4], w[5]), L(w[1], 6, w[2]), glass, Enum.Material.Glass, { Transparency = 0.5 })
	end
	for _, sx in { -1, 1 } do
		mk(a.folder, Vector3.new(T + 0.2, 3, 5), L(sx * (W / 2 - T / 2), 6, 0), glass, Enum.Material.Glass, { Transparency = 0.5 })
	end
	-- lamp
	local lamp = mk(a.folder, Vector3.new(1, 1, 1), L(0, H - 0.2, 0), Color3.fromRGB(255, 230, 170), Enum.Material.Neon, { CanCollide = false })
	local pl = Instance.new("PointLight")
	pl.Range = 26
	pl.Brightness = 1.2
	pl.Parent = lamp
	-- furniture
	mk(a.folder, Vector3.new(4, 1.5, 7), L(-5.5, 1.75, 1.5), Color3.fromRGB(184, 196, 216), Enum.Material.Fabric)
	mk(a.folder, Vector3.new(5, 0.5, 3), L(3, 3, 1), Color3.fromRGB(110, 75, 40), Enum.Material.Wood)
	for _, o in { { -1.2, -0.6 }, { 1.2, -0.6 }, { -1.2, 0.6 }, { 1.2, 0.6 } } do
		mk(a.folder, Vector3.new(0.4, 2, 0.4), L(3 + o[1], 2, 1 + o[2]), Color3.fromRGB(110, 75, 40), Enum.Material.Wood)
	end
	-- cupboards (front faces +Z)
	local bz = -D / 2 + T + 1
	local l1, l2 = {}, {}
	if hasLoot then
		if math.random() < 0.8 then for _ = 1, math.random(1, 3) do table.insert(l1, rollLoot()) end end
		if math.random() < 0.8 then for _ = 1, math.random(1, 3) do table.insert(l2, rollLoot()) end end
	end
	buildCupboard(a, L(-4.5, 1, bz), 5, 7, 2, "Wardrobe", l1)
	buildCupboard(a, L(4.5, 1, bz), 5, 4, 2, "Kitchen cabinet", l2)
	-- front door (ProximityPrompt, E)
	local doorPart = mk(a.folder, Vector3.new(5, 8, 0.6), L(4, 1 + 4, D / 2 - 0.3), Color3.fromRGB(90, 58, 30), Enum.Material.Wood)
	local hinge = hingeDoor(doorPart, L(1.5, 1, D / 2 - 0.3), math.rad(95))
	local door = { part = doorPart, hinge = hinge, open = false, hp = 100, broken = false }
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open door"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 10
	prompt.Parent = doorPart
	local function setDoor(open)
		door.open = open
		playSound(open and SOUND.Door or SOUND.Door, doorPart, 0.8, open and 1 or 0.85)
		TweenService:Create(doorPart, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { CFrame = open and hinge.open or hinge.closed }):Play()
		task.delay(open and 0.5 or 0, function() doorPart.CanCollide = not open end)
		prompt.ActionText = open and "Close door" or "Open door"
	end
	door.set = setDoor
	prompt.Triggered:Connect(function(plr)
		if door.broken then return end
		setDoor(not door.open)
		noise(a, doorPart.Position, 25)
	end)
	table.insert(a.doors, door)
	table.insert(a.houses, { cf = cf, door = door, doorOut = (cf * CFrame.new(4, 3, D / 2 + 5)).Position, doorIn = (cf * CFrame.new(4, 3, D / 2 - 5)).Position })
end

-------------------------------------------------------------------- bike
local function buildBike(a, cf)
	local m = Instance.new("Model")
	m.Name = "Bike"
	local seat = Instance.new("VehicleSeat")
	seat.Anchored = true
	seat.Size = Vector3.new(1.4, 1, 4)
	seat.CFrame = cf * CFrame.new(0, 2.2, 0)
	seat.Color = Color3.fromRGB(176, 24, 24)
	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.Parent = m
	local function part(size, off, color, shape)
		local p = mk(m, size, cf * off, color, Enum.Material.Metal, { CanCollide = false })
		if shape then p.Shape = shape end
		return p
	end
	for _, z in { -1.8, 1.8 } do
		part(Vector3.new(0.7, 2.6, 2.6), CFrame.new(0, 1.3, z), Color3.fromRGB(20, 20, 20), Enum.PartType.Cylinder)
	end
	part(Vector3.new(0.5, 0.5, 3), CFrame.new(0, 2.0, 0), Color3.fromRGB(80, 80, 90))
	part(Vector3.new(2.6, 0.4, 0.4), CFrame.new(0, 3.4, -1.7), Color3.fromRGB(30, 30, 30))
	part(Vector3.new(1, 0.8, 1.6), CFrame.new(0, 2.8, -0.7), Color3.fromRGB(176, 24, 24))
	local engine = Instance.new("Sound")
	engine.SoundId = SOUND.Engine
	engine.Looped = true
	engine.Volume = 0.6
	engine.RollOffMaxDistance = 220
	engine.Parent = seat
	m.PrimaryPart = seat
	m.Parent = a.folder
	local bike = { seat = seat, speed = 0, yaw = select(2, cf:ToEulerAnglesYXZ()), pos = seat.Position, engine = engine, noiseT = 0, model = m }
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Ride bike"
	prompt.ObjectText = "Motorbike"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 12
	prompt.Parent = seat
	prompt.Triggered:Connect(function(plr)
		local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
		if hum and not seat.Occupant then seat:Sit(hum) end
	end)
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		prompt.Enabled = seat.Occupant == nil
		if SOUND.Engine ~= "" then
			if seat.Occupant then engine:Play() else engine:Stop() end
		end
	end)
	return bike
end

local function updateBike(a, bike, dt)
	local seat = bike.seat
	local occ = seat.Occupant
	local th, st = 0, 0
	if occ then th, st = seat.ThrottleFloat, seat.SteerFloat end
	if th > 0 then bike.speed += (bike.speed < 0 and 60 or 32) * dt
	elseif th < 0 then bike.speed -= (bike.speed > 0 and 50 or 14) * dt
	else bike.speed -= math.sign(bike.speed) * math.min(math.abs(bike.speed), 12 * dt) end
	bike.speed = math.clamp(bike.speed, -12, 70)
	if math.abs(bike.speed) > 0.5 then
		bike.yaw -= st * dt * 1.9 * math.clamp(bike.speed / 18, -1, 1)
	end
	local fwd = Vector3.new(-math.sin(bike.yaw), 0, -math.cos(bike.yaw))
	local step = bike.speed * dt
	if math.abs(step) > 0.001 then
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Include
		rp.FilterDescendantsInstances = { a.solid }
		local dir = fwd * (math.sign(step) * (math.abs(step) + 3))
		local hit = workspace:Raycast(bike.pos + Vector3.new(0, 2, 0), dir, rp)
		if hit then
			if math.abs(bike.speed) > 25 and occ then
				local hum = occ.Parent:FindFirstChildOfClass("Humanoid")
				if hum then hum:TakeDamage(math.abs(bike.speed) * 0.5) end
				noise(a, bike.pos, 120)
			end
			bike.speed *= -0.2
		else
			bike.pos += fwd * step
		end
		bike.pos = Vector3.new(math.clamp(bike.pos.X, a.origin.X - HALF + 4, a.origin.X + HALF - 4), bike.pos.Y, math.clamp(bike.pos.Z, a.origin.Z - HALF + 4, a.origin.Z + HALF - 4))
	end
	bike.model:PivotTo(CFrame.new(bike.pos) * CFrame.Angles(0, bike.yaw, 0))
	if math.abs(bike.speed) > 20 then -- run zombies over
		for _, z in a.zombies do
			if z.hum.Health > 0 and (z.hrp.Position - bike.pos).Magnitude < 5 then
				z.hum:TakeDamage(35 + bike.speed)
				bike.speed *= 0.93
			end
		end
	end
	if SOUND.Engine ~= "" then bike.engine.PlaybackSpeed = 0.7 + math.abs(bike.speed) / 45 end
	if occ then
		bike.noiseT -= dt
		if bike.noiseT <= 0 then
			bike.noiseT = 0.5
			noise(a, bike.pos, 45 + math.abs(bike.speed) * 3.5) -- engine noise draws zombies
		end
	end
end

-------------------------------------------------------------------- zombies
local function spawnZombie(a, pos)
	local ok, m = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
	end)
	if not ok or not m then return end
	m.Name = "Zombie"
	local bc = m:FindFirstChildOfClass("BodyColors")
	if bc then bc:Destroy() end
	local skin = Color3.fromRGB(111, 143, 90)
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			p.Color = (p.Name:find("Leg")) and Color3.fromRGB(42, 42, 51) or (p.Name == "Torso" and Color3.fromRGB(74, 58, 58) or skin)
		end
	end
	local hum = m:FindFirstChildOfClass("Humanoid")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.MaxHealth = math.min(120, 55 + a.day * 4)
	hum.Health = hum.MaxHealth
	hum.WalkSpeed = 7
	m:PivotTo(CFrame.new(pos))
	m.Parent = a.zfolder
	local hrp = m:FindFirstChild("HumanoidRootPart")
	pcall(function() hrp:SetNetworkOwner(nil) end)
	local z = { model = m, hum = hum, hrp = hrp, state = "idle", atk = 0, groan = math.random() * 10, spd = 0.9 + math.random() * 0.25 }
	table.insert(a.zombies, z)
	hum.Died:Connect(function()
		a.kills += 1
		local i = table.find(a.zombies, z)
		if i then table.remove(a.zombies, i) end
		Debris:AddItem(m, 4)
	end)
	return z
end

local function tickZombies(a, dt)
	local dark = darkness(a.time)
	local alive = arenaPlayers(a)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { a.solid }
	for _, z in a.zombies do
		if z.hum.Health <= 0 then continue end
		z.atk -= dt
		z.groan -= dt
		local zp = z.hrp.Position
		-- look for a target
		local best, bd = nil, lerp(ZOMBIE_VISION_DAY, ZOMBIE_VISION_NIGHT, dark)
		for _, p in alive do
			local root = p.Character.HumanoidRootPart
			local d = (root.Position - zp).Magnitude
			if d < bd then
				local blocked = workspace:Raycast(zp + Vector3.new(0, 2, 0), root.Position - zp, rp)
				if not blocked or d < 10 then best, bd = p, d end
			end
		end
		if best then
			z.state, z.target = "chase", best
		elseif z.state == "chase" then
			z.state = "investigate"
			z.goal = z.target and z.target.Character and z.target.Character.HumanoidRootPart.Position or zp
			z.target = nil
		end
		local speed = 7
		if z.state == "chase" and z.target and z.target.Character then
			local tp = z.target.Character.HumanoidRootPart.Position
			z.hum:MoveTo(steerPoint(a, zp, tp))
			speed = (11 + math.min(a.day, 10) * 0.5 + dark * 3) * z.spd
			local d = (tp - zp).Magnitude
			if d < 5 and z.atk <= 0 then
				z.atk = 1.1
				local th = z.target.Character:FindFirstChildOfClass("Humanoid")
				if th then
					th:TakeDamage((8 + 7 * dark) * (1 + 0.04 * (a.day - 1)))
					playSound(SOUND.Hurt, z.target.Character.Head, 0.8)
				end
			end
		elseif z.state == "investigate" and z.goal then
			z.hum:MoveTo(steerPoint(a, zp, z.goal))
			speed = 9 * z.spd
			if (z.goal - zp).Magnitude < 6 then z.state, z.goal = "idle", nil end
		elseif math.random() < 0.05 then
			z.hum:MoveTo(zp + Vector3.new(math.random(-14, 14), 0, math.random(-14, 14)))
			speed = 4
		end
		z.hum.WalkSpeed = speed
		-- bash closed doors we are leaning on
		if z.state ~= "idle" then
			for _, door in a.doors do
				if not door.open and (door.part.Position - zp).Magnitude < 7 then
					door.hp -= 9 * dt
					if door.hp <= 0 then
						door.broken = true
						door.set(true)
						playSound(SOUND.DoorBreak, door.part, 1)
						noise(a, door.part.Position, 50)
					end
				end
			end
		end
		if z.groan <= 0 then
			z.groan = z.state == "chase" and 4 + math.random() * 3 or 10 + math.random() * 8
			playSound(SOUND.Groan, z.hrp, 0.9, 0.8 + math.random() * 0.4, 120)
		end
	end
end

local function managePopulation(a)
	local alive = arenaPlayers(a)
	if #alive == 0 then return end
	local dark = darkness(a.time)
	local target = math.min(46, math.floor(lerp(10 + a.day, 24 + a.day * 3, dark)))
	if #a.zombies < target then
		for _ = 1, 2 do
			local ref = alive[math.random(#alive)].Character.HumanoidRootPart.Position
			local ang, r = math.random() * math.pi * 2, 110 + math.random() * 70
			local p = a.origin + Vector3.new(math.clamp(ref.X - a.origin.X + math.cos(ang) * r, -HALF + 8, HALF - 8), 4, math.clamp(ref.Z - a.origin.Z + math.sin(ang) * r, -HALF + 8, HALF - 8))
			local near = false
			for _, pl in alive do if (pl.Character.HumanoidRootPart.Position - p).Magnitude < 90 then near = true end end
			if not near and not houseAt(a, p) then
				local z = spawnZombie(a, p)
				if z then z.state, z.goal = "investigate", ref end
			end
		end
	elseif #a.zombies > target + 4 then
		local z = a.zombies[1]
		if z then
			local far = true
			for _, pl in alive do if (pl.Character.HumanoidRootPart.Position - z.hrp.Position).Magnitude < 130 then far = false end end
			if far then z.model:Destroy(); table.remove(a.zombies, 1) end
		end
	end
end

-------------------------------------------------------------------- arena lifecycle
local function buildWorld(a)
	local o = a.origin
	local f = Instance.new("Folder")
	f.Name = "Arena" .. a.id
	f.Parent = workspace
	a.folder = f
	a.solid = Instance.new("Folder"); a.solid.Name = "Solid"; a.solid.Parent = f
	a.zfolder = Instance.new("Folder"); a.zfolder.Name = "Zombies"; a.zfolder.Parent = f
	mk(f, Vector3.new(HALF * 2 + 20, 2, HALF * 2 + 20), CFrame.new(o + Vector3.new(0, -1, 0)), Color3.fromRGB(75, 107, 57), Enum.Material.Grass)
	mk(f, Vector3.new(16, 0.2, HALF * 2), CFrame.new(o + Vector3.new(0, 0.1, 0)), Color3.fromRGB(59, 59, 64), Enum.Material.Asphalt)
	mk(f, Vector3.new(HALF * 2, 0.2, 16), CFrame.new(o + Vector3.new(0, 0.12, 0)), Color3.fromRGB(59, 59, 64), Enum.Material.Asphalt)
	mk(f, Vector3.new(30, 0.25, 30), CFrame.new(o + Vector3.new(0, 0.15, 0)), Color3.fromRGB(88, 90, 96), Enum.Material.Concrete)
	-- invisible boundary walls
	for _, w in { { 0, -HALF - 10, HALF * 2 + 20, 2 }, { 0, HALF + 10, HALF * 2 + 20, 2 }, { -HALF - 10, 0, 2, HALF * 2 + 20 }, { HALF + 10, 0, 2, HALF * 2 + 20 } } do
		mk(f, Vector3.new(w[3], 120, w[4]), CFrame.new(o + Vector3.new(w[1], 60, w[2])), Color3.new(), nil, { Transparency = 1 })
	end
	a.houses, a.doors, a.zombies = {}, {}, {}
	-- houses: 16 spots, door faces the nearer road
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			for _, s in { { 60, 60 }, { 140, 60 }, { 60, 140 }, { 140, 140 } } do
				local x, z = sx * s[1] + math.random(-8, 8), sz * s[2] + math.random(-8, 8)
				local face = math.abs(x) < math.abs(z) and Vector3.new(-sx, 0, 0) or Vector3.new(0, 0, -sz)
				buildHouse(a, CFrame.new(o + Vector3.new(x, 0, z)) * CFrame.Angles(0, math.atan2(face.X, face.Z), 0), math.random() < 0.55)
			end
		end
	end
	-- trees
	for _ = 1, 90 do
		local x, z = math.random(-HALF + 6, HALF - 6), math.random(-HALF + 6, HALF - 6)
		if math.abs(x) > 14 and math.abs(z) > 14 and not houseAt(a, o + Vector3.new(x, 0, z)) then
			local h = 12 + math.random() * 8
			mk(a.solid, Vector3.new(2, h, 2), CFrame.new(o + Vector3.new(x, h / 2, z)), Color3.fromRGB(90, 59, 34), Enum.Material.Wood)
			mk(a.folder, Vector3.new(11, 11, 11), CFrame.new(o + Vector3.new(x, h + 3, z)), Color3.fromRGB(47, 90, 44), Enum.Material.Grass, { Shape = Enum.PartType.Ball, CanCollide = false })
		end
	end
	-- wrecked cars on the roads
	for _, c in { { 0, -60 }, { 0, 90 }, { 80, 0 }, { -110, 0 } } do
		mk(a.solid, Vector3.new(7, 3, 14), CFrame.new(o + Vector3.new(c[1] + 4, 2, c[2])), Color3.fromRGB(120, 40, 40), Enum.Material.Metal)
	end
	-- bike on the player's right (+X) at spawn
	a.bike = buildBike(a, CFrame.new(o + Vector3.new(9, 0, 0)))
end

local function setupPlayerInArena(a, plr, idx)
	plr.RespawnLocation = nil
	plr:LoadCharacter()
	local char = plr.Character or plr.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart")
	char:PivotTo(CFrame.lookAt(a.origin + Vector3.new(-6 + idx * 3, 5, 6), a.origin + Vector3.new(-6 + idx * 3, 5, -50))) -- facing -Z, bike on the right
	plr:SetAttribute("Arena", a.id)
	plr:SetAttribute("Ammo", 18)
	plr:SetAttribute("Medkits", 0)
	plr:SetAttribute("Food", 0)
	plr:SetAttribute("Door", nil)
	for _, name in { "Pistol", "Bat" } do
		local t = Instance.new("Tool")
		t.Name = name
		t.CanBeDropped = false
		local h = Instance.new("Part")
		h.Name = "Handle"
		h.Size = name == "Pistol" and Vector3.new(0.4, 0.8, 1.8) or Vector3.new(0.5, 0.5, 3.5)
		h.Color = name == "Pistol" and Color3.fromRGB(25, 25, 25) or Color3.fromRGB(140, 96, 56)
		h.Parent = t
		t.Parent = plr.Backpack
	end
	-- DAY counter above the head
	local head = char:WaitForChild("Head")
	local lbl = billboard(head, "DAY 1", UDim2.fromOffset(150, 40), Vector3.new(0, 3.2, 0))
	lbl.TextColor3 = Color3.fromRGB(242, 177, 52)
	a.labels[plr] = lbl
	char:FindFirstChildOfClass("Humanoid").Died:Connect(function()
		msg(plr, "You died! Wait for your squad...", "#ff6655")
		if #arenaPlayers(a) == 0 then a.endAt = os.clock() + 4 end
	end)
end

local function endArena(a)
	arenas[a.id] = nil
	local d = doors[a.id]
	d.arena = nil
	for _, p in a.players do
		if p.Parent then
			R_Status:FireClient(p, { active = false })
			msg(p, ("ALL SURVIVORS FELL - you survived %d day(s), %d kills"):format(a.day, a.kills), "#ff6655")
			p:SetAttribute("Arena", nil)
			p.RespawnLocation = spawnLoc
			p:LoadCharacter()
		end
	end
	a.folder:Destroy()
	refreshDoor(d)
end

local function startArena(d)
	local a = {
		id = d.id, origin = Vector3.new(d.id * 1000, 0, 0), players = table.clone(d.players),
		time = 15, day = 1, kills = 0, labels = {}, popT = 0, zT = 0, sT = 0, fT = 0,
	}
	d.players = {}
	d.countdown = nil
	d.arena = a
	arenas[d.id] = a
	refreshDoor(d)
	buildWorld(a)
	for i, p in a.players do
		task.spawn(setupPlayerInArena, a, p, i)
	end
	for i = 1, 14 do spawnZombie(a, a.origin + Vector3.new(math.random(-HALF + 20, HALF - 20), 4, math.random(-HALF + 20, HALF - 20))) end
end

-------------------------------------------------------------------- combat remotes
R_Fire.OnServerEvent:Connect(function(plr, kind, target)
	local aId = plr:GetAttribute("Arena")
	local a = aId and arenas[aId]
	local char = plr.Character
	if not a or not char or typeof(target) ~= "Vector3" then return end
	local hum, root = char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart")
	if not hum or hum.Health <= 0 or not root then return end
	local now = os.clock()
	if (plr:GetAttribute("CD") or 0) > now then return end
	if kind == "Pistol" then
		local ammo = plr:GetAttribute("Ammo") or 0
		if ammo <= 0 then return msg(plr, "Out of ammo", "#ff9a5a") end
		plr:SetAttribute("CD", now + 0.33)
		plr:SetAttribute("Ammo", ammo - 1)
		local origin = char.Head.Position
		local dir = (target - origin).Unit * 300
		local rp = RaycastParams.new()
		rp.FilterDescendantsInstances = { char }
		rp.FilterType = Enum.RaycastFilterType.Exclude
		local hit = workspace:Raycast(origin, dir, rp)
		local endPos = hit and hit.Position or origin + dir
		local tr = mk(a.folder, Vector3.new(0.15, 0.15, (endPos - origin).Magnitude), CFrame.lookAt(origin, endPos) * CFrame.new(0, 0, -(endPos - origin).Magnitude / 2), Color3.fromRGB(255, 233, 160), Enum.Material.Neon, { CanCollide = false })
		Debris:AddItem(tr, 0.06)
		playSound(SOUND.Gun, root, 1, 1, 400)
		noise(a, root.Position, 220) -- gunshots are LOUD
		if hit then
			local zm = hit.Instance:FindFirstAncestorOfClass("Model")
			local zh = zm and zm.Name == "Zombie" and zm:FindFirstChildOfClass("Humanoid")
			if zh then
				zh:TakeDamage(hit.Instance.Name == "Head" and 50 or 25)
				for _, z in a.zombies do
					if z.model == zm and z.state ~= "chase" then z.state, z.target = "chase", plr end
				end
			end
		end
	elseif kind == "Bat" then
		plr:SetAttribute("CD", now + 0.6)
		playSound(SOUND.Bat, root, 0.8)
		for _, z in a.zombies do
			local off = z.hrp.Position - root.Position
			if off.Magnitude < 9 and off.Unit:Dot(root.CFrame.LookVector) > 0.2 then
				z.hum:TakeDamage(30)
				z.hrp.AssemblyLinearVelocity = off.Unit * 40 + Vector3.new(0, 15, 0)
			end
		end
		noise(a, root.Position, 40)
	end
end)

R_Heal.OnServerEvent:Connect(function(plr)
	local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or hum.Health >= hum.MaxHealth then return end
	if (plr:GetAttribute("Medkits") or 0) > 0 then
		plr:SetAttribute("Medkits", plr:GetAttribute("Medkits") - 1)
		hum.Health = math.min(hum.MaxHealth, hum.Health + 55)
	elseif (plr:GetAttribute("Food") or 0) > 0 then
		plr:SetAttribute("Food", plr:GetAttribute("Food") - 1)
		hum.Health = math.min(hum.MaxHealth, hum.Health + 20)
	else
		msg(plr, "Nothing to heal with", "#cccccc")
	end
end)

-------------------------------------------------------------------- players join / leave
Players.PlayerAdded:Connect(function(plr)
	plr.RespawnLocation = spawnLoc
	plr:LoadCharacter()
end)
Players.PlayerRemoving:Connect(function(plr) leaveDoor(plr) end)
for _, p in Players:GetPlayers() do
	p.RespawnLocation = spawnLoc
	task.spawn(function() p:LoadCharacter() end)
end

-------------------------------------------------------------------- main loop
local lobbyT = 0
RunService.Heartbeat:Connect(function(dt)
	-- lobby countdowns (min 1 player, max 5; restarts when someone joins)
	lobbyT += dt
	if lobbyT >= 1 then
		lobbyT = 0
		for _, d in doors do
			if not d.arena and #d.players > 0 then
				d.countdown = (d.countdown or 20) - 1
				if #d.players >= 5 then d.countdown = math.min(d.countdown, 5) end
				if d.countdown <= 0 then startArena(d) else refreshDoor(d) end
			end
		end
	end
	for _, a in arenas do
		if not a.bike then continue end
		-- time: day = 120s, night = 180s, loops forever
		a.time += dt
		if a.time >= CYCLE then
			a.time -= CYCLE
			a.day += 1
			for _, p in a.players do msg(p, "DAY " .. a.day, "#f2b134") end
		end
		updateBike(a, a.bike, dt)
		a.zT += dt
		if a.zT >= 0.3 then tickZombies(a, a.zT); a.zT = 0 end
		a.popT += dt
		if a.popT >= 1.5 then a.popT = 0; managePopulation(a) end
		-- footsteps make noise
		a.fT += dt
		if a.fT >= 0.5 then
			a.fT = 0
			for _, p in arenaPlayers(a) do
				local root = p.Character.HumanoidRootPart
				local v = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
				local seated = p.Character.Humanoid.SeatPart
				if not seated then
					if v > 20 then noise(a, root.Position, 80) elseif v > 10 then noise(a, root.Position, 35) elseif v > 2 then noise(a, root.Position, 8) end
				end
			end
		end
		-- status to clients + day label
		a.sT += dt
		if a.sT >= 1 then
			a.sT = 0
			for _, p in a.players do
				if p.Parent then R_Status:FireClient(p, { active = true, time = a.time, day = a.day, kills = a.kills }) end
				local lbl = a.labels[p]
				if lbl then lbl.Text = ("DAY %d %s"):format(a.day, a.time < DAY and "(day)" or "(night)") end
			end
		end
		if a.endAt and os.clock() >= a.endAt then endArena(a) end
	end
end)

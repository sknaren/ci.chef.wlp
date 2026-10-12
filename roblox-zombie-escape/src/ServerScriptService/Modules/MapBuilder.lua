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

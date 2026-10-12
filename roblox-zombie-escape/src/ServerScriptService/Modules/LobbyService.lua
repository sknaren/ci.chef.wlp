-- ModuleScript: ServerScriptService/Modules/LobbyService
-- Lobby with private party rooms (max Config.PartyMax players each).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.RemoteHub)

local Lobby = {}
Lobby.onEnterGame = nil -- set by GameManager (single-place mode)
Lobby.spawnCFrame = CFrame.new(0, Config.LobbyHeight + 4, 45)

local rooms = {}

local function notify(player: Player, text: string)
	Remotes.Notify:FireClient(player, text)
end

local function part(parent, name, size, position, color, material, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = position
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.Anchored = true
	p.Parent = parent
	return p
end

local function refresh(room)
	for i = #room.members, 1, -1 do
		if room.members[i].Parent == nil then
			table.remove(room.members, i)
		end
	end
	if #room.members == 0 then
		room.host = nil
	elseif not table.find(room.members, room.host) then
		room.host = room.members[1]
	end

	local names = {}
	for _, p in room.members do
		table.insert(names, (p == room.host and "* " or "") .. p.DisplayName)
	end
	local status = room.locked and "STARTING..." or (#room.members == 0 and "Empty - step up to join" or table.concat(names, "\n"))
	room.label.Text = ("PRIVATE PARTY %d  [%d/%d]\n%s"):format(room.index, #room.members, Config.PartyMax, status)
end

local function roomOf(player: Player)
	for _, room in rooms do
		if table.find(room.members, player) then
			return room
		end
	end
	return nil
end

local function leave(player: Player)
	local room = roomOf(player)
	if room then
		table.remove(room.members, table.find(room.members, player))
		refresh(room)
	end
end

local function join(player: Player, room)
	if room.locked then
		notify(player, "That party is already starting")
		return
	end
	if #room.members >= Config.PartyMax then
		notify(player, "Party is full (" .. Config.PartyMax .. "/" .. Config.PartyMax .. ")")
		return
	end
	leave(player)
	table.insert(room.members, player)
	refresh(room)
	notify(player, ("Joined party %d. The host (*) presses START."):format(room.index))
end

local function launch(members)
	if Config.GamePlaceId == 0 then
		-- single-place mode: move the party into the arena
		for _, player in members do
			local char = player.Character
			if char then
				player:SetAttribute("InGame", true)
				char:PivotTo(CFrame.new(math.random(-6, 6), 5, math.random(-6, 6)))
				if Lobby.onEnterGame then
					Lobby.onEnterGame(player)
				end
			end
		end
	else
		-- real private server for this party only
		local ok, err = pcall(function()
			local code = TeleportService:ReserveServer(Config.GamePlaceId)
			local options = Instance.new("TeleportOptions")
			options.ReservedServerAccessCode = code
			TeleportService:TeleportAsync(Config.GamePlaceId, members, options)
		end)
		if not ok then
			warn("Teleport failed: " .. tostring(err))
			for _, player in members do
				notify(player, "Teleport failed - check GamePlaceId and that the game is published")
			end
		end
	end
end

local function startRoom(room)
	if room.locked or #room.members == 0 then
		return
	end
	room.locked = true
	for t = Config.StartCountdown, 1, -1 do
		for _, p in room.members do
			notify(p, "Game starts in " .. t)
		end
		room.label.Text = ("PRIVATE PARTY %d\nStarting in %d..."):format(room.index, t)
		task.wait(1)
	end

	local members = {}
	for _, p in room.members do
		if p.Parent then
			table.insert(members, p)
		end
	end
	room.members = {}
	room.host = nil
	if #members > 0 then
		launch(members)
	end
	room.locked = false
	refresh(room)
end

function Lobby.build()
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	folder.Parent = workspace

	local y = Config.LobbyHeight
	part(folder, "LobbyFloor", Vector3.new(160, 2, 160), Vector3.new(0, y, 0), Color3.fromRGB(35, 35, 45), Enum.Material.Concrete)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(0, y + 1.5, 45)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(80, 120, 200)
	spawn.Parent = folder

	local title = part(folder, "Title", Vector3.new(1, 1, 1), Vector3.new(0, y + 25, 60), Color3.new(0, 0, 0), nil, 1)
	title.CanCollide = false
	local tg = Instance.new("BillboardGui")
	tg.Size = UDim2.fromOffset(500, 100)
	tg.AlwaysOnTop = true
	tg.Adornee = title
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.Text = "ZOMBIE ESCAPE\nPick a private party (max " .. Config.PartyMax .. ")"
	tl.TextScaled = true
	tl.Font = Enum.Font.GothamBlack
	tl.TextColor3 = Color3.fromRGB(255, 80, 80)
	tl.Parent = tg
	tg.Parent = title

	local n = Config.LobbyRooms
	for i = 1, n do
		local x = (i - (n + 1) / 2) * 34
		local room = { index = i, members = {}, host = nil, locked = false }
		rooms[i] = room

		local pad = part(folder, "Pad" .. i, Vector3.new(20, 1, 20), Vector3.new(x, y + 1.5, -30), Color3.fromRGB(60, 200, 120), Enum.Material.Neon, 0.3)
		local glass = Color3.fromRGB(150, 200, 255)
		part(folder, "WallBack" .. i, Vector3.new(20, 12, 1), Vector3.new(x, y + 7, -40), glass, Enum.Material.Glass, 0.6)
		part(folder, "WallL" .. i, Vector3.new(1, 12, 20), Vector3.new(x - 10, y + 7, -30), glass, Enum.Material.Glass, 0.6)
		part(folder, "WallR" .. i, Vector3.new(1, 12, 20), Vector3.new(x + 10, y + 7, -30), glass, Enum.Material.Glass, 0.6)

		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(260, 110)
		gui.StudsOffset = Vector3.new(0, 10, 0)
		gui.AlwaysOnTop = true
		gui.Adornee = pad
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 0.4
		label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Parent = gui
		gui.Parent = pad
		room.label = label

		local joinPrompt = Instance.new("ProximityPrompt")
		joinPrompt.ActionText = "Join / Leave"
		joinPrompt.ObjectText = "Private Party " .. i
		joinPrompt.HoldDuration = 0
		joinPrompt.MaxActivationDistance = 12
		joinPrompt.RequiresLineOfSight = false
		joinPrompt.Parent = pad
		joinPrompt.Triggered:Connect(function(player)
			if roomOf(player) == room then
				leave(player)
				notify(player, "Left the party")
			else
				join(player, room)
				if #room.members >= Config.PartyMax then
					task.spawn(startRoom, room)
				end
			end
		end)

		local button = part(folder, "Start" .. i, Vector3.new(4, 1, 4), Vector3.new(x, y + 1.5, -12), Color3.fromRGB(255, 150, 40), Enum.Material.Neon)
		local startPrompt = Instance.new("ProximityPrompt")
		startPrompt.ActionText = "START GAME"
		startPrompt.ObjectText = "Host only"
		startPrompt.HoldDuration = 0.5
		startPrompt.MaxActivationDistance = 10
		startPrompt.RequiresLineOfSight = false
		startPrompt.Parent = button
		startPrompt.Triggered:Connect(function(player)
			if room.host ~= player then
				notify(player, "Only the party host (*) can start")
				return
			end
			startRoom(room)
		end)

		refresh(room)
	end

	Players.PlayerRemoving:Connect(leave)
	return spawn
end

return Lobby

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

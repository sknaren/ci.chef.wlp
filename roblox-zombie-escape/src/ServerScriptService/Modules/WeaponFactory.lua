-- ModuleScript: ServerScriptService/Modules/WeaponFactory
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config)

local Factory = {}

function Factory.create(name: string): Tool?
	local stats = Config.Weapons[name]
	if not stats then
		return nil
	end

	local tool = Instance.new("Tool")
	tool.Name = name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = name

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = stats.HandleSize
	handle.Color = stats.Color
	handle.Material = Enum.Material.Metal
	handle.Parent = tool

	tool:SetAttribute("IsGun", true)
	tool:SetAttribute("Mag", stats.MagSize)
	tool:SetAttribute("MagSize", stats.MagSize)
	tool:SetAttribute("FireRate", stats.FireRate)
	tool:SetAttribute("Auto", stats.Auto)
	tool:SetAttribute("Reloading", false)
	return tool
end

return Factory

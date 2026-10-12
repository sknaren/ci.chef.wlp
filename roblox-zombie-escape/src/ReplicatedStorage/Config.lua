-- ModuleScript: ReplicatedStorage/Config
-- All game tuning lives here.
return {
	MapSize = 400,
	GridStep = 120,

	StartReserve = 36,
	MaxReserve = 180,
	AmmoPickup = 24,
	MedkitHeal = 50,
	KeysNeeded = 3,
	LootRespawn = 90,

	ZombieMax = 30,
	ZombieSpawnInterval = 3,
	ZombiesPerHouse = 2,
	ZombieHealth = 60,
	ZombieSpeed = 11,
	ZombieDamage = 12,
	ZombieAttackCooldown = 1,
	ZombieAttackRange = 5,
	ZombieDetectRange = 70,
	ZombieMinSpawnDistance = 60,
	ZombieAmmoDropChance = 0.15,

	-- name, weight (Pistol is given at spawn, so it is not in the loot table)
	LootTable = {
		{ "Ammo", 40 },
		{ "Medkit", 20 },
		{ "Shotgun", 22 },
		{ "Rifle", 18 },
	},

	Weapons = {
		Pistol = {
			Damage = 20, FireRate = 0.35, MagSize = 12, Range = 250, Pellets = 1,
			Spread = 0.01, ReloadTime = 1.2, Auto = false,
			HandleSize = Vector3.new(0.4, 0.8, 1.6), Color = Color3.fromRGB(60, 60, 60),
		},
		Rifle = {
			Damage = 24, FireRate = 0.11, MagSize = 30, Range = 400, Pellets = 1,
			Spread = 0.025, ReloadTime = 2, Auto = true,
			HandleSize = Vector3.new(0.4, 0.7, 3), Color = Color3.fromRGB(40, 70, 40),
		},
		Shotgun = {
			Damage = 12, FireRate = 0.9, MagSize = 6, Range = 80, Pellets = 8,
			Spread = 0.08, ReloadTime = 2.5, Auto = false,
			HandleSize = Vector3.new(0.5, 0.7, 2.8), Color = Color3.fromRGB(110, 70, 30),
		},
	},
}

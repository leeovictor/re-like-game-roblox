--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local items = require(ReplicatedStorage.Shared.inventory.items)
local CombatConfig = require(StarterPlayer.StarterPlayerScripts.Client.combat.CombatConfig)

export type CombatHudStats = {
	weaponName: string,
	loadedAmmo: string,
	reserveAmmo: string,
}

local function getEquippedWeaponStats(inventory: items.InventoryState?): CombatHudStats
	local equippedWeapon: items.ItemInstance? = nil
	local weaponConfig: CombatConfig.WeaponConfig? = nil
	local loadedAmmo: number? = nil
	local reserveAmmo = 0

	if inventory ~= nil then
		local equippedWeaponUid = inventory.equipped.weapon
		if equippedWeaponUid ~= nil then
			for _, instance in inventory.items do
				if instance.uid == equippedWeaponUid then
					equippedWeapon = instance
					break
				end
			end
		end
		if equippedWeapon ~= nil then
			weaponConfig = CombatConfig[equippedWeapon.itemId]
			if equippedWeapon.attributes ~= nil then
				local value = equippedWeapon.attributes.loadedAmmo
				if type(value) == "number" then
					loadedAmmo = value
				end
			end
			if loadedAmmo == nil and weaponConfig ~= nil
				and (equippedWeapon.attributes == nil or equippedWeapon.attributes.loadedAmmo == nil)
			then
				loadedAmmo = weaponConfig.magazineSize
			end
			if weaponConfig ~= nil then
				for _, instance in inventory.items do
					if instance.itemId == weaponConfig.ammoItemId and instance.quantity ~= nil then
						reserveAmmo += instance.quantity
					end
				end
			end
		end
	end

	local equippedWeaponDefinition = if equippedWeapon ~= nil then items[equippedWeapon.itemId] else nil
	return {
		weaponName = if equippedWeaponDefinition ~= nil then equippedWeaponDefinition.name else "SEM ARMA",
		loadedAmmo = if loadedAmmo ~= nil then tostring(loadedAmmo) else "--",
		reserveAmmo = if weaponConfig ~= nil then tostring(reserveAmmo) else "--",
	}
end

return {
	getEquippedWeaponStats = getEquippedWeaponStats,
}

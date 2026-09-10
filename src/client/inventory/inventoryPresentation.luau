--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local items = require(ReplicatedStorage.Shared.inventory.items)
local CombatConfig = require(StarterPlayer.StarterPlayerScripts.Client.combat.CombatConfig)

export type DisplayItem = {
	name: string,
	quantity: number?,
}

local function resolveDisplayItem(itemId: items.ItemId, quantity: number?): DisplayItem
	local item = items[itemId]
	return {
		name = if item ~= nil then item.name else itemId,
		quantity = quantity,
	}
end

local function getDisplayQuantity(instance: items.ItemInstance): number?
	if instance.quantity ~= nil then
		return instance.quantity
	end
	local definition = items[instance.itemId]
	if definition == nil or definition.category ~= "weapon" then
		return nil
	end
	local authoredLoadedAmmo = if instance.attributes ~= nil then instance.attributes.loadedAmmo else nil
	if authoredLoadedAmmo ~= nil then
		return if type(authoredLoadedAmmo) == "number" then authoredLoadedAmmo else nil
	end
	local config = CombatConfig[instance.itemId]
	return if config ~= nil then config.magazineSize else nil
end

local function isItemEquipped(equipped: { [string]: string }, uid: string): boolean
	for _, equippedUid in equipped do
		if equippedUid == uid then
			return true
		end
	end
	return false
end

return {
	resolveDisplayItem = resolveDisplayItem,
	getDisplayQuantity = getDisplayQuantity,
	isItemEquipped = isItemEquipped,
}

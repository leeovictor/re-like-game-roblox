--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local items = require(ReplicatedStorage.Shared.inventory.items)
local InventoryStore = require(ReplicatedStorage.Shared.inventory.InventoryStore)
local Signal = require(ReplicatedStorage.Packages.Signal)

type SignalConnection = {
	Disconnect: (self: SignalConnection) -> (),
}
type ChangedSignal = {
	Fire: (self: ChangedSignal, snapshot: items.InventoryState?) -> (),
	Connect: (self: ChangedSignal, callback: (snapshot: items.InventoryState?) -> ()) -> SignalConnection,
}

export type InventoryController = {
	changed: ChangedSignal,
	started: boolean,
	state: items.InventoryState?,
	start: (self: InventoryController) -> (),
	stop: (self: InventoryController) -> (),
	getState: (self: InventoryController) -> items.InventoryState?,
	addInstance: (self: InventoryController, instance: items.ItemInstance) -> boolean,
	equip: (self: InventoryController, uid: string) -> boolean,
	getEquipped: (self: InventoryController, slot: string) -> items.ItemInstance?,
	updateAttributes: (self: InventoryController, uid: string, attributes: items.ItemAttributes) -> boolean,
	consumeLoadedAmmo: (self: InventoryController, weaponUid: string) -> boolean,
	reloadWeapon: (self: InventoryController, weaponUid: string, ammoUid: string, amount: number, loadedAmmo: number) -> boolean,
}

local InventoryController = {}
InventoryController.__index = InventoryController

local function hasCapability(itemId: string, capability: string): boolean
	local definition = items[itemId]
	if definition == nil then
		return false
	end
	for _, value in definition.capabilities do
		if value == capability then
			return true
		end
	end
	return false
end

local function copyAttributes(attributes: items.ItemAttributes?): items.ItemAttributes
	return if attributes == nil then {} else table.clone(attributes)
end

function InventoryController.new(): InventoryController
	local self = setmetatable({
		changed = (Signal.new() :: any) :: ChangedSignal,
		started = false,
		state = nil :: items.InventoryState?,
	}, InventoryController)
	return (self :: any) :: InventoryController
end

function InventoryController.start(self: InventoryController): ()
	if self.started then
		return
	end
	self.started = true
	self.state = InventoryStore.defaultInventory()
end

function InventoryController.stop(self: InventoryController): ()
	if not self.started then
		return
	end
	self.started = false
	self.state = nil
end

function InventoryController.getState(self: InventoryController): items.InventoryState?
	return self.state
end

function InventoryController.addInstance(self: InventoryController, instance: items.ItemInstance): boolean
	if not self.started or self.state == nil then
		return false
	end
	local updated = InventoryStore.addInstance(self.state, instance)
	if updated == nil then
		return false
	end
	self.state = updated
	self.changed:Fire(updated)
	return true
end

function InventoryController.equip(self: InventoryController, uid: string): boolean
	if not self.started or self.state == nil then
		return false
	end
	local instance = InventoryStore.findInstance(self.state, uid)
	if instance == nil then
		return false
	end
	local definition = items[instance.itemId]
	if definition == nil or definition.category ~= "weapon" or not hasCapability(instance.itemId, "equip") then
		return false
	end
	local updated = InventoryStore.equip(self.state, "weapon", uid)
	if updated == nil then
		return false
	end
	self.state = updated
	self.changed:Fire(updated)
	return true
end

function InventoryController.getEquipped(self: InventoryController, slot: string): items.ItemInstance?
	if not self.started or self.state == nil then
		return nil
	end
	local uid = self.state.equipped[slot]
	if uid == nil then
		return nil
	end
	return InventoryStore.findInstance(self.state, uid)
end

function InventoryController.updateAttributes(self: InventoryController, uid: string, attributes: items.ItemAttributes): boolean
	if not self.started or self.state == nil then
		return false
	end
	local updated = InventoryStore.updateAttributes(self.state, uid, attributes)
	if updated == nil then
		return false
	end
	self.state = updated
	self.changed:Fire(updated)
	return true
end

function InventoryController.consumeLoadedAmmo(self: InventoryController, weaponUid: string): boolean
	if not self.started or self.state == nil then
		return false
	end
	local weapon = InventoryStore.findInstance(self.state, weaponUid)
	local loadedAmmo = if weapon ~= nil and weapon.attributes ~= nil then weapon.attributes.loadedAmmo else nil
	if weapon == nil or type(loadedAmmo) ~= "number" or loadedAmmo <= 0 or loadedAmmo ~= math.floor(loadedAmmo) then
		return false
	end
	local attributes = copyAttributes(weapon.attributes)
	attributes.loadedAmmo = loadedAmmo - 1
	local updated = InventoryStore.updateAttributes(self.state, weaponUid, attributes)
	if updated == nil then
		return false
	end
	self.state = updated
	self.changed:Fire(updated)
	return true
end

function InventoryController.reloadWeapon(
	self: InventoryController,
	weaponUid: string,
	ammoUid: string,
	amount: number,
	loadedAmmo: number
): boolean
	if not self.started or self.state == nil then
		return false
	end
	if type(amount) ~= "number" or amount <= 0 or amount ~= math.floor(amount)
		or type(loadedAmmo) ~= "number" or loadedAmmo < 0 or loadedAmmo ~= math.floor(loadedAmmo)
	then
		return false
	end
	local weapon = InventoryStore.findInstance(self.state, weaponUid)
	local ammo = InventoryStore.findInstance(self.state, ammoUid)
	if weapon == nil or ammo == nil or weapon.itemId ~= "handgun" or ammo.itemId ~= "handgun_ammo"
		or ammo.quantity == nil or ammo.quantity < amount
	then
		return false
	end
	local weaponAttributes = copyAttributes(weapon.attributes)
	weaponAttributes.loadedAmmo = loadedAmmo
	local withLoadedAmmo = InventoryStore.updateAttributes(self.state, weaponUid, weaponAttributes)
	if withLoadedAmmo == nil then
		return false
	end
	local updated = InventoryStore.removeQuantity(withLoadedAmmo, ammoUid, amount)
	if updated == nil then
		return false
	end
	self.state = updated
	self.changed:Fire(updated)
	return true
end

return InventoryController

--!strict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(script.Parent.CombatConfig)
local EnemyControllerModule = require(script.Parent.Parent.enemies.EnemyController)
local CharacterRoot = require(script.Parent.Parent.player.CharacterRoot)
local InventoryControllerModule = require(script.Parent.Parent.inventory.InventoryController)
local TankController = require(script.Parent.Parent.player.TankController)
local enemyTypes = require(script.Parent.Parent.enemies.types)

local items = require(game:GetService("ReplicatedStorage").Shared.inventory.items)

type Enemy = enemyTypes.Enemy
type SignalConnection = {
	Disconnect: (self: SignalConnection) -> (),
}

export type Dependencies = {
	inventory: InventoryControllerModule.InventoryController,
	enemies: EnemyControllerModule.EnemyController,
	movement: TankController.MovementController,
}

export type CombatState = "neutral" | "aiming" | "reloading"

export type CombatService = {
	state: CombatState,
	started: boolean,
	start: (self: CombatService) -> (),
	stop: (self: CombatService) -> (),
	update: (self: CombatService, deltaTime: number) -> (),
	beginAim: (self: CombatService) -> (),
	endAim: (self: CombatService) -> (),
	shoot: (self: CombatService) -> boolean,
	requestReload: (self: CombatService) -> boolean,
	setTurnInput: (self: CombatService, left: boolean, right: boolean) -> boolean,
	acquireLock: (self: CombatService) -> (() -> ()),
	dependencies: Dependencies,
	aimHeld: boolean,
	turnLeft: boolean,
	turnRight: boolean,
	nextShotAt: number,
	reloadElapsed: number,
	reloadWeaponUid: string?,
	reloadGeneration: number,
	externalLockCount: number,
	externalLockGeneration: number,
	aimWeaponUid: string?,
	aimMovementRelease: (() -> ())?,
	reloadMovementRelease: (() -> ())?,
	inventoryConnection: SignalConnection?,
	mutatingInventory: boolean,
}

local CombatService = {}
CombatService.__index = CombatService

local function isInteger(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge and value == math.floor(value)
end

local function copyAttributes(attributes: items.ItemAttributes?): items.ItemAttributes
	return if attributes == nil then {} else table.clone(attributes)
end

local function releaseAimMovementLock(self: CombatService): ()
	local release = self.aimMovementRelease
	self.aimMovementRelease = nil
	if release ~= nil then
		release()
	end
end

local function releaseReloadMovementLock(self: CombatService): ()
	local release = self.reloadMovementRelease
	self.reloadMovementRelease = nil
	if release ~= nil then
		release()
	end
end

local function abortActiveAction(self: CombatService): ()
	self.aimWeaponUid = nil
	self.reloadWeaponUid = nil
	self.reloadElapsed = 0
	self.reloadGeneration += 1
	releaseAimMovementLock(self)
	releaseReloadMovementLock(self)
	self.state = "neutral"
end

local function getWeapon(self: CombatService): (items.ItemInstance?, typeof(CombatConfig.handgun)?)
	local weapon = self.dependencies.inventory:getEquipped("weapon")
	if weapon == nil then
		return nil, nil
	end
	return weapon, CombatConfig[weapon.itemId]
end

local function getLoadedAmmo(weapon: items.ItemInstance, config: typeof(CombatConfig.handgun)): number?
	local value = if weapon.attributes ~= nil then weapon.attributes.loadedAmmo else nil
	if type(value) ~= "number" or not isInteger(value) or value < 0 or value > config.magazineSize then
		return nil
	end
	return value
end

local function ensureLoadedAmmo(self: CombatService, weapon: items.ItemInstance, config: typeof(CombatConfig.handgun)): ()
	local value = if weapon.attributes ~= nil then weapon.attributes.loadedAmmo else nil
	if value ~= nil then
		return
	end
	local attributes = copyAttributes(weapon.attributes)
	attributes.loadedAmmo = config.magazineSize
	self.mutatingInventory = true
	self.dependencies.inventory:updateAttributes(weapon.uid, attributes)
	self.mutatingInventory = false
end

local function findReserve(self: CombatService, config: typeof(CombatConfig.handgun)): (string?, number)
	local state = self.dependencies.inventory:getState()
	if state == nil then
		return nil, 0
	end
	for _, instance in state.items do
		if instance.itemId == config.ammoItemId and instance.quantity ~= nil and instance.quantity > 0 then
			return instance.uid, instance.quantity
		end
	end
	return nil, 0
end

local function beginReload(self: CombatService, config: typeof(CombatConfig.handgun), weapon: items.ItemInstance): boolean
	local _, reserveQuantity = findReserve(self, config)
	local loadedAmmo = getLoadedAmmo(weapon, config)
	if loadedAmmo == nil or loadedAmmo >= config.magazineSize or reserveQuantity <= 0 then
		return false
	end
	releaseAimMovementLock(self)
	self.reloadGeneration += 1
	self.reloadElapsed = 0
	self.reloadWeaponUid = weapon.uid
	self.reloadMovementRelease = self.dependencies.movement:acquireMovementLock()
	self.state = "reloading"
	return true
end

local function acquireInitialTarget(self: CombatService, config: typeof(CombatConfig.handgun)): ()
	local playerRoot = CharacterRoot.get()
	local character = Players.LocalPlayer.Character
	if playerRoot == nil or character == nil then
		return
	end

	local candidates = self.dependencies.enemies:getActiveEnemies()
	table.sort(candidates, function(left, right)
		local leftDistance = (left.root :: BasePart).Position - playerRoot.Position
		local rightDistance = (right.root :: BasePart).Position - playerRoot.Position
		return leftDistance.Magnitude < rightDistance.Magnitude
	end)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	for _, enemy in candidates do
		local root = enemy.root
		if root ~= nil then
			local offset = root.Position - playerRoot.Position
			if offset.Magnitude <= config.acquisitionRadius then
				local result = Workspace:Raycast(playerRoot.Position, offset, params)
				if result ~= nil and result.Instance:IsDescendantOf(enemy.model) then
					self.dependencies.movement:setLookVector(offset)
					return
				end
			end
		end
	end
end

local function finishReload(self: CombatService): ()
	local weaponUid = self.reloadWeaponUid
	local weapon = self.dependencies.inventory:getEquipped("weapon")
	if weaponUid ~= nil and weapon ~= nil and weapon.uid == weaponUid then
		local config = CombatConfig[weapon.itemId]
		if config ~= nil then
			local loadedAmmo = getLoadedAmmo(weapon, config)
			local ammoUid, reserveQuantity = findReserve(self, config)
			if loadedAmmo ~= nil and ammoUid ~= nil then
				local amount = math.min(config.magazineSize - loadedAmmo, reserveQuantity)
				if amount > 0 then
					self.mutatingInventory = true
					self.dependencies.inventory:reloadWeapon(weaponUid, ammoUid, amount, loadedAmmo + amount)
					self.mutatingInventory = false
				end
			end
		end
	end
	self.reloadWeaponUid = nil
	self.reloadElapsed = 0
	self.reloadGeneration += 1
	releaseReloadMovementLock(self)
	self.state = "neutral"
	if self.aimHeld and self.externalLockCount == 0 then
		self:beginAim()
	end
end

function CombatService.new(dependencies: Dependencies): CombatService
	local self = setmetatable({
		state = "neutral",
		started = false,
		dependencies = dependencies,
		aimHeld = false,
		turnLeft = false,
		turnRight = false,
		nextShotAt = 0,
		reloadElapsed = 0,
		reloadWeaponUid = nil,
		reloadGeneration = 0,
		externalLockCount = 0,
		externalLockGeneration = 0,
		aimWeaponUid = nil,
		aimMovementRelease = nil,
		reloadMovementRelease = nil,
		inventoryConnection = nil,
		mutatingInventory = false,
	}, CombatService)
	return (self :: any) :: CombatService
end

function CombatService.start(self: CombatService): ()
	if self.started then
		return
	end
	self.started = true
	self.inventoryConnection = self.dependencies.inventory.changed:Connect(function()
		if self.mutatingInventory then
			return
		end
		local weapon = self.dependencies.inventory:getEquipped("weapon")
		local equippedUid = if weapon ~= nil then weapon.uid else nil
		if (self.state == "reloading" and equippedUid ~= self.reloadWeaponUid)
			or (self.state == "aiming" and equippedUid ~= self.aimWeaponUid)
		then
			abortActiveAction(self)
		end
		local config = if weapon ~= nil then CombatConfig[weapon.itemId] else nil
		if weapon ~= nil and config ~= nil then
			ensureLoadedAmmo(self, weapon, config)
		end
	end)
	local weapon, config = getWeapon(self)
	if weapon ~= nil and config ~= nil then
		ensureLoadedAmmo(self, weapon, config)
	end
end

function CombatService.stop(self: CombatService): ()
	if not self.started then
		return
	end
	self.started = false
	self.externalLockGeneration += 1
	self.externalLockCount = 0
	if self.inventoryConnection ~= nil then
		self.inventoryConnection:Disconnect()
		self.inventoryConnection = nil
	end
	abortActiveAction(self)
	self.aimHeld = false
	self.turnLeft = false
	self.turnRight = false
end

function CombatService.update(self: CombatService, deltaTime: number): ()
	if not self.started then
		return
	end
	if self.state == "reloading" then
		self.reloadElapsed += deltaTime
		local weapon = self.reloadWeaponUid
		if self.reloadElapsed >= (if weapon ~= nil then (CombatConfig[(self.dependencies.inventory:getEquipped("weapon") or { itemId = "" }).itemId] or CombatConfig.handgun).reloadDuration else CombatConfig.handgun.reloadDuration) then
			finishReload(self)
		end
		return
	end
	if self.state ~= "aiming" or self.externalLockCount > 0 then
		return
	end
	local _, config = getWeapon(self)
	if config == nil then
		return
	end
	local sign = if self.turnRight then -1 elseif self.turnLeft then 1 else 0
	if sign ~= 0 then
		local root = CharacterRoot.get()
		if root ~= nil then
			local direction = CFrame.Angles(0, sign * config.aimTurnSpeed * deltaTime, 0):VectorToWorldSpace(root.CFrame.LookVector)
			self.dependencies.movement:setLookVector(direction)
		end
	end
end

function CombatService.beginAim(self: CombatService): ()
	self.aimHeld = true
	if not self.started or self.externalLockCount > 0 or self.state ~= "neutral" then
		return
	end
	local weapon, config = getWeapon(self)
	if weapon == nil or config == nil or getLoadedAmmo(weapon, config) == nil then
		return
	end
	self.aimMovementRelease = self.dependencies.movement:acquireMovementLock()
	self.state = "aiming"
		self.aimWeaponUid = weapon.uid
	acquireInitialTarget(self, config)
end

function CombatService.endAim(self: CombatService): ()
	self.aimHeld = false
	if self.state ~= "aiming" then
		return
	end
	abortActiveAction(self)
end

function CombatService.shoot(self: CombatService): boolean
	if not self.started or self.externalLockCount > 0 or self.state ~= "aiming" then
		return false
	end
	local weapon, config = getWeapon(self)
	if weapon == nil or config == nil or getLoadedAmmo(weapon, config) == nil or os.clock() < self.nextShotAt then
		return false
	end
	if not self.dependencies.inventory:consumeLoadedAmmo(weapon.uid) then
		return false
	end
	self.nextShotAt = os.clock() + config.shotCooldown
	local root = CharacterRoot.get()
	local character = Players.LocalPlayer.Character
	if root ~= nil and character ~= nil then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local result = Workspace:Raycast(root.Position, root.CFrame.LookVector * config.shotRange, params)
		if result ~= nil then
			for _, enemy in self.dependencies.enemies:getActiveEnemies() do
				if result.Instance:IsDescendantOf(enemy.model) then
					self.dependencies.enemies:applyDamage(enemy, config.damage)
					break
				end
			end
		end
	end
	local updatedWeapon = self.dependencies.inventory:getEquipped("weapon")
	if updatedWeapon ~= nil and getLoadedAmmo(updatedWeapon, config) == 0 then
		beginReload(self, config, updatedWeapon)
	end
	return true
end

function CombatService.requestReload(self: CombatService): boolean
	if not self.started or self.state ~= "aiming" or not self.aimHeld or self.externalLockCount > 0 then
		return false
	end
	local weapon, config = getWeapon(self)
	if weapon == nil or config == nil then
		return false
	end
	return beginReload(self, config, weapon)
end

function CombatService.setTurnInput(self: CombatService, left: boolean, right: boolean): boolean
	self.turnLeft = left
	self.turnRight = right
	return self.state == "aiming" or self.state == "reloading" or self.externalLockCount > 0
end

function CombatService.acquireLock(self: CombatService): () -> ()
	self.externalLockCount += 1
	abortActiveAction(self)
	local acquiredGeneration = self.externalLockGeneration
	local released = false
	return function()
		if released then
			return
		end
		released = true
		if acquiredGeneration ~= self.externalLockGeneration then
			return
		end
		self.externalLockCount -= 1
	end
end

return CombatService

--!strict

local Players = game:GetService("Players")
local playerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
local client = playerScripts:WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local Config = require(client.player.FootstepConfig)
local FootstepController = require(client.player.FootstepController)

return function()
	local defaultSurfaceSounds = Config.surfaceSounds
	local configuredSurfaceSounds: { [Enum.Material]: { string } } = {}

	describe("FootstepController", function()
		afterEach(function()
			FootstepController.stop()
			Config.surfaceSounds = defaultSurfaceSounds
			table.clear(configuredSurfaceSounds)
		end)

		it("creates a pool for a configured floor material", function()
			local soundId = Config.soundIds[1]
			assert(soundId ~= nil, "FootstepConfig must contain a fallback sound")
			configuredSurfaceSounds[Enum.Material.Wood] = { soundId }
			Config.surfaceSounds = configuredSurfaceSounds

			FootstepController.start()

			local character = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
			local rootPart = character:WaitForChild("HumanoidRootPart")
			local surfaceSound = rootPart:WaitForChild("Footstep_Wood_1", 2)

			expect(surfaceSound).to.be.ok()
			if surfaceSound == nil then
				return
			end
			expect(surfaceSound:IsA("Sound")).to.equal(true)
		end)
	end)
end

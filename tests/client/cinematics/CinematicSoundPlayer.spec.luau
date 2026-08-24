--!strict

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local CinematicSoundPlayer = require(client.cinematics.CinematicSoundPlayer)

return function()
	describe("CinematicSoundPlayer", function()
		local soundFolder: Folder? = nil
		local player: any = nil

		beforeEach(function()
			local folder = Instance.new("Folder")
			folder.Name = "CinematicSoundPlayerSpec"
			folder.Parent = SoundService
			soundFolder = folder
		end)

		afterEach(function()
			if player ~= nil then
				player:stop(1)
				player:stop(2)
				player = nil
			end
			if soundFolder ~= nil then
				soundFolder:Destroy()
				soundFolder = nil
			end
		end)

		it("deduplica e armazena templates preparados", function()
			local folder = assert(soundFolder, "sound fixture was not created")
			local preloadCalls = 0
			player = CinematicSoundPlayer.new({
				parent = folder,
				preloadAsync = function(_sounds: { Sound })
					preloadCalls += 1
				end,
				isLoaded = function(_sound: Sound): boolean
					return true
				end,
			})

			expect(player:preload({ "rbxassetid://10", "rbxassetid://10" })).to.equal(true)
			expect(preloadCalls).to.equal(1)
			expect(player:preload({ "rbxassetid://10" })).to.equal(true)
			expect(preloadCalls).to.equal(1)
		end)

		it("agrupa one-shots por execucao", function()
			local folder = assert(soundFolder, "sound fixture was not created")
			player = CinematicSoundPlayer.new({
				parent = folder,
				preloadAsync = function(_sounds: { Sound }) end,
				isLoaded = function(_sound: Sound): boolean
					return true
				end,
			})

			expect(player:preload({ "rbxassetid://10" })).to.equal(true)
			player:play("rbxassetid://10", 1)
			player:play("rbxassetid://10", 2)
			expect(player:getActiveCount(1)).to.equal(1)
			expect(player:getActiveCount(2)).to.equal(1)

			player:stop(1)
			expect(player:getActiveCount(1)).to.equal(0)
			expect(player:getActiveCount(2)).to.equal(1)
		end)
	end)
end

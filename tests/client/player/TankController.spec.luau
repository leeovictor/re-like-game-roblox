--!strict

local fs = require("@lune/fs")
local harness = require("../../support/harness")

local function read(path: string): string
	return fs.readFile(path)
end

local function assertContains(source: string, text: string, message: string): ()
	harness.assert.truthy(string.find(source, text, 1, true), message)
end

harness.describe("TankController", function()
	harness.it("registra as teclas com ContextActionService e consome o controle padrao", function()
		local source = read("src/client/player/TankController.luau")
		assertContains(source, "ContextActionService", "controller must use ContextActionService")
		assertContains(source, "BindActionAtPriority", "controller must bind actions at a priority")
		assertContains(source, "Enum.ContextActionResult.Sink", "tank actions must sink default movement")
		assertContains(source, "Enum.KeyCode.W", "controller must bind W")
		assertContains(source, "Enum.KeyCode.S", "controller must bind S")
		assertContains(source, "Enum.KeyCode.A", "controller must bind A")
		assertContains(source, "Enum.KeyCode.D", "controller must bind D")
	end)

	harness.it("aplica movimento, rotacao e desativa AutoRotate", function()
		local source = read("src/client/player/TankController.luau")
		assertContains(source, "RunService.PreRender", "controller must update every frame")
		assertContains(source, "humanoid:Move", "controller must drive Humanoid movement")
		assertContains(source, "AutoRotate = false", "controller must disable automatic rotation")
		assertContains(source, "CFrame.Angles", "controller must rotate the root part")
	end)

	harness.it("e iniciado pelo cliente", function()
		local source = read("src/client/init.client.luau")
		assertContains(source, "script.player.TankController", "client init must require TankController")
		assertContains(source, "TankController.start()", "client init must start TankController")
	end)
end)

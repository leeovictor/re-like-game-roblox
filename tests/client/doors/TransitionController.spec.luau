--!strict

local Players = game:GetService("Players")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local TransitionController = require(client.doors.TransitionController)

local function waitFor(predicate: () -> boolean): boolean
	local deadline = os.clock() + 3
	while os.clock() < deadline do
		if predicate() then
			return true
		end
		task.wait()
	end
	return predicate()
end

return function()
	describe("TransitionController", function()
		local gui: PlayerGui
		local controller: any

		beforeEach(function()
			gui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
			controller = TransitionController.new(gui)
			controller.start()
		end)

		afterEach(function()
			controller.stop()
			local existing = gui:FindFirstChild("DoorTransitionGui")
			if existing ~= nil then
				existing:Destroy()
			end
		end)

		it("creates one reusable transparent fullscreen fade", function()
			controller.start()
			controller.start()
			local screen = gui:FindFirstChild("DoorTransitionGui") :: ScreenGui
			expect(screen).to.be.ok()
			expect(screen.ResetOnSpawn).to.equal(false)
			expect(screen.IgnoreGuiInset).to.equal(true)
			local fade = screen:FindFirstChild("Fade") :: Frame
			expect(fade).to.be.ok()
			expect(fade.Size).to.equal(UDim2.fromScale(1, 1))
			expect(fade.BackgroundTransparency).to.equal(1)
		end)

		it("runs the request while the fade is opaque and fades back on success", function()
			local observed: number? = nil
			local callbackResult: any = nil
			local accepted = controller.run(function()
				observed = ((gui:FindFirstChild("DoorTransitionGui") :: ScreenGui):FindFirstChild("Fade") :: Frame).BackgroundTransparency
				return { success = true, action = "enter" }
			end, function(result: any)
				callbackResult = result
			end)
			expect(accepted).to.equal(true)
			expect(waitFor(function()
				return callbackResult ~= nil
			end)).to.equal(true)
			expect(observed).to.equal(0)
			expect(((gui:FindFirstChild("DoorTransitionGui") :: ScreenGui):FindFirstChild("Fade") :: Frame).BackgroundTransparency).to.equal(1)
			expect(callbackResult.success).to.equal(true)
		end)

		it("reverts the fade and preserves a failed result", function()
			local callbackResult: any = nil
			controller.run(function()
				return { success = false, reason = "locked" }
			end, function(result: any)
				callbackResult = result
			end)
			expect(waitFor(function()
				return callbackResult ~= nil
			end)).to.equal(true)
			expect(callbackResult.reason).to.equal("locked")
			expect(((gui:FindFirstChild("DoorTransitionGui") :: ScreenGui):FindFirstChild("Fade") :: Frame).BackgroundTransparency).to.equal(1)
			local screen = gui:FindFirstChild("DoorTransitionGui") :: ScreenGui
			expect(#screen:GetChildren()).to.equal(1)
		end)

		it("rejects concurrent runs and stop cancels the active run", function()
			local release = false
			local first = controller.run(function()
				while not release do
					task.wait()
				end
				return { success = true, action = "enter" }
			end, function() end)
			expect(first).to.equal(true)
			expect(controller.run(function()
				return { success = true, action = "enter" }
			end, function() end)).to.equal(false)
			controller.stop()
			release = true
			task.wait()
			expect(((gui:FindFirstChild("DoorTransitionGui") :: ScreenGui):FindFirstChild("Fade") :: Frame).BackgroundTransparency).to.equal(1)
		end)
	end)
end

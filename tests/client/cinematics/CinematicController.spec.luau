--!strict

local Players = game:GetService("Players")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local CinematicController = require(client.cinematics.CinematicController)

type Fixture = {
	waited: { number },
	calls: { string },
	releasedLocks: number,
	preloaded: { { string } },
	active: boolean,
}

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

local function effect(name: string, attributes: any): any
	return {
		name = name,
		attributes = attributes,
	}
end

local function validTimeline(): any
	return {
		{
			frame = 1,
			duration = 0.25,
			effects = {
				effect("play-sound", { soundId = "rbxassetid://10" }),
				effect("set-camera-shot", { shot = "Generator" }),
			},
		},
		{
			frame = 2,
			duration = 0.5,
			effects = {},
		},
	}
end

local function dependenciesFor(fixture: Fixture, waitFunction: ((duration: number) -> ())?): any
	local wait = waitFunction or function(duration: number)
		table.insert(fixture.waited, duration)
	end

	return {
		camera = {
			hasShot = function(shotId: string): boolean
				return shotId == "Default" or shotId == "Generator"
			end,
			setCinematicShot = function(shotId: string): boolean
				table.insert(fixture.calls, "camera:" .. shotId)
				return true
			end,
			clearCinematicShot = function()
				table.insert(fixture.calls, "camera:clear")
			end,
		},
		movement = {
			acquireMovementLock = function(): () -> ()
				table.insert(fixture.calls, "movement:acquire")
				return function()
					fixture.releasedLocks += 1
					table.insert(fixture.calls, "movement:release")
				end
			end,
		},
		sound = {
			preload = function(soundIds: { string }): boolean
				table.insert(fixture.preloaded, table.clone(soundIds))
				table.insert(fixture.calls, "sound:preload")
				return true
			end,
			play = function(soundId: string, _executionId: number)
				table.insert(fixture.calls, "sound:" .. soundId)
			end,
			stop = function(_executionId: number)
				table.insert(fixture.calls, "sound:stop")
			end,
		},
		wait = wait,
	}
end

return function()
	describe("CinematicController", function()
		local controllers: { any } = {}
		local fixtures: { Fixture } = {}

		beforeEach(function()
			controllers = {}
			fixtures = {}
		end)

		afterEach(function()
			for _, fixture in fixtures do
				fixture.active = false
			end
			for _, controller in controllers do
				controller:stop()
			end
			controllers = {}
			fixtures = {}
		end)

		local function newController(waitFunction: ((duration: number) -> ())?): (any, Fixture)
			local fixture: Fixture = {
				waited = {},
				calls = {},
				releasedLocks = 0,
				preloaded = {},
				active = true,
			}
			local controller = CinematicController.new(dependenciesFor(fixture, waitFunction))
			table.insert(controllers, controller)
			table.insert(fixtures, fixture)
			return controller, fixture
		end

		it("rejeita timelines invalidas", function()
			local controller = newController()
			local invalidTimelines = {
				{},
				{ { frame = 2, duration = 0, effects = {} } },
				{ { frame = 1.5, duration = 0, effects = {} } },
				{ { frame = 0 / 0, duration = 0, effects = {} } },
				{ { frame = 1, duration = -1, effects = {} } },
				{ { frame = 1, duration = math.huge, effects = {} } },
				{ { frame = 1, duration = 0, effects = { [1] = effect("play-sound", { soundId = "rbxassetid://10" }), [3] = effect("play-sound", { soundId = "rbxassetid://11" }) } } },
				{ { frame = 1, duration = 0, effects = {}, extra = true } },
				{ { frame = 1, duration = 0, effects = { effect("play-sound", { soundId = "rbxassetid://10" , extra = true }) } } },
				{ { frame = 1, duration = 0, effects = { effect("unknown", {}) } } },
				{ { frame = 1, duration = 0, effects = { effect("set-camera-shot", { shot = "Missing" }) } } },
				{ { frame = 1, duration = 0, effects = { effect("play-sound", { soundId = "https://example.com/10" }) } } },
			}

			for _, timeline in invalidTimelines do
				expect(controller:preload(timeline)).to.equal(false)
			end
		end)

		it("precarrega sem adquirir movimento ou camera", function()
			local controller, fixture = newController()

			expect(controller:preload(validTimeline())).to.equal(true)
			expect(#fixture.preloaded).to.equal(1)
			expect(fixture.releasedLocks).to.equal(0)
			expect(table.find(fixture.calls, "movement:acquire")).to.equal(nil)
			expect(table.find(fixture.calls, "camera:clear")).to.equal(nil)
		end)

		it("precarrega antes dos efeitos e preserva a ordem da timeline", function()
			local controller, fixture = newController()

			expect(controller:play(validTimeline())).to.equal(true)
			expect(waitFor(function()
				return fixture.releasedLocks == 1
			end)).to.equal(true)

			local expectedCalls = {
				"sound:preload",
				"movement:acquire",
				"sound:rbxassetid://10",
				"camera:Generator",
				"camera:clear",
				"movement:release",
			}
			expect(#fixture.calls).to.equal(#expectedCalls)
			for index, call in expectedCalls do
				expect(fixture.calls[index]).to.equal(call)
			end
			expect(#fixture.waited).to.equal(2)
			expect(fixture.waited[1]).to.equal(0.25)
			expect(fixture.waited[2]).to.equal(0.5)
			expect(table.find(fixture.calls, "sound:stop")).to.equal(nil)
		end)

		it("rejeita uma segunda execucao enquanto a primeira esta ocupada", function()
			local fixture: Fixture
			local controller: any
			controller, fixture = newController(function(duration: number)
				table.insert(fixture.waited, duration)
				while fixture.active do
					task.wait()
				end
			end)

			expect(controller:play(validTimeline())).to.equal(true)
			expect(waitFor(function()
				return controller:isPlaying()
			end)).to.equal(true)
			expect(controller:play(validTimeline())).to.equal(false)

			controller:stop()
			fixture.active = false
			task.wait()
			expect(controller:isPlaying()).to.equal(false)
		end)

		it("cancela a geracao atual e interrompe apenas seus efeitos", function()
			local fixture: Fixture
			local controller: any
			controller, fixture = newController(function(duration: number)
				table.insert(fixture.waited, duration)
				while fixture.active do
					task.wait()
				end
			end)
			local timeline = {
			{ frame = 1, duration = 1, effects = { effect("set-camera-shot", { shot = "Generator" }) } },
			{ frame = 2, duration = 0, effects = { effect("play-sound", { soundId = "rbxassetid://10" }) } },
		}

			expect(controller:play(timeline)).to.equal(true)
			expect(waitFor(function()
				return controller:isPlaying()
			end)).to.equal(true)

			controller:stop()
			fixture.active = false
			task.wait()

			expect(controller:isPlaying()).to.equal(false)
			expect(fixture.releasedLocks).to.equal(1)
			expect(table.find(fixture.calls, "camera:clear")).to.be.ok()
			expect(table.find(fixture.calls, "sound:stop")).to.be.ok()
			expect(table.find(fixture.calls, "sound:rbxassetid://10")).to.equal(nil)
		end)
	end)
end

--!strict

return function()
	describe("TestEZ smoke", function()
		it("recebe os servicos Roblox e executa dentro do DataModel", function()
			expect(game:GetService("ReplicatedStorage").Shared).to.be.ok()
			expect(typeof(Vector3.new(1, 2, 3))).to.equal("Vector3")
		end)
	end)
end

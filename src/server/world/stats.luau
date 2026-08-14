local Types = require(script.Parent.types)

-- Conta células "Rock", "Air" e "Outside".
local function countStats(grid: Types.Grid3D): Types.WorldStats
	local solidCells = 0
	local airCells = 0
	local shellCells = 0
	grid:forEachCell(function(_cell, value)
		if value == "Rock" then
			solidCells += 1
		elseif value == "Air" then
			airCells += 1
		elseif value == "Outside" then
			shellCells += 1
		end
	end)
	return {
		totalCells = grid.size.X * grid.size.Y * grid.size.Z,
		solidCells = solidCells,
		shellCells = shellCells,
		airCells = airCells,
	}
end

return {
	countStats = countStats,
}

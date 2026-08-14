local Types = require(script.Parent.Parent.world.types)

-- Caixa delimitadora total do volume de geração (coordenadas de mundo).
export type BoundingBoxDefinition = {
	min: Vector3,
	max: Vector3,
}

-- Cilindro finito ao longo do eixo X.
export type CylinderDefinition = {
	center: Vector3, -- centro do cilindro (eixo passa por center.X)
	lengthStuds: number, -- comprimento total em X
	radiusStuds: number, -- raio no plano YZ
}

-- Plano horizontal (chão) em y fixo, com ruído de baixa amplitude.
export type PlaneDefinition = {
	yStuds: number, -- altura base do piso
	noiseAmplitudeStuds: number, -- perturbação do piso (studs)
	noiseFrequency: number, -- escala do ruído do piso
}

-- Ruído aplicado à parede (entre inner e outer).
export type WallNoiseDefinition = {
	amplitudeStuds: number, -- perturbação do SDF da parede
	frequency: number, -- escala do ruído da parede
}

-- Template completo de uma caverna.
export type CaveTemplate = {
	bounds: BoundingBoxDefinition,
	innerCylinder: CylinderDefinition,
	outerCylinder: CylinderDefinition,
	floorPlane: PlaneDefinition,
	wallNoise: WallNoiseDefinition,
}

-- Configuração operacional da engine (independente da forma).
export type CaveEngineConfig = {
	seed: number,
	resolution: number, -- studs por voxel (fixo: 4)
	shellThicknessStuds: number, -- casca Outside nas bordas da caixa, múltiplo de resolution
}

-- Estatísticas da geração.
export type CaveStats = {
	totalCells: number,
	rockCells: number,
	airCells: number,
	outsideCells: number,
}

-- Resultado da geração.
export type CaveGenerationResult = {
	success: boolean,
	error: string?,
	grid: Types.Grid3D?,
	stats: CaveStats?,
	elapsedSeconds: number,
}

-- Classe da engine.
export type CaveEngine = {
	getSeed: (self: CaveEngine) -> number,
	generate: (self: CaveEngine, template: CaveTemplate) -> CaveGenerationResult,
}

local CaveEngine = {}
CaveEngine.__index = CaveEngine

-- Valida a config. Retorna string de erro ou nil.
-- Config inválida é erro de programação → engine usa error() na construção.
local function validateConfig(config: CaveEngineConfig): string?
	if config == nil then
		return "config não pode ser nil"
	end
	if config.resolution <= 0 then
		return "resolution deve ser > 0"
	end
	if config.shellThicknessStuds < 0 then
		return "shellThicknessStuds deve ser >= 0"
	end
	if config.shellThicknessStuds > 0 then
		if config.shellThicknessStuds % config.resolution ~= 0 then
			return "shellThicknessStuds deve ser múltiplo de resolution"
		end
	end
	return nil
end

-- Valida o template contra a config. Retorna string de erro ou nil.
-- Template pode ser dinâmico → erro retornado (não error()) e reportado no result.
local function validateTemplate(template: CaveTemplate, config: CaveEngineConfig): string?
	if template == nil then
		return "template não pode ser nil"
	end

	-- bounds ------------------------------------------------------------------
	local b = template.bounds
	if b == nil then
		return "bounds não pode ser nil"
	end
	if b.min.X >= b.max.X or b.min.Y >= b.max.Y or b.min.Z >= b.max.Z then
		return "bounds.min deve ser menor que bounds.max em todos os eixos"
	end
	local sizeX = b.max.X - b.min.X
	local sizeY = b.max.Y - b.min.Y
	local sizeZ = b.max.Z - b.min.Z
	if sizeX % config.resolution ~= 0 then
		return "dimensão X da caixa não é múltipla de resolution"
	end
	if sizeY % config.resolution ~= 0 then
		return "dimensão Y da caixa não é múltipla de resolution"
	end
	if sizeZ % config.resolution ~= 0 then
		return "dimensão Z da caixa não é múltipla de resolution"
	end

	-- cilindros ---------------------------------------------------------------
	local inner = template.innerCylinder
	local outer = template.outerCylinder
	if inner == nil then
		return "innerCylinder não pode ser nil"
	end
	if outer == nil then
		return "outerCylinder não pode ser nil"
	end
	if inner.radiusStuds <= 0 then
		return "innerCylinder.radiusStuds deve ser > 0"
	end
	if outer.radiusStuds <= 0 then
		return "outerCylinder.radiusStuds deve ser > 0"
	end
	if outer.radiusStuds <= inner.radiusStuds then
		return "outerCylinder.radiusStuds deve ser > innerCylinder.radiusStuds"
	end
	if inner.lengthStuds <= 0 then
		return "innerCylinder.lengthStuds deve ser > 0"
	end
	if outer.lengthStuds <= 0 then
		return "outerCylinder.lengthStuds deve ser > 0"
	end
	if outer.lengthStuds < inner.lengthStuds then
		return "outerCylinder.lengthStuds deve ser >= innerCylinder.lengthStuds"
	end

	-- coaxiais (mesmo centro YZ)
	if inner.center.Y ~= outer.center.Y or inner.center.Z ~= outer.center.Z then
		return "cilindros devem compartilhar o mesmo centro YZ"
	end

	-- contidos na caixa
	local outerHalfX = outer.lengthStuds / 2
	local outerMinX = outer.center.X - outerHalfX
	local outerMaxX = outer.center.X + outerHalfX
	local outerMinY = outer.center.Y - outer.radiusStuds
	local outerMaxY = outer.center.Y + outer.radiusStuds
	local outerMinZ = outer.center.Z - outer.radiusStuds
	local outerMaxZ = outer.center.Z + outer.radiusStuds
	if outerMinX < b.min.X or outerMaxX > b.max.X then
		return "outerCylinder extrapola bounds em X"
	end
	if outerMinY < b.min.Y or outerMaxY > b.max.Y then
		return "outerCylinder extrapola bounds em Y"
	end
	if outerMinZ < b.min.Z or outerMaxZ > b.max.Z then
		return "outerCylinder extrapola bounds em Z"
	end

	local innerHalfX = inner.lengthStuds / 2
	local innerMinX = inner.center.X - innerHalfX
	local innerMaxX = inner.center.X + innerHalfX
	local innerMinY = inner.center.Y - inner.radiusStuds
	local innerMaxY = inner.center.Y + inner.radiusStuds
	local innerMinZ = inner.center.Z - inner.radiusStuds
	local innerMaxZ = inner.center.Z + inner.radiusStuds
	if innerMinX < b.min.X or innerMaxX > b.max.X then
		return "innerCylinder extrapola bounds em X"
	end
	if innerMinY < b.min.Y or innerMaxY > b.max.Y then
		return "innerCylinder extrapola bounds em Y"
	end
	if innerMinZ < b.min.Z or innerMaxZ > b.max.Z then
		return "innerCylinder extrapola bounds em Z"
	end

	-- espaço para a casca entre outer e cada face da caixa
	local shell = config.shellThicknessStuds
	if shell > 0 then
		local gapX = math.min(outerMinX - b.min.X, b.max.X - outerMaxX)
		local gapY = math.min(outerMinY - b.min.Y, b.max.Y - outerMaxY)
		local gapZ = math.min(outerMinZ - b.min.Z, b.max.Z - outerMaxZ)
		if gapX < shell then
			return "espaço insuficiente entre outerCylinder e bounds em X para a casca"
		end
		if gapY < shell then
			return "espaço insuficiente entre outerCylinder e bounds em Y para a casca"
		end
		if gapZ < shell then
			return "espaço insuficiente entre outerCylinder e bounds em Z para a casca"
		end
	end

	-- interior após a casca não vazio
	if 2 * shell >= math.min(sizeY, sizeZ) then
		return "caixa pequena demais: interior após casca seria vazio"
	end

	-- plano (chão) ------------------------------------------------------------
	local floor = template.floorPlane
	if floor == nil then
		return "floorPlane não pode ser nil"
	end
	if floor.noiseAmplitudeStuds < 0 then
		return "floorPlane.noiseAmplitudeStuds deve ser >= 0"
	end
	if floor.noiseFrequency <= 0 then
		return "floorPlane.noiseFrequency deve ser > 0"
	end
	if floor.yStuds < outerMinY or floor.yStuds > outerMaxY then
		return "floorPlane.yStuds deve estar dentro da altura do outerCylinder"
	end

	-- ruído da parede ----------------------------------------------------------
	local wn = template.wallNoise
	if wn == nil then
		return "wallNoise não pode ser nil"
	end
	if wn.amplitudeStuds < 0 then
		return "wallNoise.amplitudeStuds deve ser >= 0"
	end
	if wn.amplitudeStuds > outer.radiusStuds - inner.radiusStuds then
		return "wallNoise.amplitudeStuds deve ser <= (outerRadius - innerRadius)"
	end
	if wn.frequency <= 0 then
		return "wallNoise.frequency deve ser > 0"
	end

	return nil
end

-- Constrói a engine. Guarda config, seed e Random.new(seed) (determinismo).
function CaveEngine.new(config: CaveEngineConfig): CaveEngine
	local err = validateConfig(config)
	if err then
		error(err, 2)
	end

	local self = setmetatable({
		config = config,
		seed = config.seed,
		random = Random.new(config.seed),
	}, CaveEngine)

	return self
end

-- Retorna a seed da engine.
function CaveEngine:getSeed(): number
	return self.seed
end

-- Implementado na task 4.
function CaveEngine:generate(_template: CaveTemplate): CaveGenerationResult
	error("generate ainda não implementado")
end

return CaveEngine

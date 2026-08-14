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

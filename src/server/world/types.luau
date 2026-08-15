--!strict

-- Material de uma célula do grid lógico.
export type GridCell = "Rock" | "Air" | "Outside"
-- "Rock"    : sólido gerado
-- "Air"     : vazio esculpido (passos futuros: salas, túneis)
-- "Outside" : casca externa protegida, nunca esculpida

-- Representação canônica do mundo em memória. Todo o pipeline lógico opera
-- sobre esta estrutura; o Terrain é escrito apenas na etapa final.
export type Grid3D = {
	-- Metadados
	resolution: number, -- studs por voxel (fixo: 4)
	minCell: Vector3int16, -- célula mínima (1, 1, 1)
	size: Vector3int16, -- tamanho em células (32, 16, 32)
	worldMin: Vector3, -- canto mínimo em studs (-64, -84, -64)
	worldMax: Vector3, -- canto máximo em studs (64, -20, 64)
	center: Vector3, -- centro do volume (0, -52, 0)

	-- Armazenamento: cells[x][y][z], cada eixo indexado de 1..size
	cells: { { { GridCell } } },

	-- Métodos (implementados em grid.luau)
	worldToCell: (self: Grid3D, position: Vector3) -> Vector3int16?,
	cellToWorld: (self: Grid3D, cell: Vector3int16) -> Vector3,
	inBounds: (self: Grid3D, cell: Vector3int16) -> boolean,
	setCell: (self: Grid3D, cell: Vector3int16, value: GridCell) -> (),
	getCell: (self: Grid3D, cell: Vector3int16) -> GridCell,
	forEachCell: (self: Grid3D, callback: (cell: Vector3int16, value: GridCell) -> ()) -> (),
	toDebugString: (self: Grid3D) -> string,
}

-- Configuração completa do mundo. Os valores entre parênteses são os do
-- protótipo de teste.
export type WorldConfig = {
	seed: number, -- semente determinística (1337)
	resolution: number, -- studs por voxel (4)
	mapSizeStuds: Vector3, -- lados múltiplos de resolution (128, 64, 128)
	worldCenter: Vector3, -- centro do volume (0, -52, 0)
	shellThicknessStuds: number, -- casca externa, múltiplo de resolution (12)
	writeToTerrain: boolean, -- se true, escreve o grid no Terrain ao final (true)
	writeChunkSizeCells: number?, -- células por eixo em cada WriteVoxels (default 64)

	-- Categorias de salas (passo 2)
	pitProbability: number, -- chance de cada sala (exceto a âncora) ser um fosso (0.15)
	pitRadiusStuds: number, -- raio horizontal do fosso em studs (45)
	pitNoiseAmplitude: number, -- rugosidade da superfície das paredes do fosso (0.18)
	pitNoiseFrequency: number, -- escala do ruído do fosso (0.08)

	-- Geração de salas (passo 2)
	roomCount: number, -- nº de salas desejado (8)
	roomRadiusMin: number, -- raio base mínimo em studs (40)
	roomRadiusMax: number, -- raio base máximo em studs (80)
	roomMinSpacingStuds: number, -- distância mínima entre centros (120)
	roomPlacementAttempts: number, -- tentativas máx. de posicionar cada sala (200)
	roomVerticalScale: number, -- achatamento em Y; 1 = esfera (0.7)
	roomNoiseAmplitude: number, -- perturbação relativa do raio, >= 0 (0.15)
	roomNoiseFrequency: number, -- escala do ruído, > 0 (0.04)

	-- Geração de túneis (passo 3)
	tunnelRadiusStuds: number, -- raio base do túnel em studs (16)
	tunnelConnectRatio: number, -- fração das salas (excl. sala 1) na rede (0.75)
	tunnelLoopProbability: number, -- chance de aresta extra (loop) na rede (0.2)
	tunnelStepStuds: number, -- espaçamento de amostragem do caminho (8)
	tunnelJitterAmplitude: number, -- limite do desvio acumulado do caminho (20)
	tunnelNoiseAmplitude: number, -- variação relativa do raio (0.25)
	tunnelNoiseFrequency: number, -- escala do ruído do raio (0.06)
}

-- Categoria de uma sala gerada.
export type RoomKind = "standard" | "pit"
-- "standard": sala orgânica de blobs (carveRoom)
-- "pit"     : fosso vertical que atravessa o interior, sem fundo visível (carvePit)

-- Dados de uma sala gerada (usado pelo futuro passo de túneis).
export type RoomData = {
	index: number, -- 1-based, ordem de criação
	centerCell: Vector3int16, -- centro da sala em células
	centerWorld: Vector3, -- grid:cellToWorld(centerCell)
	radiusStuds: number, -- raio base sorteado da sala
	kind: RoomKind, -- categoria da sala
}

export type RoomsResult = {
	success: boolean,
	error: string?, -- mensagem se success == false
	rooms: { RoomData }?, -- nil se falhou; pode ter menos que roomCount
	airCells: number?, -- total de células "Air" no grid após o carve
	elapsedSeconds: number,
}

-- Aresta entre duas salas conectadas.
export type TunnelEdge = {
	a: RoomData, -- extremidade 1
	b: RoomData, -- extremidade 2
}

export type TunnelsResult = {
	success: boolean,
	error: string?, -- mensagem se success == false
	edges: { TunnelEdge }?, -- arestas esculpidas (nil se falhou)
	connectedRooms: { RoomData }?, -- salas que entraram na rede
	isolatedRooms: { RoomData }?, -- salas fora da rede (sem túnel)
	airCells: number?, -- total de células "Air" após o carve
	elapsedSeconds: number,
}

export type WorldStats = {
	totalCells: number, -- 16.384
	solidCells: number, -- células "Rock" (interior: 6.760)
	shellCells: number, -- células "Outside" (casca: 9.624)
	airCells: number, -- células "Air" esculpidas
}

export type GenerationResult = {
	success: boolean,
	error: string?, -- mensagem se success == false
	elapsedSeconds: number, -- tempo total (lógica + escrita, se aplicável)
	writeSeconds: number?, -- tempo da escrita no Terrain (se writeToTerrain)
	grid: Grid3D?, -- nil se falhou
	stats: WorldStats?,
}

return {}

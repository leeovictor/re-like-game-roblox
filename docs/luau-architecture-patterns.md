# Padroes de Arquitetura Luau

Este documento define como novos modulos de gameplay devem ser estruturados no
projeto Roblox. Ele combina os padroes de scripting usados no projeto com as
ideias do guia [Luau Scripting Patterns: Clean Architecture for Roblox Game
Code](https://simplified.media/guides/luau-scripting-patterns).

Estas regras se aplicam principalmente a novos managers, controllers e services
client-side. Modulos existentes nao precisam ser migrados apenas por causa deste
documento. Quando um modulo existente for alterado, aplique estas regras a
parte modificada sem alterar contratos de comportamento fora do escopo da
tarefa.

## 1. Escolha a forma mais simples

Antes de criar um modulo, decida se ele representa um sistema unico, uma
entidade com varias instancias ou apenas uma biblioteca:

- Use o padrao de modulo para um sistema que deve ter uma unica instancia
  logica por sessao.
- Use uma classe Luau apenas quando varias instancias independentes precisarem
  existir simultaneamente em runtime.
- Use um modulo puro para transformar entradas em saidas ou fornecer dados sem
  manter estado mutavel de runtime.
- Use componentes quando comportamentos independentes precisarem ser
  combinados em varias entidades.

Nao use classes, constructors ou hierarquias de heranca por convencao. Cada
abstracao deve resolver uma necessidade concreta de isolamento, composicao ou
reuso.

## 2. Modulo padrao para singletons

Managers, controllers e services de instancia unica devem retornar uma tabela
com funcoes publicas. O estado privado pode permanecer no escopo do modulo,
pois o Roblox reutiliza o valor retornado por `require()`:

```luau
-- InventoryController.luau
local InventoryController = {}

local items: { [string]: number } = {}

function InventoryController.start(): ()
	-- Inicializa conexoes e tarefas do sistema, se necessario.
end

function InventoryController.getItemCount(itemId: string): number
	return items[itemId] or 0
end

function InventoryController.addItem(itemId: string, amount: number): ()
	items[itemId] = InventoryController.getItemCount(itemId) + amount
end

return InventoryController
```

Regras para esse formato:

- Use funcoes com `.` e nao metodos de instancia com `:`.
- Mantenha tabelas, conexoes e detalhes de implementacao fora da API publica.
- Exporte tipos pelo proprio modulo quando consumidores precisarem deles.
- Mantenha `--!strict` em modulos Luau.
- Torne `start`, `stop`, `init` ou funcoes equivalentes idempotentes quando o
  modulo criar conexoes, listeners ou tarefas.
- Inclua cleanup explicito para recursos criados pelo modulo.
- Nao crie um `new()` que apenas embrulha um singleton em uma tabela.

O fato de o `require()` ser cacheado nao substitui a regra de descoberta entre
sistemas client-side. Esses modulos devem ser registrados no locator descrito
na secao 4.

## 3. Quando usar uma classe

Use uma classe Luau com metatable quando o jogo precisa de varias instancias
com o mesmo contrato, mas com estado completamente independente. Cada
instancia deve possuir seu proprio estado, conexoes e lifecycle.

`src/client/enemies/Enemy.luau` e o exemplo de referencia: a partida pode ter
varios inimigos ao mesmo tempo e cada inimigo possui um model, estado atual,
pathfinding, timers e sinais proprios.

```luau
local Enemy = {}
Enemy.__index = Enemy

function Enemy.new(model: Model): Enemy
	return setmetatable({
		model = model,
		destroyed = false,
	}, Enemy)
end

function Enemy.update(self: Enemy, dt: number): ()
	if self.destroyed then
		return
	end

	-- Atualiza somente esta instancia.
end

function Enemy.destroy(self: Enemy): ()
	if self.destroyed then
		return
	end

	self.destroyed = true
	self.model:Destroy()
end
```

Uma classe e adequada quando:

- varias entidades do mesmo tipo existem simultaneamente;
- cada entidade tem estado mutavel independente;
- o caller precisa criar e destruir entidades durante o jogo;
- o lifecycle da entidade nao coincide com o lifecycle do sistema inteiro.

Uma classe nao e adequada apenas porque um modulo possui varias funcoes ou
porque o nome termina com `Controller`, `Manager` ou `Service`.

## 4. Locator para runtime client-side

O locator em `src/shared/locator/` e o registro central para controllers e
services client-side de instancia unica. O bootstrap deve carregar, inicializar
e registrar cada modulo antes de conectar handlers que dependam dele.

O bootstrap atual e `src/client/init.client.luau`:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Locator = require(ReplicatedStorage.Shared.locator.locator)
local InventoryController = require(
	StarterPlayer.StarterPlayerScripts.Client.inventory.InventoryController
)

InventoryController.start()
Locator.register("InventoryController", InventoryController)
```

Um consumidor client-side deve obter outro controller ou service pelo locator:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locator = require(ReplicatedStorage.Shared.locator.locator)
local InventoryTypes = require(
	ReplicatedStorage.Shared.inventory.InventoryTypes
)

local inventory = Locator.get<InventoryTypes.Api>("InventoryController")
local count = inventory.getItemCount("medkit")
```

Regras do locator:

- Registre cada singleton uma unica vez.
- Use nomes estaveis, descritivos e consistentes com o modulo registrado.
- Registre no bootstrap, nao dentro de um consumidor.
- Consulte o locator somente para servicos/controllers de runtime registrados.
- Modulos puros, configuracoes, tipos e pacotes devem continuar usando
  `require()` direto.
- Nao crie uma nova instancia quando o locator ja fornece o sistema.
- Nao use caminhos alternativos de `require()` para obter o mesmo singleton em
  consumidores client-side.
- Registre dependencias antes de conectar handlers que as utilizam.

O locator reduz o acoplamento ao caminho fisico dos modulos, mas nao deve ser
usado para esconder todas as dependencias. A API publica ainda deve ser pequena
e clara, e a ordem de inicializacao deve permanecer visivel no bootstrap.

## 5. Modulos puros e composicao

Modulos puros nao possuem estado de runtime compartilhado. Eles podem ser
importados diretamente por qualquer consumidor que precise da mesma logica:

```luau
local function clamp(value: number, minimum: number, maximum: number): number
	return math.max(minimum, math.min(maximum, value))
end

return {
	clamp = clamp,
}
```

A composicao de sistemas deve acontecer no bootstrap ou em uma camada de
coordenacao claramente identificada. Nao crie um controller default dentro de
outro controller e nao procure uma dependencia dinamicamente durante cada
operacao quando ela puder ser registrada e consultada pelo locator.

Para client-side, os imports devem seguir o mapeamento do projeto:

- modulos client-side usam caminhos absolutos a partir de
  `StarterPlayer.StarterPlayerScripts.Client`;
- modulos shared e pacotes usam `ReplicatedStorage`;
- confirme `default.project.json` antes de alterar um caminho de `require()`.

## 6. Observer e signals

Use o padrao observer quando um evento precisar ser consumido por varios
sistemas sem que o produtor conheca todos os consumidores. Use sinais Roblox,
`BindableEvent` ou o pacote `Signal` conforme o escopo e o contrato do evento.

```luau
local Signal = require(ReplicatedStorage.Packages.Signal)

local PickupManager = {}
PickupManager.collected = Signal.new()

function PickupManager.collect(itemId: string): ()
	PickupManager.collected:Fire(itemId)
end

return PickupManager
```

Regras:

- O produtor publica um evento com um contrato claro.
- Consumidores se inscrevem sem importar detalhes internos do produtor quando o
  locator ou o contrato compartilhado ja forem suficientes.
- Armazene todas as conexoes criadas por uma entidade ou sistema.
- Desconecte conexoes no cleanup ou no lifecycle correspondente.
- Prefira uma chamada direta quando existem apenas dois sistemas conhecidos e
  nao ha necessidade de desacoplamento.
- Use closures quando um callback precisar preservar um modulo ou uma
  instancia especifica.

Signals nao devem ser usados para esconder uma chamada obrigatoria ou para
substituir uma API direta sem necessidade.

## 7. State machines

Use uma state machine quando um sistema possuir modos de comportamento
distintos e transicoes observaveis. Exemplos incluem IA de inimigos, fases de
uma rodada, combate, portas e fluxos de interface.

Uma implementacao simples usa handlers indexados pelo estado atual:

```luau
local RoundManager = {}

local currentState = "WaitingForPlayers"

local stateHandlers = {
	WaitingForPlayers = function(context: RoundContext): string?
		if context.playerCount >= 2 then
			return "Countdown"
		end
		return nil
	end,
	Countdown = function(context: RoundContext): string?
		if context.timeRemaining <= 0 then
			return "InProgress"
		end
		return nil
	end,
}

function RoundManager.update(context: RoundContext): ()
	local handler = stateHandlers[currentState]
	if handler == nil then
		warn("[RoundManager] invalid state: " .. currentState)
		return
	end

	local nextState = handler(context)
	if nextState ~= nil then
		currentState = nextState
	end
end

return RoundManager
```

Regras:

- Nomeie os estados explicitamente.
- Mantenha a transicao em um unico lugar quando possivel.
- Valide estados desconhecidos e transicoes invalidas.
- Use logs com contexto para investigar sistemas presos em um estado.
- Nao use uma state machine para um fluxo que possui apenas uma decisao simples.

Quando a state machine pertence a uma entidade com varias instancias, o estado
atual deve ficar na instancia da classe, nao em uma tabela global compartilhada.

## 8. Component architecture

Use componentes para dividir comportamentos que podem ser combinados em varias
entidades. Exemplos sao `HealthComponent`, `MovementComponent` e
`CombatComponent`.

Um componente deve ter uma responsabilidade clara e uma API pequena. Ele pode
ser um modulo puro, um modulo singleton ou uma classe, dependendo de quantas
instancias independentes existirem. Nao introduza uma classe base ou um
framework de componentes apenas para padronizar nomes.

Componentes devem se comunicar por contratos diretos ou signals quando isso
reduzir acoplamento. Ao destruir uma entidade, destrua tambem os componentes,
desconecte sinais e remova referencias que mantem objetos vivos.

Use component architecture quando:

- comportamentos precisam ser reutilizados por entidades diferentes;
- entidades precisam de combinacoes diferentes de comportamentos;
- separar responsabilidades reduz um modulo monolitico.

Evite componentes para uma entidade pequena, fixa e que nunca sera composta
com outras capacidades.

## 9. Data-driven design

Separe dados de configuracao da logica sempre que o conteudo variar sem mudar o
algoritmo. Itens, inimigos, objetivos, sons e configuracoes devem ser tabelas
de dados quando apropriado:

```luau
return {
	Medkit = {
		displayName = "Medkit",
		maxStack = 3,
		useAction = "Heal",
	},
	Keycard = {
		displayName = "Keycard",
		maxStack = 1,
		useAction = "UnlockDoor",
	},
}
```

Regras:

- Coloque definicoes em modulos de dados separados da logica de runtime.
- Use ids estaveis para referenciar dados.
- Valide dados importantes no startup quando uma entrada invalida impedir o
  sistema de funcionar corretamente.
- Nao crie uma tabela de configuracao para um valor unico que nunca sera
  reutilizado.
- Evite duplicar a mesma definicao em controllers diferentes.

## 10. Error handling e observabilidade

Use `pcall` ou `xpcall` nas fronteiras que podem falhar, como DataStore,
HttpService, carregamento de assets e processamento de input nao confiavel.
Depois de uma falha, escolha explicitamente entre retry, fallback, degradacao
graciosa ou encerramento do recurso.

```luau
local success, result = pcall(function()
	return dataStore:GetAsync(key)
end)

if not success then
	warn(string.format(
		"[DataService] GetAsync failed key=%s error=%s",
		key,
		tostring(result)
	))
	return nil
end

return result
```

Regras:

- Inclua o nome do sistema e a operacao no log.
- Inclua a entidade relevante, como player, item ou inimigo, quando seguro e
  util.
- Nao use `pcall` para esconder erros de programacao previsiveis.
- Nao permita que um loop principal morra silenciosamente por uma excecao nao
  tratada.
- Combine tratamento de erro com tipos Luau e `--!strict`.

## 11. Anti-padroes

Evite:

- usar `new()` e metatables para todo controller, manager ou service;
- criar multiplas instancias de um sistema que deveria ser singleton;
- acessar um singleton client-side por `require()` direto em cada consumidor em
  vez do locator;
- registrar o mesmo nome mais de uma vez;
- esconder dependencias essenciais em lookups dinamicos durante uma operacao;
- compartilhar estado mutavel entre instancias de uma classe;
- passar um metodo de instancia como callback sem preservar o receptor;
- manter conexoes, sinais ou tarefas depois do cleanup;
- usar signals para chamadas diretas simples;
- transformar toda logica condicional em state machine;
- criar componentes ou camadas de dados sem reuso ou variacao real;
- envolver cada funcao em `pcall` sem uma fronteira que possa falhar;
- usar Parallel Luau como parte deste padrao sem uma decisao arquitetural
  especifica e validacao de performance.

## 12. Checklist para novos modulos

Antes de adicionar um novo controller, manager ou service, confirme:

- Este modulo precisa de uma unica instancia ou de varias instancias?
- Se for singleton, ele retorna uma tabela de funcoes e evita `new()`?
- Se for uma classe, cada instancia possui estado e cleanup independentes?
- O modulo sera registrado no locator se for um singleton de runtime client-side?
- Consumidores client-side usam `Locator.get()` para obter esse singleton?
- O bootstrap torna a ordem de inicializacao explicita?
- Events e signals sao realmente necessarios para o nivel de desacoplamento?
- Uma state machine ou component architecture resolve um problema concreto?
- Dados variaveis estao separados da logica?
- Fronteiras que podem falhar possuem tratamento de erro adequado?
- Conexoes, tarefas, Instances e sinais possuem cleanup?

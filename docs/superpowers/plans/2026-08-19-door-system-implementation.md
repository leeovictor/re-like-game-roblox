# Sistema de Portas e Transicoes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar portas configuraveis, desbloqueio por item, travessia server-authoritative, deteccao client-side e transicao visual ao jogo.

**Architecture:** A primeira task entrega os contratos compartilhados e uma `StudioDoorScene` visivel em Play, sem implementar interacao. A segunda task implementa toda a autoridade server-side e integra a cena ao bootstrap. A terceira task implementa deteccao, input, dialogos e fade client-side, consumindo os contratos sem redefini-los. As tasks sao executadas sequencialmente em tres sessoes.

**Tech Stack:** Luau `--!strict`, Roblox `CollectionService`, `WorldRoot:Shapecast`, `RemoteFunction`, `TweenService`, React/ReactRoblox ja existentes, Rojo 7.7.0, Selene 0.29.0, luau-lsp 1.69.0 e TestEZ executado no Roblox Studio.

## Global Constraints

- Executar exatamente tres tasks e na ordem `DoorTestScene`, `server`, `client`; nao paralelizar.
- A Task 1 e dona dos tipos e constantes compartilhados e de `InteractDoor`; Tasks 2 e 3 apenas consomem esse contrato.
- `src/server/init.server.luau` e o unico seam de integracao compartilhado: a Task 1 adiciona a criacao da cena e a Task 2 acrescenta o `DoorService` sem remover nem mover essa chamada.
- `StudioDoorScene` so e chamada quando `RunService:IsStudio()` e cria objetos runtime-only em `Workspace.DoorTestScene`.
- A fixture da cena nao cria pickups, nao altera inventario, nao cria prompts e nao implementa teleporte ou input.
- O servidor e a unica autoridade para validar acoes, alterar `DoorModel.Locked` e teleportar personagens.
- A chave exigida nunca e consumida; o desbloqueio dura apenas durante o servidor atual.
- O cliente envia somente `{ door = doorModel, action = "unlock" | "enter" }` para `InteractDoor`.
- `RequiredItemId`, `Locked` e efeitos de item enviados pelo cliente nunca sao tratados como autoridade.
- A deteccao usa ShapeCast com `PROBE_OFFSET = 2.5` e `PROBE_SIZE = Vector3.new(4, 5, 3)`; nao adicionar uma segunda verificacao client-side de distancia.
- A tecla de interacao e `F`. Enquanto o `DialogueController` estiver ativo, ele continua consumindo `F`.
- `TransitionController` usa uma unica constante `TRANSITION_SOUND_ID = ""`; nenhum `Sound` e criado enquanto ela estiver vazia.
- Nao criar specs de React/UI nem spec separado para `StudioDoorScene`; a cena sera verificada manualmente em Play.
- Todos os modulos e specs novos permanecem `--!strict`; nao usar `--!nocheck`, ignores amplos ou tipos globais para esconder diagnosticos.
- Nao editar `Packages/` ou `DevPackages/`.
- `test.project.json` continua sem iniciar `src/server/init.server.luau` ou `src/client/init.client.luau`.
- Specs que criam Instances, conexoes ou estado mutavel devem criar fixtures isoladas em `beforeEach` e limpar tudo em `afterEach`.
- Nao usar `git add .`; preservar arquivos nao relacionados, incluindo o spec de design nao rastreado se ele continuar nessa situacao.

## File Map

| Arquivo | Task | Responsabilidade |
|---|---:|---|
| `src/shared/doors/doorTypes.luau` | 1 | Constantes de autoria e tipos de request/result compartilhados |
| `src/shared/remotes.luau` | 1 | Criacao/reuso do `InteractDoor` `RemoteFunction` |
| `src/server/doors/StudioDoorScene.luau` | 1 | Fixture visual idempotente, sem logica de portas |
| `src/server/init.server.luau` | 1 e 2 | Criacao Studio da fixture; depois composicao do servidor de portas |
| `test.project.json` | 1 e 3 | Mapeamento de `server/doors`; depois mapeamento de `client/doors` |
| `src/server/doors/DoorUnlockBehavior.luau` | 2 | Behavior `unlock` de validacao do item sem consumo |
| `src/server/doors/DoorService.luau` | 2 | Autoridade, validacao, desbloqueio, travessia e binding remoto |
| `tests/server/doors/DoorService.spec.luau` | 2 | Contrato server-side e integracao com ItemUseService |
| `src/client/doors/TransitionController.luau` | 3 | Fade, reversao, audio opcional e lifecycle |
| `src/client/doors/DoorController.luau` | 3 | ShapeCast, F, inventario local, dialogos e requests |
| `tests/client/doors/TransitionController.spec.luau` | 3 | Fade, audio vazio e reversao |
| `tests/client/doors/DoorController.spec.luau` | 3 | Deteccao e decisao do fluxo client-side |
| `src/client/init.client.luau` | 3 | Inicializacao dos dois controladores |
| `README.md` | 3 | Inclusao dos diretorios de portas no comando de typecheck |

## Task 1: DoorTestScene And Shared Contract

**Objetivo da sessao:** ao final desta task, um Play Studio no projeto normal cria tres portas visiveis no `Workspace`, sem permitir ainda qualquer interacao de porta. A task tambem deixa estavel o contrato que server e client consumirao.

**Files:**
- Create: `src/shared/doors/doorTypes.luau`
- Modify: `src/shared/remotes.luau`
- Create: `src/server/doors/StudioDoorScene.luau`
- Modify: `src/server/init.server.luau` para chamar a cena somente no Studio
- Modify: `test.project.json` para mapear `src/server/doors`
- Test manually: `Workspace.DoorTestScene` em Play no projeto normal

**Interfaces:**
- Produces `DoorAction`, `DoorFailureReason`, `DoorRequest`, `DoorActionResult` e as constantes de nomes/atributos usadas por todas as tasks.
- Produces `StudioDoorScene.create(): ()`.
- Produces `ReplicatedStorage.Remotes.InteractDoor` como `RemoteFunction`; a Task 2 sera dona do binding server e a Task 3 sera consumidora client.
- Does not consume `DoorService`, `DoorController`, `TransitionController` ou qualquer behavior de inventario.

- [ ] **Step 1: Define the shared door contract before implementing the fixture**

Criar `src/shared/doors/doorTypes.luau` com `--!strict`. O modulo deve retornar as constantes runtime e exportar os tipos abaixo. Nao colocar regra de distancia, teleport ou inventario nesse arquivo.

```lua
--!strict

export type DoorAction = "unlock" | "enter"

export type DoorFailureReason =
	"invalid_door"
	| "too_far"
	| "ambiguous_side"
	| "locked"
	| "already_unlocked"
	| "missing_item"
	| "busy"
	| "invalid_config"

export type DoorRequest = {
	door: Model,
	action: DoorAction,
}

export type DoorActionResult = {
	success: boolean,
	reason: DoorFailureReason?,
	action: DoorAction?,
}

return {
	DOOR_TAG = "Door",
	DOORWAY_NAME = "Doorway",
	CENTER_NAME = "Center",
	LOCKED_DIALOGUE_NAME = "LockedDialogue",
	LOCKED_ATTRIBUTE = "Locked",
	REQUIRED_ITEM_ID_ATTRIBUTE = "RequiredItemId",
	FALLBACK_LOCKED_MESSAGE = "Porta trancada.",
}
```

Usar os tipos atraves do modulo real, por exemplo `type DoorActionResult = doorTypes.DoorActionResult`, para que o sourcemap Roblox resolva a mesma definicao em server e client.

- [ ] **Step 2: Add the shared remote without binding behavior**

Adicionar somente a entrada abaixo ao retorno de `src/shared/remotes.luau`:

```lua
InteractDoor = _ensureRemote("InteractDoor", "RemoteFunction"),
```

Manter a validacao existente de classe. Nao adicionar `OnServerInvoke`, `OnClientInvoke`, `RemoteEvent` de estado ou qualquer atributo remoto. Os atributos `Locked` e `RequiredItemId` continuam sendo a comunicacao replicada de estado.

- [ ] **Step 3: Write the idempotent scene builder**

Criar `StudioDoorScene.create()` em `src/server/doors/StudioDoorScene.luau`.

Implementar nesta ordem:

1. Procurar `Workspace:FindFirstChild("DoorTestScene")` antes de criar qualquer instancia.
2. Se nao existir, criar uma `Folder` chamada `DoorTestScene`.
3. Se existir e nao for `Folder`, falhar com erro explicito `Workspace.DoorTestScene must be a Folder`.
4. Criar tres `Model`s filhos da pasta, adicionar a tag `Door` com `CollectionService:AddTag` e aplicar os atributos `Locked` e `RequiredItemId`.
5. Criar em cada modelo um `Doorway` `Part` ancorado, com colisao habilitada, `Center` `Attachment` filho direto e orientacao consistente do eixo Z.
6. Criar `LockedDialogue` apenas em `MissingKeyDoor` e `KeyDoor`, com `StringValue`s diretos chamados `01_Locked` e `02_Hint`.
7. Criar piso, paredes baixas e partes de apoio com nomes que nao sejam `Doorway` e sem adicionar a tag `Door`.
8. Parentear a pasta completa em `Workspace` depois que seus filhos estiverem configurados, evitando que uma fixture parcial seja observada.

Usar configuracao fixa em uma tabela local. Os tres modelos devem ter estes valores:

| Modelo | `Locked` | `RequiredItemId` | Cor/posicao |
|---|---:|---|---|
| `MissingKeyDoor` | `true` | `iron_key` | corredor esquerdo, cor vermelha |
| `KeyDoor` | `true` | `iron_key` | corredor central, cor dourada |
| `OpenDoor` | `false` | `""` | corredor direito, cor verde |

As posicoes exatas podem ser constantes do modulo, mas devem ser fixas, separadas o suficiente para o jogador abordar cada porta e alinhadas ao mesmo plano de teste. Usar dimensoes do `Doorway` que deixem `Center` no plano de passagem e a altura da abertura compativel com o personagem.

Para os dialogos usar texto nao vazio, por exemplo:

```text
MissingKeyDoor/01_Locked = "A porta esta trancada."
MissingKeyDoor/02_Hint = "Procure uma chave de ferro."
KeyDoor/01_Locked = "A porta exige uma chave de ferro."
KeyDoor/02_Hint = "Use F depois de encontrar a chave."
```

Nao criar `ProximityPrompt`, `ScreenGui`, `Sound`, pickup, atributo de destino ou conexao de input.

- [ ] **Step 4: Integrate scene creation into the current server bootstrap**

Adicionar o require de `StudioDoorScene` e, imediatamente depois de `pickupService:start()`, adicionar:

```lua
if RunService:IsStudio() then
	StudioDoorScene.create()
end
```

Nao criar ainda `DoorService`. A chamada deve ficar no bootstrap para que a primeira task seja verificavel em Play e para que a Task 2 possa inserir o service depois dela. A Task 2 deve preservar a ordem `PickupService:start()` -> `StudioDoorScene.create()` -> `DoorService:start()`.

- [ ] **Step 5: Map the server door directory in the test project**

Adicionar `doors` ao mesmo nivel de `inventory`, `items` e `pickups` em `ServerScriptService.Server` dentro de `test.project.json`:

```json
"doors": {
  "$path": "src/server/doors"
}
```

Esse mapeamento permite que a Task 2 carregue `DoorService` e permite a verificacao direta da fixture no DataModel de teste, sem iniciar `init.server.luau`.

- [ ] **Step 6: Run the isolated static checks for the scene task**

Executar:

```bash
selene --config selene.roblox.toml src/shared/doors src/server/doors
rojo build -o /tmp/dungeon-game-canve-door-scene.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-door-scene-test.rbxlx test.project.json
```

Esperado: exit code `0` nos tres comandos, com o modulo da cena e o contrato presentes nos dois sourcemaps correspondentes.

- [ ] **Step 7: Verify the scene visually and verify idempotence**

Iniciar Play no projeto normal, esperar o servidor, e no DataModel `Server` verificar `Workspace.DoorTestScene`.

Confirmar:

- `MissingKeyDoor`, `KeyDoor` e `OpenDoor` aparecem uma vez;
- cada modelo tem a tag `Door`, `Doorway` e `Doorway.Center`;
- os atributos correspondem a tabela;
- as duas portas trancadas possuem dois `StringValue`s diretos;
- nenhum pickup foi criado pela cena;
- chamar `require(game.ServerScriptService.Server.doors.StudioDoorScene).create()` uma segunda vez nao cria uma segunda pasta;
- parar Play remove a pasta runtime-only;
- um Play novo recria exatamente uma pasta e tres portas.

Nao testar desbloqueio ou travessia nesta task; o remote ainda nao possui handler server.

- [ ] **Step 8: Commit only the first task files**

Quando os checks e a verificacao manual passarem, o commit da primeira sessao deve incluir somente:

```bash
git add src/shared/doors/doorTypes.luau src/shared/remotes.luau src/server/doors/StudioDoorScene.luau src/server/init.server.luau test.project.json
git commit -m "feat: add studio door test scene"
```

Nao usar `git add .` e nao incluir specs, README ou modulos de server/client ainda inexistentes.

## Task 2: Server Door Authority

**Objetivo da sessao:** implementar o `DoorService`, validar toda acao no servidor, integrar o behavior de unlock sem consumo e deixar o fluxo `InteractDoor` testado no TestEZ server. A fixture da Task 1 deve continuar aparecendo antes do service iniciar.

**Files:**
- Create: `src/server/doors/DoorUnlockBehavior.luau`
- Create: `src/server/doors/DoorService.luau`
- Create: `tests/server/doors/DoorService.spec.luau`
- Modify: `src/server/init.server.luau` para registrar o behavior e iniciar o service
- Use existing: `src/shared/doors/doorTypes.luau`, `src/shared/remotes.luau`, `src/server/items/ItemUseService.luau`, `src/server/items/ItemBehaviorRegistry.luau`
- Do not modify: `StudioDoorScene.luau` or any client file

**Interfaces:**
- Consumes `StudioDoorScene.create()`, `doorTypes.DoorRequest`, `doorTypes.DoorActionResult` and `remotes.InteractDoor` from Task 1.
- Produces `DoorService.new(itemUseService): Service`, with idempotent `start()` and `stop()` methods.
- Produces `DoorUnlockBehavior.create(): ItemBehavior` for registration before the service starts.
- `InteractDoor.OnServerInvoke` accepts untrusted data and returns a complete `DoorActionResult` on every path.

- [ ] **Step 1: Define the server service contract and test fixture helpers**

Comecar o spec `tests/server/doors/DoorService.spec.luau` com `--!strict`, imports do DataModel real e fixtures destruidas em `afterEach`.

Os helpers devem criar uma porta real com esta arvore:

```text
Model [tag Door]
+-- Doorway [Part]
    +-- Center [Attachment]
```

O helper deve aplicar `Locked` e `RequiredItemId`, parentear a porta em `Workspace` quando o teste precisar de uma porta valida e registrar cada root criado para destruicao. Outro helper deve criar um personagem minimo com `Model` e `HumanoidRootPart` `Part`, parentear o personagem em `Workspace` e devolver um fake player com campo `Character` apontando para esse model.

Criar um fake `ItemUseService` que capture o request recebido e permita devolver sucesso ou falha. Para os testes de consumo real, criar tambem um `ItemBehaviorRegistry`, registrar `DoorUnlockBehavior.create()` e construir o `ItemUseService` com um fake inventory no mesmo padrao de `tests/server/items/ItemUseService.spec.luau`.

Limpar em `afterEach`:

- models, personagens e pastas parentados em `Workspace`;
- tags adicionadas ao `CollectionService` por meio da destruicao dos models;
- `remotes.InteractDoor.OnServerInvoke`;
- sinais/conexoes criados pelo service;
- estado das tabelas de fake inventory.

- [ ] **Step 2: Write the failing server contract tests**

Cobrir no spec os seguintes casos com nomes explicitos:

1. `start()` liga o `InteractDoor` e `stop()` remove o callback sem duplicar binding.
2. Uma porta tagueada com `Model/Doorway/Center` e aceita.
3. Modelo sem tag, sem `Doorway`, sem `Center`, fora de `Workspace` ou com atributos de tipos errados retorna `invalid_door` ou `invalid_config`, conforme a falha.
4. Jogador alem da tolerancia retorna `too_far`.
5. Jogador praticamente sobre o plano do `Center` retorna `ambiguous_side`.
6. Pedido `enter` em porta trancada retorna `locked` sem mover o personagem.
7. Pedido `unlock` em porta aberta retorna `already_unlocked`.
8. Pedido `unlock` com item compativel retorna sucesso com `action = "unlock"`, muda `Locked` para `false` e mantem o item no inventario.
9. Pedido `unlock` sem item ou com item de outro `itemId` retorna `missing_item` e mantem `Locked = true`.
10. Porta trancada sem `RequiredItemId` valido retorna `invalid_config` e nunca chama `ItemUseService`.
11. Pedido `enter` em porta aberta teleporta para o lado oposto, alem da espessura do `Doorway`, preserva altura segura e orienta o personagem para longe da porta.
12. Pedido `enter` com jogador em cada lado produz destinos opostos.
13. Uma segunda acao concorrente na mesma porta retorna `busy` e nao duplica desbloqueio ou teleporte.

Para invocar o callback diretamente sem simular rede, usar a referencia do `RemoteFunction`:

```lua
local invoke = assert(InteractDoor.OnServerInvoke)
local result = invoke(player :: any, {
	door = door,
	action = "enter",
})
```

O spec deve afirmar o contrato publico, nao detalhes de tabelas privadas do service.

- [ ] **Step 3: Run the server spec before implementation**

Executar o build e iniciar Play limpo no projeto de testes. No DataModel `Server`, rodar:

```lua
return require(game.ServerScriptService.TestEZRunner).run()
```

Esperado: falha de require para `DoorService` ou falhas de contrato, confirmando que o spec aponta para `Server.doors` real mapeado pela Task 1.

- [ ] **Step 4: Implement the pure unlock behavior**

Criar `DoorUnlockBehavior.luau` com uma funcao `create()` que devolve um `ItemBehavior`.

O `canUse` deve:

- ler `context.requiredItemId` como string nao vazia;
- retornar `true` somente quando `instance.itemId == context.requiredItemId`;
- retornar `false, "missing_item"` para item ausente, id diferente ou contexto invalido.

O `use` deve retornar somente:

```lua
{
	success = true,
}
```

Nao retornar `consumeInstance`, `consumeQuantity`, `updateAttributes` ou `equipSlot`. A verificacao de catalogo e capability continua no `ItemUseService`; o behavior apenas confere o `itemId` especifico pedido pela porta.

- [ ] **Step 5: Implement structural and spatial validation in DoorService**

Criar `DoorService.new(itemUseService)` e manter os servicos Roblox necessarios como dependencias do modulo. O `start()` deve ser idempotente, validar/logar os modelos retornados por `CollectionService:GetTagged("Door")` e instalar o callback de `InteractDoor`. Cada request deve revalidar a instancia atual, sem confiar em uma lista client-side ou em cache de atributos.

Centralizar helpers privados para:

- validar que `request` e tabela, `request.door` e `Model` e `request.action` e `"unlock"` ou `"enter"`;
- validar `door:IsDescendantOf(Workspace)` e `CollectionService:HasTag(door, DOOR_TAG)`;
- encontrar `Doorway` como `BasePart` direto e `Center` como `Attachment` direto de `Doorway`;
- validar `Locked` como boolean e `RequiredItemId` como string;
- consultar o catalogo e confirmar que um `RequiredItemId` trancado existe e possui capability `"unlock"`;
- localizar `player.Character` e `HumanoidRootPart` como `BasePart`;
- calcular `signedDistance = (root.Position - center.WorldPosition):Dot(center.WorldCFrame.ZVector)`;
- rejeitar `math.abs(signedDistance) <= SIDE_EPSILON` com `ambiguous_side`;
- rejeitar distancia maior que a tolerancia server-side com `too_far`.

Usar constantes nomeadas no service. A tolerancia server-side deve ser `6` studs, `SIDE_EPSILON` deve ser `0.25` studs e a margem de saida deve ser `3` studs. A tolerancia e uma defesa do servidor e nao substitui o probe client-side.

O servidor deve produzir `invalid_config` para porta trancada sem id, id desconhecido ou item sem capability unlock. Uma porta aberta pode ter `RequiredItemId = ""`.

- [ ] **Step 6: Implement unlock, entry and per-door locking**

Manter uma tabela privada `busy: { [Model]: boolean }`. Marcar a porta antes de qualquer chamada ao `ItemUseService` ou teleporte e limpar em um bloco de conclusao que tambem execute quando houver erro.

Para `unlock`:

1. Rejeitar `Locked == false` com `already_unlocked`.
2. Criar internamente o request de item:

```lua
{
	capability = "unlock",
	context = {
		requiredItemId = requiredItemId,
	},
}
```

3. Chamar `itemUseService:use(player, request)`.
4. Converter qualquer falha de compatibilidade em `missing_item`.
5. Em sucesso, definir `door:SetAttribute(LOCKED_ATTRIBUTE, false)` e retornar `{ success = true, action = "unlock" }`.
6. Nunca remover ou alterar a instancia da chave.

Para `enter`:

1. Rejeitar `Locked == true` com `locked`.
2. Calcular `side = if signedDistance > 0 then 1 else -1`.
3. Calcular a posicao oposta com `Doorway.Size.Z / 2 + EXIT_MARGIN` ao longo de `-center.WorldCFrame.ZVector * side`.
4. Manter a altura atual do `HumanoidRootPart` para nao colocar o personagem dentro do piso.
5. Usar `character:PivotTo` ou o `HumanoidRootPart.CFrame` server-side com `CFrame.lookAt`, orientando o personagem para o lado oposto ao plano da porta.
6. Retornar `{ success = true, action = "enter" }` somente depois de aplicar a nova posicao.

Se a posicao estiver no plano ou o personagem nao for valido, nao executar nenhum teleporte.

- [ ] **Step 7: Bind the service and compose the server bootstrap**

No `src/server/init.server.luau`:

1. Requerer `DoorService` e `DoorUnlockBehavior` a partir de `script.doors`.
2. Registrar exatamente uma vez antes do service iniciar:

```lua
assert(behaviorRegistry:register("unlock", DoorUnlockBehavior.create()))
```

3. Manter a criacao de `itemUseService` e o binding de `UseItem` existentes.
4. Manter `pickupService:start()` antes da fixture.
5. Manter a chamada da Task 1:

```lua
if RunService:IsStudio() then
	StudioDoorScene.create()
end
```

6. Criar e iniciar o service depois da cena:

```lua
local doorService = DoorService.new(itemUseService)
doorService:start()
```

Nao mover a cena para dentro do `DoorService`; o bootstrap continua explicitando a ordem de composicao.

- [ ] **Step 8: Run the server suite and static checks for this task**

Executar:

```bash
selene --config selene.roblox.toml src/server/doors src/server/init.server.luau
selene --config selene.roblox-tests.toml tests/server/doors
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
```

Rodar no Studio:

```lua
return require(game.ServerScriptService.TestEZRunner).run()
```

Esperado: `failed == 0`, sem callback remoto duplicado, sem fixture sobrando no `Workspace` depois dos specs e sem alteracao de inventario nos testes de unlock.

- [ ] **Step 9: Commit only the server task files**

Quando a suite server passar, criar o commit da segunda sessao com a lista explicita:

```bash
git add src/server/doors/DoorUnlockBehavior.luau src/server/doors/DoorService.luau tests/server/doors/DoorService.spec.luau src/server/init.server.luau
git commit -m "feat: add server door authority"
```

Nao incluir ainda `src/client/doors`, specs client, README ou alteracoes fora do bootstrap server.

## Task 3: Client Detection And Transition

**Objetivo da sessao:** consumir o contrato compartilhado e o endpoint server para entregar o fluxo completo de interacao, incluindo ShapeCast, inventario local, sequencia de dialogo, fade, som opcional e tratamento de rejeicao. Esta task tambem executa a verificacao final dos tres subsistemas.

**Files:**
- Create: `src/client/doors/TransitionController.luau`
- Create: `src/client/doors/DoorController.luau`
- Create: `tests/client/doors/TransitionController.spec.luau`
- Create: `tests/client/doors/DoorController.spec.luau`
- Modify: `src/client/init.client.luau`
- Modify: `test.project.json` para mapear `src/client/doors`
- Modify: `README.md` para incluir `src/server/doors` e `src/client/doors` no typecheck
- Do not modify: `src/shared/doors/doorTypes.luau`, `src/shared/remotes.luau`, `DoorService.luau` or `StudioDoorScene.luau`

**Interfaces:**
- Consumes `doorTypes.DoorRequest`, `doorTypes.DoorActionResult`, the `InteractDoor` RemoteFunction, `InventoryController.getState()`, `DialogueController.getState/show()` and the scene attributes.
- Produces `TransitionController.start()`, `TransitionController.stop()` and `TransitionController.run(request, callback)`.
- Produces `DoorController.start()`, `DoorController.stop()`, `DoorController.getTarget()` and a `new(dependencies)` factory used by specs to inject a fake remote/dialogue/transition without changing production behavior.

- [ ] **Step 1: Add the client door mapping and test scaffolding**

Adicionar ao nivel de `camera`, `dialogue`, `inventory`, `pickups`, `player` e `ui` em `StarterPlayer.StarterPlayerScripts.Client`:

```json
"doors": {
  "$path": "src/client/doors"
}
```

Criar os dois specs estritos antes dos modulos de producao. Os specs devem importar pelo DataModel real:

```lua
local Players = game:GetService("Players")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local DoorController = require(client.doors.DoorController)
```

Usar `beforeEach` para criar portas/personagens/gui e `afterEach` para chamar `stop()`, destruir Instances e limpar callbacks de input. Nao alterar os runners.

- [ ] **Step 2: Define the TransitionController API and failing transition tests**

Usar um controlador instanciavel para permitir fixtures independentes, mantendo uma instancia default no modulo para o jogo:

```lua
export type TransitionRequest = () -> DoorActionResult
export type TransitionCallback = (result: DoorActionResult) -> ()
export type TransitionController = {
	start: () -> (),
	stop: () -> (),
	run: (request: TransitionRequest, callback: TransitionCallback) -> boolean,
}
```

O modulo deve expor uma factory `new(playerGui: PlayerGui): TransitionController` e os metodos da instancia default. A instancia default deve usar `Players.LocalPlayer:WaitForChild("PlayerGui")`.

Escrever `TransitionController.spec.luau` para verificar:

1. `start()` e idempotente e cria um `ScreenGui` preto com `Frame` full-screen inicialmente transparente.
2. `run()` faz o callback de request somente depois de o frame atingir transparencia `0`; o callback deve observar esse valor.
3. Resultado de sucesso com `action = "enter"` termina com transparencia `1` e executa o callback.
4. Resultado de falha termina com transparencia `1`, nao deixa a tela preta e executa o callback com a falha original.
5. Com `TRANSITION_SOUND_ID = ""`, nenhum Sound de transicao e criado ou tocado.
6. `run()` rejeita uma segunda chamada enquanto a primeira esta ativa.
7. `stop()` cancela o estado ativo e deixa a tela transparente.

Para nao depender de um tempo fixo no teste, aguardar o callback com um loop limitado por timeout e verificar o estado do frame dentro do request e ao final. Remover a GUI criada em `afterEach`.

- [ ] **Step 3: Implement the TransitionController**

Criar `src/client/doors/TransitionController.luau` com estas regras:

- Constantes locais `FADE_IN_DURATION`, `FADE_OUT_DURATION` e uma unica `TRANSITION_SOUND_ID = ""`.
- Criar/reusar `ScreenGui.Name = "DoorTransitionGui"`, `ResetOnSpawn = false`, `IgnoreGuiInset = true` e um `Frame.Name = "Fade"` cobrindo `UDim2.fromScale(1, 1)`.
- O frame deve ser preto, ter `ZIndex` acima da UI normal e iniciar com `BackgroundTransparency = 1`.
- `run()` deve retornar `false` se o controlador nao estiver iniciado ou estiver ocupado.
- Ao aceitar, marcar busy, animar `1 -> 0`, executar `request` dentro de `pcall` quando a tela estiver preta e converter erro de invocacao em `{ success = false }` sem deixar a tela preta.
- Em sucesso com `action = "enter"`, criar um Sound somente se `TRANSITION_SOUND_ID ~= ""`, tocar uma vez e animar `0 -> 1`.
- Em qualquer falha, nao tocar som e animar `0 -> 1` para reverter o fade.
- Limpar busy ao final, inclusive quando `request` gerar erro.
- `stop()` deve invalidar uma geracao em andamento, parar tween se necessario e garantir transparencia `1`.

O controlador nao deve teleportar o personagem nem chamar `InteractDoor`; recebe a funcao de request da `DoorController`.

- [ ] **Step 4: Define the DoorController dependency boundary and failing decision tests**

Definir em `DoorController.luau` as dependencias injetaveis abaixo para os specs nao dependerem de rede real:

```lua
export type Dependencies = {
	getInventory: () -> InventoryState?,
	invokeDoor: (request: DoorRequest) -> DoorActionResult,
	dialogue: {
		getState: () -> DialogState?,
		show: (text: string, callback: ((nil, string) -> ())?) -> (),
	},
	transition: {
		run: (request: () -> DoorActionResult, callback: (result: DoorActionResult) -> ()) -> boolean,
	},
}
```

Antes desse tipo, criar aliases para `InventoryState` a partir de
`ReplicatedStorage.Shared.inventory.items` e para `DialogState` a partir do tipo
exportado por `DialogueController`. O `DoorController` deve importar apenas os
contratos existentes e nao copiar as definicoes de inventario ou dialogo.

O modulo deve expor `new(dependencies)` e uma instancia default. A instancia default liga `getInventory` a `InventoryController.getState`, `invokeDoor` a `InteractDoor:InvokeServer`, `dialogue` ao `DialogueController` e `transition` ao `TransitionController` default.

Escrever `DoorController.spec.luau` para cobrir:

1. ShapeCast detecta uma porta no volume a frente do `HumanoidRootPart`.
2. Porta fora de `PROBE_OFFSET`/`PROBE_SIZE` nao e detectada.
3. Duas portas no mesmo volume resultam no `RaycastResult` mais proximo.
4. Rotacionar o `HumanoidRootPart` muda a direcao de deteccao; a porta atras nao e alvo.
5. `getTarget()` publica o modelo atual e retorna `nil` quando nao ha alvo.
6. Porta trancada sem o item ordena os `StringValue`s diretos por nome, chama `Dialogue.show` sequencialmente e nao chama `invokeDoor`.
7. Pasta ausente, vazia ou com valores vazios usa exatamente `"Porta trancada."`.
8. Porta trancada com item envia `{ door = model, action = "unlock" }`, sem `RequiredItemId` ou `Locked`, e mostra `"Porta destrancada"` somente em sucesso.
9. Porta aberta envia `{ door = model, action = "enter" }` atraves do `TransitionController`.
10. Dialogo ativo impede que `F` gere outra acao da porta.
11. Rejeicao server-side com `locked`, `missing_item` ou `invalid_config` nao deixa um fade pendente.

Para acionar `F` sem fabricar `InputObject`, obter o callback pelo `ContextActionService:GetAllBoundActionInfo()` e chama-lo com `Enum.UserInputState.Begin`, como nos specs existentes de dialogo.

- [ ] **Step 5: Implement ShapeCast and target lifecycle**

Em `DoorController.luau`:

- Criar um `Part` de probe reutilizavel, nao parentado, com `Size = Vector3.new(4, 5, 3)` e `CFrame` atualizado para `root.CFrame + root.CFrame.LookVector * 2.5`.
- Usar `workspace:Shapecast(probe, Vector3.zero, raycastParams)`; o resultado unico ja e o hit mais proximo e sua propriedade `Distance` e a distancia usada pelo Roblox.
- Configurar `RaycastParams.FilterType = Exclude` e excluir o personagem local.
- Subir de `result.Instance` pelos ancestrais ate encontrar um `Model` com a tag `Door`; ignorar hits que nao pertençam a uma porta.
- Atualizar o alvo em `RunService.PreRender` e executar uma varredura inicial em `start()`.
- `start()` deve ser idempotente e bindar a acao `DungeonDoorInteract` na prioridade `Enum.ContextActionPriority.High.Value`, abaixo do `DialogueController` que usa `High + 1`.
- `stop()` deve desconectar `PreRender`, desbindar a acao, destruir o probe e limpar o alvo.
- `getTarget()` deve retornar o ultimo modelo detectado sem permitir que consumidores alterem o estado.

Nao usar `GetPartBoundsInBox`, `ProximityPrompt`, distancia adicional client-side ou uma lista central de salas.

- [ ] **Step 6: Implement input decisions, dialogue sequence and remote requests**

No callback da acao `F`, processar somente `Enum.UserInputState.Begin` e sempre retornar `Enum.ContextActionResult.Sink`.

1. Se `dependencies.dialogue.getState() ~= nil`, nao processar porta.
2. Se nao houver alvo, nao fazer request.
3. Ler `Locked` e `RequiredItemId` do modelo atual.
4. Se `Locked == false`, chamar `transition.run` com uma closure que envia exatamente `{ door = target, action = "enter" }`.
5. Se `Locked == true`, procurar no snapshot local um item com `itemId == RequiredItemId`.
6. Com item, chamar `invokeDoor({ door = target, action = "unlock" })`; em sucesso com action `unlock`, exibir `Dialogue.show("Porta destrancada")` e nao iniciar entrada.
7. Sem item, nao chamar `invokeDoor`; ler os `StringValue`s filhos diretos de `LockedDialogue`, ordenar por `Name` e encadear `Dialogue.show` apenas quando a mensagem anterior terminar com reason `"completed"`.
8. Se a pasta nao existir, estiver vazia ou todos os valores forem vazios, exibir o fallback de `doorTypes.FALLBACK_LOCKED_MESSAGE`.
9. Se o jogador cancelar a sequencia, nao abrir a proxima mensagem.
10. Se um request server retornar `missing_item`, exibir o dialogo de porta trancada; para `locked`, `already_unlocked`, `busy` ou `invalid_config`, nao iniciar outro request e deixar a proxima varredura refletir os atributos replicados.

O cliente nunca deve escrever `Locked`, `RequiredItemId` ou qualquer atributo do modelo.

- [ ] **Step 7: Start the client controllers without changing existing order**

Em `src/client/init.client.luau`, requerer `TransitionController` e `DoorController`. Manter a inicializacao existente de camera, tanque, pickups, inventario e dialogo. Iniciar os novos controladores depois de `InventoryController.start()` e `DialogueController.start()` e antes de renderizar o `App`:

```lua
TransitionController.start()
DoorController.start()
```

Nao adicionar UI React para a transicao e nao mover o `DialogueController` para dentro da porta.

- [ ] **Step 8: Update the documented typecheck paths**

Em `README.md`, atualizar o comando de `luau-lsp analyze` para incluir `src/server/doors` depois de `src/server/pickups` e `src/client/doors` depois de `src/client/camera` ou antes de `src/client/dialogue`, preservando flags, definicoes e exclusao dos entrypoints. O trecho final deve conter todas estas pastas:

```text
src/shared
src/server/inventory src/server/items src/server/pickups src/server/doors
src/client/camera src/client/doors src/client/dialogue src/client/inventory
src/client/pickups src/client/player src/client/ui
tests
```

- [ ] **Step 9: Run the complete static verification**

Executar exatamente nesta ordem:

```bash
selene --config selene.roblox.toml src
selene --config selene.roblox-tests.toml tests
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --definitions @testez=typecheck/testez.d.luau \
  --sourcemap test-sourcemap.json --formatter gnu \
  src/shared \
  src/server/inventory src/server/items src/server/pickups src/server/doors \
  src/client/camera src/client/doors src/client/dialogue src/client/inventory \
  src/client/pickups src/client/player src/client/ui \
  tests
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

Esperado: exit code `0` em cada comando, sem suppressions novas e com os dois builds concluindo.

- [ ] **Step 10: Run both TestEZ runners twice in clean Play sessions**

Servir ou sincronizar `test.project.json` na sessao Studio `RE Like Test`. Em cada uma de duas rodadas independentes:

1. Iniciar Play limpo pelo MCP.
2. No DataModel `Server`, executar:

```lua
return require(game.ServerScriptService.TestEZRunner).run()
```

3. No DataModel `Client`, executar:

```lua
return require(game.Players.LocalPlayer.PlayerScripts.TestEZClientRunner).run()
```

4. Confirmar `failed == 0` nos dois resultados.
5. Verificar Output para erros de require, bindings, `OnServerInvoke` ou callbacks nao protegidos.
6. Parar Play e confirmar que fixtures, conexoes, GUI de transicao e tags temporarias foram limpas.

Nao executar `init.server.luau` ou `init.client.luau` no test place como parte dos runners; os entrypoints continuam exclusivos do projeto normal.

- [ ] **Step 11: Manually verify the integrated normal place**

Executar Play no projeto normal e verificar o fluxo end-to-end:

1. As tres portas aparecem no `Workspace` sem erros no Output.
2. Antes de coletar `iron_key`, abordar `MissingKeyDoor`, olhar diretamente e pressionar `F`; as mensagens aparecem em ordem e `Locked` continua `true`.
3. Coletar o pickup existente de `iron_key`; o inventario local passa a conter o item.
4. Abordar `KeyDoor` e pressionar `F`; a porta muda para `Locked = false`, aparece `Porta destrancada`, o jogador nao e teleportado e a chave permanece.
5. Pressionar `F` novamente; o fade fecha, o servidor move o jogador para o lado oposto, nenhum som e criado com o ID vazio e o fade retorna.
6. Abordar `OpenDoor` e pressionar `F`; a travessia ocorre diretamente pelo mesmo fluxo.
7. Forcar uma rejeicao de `enter` durante um estado stale ou busy e confirmar que o fade volta, sem tela preta presa.
8. Parar Play, iniciar outro Play e confirmar que a cena e recriada uma vez e que `Locked` volta ao valor inicial, sem persistencia entre sessoes.

- [ ] **Step 12: Inspect the final worktree and commit the client task**

Executar:

```bash
git status --short
git diff --check
git log --oneline -10
```

Confirmar que nao ha build gerado rastreado, que o spec de design nao foi incluido por acidente e que somente os arquivos da feature foram alterados. Entao criar o terceiro commit:

```bash
git add src/client/doors tests/client/doors src/client/init.client.luau test.project.json README.md
git commit -m "feat: add client door interaction"
```

## Self-Review Checklist

- [ ] A Task 1 e executavel sozinha e termina com `Workspace.DoorTestScene` visivel no Play normal.
- [ ] Os tipos compartilhados e `InteractDoor` sao definidos uma vez, antes de server e client.
- [ ] A Task 1 nao implementa desbloqueio, teleporte, input ou UI.
- [ ] A Task 2 revalida porta, Workspace, tag, estrutura, atributos, distancia, lado, estado, inventario e concorrencia.
- [ ] O behavior `unlock` valida exatamente o `itemId` e nao retorna mutacao de inventario.
- [ ] O servidor altera `Locked` para `false` e o atributo replica automaticamente.
- [ ] A Task 3 usa `Shapecast`, seleciona o hit mais proximo e nao adiciona distancia client-side.
- [ ] Dialogos leem `StringValue`s diretos, ordenam por nome, usam fallback e respeitam cancelamento.
- [ ] O jogador nao atravessa no mesmo `F` que destranca.
- [ ] O fade e iniciado antes de `enter`, o request ocorre com tela preta e toda falha reverte a transparencia.
- [ ] `TRANSITION_SOUND_ID` e a unica configuracao de audio e continua vazia.
- [ ] Nao existem specs React/UI nem spec separado da cena.
- [ ] `test.project.json` mapeia `server/doors` e `client/doors`, mas nao inicia os entrypoints normais.
- [ ] Lint, sourcemap, typecheck, builds e os dois runners TestEZ passam em duas sessoes Play limpas.

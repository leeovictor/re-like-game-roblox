# DoorManager Client-Side Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task inline. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrar o dominio de portas da autoridade server-side atual para um `DoorManager` client-side, preservando o detector generico, a transicao, os eventos e o estado local durante a sessao.

**Architecture:** O `InteractionController` continuara sendo o unico dono do binding de `F` e encaminhara modelos para o `DoorController`. Um `DoorManager` instanciado no composition root recebera somente o `InventoryController`, usara `CharacterRoot.get()` diretamente e concentrara validacao, unlock local, concorrencia e teleporte. `DoorService`, `DoorUnlockBehavior` e `InteractDoor` serao removidos sem alterar a autoridade server-side dos sistemas genericos de inventario e pickups.

**Tech Stack:** Luau `--!strict`, Roblox `CollectionService`, `Workspace`, `Players.LocalPlayer`, `TweenService`, `RemoteFunction` somente nos sistemas que ainda o utilizam, React/ReactRoblox sem novas specs de UI, TestEZ executado no Roblox Studio, Rojo `7.7.0`, Selene `0.29.0` e `luau-lsp 1.69.0`.

## Global Constraints

- Partir do `InteractionController` ja existente; nao recriar deteccao, binding de `F` ou handler generico.
- Preservar `DoorController.new(...)` como handler e `TransitionController` como controller local de fade.
- Construir o manager com `DoorManager.new({ inventory = InventoryController })`.
- `getCharacterRoot` nao sera dependencia; o manager importara diretamente o utilitario `src/client/player/CharacterRoot.luau`.
- `CharacterRoot.get()` consultara `Players.LocalPlayer.Character` e retornara somente um `HumanoidRootPart` `BasePart` valido.
- `Locked` sera a fonte de verdade do runtime na copia client-side do modelo.
- Unlock nao consumira nem alterara o snapshot do inventario e nao chamara `InventoryController.use`.
- O cliente validara, desbloqueara e teleportara localmente; esta arquitetura e deliberadamente single-player e nao e uma fronteira de seguranca multiplayer.
- Preservar `MAX_DISTANCE = 6`, `SIDE_EPSILON = 0.001`, `EXIT_MARGIN = 3` e a normal baseada em `Center.WorldCFrame.XVector`.
- `DoorKey` sera estavel quando presente, mas opcional para gameplay; sem ele, o `DoorController` nao publicara eventos de objetivos.
- A autoria usara `access_card`, que existe no catalogo e possui capability `unlock`; nao usar `iron_key` em codigo novo.
- `StudioDoorScene` foi removida e nao deve ser recriada, referenciada ou substituida por outra fixture server-side.
- Portas nao podem ser descarregadas e recriadas durante a run; o mapa deve manter `StreamingEnabled` desabilitado para preservar o atributo local entre respawns.
- O `DoorManager` nao tera `start()` ou `stop()`, pois nao criara bindings, conexoes ou tarefas.
- Fixtures que criam Instances, tags, personagens, conexoes ou estado mutavel devem ser isoladas em `beforeEach` e limpas em `afterEach`.
- Specs client-side devem usar o DataModel real e TestEZ; nao criar specs de UI.
- Nao editar `Packages/` ou `DevPackages/`.
- Depois de alterar scripts ou specs usados pelo TestEZ, parar e iniciar novamente o Play no Roblox Studio antes de executar os runners; nao usar `rojo sync` neste trabalho, pois a sincronizacao sera feita manualmente.
- Executar o LSP ao final de cada task, usando o comando correspondente ao estado da arvore naquela task.
- A execucao sera inline nesta sessao; nao despachar subagentes e nao realizar revisoes isoladas. A verificacao fica incorporada a cada task.
- Nao executar `git add`, `git commit`, `git amend`, `git reset` ou qualquer outra operacao de staging/commit.
- Preservar mudancas preexistentes no worktree, incluindo a remocao de `src/server/doors/StudioDoorScene.luau` e o spec de design nao rastreado.

## File Map

| Arquivo | Acao | Responsabilidade |
|---|---|---|
| `src/client/player/CharacterRoot.luau` | Criar | Leitura stateless do `HumanoidRootPart` local |
| `src/client/doors/DoorManager.luau` | Criar | Validacao, inventario, estado local, concorrencia e teleporte |
| `tests/client/doors/DoorManager.spec.luau` | Criar | Contrato client-side do manager e invariantes geometricas |
| `src/client/doors/DoorController.luau` | Modificar | Usar manager em vez de inventario/remoto direto |
| `tests/client/doors/DoorController.spec.luau` | Modificar | Usar fake do manager e reativar o spec |
| `src/client/init.client.luau` | Modificar | Compor e registrar `DoorManager` e `DoorController` |
| `src/server/utils/DoorModelInitializer.luau` | Modificar | Usar `access_card` e preservar `DoorKey` authored |
| `src/server/init.server.luau` | Modificar | Remover composicao server-side de portas |
| `src/shared/remotes.luau` | Modificar | Remover `InteractDoor` |
| `src/server/doors/DoorService.luau` | Remover | Autoridade server-side obsoleta |
| `src/server/doors/DoorUnlockBehavior.luau` | Remover | Behavior de unlock obsoleto |
| `tests/server/doors/DoorService.spec.luau` | Remover | Specs server-side obsoletos |
| `test.project.json` | Modificar | Remover o mapeamento server-side de portas |
| `README.md` | Modificar | Remover `src/server/doors` do typecheck |
| `docs/superpowers/specs/2026-08-18-door-system-design.md` | Modificar | Marcar o design server-authoritative como historico |
| `docs/superpowers/specs/2026-08-22-generic-interaction-system-design.md` | Modificar | Atualizar a integracao atual de portas |
| `docs/superpowers/specs/2026-08-22-objective-system-design.md` | Modificar | Atualizar a origem dos eventos e a autoridade de portas |

`src/client/interactions/InteractionController.luau`,
`src/client/doors/TransitionController.luau`,
`src/client/inventory/InventoryController.luau`,
`src/client/events/GameplayEvents.luau` e o mapeamento client-side existente nao
serao refatorados alem dos ajustes necessarios aos consumidores.

## Verification Commands

Os comandos abaixo devem ser executados no final de cada task. O comando
`pre-cleanup` e usado enquanto `src/server/doors` ainda existe. O comando
`post-cleanup` e usado depois da remocao dos arquivos server-side.

### Lint completo

```bash
selene --config selene.roblox.toml src
selene --config selene.roblox-tests.toml tests
```

### LSP pre-cleanup

```bash
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --definitions @testez=typecheck/testez.d.luau \
  --sourcemap test-sourcemap.json --formatter gnu \
  src/shared \
  src/server/inventory src/server/items src/server/pickups src/server/doors src/server/player \
  src/client/camera src/client/doors src/client/dialogue src/client/interactions \
  src/client/inventory src/client/pickups src/client/player src/client/ui \
  tests
```

### LSP post-cleanup

```bash
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --definitions @testez=typecheck/testez.d.luau \
  --sourcemap test-sourcemap.json --formatter gnu \
  src/shared \
  src/server/inventory src/server/items src/server/pickups src/server/player \
  src/client/camera src/client/doors src/client/dialogue src/client/interactions \
  src/client/inventory src/client/pickups src/client/player src/client/ui \
  tests
```

O LSP deve ser executado em toda task, mesmo quando a task alterar somente um
arquivo client-side. Nao usar `--!nocheck`, ignores amplos, `typeErrors: false`
ou definicoes globais adicionais para ocultar diagnosticos.

## Task 1: CharacterRoot And DoorManager

**Objetivo:** criar o utilitario de personagem e portar as regras de dominio de
`DoorService` para um manager client-side testavel, sem ainda alterar o
`DoorController` ou o bootstrap.

**Files:**

- Create: `src/client/player/CharacterRoot.luau`
- Create: `src/client/doors/DoorManager.luau`
- Create: `tests/client/doors/DoorManager.spec.luau`
- Use: `src/shared/doors/doorTypes.luau`
- Use: `src/shared/interactions/interactionTypes.luau`
- Use: `src/shared/inventory/items.luau`
- Use: `src/shared/inventory/catalog.luau`
- Use: `src/client/inventory/InventoryController.luau`

**Interfaces:**

- Consumes `InventoryController.InventoryController` e os tipos compartilhados
  existentes.
- Produces `CharacterRoot.get(): BasePart?`.
- Produces `DoorManager.new({ inventory = InventoryController })`.
- Produces `DoorManager:isLocked(door) -> (boolean?, DoorFailureReason?)`.
- Produces `DoorManager:unlock(door) -> DoorActionResult`.
- Produces `DoorManager:enter(door) -> DoorActionResult`.
- Does not change `Locked` no servidor, usar remote ou criar lifecycle.

- [ ] **Step 1: Criar as fixtures client-side antes da implementacao**

No novo spec, criar helpers seguindo o padrao dos specs client-side existentes:

```lua
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local DoorManager = require(client.doors.DoorManager)
local doorTypes = require(ReplicatedStorage.Shared.doors.doorTypes)
local interactionTypes = require(ReplicatedStorage.Shared.interactions.interactionTypes)
```

O helper `makeDoor(locked, requiredItemId)` deve criar um `Model` parentado em
`Workspace`, aplicar `Interactable`, `InteractionType = "Door"`, `Locked` e
`RequiredItemId`, e criar `Doorway` como `Part` com um `Center` `Attachment`.
Deve aceitar opcoes para omitir a tag, o tipo, `Doorway`, `Center`, `Locked` ou
`RequiredItemId`, para testar cada falha sem duplicar fixtures.

O helper `makeCharacter(position)` deve criar um `Model` com um
`HumanoidRootPart` `Part`, parenta-lo em `Workspace`, atribui-lo a
`Players.LocalPlayer.Character` e retornar model e root. O `beforeEach` deve
guardar o personagem original e retirar seu parent para evitar interferencia.

O fake de inventario deve expor a mesma chamada usada pelo manager:

```lua
local inventory = {
    state = { version = 1, items = {}, equipped = {} },
}
function inventory.getState()
    return inventory.state
end
```

Como a API real e chamada com ponto, o manager deve chamar
`dependencies.inventory.getState()`; o fake pode aceitar `self` apenas para
facilitar a mutacao do estado nos testes. O fake tambem deve registrar se
`use()` foi chamado e falhar o teste caso isso ocorra.

O `afterEach` deve parar qualquer fixture criada pelo teste, destruir portas e
personagens, desconectar sinais, restaurar `Players.LocalPlayer.Character` e
limpar as referencias mutaveis do fake.

- [ ] **Step 2: Escrever os testes client-side do contrato do manager**

Adicionar testes com nomes explicitos para os comportamentos abaixo:

1. `new` aceita a dependencia nomeada `inventory`.
2. `isLocked` retorna `true` para porta valida fechada.
3. `isLocked` retorna `false` para porta valida aberta.
4. `isLocked` rejeita alvo que nao e `Model`.
5. `isLocked` rejeita modelo fora de `Workspace`.
6. `isLocked` rejeita ausencia da tag `Interactable`.
7. `isLocked` rejeita `InteractionType` ausente ou diferente de `Door`.
8. `isLocked` rejeita `Doorway` ausente ou que nao seja `BasePart` direto.
9. `isLocked` rejeita `Center` ausente ou que nao seja `Attachment` direto.
10. `isLocked` rejeita `Locked` que nao seja booleano.
11. `isLocked` rejeita `RequiredItemId` que nao seja string.
12. `isLocked` rejeita porta fechada sem item requerido valido.
13. `isLocked` aceita porta aberta com `RequiredItemId = ""`.
14. `unlock` retorna `too_far` para personagem distante e nao altera `Locked`.
15. `unlock` retorna `ambiguous_side` quando o root esta exatamente no plano do
    `Center` e nao altera `Locked`.
16. `unlock` retorna `already_unlocked` para uma porta aberta.
17. `unlock` retorna `missing_item` sem snapshot ou sem item compativel.
18. `unlock` aceita um `access_card` e um item com capability `unlock`.
19. Unlock bem-sucedido define `Locked = false` localmente.
20. Unlock bem-sucedido preserva o item e nao chama `inventory.use`.
21. `enter` retorna `locked` e nao move o root para porta fechada.
22. `enter` retorna `too_far` para personagem distante.
23. `enter` retorna `ambiguous_side` no plano do `Center`.
24. `enter` move o root para o lado oposto usando o eixo X do `Center`.
25. `enter` preserva a altura do root e orienta o personagem na direcao de saida.
26. Players em lados opostos recebem destinos em lados opostos.
27. Uma reentrada durante `unlock` retorna `busy` para a mesma porta.
28. O lock `busy` e isolado entre duas portas.
29. O lock `busy` e isolado entre duas instancias de `DoorManager`.
30. O atributo local continua `false` depois de substituir o personagem por um
    novo respawn.

Para o teste geometrico, nao afirmar uma posicao numerica de tuning. Calcular o
vetor `root.Position - center.WorldPosition` depois da operacao e afirmar que o
produto escalar com `center.WorldCFrame.XVector` tem sinal oposto ao lado de
origem, que a distancia ao centro excede `doorway.Size.X / 2` e que o valor de Y
permanece igual.

O teste de concorrencia deve fazer o fake de `getState()` chamar novamente
`manager:unlock(door)` durante o unlock externo. O resultado interno deve ser
`busy`, e o unlock externo deve ser o unico a alterar `Locked`.

- [ ] **Step 3: Rodar o spec antes de criar os modulos**

Parar e iniciar o Play do projeto de testes manualmente. Rodar no DataModel
client-side:

```lua
return require(game.Players.LocalPlayer.PlayerScripts.TestEZClientRunner).run()
```

Esperado: o novo spec nao consegue carregar `DoorManager`, ou falha nos
contratos porque os modulos ainda nao existem. Nao corrigir a falha adicionando
um fallback ou desabilitando o spec.

- [ ] **Step 4: Implementar `CharacterRoot` sem estado**

Criar o modulo com este comportamento exato:

```lua
--!strict

local Players = game:GetService("Players")

local CharacterRoot = {}

function CharacterRoot.get(): BasePart?
	local character = Players.LocalPlayer.Character
	if character == nil then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end

	return root
end

return CharacterRoot
```

Nao criar cache, conexao `CharacterAdded`, `WaitForChild` ou dependencia de
`DoorManager` neste utilitario.

- [ ] **Step 5: Implementar a validacao estrutural do `DoorManager`**

O modulo deve importar `CollectionService`, `Workspace`,
`ReplicatedStorage.Shared.doors.doorTypes`,
`ReplicatedStorage.Shared.interactions.interactionTypes`,
`ReplicatedStorage.Shared.inventory.catalog`,
`ReplicatedStorage.Shared.inventory.items`, `InventoryController` para o
contrato da dependencia e `script.Parent.Parent.player.CharacterRoot`.

Definir no escopo do modulo:

```lua
local MAX_DISTANCE = 6
local SIDE_EPSILON = 0.001
local EXIT_MARGIN = 3
```

Implementar helpers privados com estes contratos:

```lua
local function failure(reason: doorTypes.DoorFailureReason): doorTypes.DoorActionResult
local function hasUnlockCapability(itemId: string): boolean
local function getDoorParts(door: Model): (BasePart?, Attachment?)
local function validateDoor(door: Model): (BasePart?, Attachment?, boolean?, string?, doorTypes.DoorActionResult?)
```

`validateDoor` deve rejeitar, nesta ordem, alvo nao-Model ou fora de
`Workspace`, tag `Interactable` ausente, `InteractionType` diferente de `Door`,
estrutura `Doorway`/`Center` invalida, `Locked` nao booleano e
`RequiredItemId` nao string. Quando `Locked` for `true`, tambem deve rejeitar
string vazia, item inexistente no catalogo ou item sem capability `unlock` com
`invalid_config`. A ausencia de `DoorKey` nunca deve ser rejeicao do manager.

`isLocked` deve chamar a validacao e retornar `locked, nil` para porta valida ou
`nil, reason` para falha. Nao deve consultar personagem, distancia, lado ou
`busy`.

- [ ] **Step 6: Implementar unlock local, entrada local e concorrencia**

`DoorManager.new(dependencies)` deve criar uma tabela `busy` privada e devolver
uma instancia com metodos usando `:`. A dependencia deve ser validada no
construtor o suficiente para produzir um erro claro se `inventory` nao for uma
tabela com `getState` callable; nao adicionar compatibilidade com uma API
global ou singleton antigo.

`unlock` deve seguir esta ordem observavel:

1. Validar a porta com `validateDoor`.
2. Obter `root = CharacterRoot.get()`; retornar `invalid_door` se ausente.
3. Rejeitar `too_far` quando `(root.Position - center.WorldPosition).Magnitude > 6`.
4. Calcular `signedDistance` com `offset:Dot(center.WorldCFrame.XVector)`.
5. Rejeitar `ambiguous_side` quando `math.abs(signedDistance) <= 0.001`.
6. Rejeitar `busy` se `busy[door]` ja estiver ativo.
7. Marcar `busy[door] = true` antes de consultar o inventario.
8. Retornar `already_unlocked` se a porta nao estiver mais locked.
9. Obter `snapshot = dependencies.inventory.getState()`.
10. Procurar em `snapshot.items` uma instancia com `item.itemId == requiredItemId`.
11. Retornar `missing_item` e liberar o lock se nao houver instancia.
12. Definir `door:SetAttribute(doorTypes.LOCKED_ATTRIBUTE, false)` somente no
    cliente.
13. Liberar o lock e retornar `{ success = true, action = "unlock" }`.

O caminho de inventario nao pode chamar `inventory.use`, `UseItem`,
`ItemUseService` ou qualquer remote. Toda falha deve liberar `busy[door]` antes
de retornar, inclusive falhas produzidas por `pcall` ao ler o snapshot.

`enter` deve validar a porta, obter root, validar distancia, calcular o lado,
rejeitar o plano ambiguo e adquirir `busy[door]`. Depois deve retornar `locked`
sem alterar o root se o atributo estiver fechado. Para uma porta aberta, usar:

```lua
local side = if signedDistance > 0 then 1 else -1
local direction = -center.WorldCFrame.XVector * side
local destination = center.WorldPosition + direction * (doorway.Size.X / 2 + EXIT_MARGIN)
destination = Vector3.new(destination.X, root.Position.Y, destination.Z)
root.CFrame = CFrame.lookAt(destination, destination + direction)
```

Liberar `busy[door]` em todos os caminhos e retornar
`{ success = true, action = "enter" }` somente depois de mover o root.

- [ ] **Step 7: Rodar os testes do manager depois da implementacao**

Parar e iniciar o Play novamente. Rodar o runner client-side e confirmar que os
30 contratos do manager passam, sem specs skipped por um retorno global. Rodar
tambem o runner server-side existente para confirmar que esta task nao alterou
o bootstrap server-side ainda ativo.

- [ ] **Step 8: Executar verificacoes estaticas da Task 1**

Executar o lint completo e o comando **LSP pre-cleanup** definido em
`Verification Commands`. Nao executar `rojo sync`. Se o LSP apontar um erro de
tipo, corrigir o contrato ou o mapeamento real antes de prosseguir; nao ocultar
o erro com suppressions.

## Task 2: Integrate DoorManager Into DoorController

**Objetivo:** substituir o uso direto de `InteractDoor` e do inventario pelo
manager, mantendo o comportamento de dialogo, transicao e eventos.

**Files:**

- Modify: `src/client/doors/DoorController.luau`
- Modify: `tests/client/doors/DoorController.spec.luau`
- Use: `src/client/doors/DoorManager.luau`
- Use: `src/client/doors/TransitionController.luau`
- Use: `src/client/dialogue/DialogueController.luau`
- Use: `src/client/events/GameplayEvents.luau`

**Interfaces:**

- Consumes `DoorManager.DoorManager`, `DialogueController.DialogueController`
  e `TransitionController.TransitionController`.
- Produces `DoorController.new({ manager, dialogue, transition })` como
  `interactionTypes.InteractionHandler`.
- Remove os imports operacionais de `InventoryController`, `items` e `remotes`.

- [ ] **Step 1: Reescrever o spec com fake de manager antes da implementacao**

Remover o bloco temporario que retorna imediatamente no inicio de
`tests/client/doors/DoorController.spec.luau`. Remover o fake de
`remotes.InteractDoor`, `actualInteractDoor`, `inventoryItems` e
`invokeResult`.

Criar um fake de manager por fixture com estado e chamadas observaveis:

```lua
local managerLocked = true
local unlockResult: any = { success = false, reason = "missing_item" }
local enterResult: any = { success = true, action = "enter" }
local managerCalls = { isLocked = 0, unlock = 0, enter = 0 }

local manager = {
	isLocked = function(_self: any, _door: Model): (boolean?, doorTypes.DoorFailureReason?)
		managerCalls.isLocked += 1
		return managerLocked, nil
	end,
	unlock = function(_self: any, _door: Model): any
		managerCalls.unlock += 1
		return unlockResult
	end,
	enter = function(_self: any, _door: Model): any
		managerCalls.enter += 1
		return enterResult
	end,
}
```

Passar os fakes em uma instancia criada explicitamente:

```lua
local controller = DoorController.new({
	manager = manager,
	dialogue = dialogue,
	transition = transition,
})
```

As fixtures de porta do controller podem continuar sendo modelos pequenos, pois
a validacao estrutural e responsabilidade do manager. Incluir `DoorKey` apenas
nos testes que verificam eventos.

Manter fakes de dialogo e transicao com as assinaturas atuais: `dialogue:show`
usa self, enquanto `transition.run(request, callback)` continua sendo chamado
com ponto pelo modulo `TransitionController` atual.

- [ ] **Step 2: Executar o spec antes de alterar o controller**

Parar e iniciar o Play de testes e executar o runner client-side. Esperado:
falhas porque `DoorController` ainda espera `inventory` e chama
`remotes.InteractDoor`, enquanto o novo spec fornece `manager`.

- [ ] **Step 3: Alterar imports e dependencias do controller**

Em `DoorController.luau`:

- remover `local items = require(ReplicatedStorage.Shared.inventory.items)`;
- remover `local remotes = require(ReplicatedStorage.Shared.remotes)`;
- remover `local InventoryController = require(script.Parent.Parent.inventory.InventoryController)`;
- adicionar o require de `DoorManager` para o contrato tipado;
- manter `doorTypes`, `interactionTypes`, `GameplayEvents`, `DialogueController`
  e `TransitionController`.

Substituir a tabela de dependencias por:

```lua
export type Dependencies = {
	manager: DoorManager.DoorManager,
	dialogue: DialogueController.DialogueController,
	transition: TransitionController.TransitionController,
}
```

Remover completamente a funcao local `invokeDoor`. Nao criar uma nova funcao
local que acesse remotes ou inventario.

- [ ] **Step 4: Implementar o fluxo do handler usando o manager**

`controller.interact(target)` deve seguir esta implementacao comportamental:

1. Retornar sem efeito se `target` nao for `Model`.
2. Executar `local locked, reason = dependencies.manager:isLocked(door)`.
3. Retornar sem dialogo/evento se `locked == nil` ou `reason ~= nil`.
4. Se `locked == false`, chamar `dependencies.transition.run` com uma closure
   que retorna `dependencies.manager:enter(door)`.
5. No callback da transicao, publicar `door_entered` somente para sucesso com
   `action = "enter"`.
6. Se `locked == true`, chamar `dependencies.manager:unlock(door)`.
7. Para sucesso com `action = "unlock"`, mostrar `Porta destrancada.` e publicar
   `door_unlocked` somente quando o callback receber `completed`.
8. Para `missing_item`, mostrar `LockedDialogue` ou o fallback e publicar
   `door_blocked` somente apos toda a sequencia receber `completed`.
9. Para cancelamento, nao avancar a sequencia e nao publicar `door_blocked`.
10. Para `locked`, `already_unlocked`, `busy`, `invalid_config`, `invalid_door`,
    `too_far` ou `ambiguous_side`, nao iniciar request adicional.

A leitura de `LockedDialogue` deve continuar filtrando somente `StringValue`
filho direto com valor nao vazio, ordenando por `Name` e usando
`doorTypes.FALLBACK_LOCKED_MESSAGE` quando nao houver mensagem. O controller nao
deve escrever `Locked`, `RequiredItemId`, `InteractionType` ou `DoorKey`.

Manter a funcao atual de publicacao de eventos: `DoorKey` ausente ou vazio gera
um warning uma vez por model e nao publica o evento.

- [ ] **Step 5: Atualizar as assertions do spec do controller**

Manter os cenarios existentes e adaptar as expectativas para o fake do manager:

- alvo que nao e model nao chama `isLocked`, `unlock`, `enter`, transicao ou dialogo;
- porta fechada chama `unlock` uma vez e nao inicia transicao;
- unlock bem-sucedido mostra a mensagem sem chamar `enter`;
- dialogos ordenados, fallback e cancelamento nao chamam o manager;
- porta aberta chama `transition.run` e somente depois chama `enter`;
- sucesso de entrada publica `door_entered` somente no callback da transicao;
- missing item mostra dialogo e publica `door_blocked` ao final;
- falhas server-side simuladas pelo fake nao criam chamadas de seguimento;
- eventos de `DoorKey` valido aparecem somente apos o resultado correto;
- ausencia de `DoorKey` nao impede o handler, mas nao publica progresso;
- nenhum teste deve substituir `remotes.InteractDoor` ou chamar
  `InventoryController.getState`.

- [ ] **Step 6: Rodar a suite client-side apos a integracao**

Parar e iniciar o Play e executar o runner client-side. Confirmar que o spec do
manager e o spec reativado do `DoorController` passam, sem depender de
`InteractDoor`.

- [ ] **Step 7: Executar verificacoes estaticas da Task 2**

Executar o lint completo e o **LSP pre-cleanup**. O LSP deve incluir tanto o
novo manager quanto `src/server/doors`, que ainda sera removido na Task 4.

## Task 3: Compose Client Runtime And Fix Authored Contract

**Objetivo:** ligar o manager ao bootstrap client-side e corrigir a ferramenta
de autoria para o catalogo e o contrato atuais, sem criar fixtures de Studio.

**Files:**

- Modify: `src/client/init.client.luau`
- Modify: `src/server/utils/DoorModelInitializer.luau`
- Use: `src/client/doors/DoorManager.luau`
- Use: `src/client/doors/DoorController.luau`
- Use: `src/client/inventory/InventoryController.luau`
- Use: `src/shared/interactions/interactionTypes.luau`

**Interfaces:**

- Produces a composicao client-side com `DoorManager` e `DoorController`
  instanciados explicitamente.
- Produces autoria com `RequiredItemId = "access_card"`, contrato comum e
  `DoorKey` preservado.
- Does not create `StudioDoorScene` or add a pickup de teste.

- [ ] **Step 1: Atualizar a composicao do client**

Em `src/client/init.client.luau`, adicionar o require:

```lua
local DoorManager = require(script.doors.DoorManager)
```

Mover a criacao do `doorController` para depois de
`InventoryController.start()` e `TransitionController.start()`. Criar a
instancia assim:

```lua
local doorManager = DoorManager.new({
	inventory = InventoryController,
})
local doorController = DoorController.new({
	manager = doorManager,
	dialogue = dialogueController,
	transition = TransitionController,
})
```

Manter:

```lua
interactionController:register("Door", doorController)
interactionController:register("Pickup", PickupController)
interactionController:register("Dialogue", dialogueInteractionController)
interactionController:start()
```

Nao chamar `DoorManager.start()`, `DoorManager.stop()` ou criar binding adicional
de `F`. `InventoryController` continua sendo a dependencia concreta passada ao
manager, e o manager chamara `inventory.getState()` com ponto.

- [ ] **Step 2: Corrigir o item e as mensagens do initializer**

Em `src/server/utils/DoorModelInitializer.luau`:

- trocar `LOCKED_ITEM_ID = "iron_key"` por `LOCKED_ITEM_ID = "access_card"`;
- trocar o hint `Procure uma chave de ferro.` por texto que mencione o cartao de
  acesso;
- manter `InteractionType = "Door"` e a tag `Interactable` ja existentes;
- manter a tag legada `Door` para ferramentas antigas;
- manter `Doorway.Center` e `LockedDialogue`.

Nao sobrescrever um `DoorKey` existente e nao vazio. O trecho deve ter esta
forma:

```lua
local existingDoorKey = model:GetAttribute(doorTypes.DOOR_KEY_ATTRIBUTE)
if type(existingDoorKey) ~= "string" or existingDoorKey == "" then
	model:SetAttribute(doorTypes.DOOR_KEY_ATTRIBUTE, model.Name)
end
```

Esse valor gerado pelo initializer e apenas um valor inicial de autoria; o
designer deve revisar sua unicidade e estabilidade no mapa. O runtime nunca
usara o nome do model como fallback para eventos.

- [ ] **Step 3: Verificar que nao houve reintroducao de fixture**

Pesquisar referencias de `StudioDoorScene` e `DoorTestScene` nos arquivos de
producao. O resultado esperado e nenhuma referencia; nao adicionar condicao
`RunService:IsStudio()` e nao criar pickup server-side.

Pesquisar tambem `iron_key` nos dois arquivos alterados. O initializer nao deve
conter mais esse item; referencias historicas em documentacao ou specs antigas
nao sao alteradas nesta task.

- [ ] **Step 4: Rodar a suite client-side integrada**

Parar e iniciar o Play do projeto de testes e executar o runner client-side.
Confirmar os testes de `DoorManager`, `DoorController`, `InteractionController`
e `TransitionController`. O projeto de testes nao deve iniciar
`init.client.luau`; a composicao deve ser verificada pelo build normal e pelo
Play manual do projeto de producao.

- [ ] **Step 5: Executar verificacoes estaticas da Task 3**

Executar o lint completo, o build do projeto normal e o **LSP pre-cleanup**.
Nao executar `rojo sync`. Se a sessao Studio nao refletir os scripts, parar e
iniciar o Play conforme as instrucoes do repositorio e aguardar a sincronizacao
manual do usuario.

## Task 4: Remove Server Door Authority And Obsolete Contract

**Objetivo:** retirar todo caminho de runtime server-side especifico de portas e
remover o remote que deixou de ter consumidores.

**Files:**

- Modify: `src/server/init.server.luau`
- Modify: `src/shared/remotes.luau`
- Modify: `test.project.json`
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-08-18-door-system-design.md`
- Modify: `docs/superpowers/specs/2026-08-22-generic-interaction-system-design.md`
- Modify: `docs/superpowers/specs/2026-08-22-objective-system-design.md`
- Delete: `src/server/doors/DoorService.luau`
- Delete: `src/server/doors/DoorUnlockBehavior.luau`
- Delete: `tests/server/doors/DoorService.spec.luau`
- Preserve deletion: `src/server/doors/StudioDoorScene.luau`

**Interfaces:**

- Produces a server bootstrap sem qualquer `DoorService`, `DoorUnlockBehavior`
  ou binding de `InteractDoor`.
- Produces `ReplicatedStorage.Shared.remotes` sem a chave `InteractDoor`.
- Produces um projeto de testes sem o mapeamento `Server.doors`.
- Preserves `InventoryService`, `ItemUseService`, `PickupService` e os remotes
  necessarios para esses sistemas.

- [ ] **Step 1: Remover a composicao de portas do bootstrap server-side**

Em `src/server/init.server.luau`:

- remover os requires de `DoorService` e `DoorUnlockBehavior`;
- remover a criacao de `behaviorRegistry:register("unlock", DoorUnlockBehavior.create())`
  especifica de portas;
- manter `ItemBehaviorRegistry.new()` e `ItemUseService.new(inventoryService, behaviorRegistry)`, pois o uso
  generico de itens continua sendo um sistema separado;
- manter `itemUseService:bind(remotes.UseItem :: RemoteFunction)`;
- remover `DoorService.new(itemUseService)` e `doorService:start()`;
- nao adicionar `StudioDoorScene` ou qualquer outro bootstrap de porta.

Depois da edicao, o trecho central deve continuar contendo o fluxo de inventario
e pickups, sem uma secao de portas:

```lua
local inventoryService = InventoryService.new()
local behaviorRegistry = ItemBehaviorRegistry.new()
local itemUseService = ItemUseService.new(inventoryService, behaviorRegistry)
itemUseService:bind(remotes.UseItem :: RemoteFunction)
inventoryService:start()

local factory = ItemInstanceFactory.new(function(): string
	return HttpService:GenerateGUID(false)
end)
local pickupService = PickupService.new(inventoryService, factory)
pickupService:start()
```

- [ ] **Step 2: Remover `InteractDoor` do contrato compartilhado**

Em `src/shared/remotes.luau`, remover somente:

```lua
InteractDoor = _ensureRemote("InteractDoor", "RemoteFunction"),
```

Manter `InventoryChanged`, `GetInventory`, `UseItem`, `PickupCollected` e
`CollectPickup`. Verificar que nenhum modulo de producao restante importa ou
indexa `remotes.InteractDoor`.

- [ ] **Step 3: Remover arquivos e mapeamento server-side**

Eliminar os dois modulos de producao e o spec server-side de portas. Em
`test.project.json`, remover o bloco:

```json
"doors": {
  "$path": "src/server/doors"
}
```

Nao remover o mapeamento client-side `StarterPlayerScripts.Client.doors`, pois
ele continua contendo `DoorManager`, `DoorController` e `TransitionController`.

- [ ] **Step 4: Atualizar README e documentacao atual**

Em `README.md`, remover `src/server/doors` da lista do comando de typecheck,
mantendo `src/server/inventory`, `src/server/items`, `src/server/pickups` e
`src/server/player`.

Em `docs/superpowers/specs/2026-08-18-door-system-design.md`, adicionar uma
nota de documento historico informando que a autoridade server-side,
`InteractDoor`, `iron_key` e `StudioDoorScene` foram supersedidos pelo design
de `2026-08-24-door-manager-client-side-design.md`. Nao reutilizar esse
documento historico como contrato atual.

Em `docs/superpowers/specs/2026-08-22-generic-interaction-system-design.md`:

- manter `InteractionController`, `Interactable`, `InteractionType`, pickups e
  a autoridade server-side de pickups;
- substituir a arquitetura de porta baseada em `InteractDoor`/`DoorService` por
  `DoorManager`/`DoorController` client-side;
- atualizar os fluxos `unlock` e `enter` para nao mencionarem request ao
  servidor;
- atualizar a tabela de autoridade para explicitar que a porta altera `Locked`
  somente na copia client-side;
- manter a prioridade de `F` e o papel do `TransitionController`.

Em `docs/superpowers/specs/2026-08-22-objective-system-design.md`:

- substituir a origem textual dos resultados `InteractDoor` por resultados do
  `DoorManager`;
- manter os eventos `door_blocked`, `door_unlocked` e `door_entered` e suas
  regras de publicacao no `DoorController`;
- atualizar a frase que diz que as regras de porta continuam server-side;
- manter `DoorKey` sem fallback para nome do model.

Os planos historicos de implementacao nao serao reescritos; a nota historica e
as atualizacoes dos documentos de arquitetura atuais evitam confundir o
contrato em uso sem apagar o registro do trabalho anterior.

- [ ] **Step 5: Fazer busca de referencias obsoletas**

Pesquisar no codigo de producao e testes por:

- `remotes.InteractDoor`;
- `InteractDoor.OnServerInvoke`;
- `DoorService` em requires ou composicao;
- `DoorUnlockBehavior` em requires ou registro;
- `StudioDoorScene` ou `DoorTestScene` em codigo runtime;
- `iron_key` em `src/`.

As unicas ocorrencias permitidas de `InteractDoor`, `DoorService`,
`DoorUnlockBehavior` ou `StudioDoorScene` depois desta task sao referencias
historicas/documentais que expliquem a migracao. Nenhuma ocorrencia pode estar
em `src/` ou em specs ativos.

- [ ] **Step 6: Rodar suites depois da remocao**

Parar e iniciar o Play de testes. Rodar o runner client-side e o runner
server-side. O server runner nao deve mais carregar `tests/server/doors`; o
client runner deve executar `DoorManager.spec.luau` e `DoorController.spec.luau`.

- [ ] **Step 7: Executar verificacoes estaticas da Task 4**

Executar lint completo, os dois builds:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

Depois executar o **LSP post-cleanup**. O comando nao pode incluir
`src/server/doors`. Nao executar `rojo sync`.

## Task 5: Clean Play And Manual Acceptance

**Objetivo:** confirmar a composicao final, o isolamento do atributo local, a
persistencia durante respawn e a ausencia de autoridade server-side.

**Files:**

- Verify: todos os arquivos das Tasks 1-4
- Use: `default.project.json`, `test.project.json`, `README.md` e o mapa authored
  atualmente aberto no Studio
- Do not create: `StudioDoorScene`, pickup de teste, remote ou spec de UI

**Interfaces:**

- Consumes o projeto final sem `InteractDoor` e sem `src/server/doors`.
- Produces evidencia dos runners TestEZ client/server e da verificacao manual.
- Does not change codigo para contornar falhas sem registrar a causa.

- [ ] **Step 1: Rodar uma sessao Play limpa do projeto de testes**

Parar o Play atual e iniciar uma nova sessao. Aguardar os runners automaticos e
consultar ambos os DataModels. Quando necessario, executar:

```lua
return require(game.Players.LocalPlayer.PlayerScripts.TestEZClientRunner).run()
```

```lua
return require(game.ServerScriptService.TestEZRunner).run()
```

Confirmar `failed == 0` nos dois resultados. Ler os warnings para garantir que
nao sao erros de require, callbacks remanescentes ou fixtures vazando entre
specs.

- [ ] **Step 2: Verificar a autoria de uma porta real**

Usar uma porta authored no mapa, sem criar uma cena programatica. Confirmar no
model:

- tag `Interactable`;
- `InteractionType = "Door"`;
- `Doorway` como `BasePart` filho direto;
- `Doorway.Center` como `Attachment`;
- `Locked` booleano;
- `RequiredItemId = "access_card"` quando fechada;
- `DoorKey` estavel quando a porta participa de objetivos;
- `LockedDialogue` opcional com `StringValue`s diretos.

Se o initializer for executado, confirmar que ele nao troca um `DoorKey` ja
existente e que seu hint menciona o cartao de acesso.

- [ ] **Step 3: Verificar o fluxo de porta aberta**

Posicionar o personagem em um lado de uma porta authored aberta e pressionar
`F`. Confirmar:

- o target e resolvido pelo `InteractionController` existente;
- o fade ocorre pelo `TransitionController` existente;
- o manager chama `CharacterRoot.get()` e move o root para o lado oposto;
- a altura e preservada;
- o personagem olha para longe da porta;
- `door_entered` ocorre somente depois do callback de sucesso;
- nenhuma chamada a `InteractDoor` aparece no Output ou no DataModel.

- [ ] **Step 4: Verificar o fluxo de porta fechada sem item**

Interagir com a porta sem `access_card`. Confirmar que `LockedDialogue` ou o
fallback aparece, que a sequencia so avanca com `F`, que cancelamento nao mostra
a mensagem seguinte e que `door_blocked` ocorre somente ao completar a sequencia.
Confirmar que `Locked` continua `true`.

- [ ] **Step 5: Verificar unlock e estado local**

Com `access_card` no inventario do jogador, interagir uma vez com a porta
fechada. Confirmar:

- a primeira interacao chama unlock e nao enter;
- `Locked` torna-se `false` no client DataModel;
- o item continua no snapshot e no inventario;
- `Porta destrancada.` aparece;
- `door_unlocked` ocorre somente apos o callback do dialogo;
- o model equivalente no server DataModel conserva o valor authored original;
- uma segunda interacao atravessa a porta sem consumir o item novamente.

- [ ] **Step 6: Verificar respawn e nova sessao**

Depois do unlock, provocar um respawn pelo fluxo normal do jogo e confirmar que
o mesmo model continua com `Locked = false` no client DataModel. Parar o Play e
iniciar uma nova sessao; confirmar que o mapa recebe novamente o valor authored
inicial. Confirmar que nenhuma cena `DoorTestScene` ou `StudioDoorScene` aparece.

- [ ] **Step 7: Executar a verificacao estatica final**

Executar novamente o lint completo, o **LSP post-cleanup** e os dois builds. O
resultado esperado e exit code `0` nos comandos estaticos e de build. Nao
executar `rojo sync`.

- [ ] **Step 8: Confirmar o estado final do worktree sem staging**

Executar `git status --short` apenas para inspecao. Confirmar que nao houve
staging ou commit automatico e que a lista contem somente as alteracoes
esperadas, incluindo a remocao preexistente de `StudioDoorScene` e o novo plano
ou spec quando aplicavel. Nao executar nenhuma operacao de commit.

## Handoff

A implementacao deve ser executada inline, task por task, na ordem acima. Cada
task termina com seus testes relevantes e o LSP correspondente; nao existe uma
etapa de revisao isolada entre elas. O trabalho permanece sem commits, sem
`rojo sync` e sem alteracoes em `Packages/` ou `DevPackages/`.

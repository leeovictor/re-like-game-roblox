# Generic Interaction Foundation Implementation Plan

> **For agentic workers:** Use the implementation workflow selected by the user. Steps use checkbox (`- [ ]`) syntax for tracking. Do not create commits; the user explicitly requested that this worktree remain uncommitted.

**Goal:** Criar o contrato compartilhado e o `InteractionController` client-side que captura `F`, detecta uma raiz interagivel e encaminha a acao para handlers de dominio.

**Architecture:** O controller sera o unico dono do binding de `F` e da busca volumetrica. Ele nao conhecera regras de portas ou pickups; recebe handlers registrados por tipo e entrega a raiz `Model` ou `BasePart` selecionada. O dominio de portas e o dominio de pickups serao integrados nos planos seguintes.

**Tech Stack:** Luau `--!strict`, Roblox `CollectionService`, `ContextActionService`, `Workspace:GetPartBoundsInRadius`, `OverlapParams`, Rojo `7.7.0`, Selene `0.29.0`, luau-lsp `1.69.0` e TestEZ no Roblox Studio.

## Global Constraints

- A tecla de interacao e `F` e existe um unico binding no `InteractionController`.
- A busca usa `Workspace:GetPartBoundsInRadius` com raio de producao `3` studs.
- O centro de producao e `HumanoidRootPart.Position + LookVector * 2.5`.
- O `OverlapParams` exclui o personagem do jogador.
- A busca acontece somente quando `F` e pressionado; nao existe polling de deteccao por `Heartbeat`.
- A raiz valida possui a tag `Interactable` e `InteractionType` igual a `Door` ou `Pickup`.
- Nao existe indicador visual de alvo ou UI de gameplay.
- A esfera de debug permanece opcional e desabilitada; qualquer conexao de `Heartbeat` fica restrita a essa visualizacao opcional.
- `DialogueController` continua usando `Enum.ContextActionPriority.High.Value + 1`; o binding de interacao usa `Enum.ContextActionPriority.High.Value`.
- `setEnabled(false)` desassocia `F`, limpa o alvo e bloqueia novos despachos; `setEnabled(true)` reassocia `F` somente se o controller estiver iniciado.
- `start()` e `stop()` sao idempotentes e aceitam chamadas antes ou depois de `setEnabled`.
- Todos os modulos e specs permanecem `--!strict`; nao usar `--!nocheck`, ignores amplos ou tipos globais para esconder diagnosticos.
- O projeto de testes usa o DataModel real, com fixtures isoladas em `beforeEach` e limpeza completa em `afterEach`.
- Nao criar `InteractionService` server-side nem um remoto generico para regras de dominio.
- `test.project.json` ja mapeia `ReplicatedStorage.Shared` para todo `src/shared`; somente `src/client/interactions` precisa de uma nova entrada explicita.
- Nao editar `Packages/` ou `DevPackages/` e nao iniciar os entrypoints normais no projeto de testes.
- Nao editar, integrar, testar ou usar `src/server/doors/StudioDoorScene.luau` como fixture.
- Nao usar `git add`, `git commit` ou qualquer operacao de staging nesta implementacao.

## File Map

| Arquivo | Responsabilidade |
|---|---|
| `src/shared/interactions/interactionTypes.luau` | Constantes e tipos do contrato comum |
| `src/client/interactions/InteractionController.luau` | Binding de `F`, probe, selecao, warnings e lifecycle |
| `tests/client/interactions/InteractionController.spec.luau` | Cobertura client-side do contrato e do algoritmo |
| `test.project.json` | Mapeamento do novo diretorio client-side |
| `README.md` | Comando de typecheck com `src/client/interactions` |

---

### Task 1: Shared Interaction Contract And Test Mapping

**Files:**
- Create: `src/shared/interactions/interactionTypes.luau`
- Modify: `test.project.json` no bloco `StarterPlayer.StarterPlayerScripts.Client`
- Modify: `README.md` no comando documentado de `luau-lsp analyze`

**Interfaces:**
- Produces `interactionTypes.INTERACTABLE_TAG`, `INTERACTION_TYPE_ATTRIBUTE`, `DOOR_TYPE`, `PICKUP_TYPE`, `ITEM_ID_ATTRIBUTE` e `QUANTITY_ATTRIBUTE`.
- Produces os tipos `InteractionType`, `InteractionHandler`, `ProbeConfig` e `Controller` para consumidores client-side.
- Does not consume nenhum handler ou service de dominio.

- [ ] **Step 1: Criar o modulo compartilhado strict**

Criar `src/shared/interactions/interactionTypes.luau` com o contrato abaixo. Os nomes de `ItemId` e `Quantity` ficam no contrato compartilhado para que o detector e o `PickupService` nao dupliquem strings de autoria.

```lua
--!strict

export type InteractionType = "Door" | "Pickup"

export type InteractionHandler = {
    interact: (target: Instance) -> (),
}

export type ProbeConfig = {
    radius: number,
    forwardOffset: number,
}

export type Controller = {
    start: () -> (),
    stop: () -> (),
    register: (interactionType: string, handler: InteractionHandler) -> (),
    setEnabled: (enabled: boolean) -> (),
    isEnabled: () -> boolean,
    getTarget: () -> Instance?,
}

return {
    INTERACTABLE_TAG = "Interactable",
    INTERACTION_TYPE_ATTRIBUTE = "InteractionType",
    DOOR_TYPE = "Door",
    PICKUP_TYPE = "Pickup",
    ITEM_ID_ATTRIBUTE = "ItemId",
    QUANTITY_ATTRIBUTE = "Quantity",
}
```

Nao colocar regras de distancia, inventario, porta ou coleta nesse modulo.

- [ ] **Step 2: Mapear o diretorio client-side no projeto de testes**

Adicionar no mesmo nivel de `camera`, `doors`, `dialogue`, `inventory`, `pickups`, `player` e `ui`:

```json
"interactions": {
  "$path": "src/client/interactions"
}
```

Nao adicionar um segundo mapeamento para `src/shared/interactions`, pois a entrada existente `ReplicatedStorage.Shared: { "$path": "src/shared" }` ja expoe o diretorio inteiro.

- [ ] **Step 3: Atualizar o typecheck documentado**

No comando de `README.md`, inserir `src/client/interactions` entre os diretorios client-side:

```text
src/client/camera src/client/doors src/client/dialogue src/client/interactions
src/client/inventory src/client/pickups src/client/player src/client/ui
```

Preservar todas as flags, definicoes e a exclusao de `src/server/init.server.luau` e `src/client/init.client.luau`.

- [ ] **Step 4: Verificar o contrato e os mapeamentos**

Executar:

```bash
selene --config selene.roblox.toml src/shared/interactions
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
rojo build -o /tmp/dungeon-game-canve-interaction-foundation-test.rbxlx test.project.json
```

Esperado: exit code `0` em todos os comandos e `ReplicatedStorage.TestEZTests.Client` capaz de resolver `client.interactions` quando o spec for criado.

---

### Task 2: Write The Failing Interaction Controller Spec

**Files:**
- Create: `tests/client/interactions/InteractionController.spec.luau`
- Use: `src/shared/interactions/interactionTypes.luau`

**Interfaces:**
- Consumes o DataModel real, `Players.LocalPlayer`, `Workspace`, `CollectionService` e `ContextActionService`.
- Produces uma suite TestEZ que define o comportamento de `InteractionController.new(probeConfig?)` antes do modulo existir.

- [ ] **Step 1: Criar fixtures isoladas**

O spec deve importar pelo caminho real do DataModel:

```lua
local Players = game:GetService("Players")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local InteractionController = require(client.interactions.InteractionController)
```

Criar em `beforeEach` um `Model` de personagem com `HumanoidRootPart` `Part`, orientar o root por `CFrame`, parentear o personagem em `Workspace` e substituir temporariamente `Players.LocalPlayer.Character`. Registrar todos os models, parts, connections de sinais e controllers para limpeza em `afterEach`. O cleanup deve chamar `stop()` antes de destruir as fixtures e restaurar o personagem original.

- [ ] **Step 2: Adicionar testes de geometria com ProbeConfig injetada**

Usar uma configuracao de teste diferente dos valores de producao, por exemplo:

```lua
local probeConfig = {
    radius = 2,
    forwardOffset = 1,
}
```

Cobrir:

1. Um `Part` tagueado com `Interactable` e `InteractionType = "Pickup"` dentro da esfera e entregue ao handler ao pressionar `F`.
2. Um alvo fora de `radius` nao e selecionado.
3. O centro segue o `LookVector` e o `forwardOffset`; girar o root muda o lado onde o alvo precisa estar.
4. Um alvo com a mesma altura do root e detectado, sem deslocamento vertical adicional.
5. Uma parte tagueada dentro do personagem e excluida pelo `OverlapParams`.
6. Um `Model` tagueado e resolvido a partir de qualquer `BasePart` descendente.
7. Duas pecas do mesmo alvo produzem uma unica raiz.
8. Duas raizes no volume selecionam a que possui a menor distancia entre a peca atingida e o centro da esfera.
9. Depois de detectar um alvo, pressionar `F` sem personagem, sem root ou sem alvo valido limpa `getTarget()`.
10. Criar ou mover um alvo depois de `start()` nao altera `getTarget()` ate outro pressionamento de `F`, provando que nao existe polling.

O helper que aciona `F` deve obter a funcao bound pelo `ContextActionService:GetAllBoundActionInfo()` e chama-la com `Enum.UserInputState.Begin`, sem fabricar entrega de rede ou `InputObject` real.

- [ ] **Step 3: Adicionar testes de contrato, warnings e handlers**

Cobrir:

1. Raiz `Interactable` sem `InteractionType` valido nao e despachada e gera warning com `GetFullName()`.
2. `InteractionType` valido sem a tag gera warning com o caminho completo.
3. `ItemId` sem a tag gera warning com o caminho completo.
4. A tag antiga `Door` sem o contrato novo gera warning, mas geometria sem qualquer metadata nao gera warning de alvo.
5. A mesma configuracao invalida nao gera outro warning em pressionamentos subsequentes de `F` durante o mesmo lifecycle.
6. Um alvo valido sem handler registrado permanece selecionado e gera warning contendo o tipo e o caminho.
7. `register("Pickup", handler)` encaminha exatamente a raiz selecionada.

Capturar warnings por `LogService.MessageOut`, filtrar `Enum.MessageType.MessageWarning` e desconectar a conexao em `afterEach`. A tabela de mensagens deve ser limpa em cada fixture.

- [ ] **Step 4: Adicionar testes de binding e lifecycle**

Verificar por `ContextActionService:GetAllBoundActionInfo()` que:

1. `start()` cria uma unica acao chamada `DungeonInteraction` com `Enum.KeyCode.F` e prioridade `Enum.ContextActionPriority.High.Value`.
2. Chamadas repetidas a `start()` nao substituem nem duplicam o binding.
3. `stop()` remove o binding, limpa o alvo e pode ser chamado repetidamente.
4. O estado inicial e habilitado.
5. `setEnabled(false)` antes de `start()` impede o binding; `setEnabled(true)` antes de `start()` permite o binding.
6. `setEnabled(false)` depois de `start()` remove `F` e limpa o alvo.
7. `setEnabled(true)` depois de `start()` reassocia `F`.
8. O binding do dialogo, quando ativo, fica em `High + 1`, portanto tem prioridade sobre `DungeonInteraction` sem o controller generico consultar o estado do dialogo.

- [ ] **Step 5: Rodar o spec antes da implementacao**

Executar o build do projeto de testes e iniciar uma sessao Play limpa. No DataModel `Client`, rodar:

```lua
return require(game.Players.LocalPlayer.PlayerScripts.TestEZClientRunner).run()
```

Esperado: falha de require para `InteractionController` ou falhas de contrato, confirmando que os testes apontam para o mapeamento real e ainda nao possuem implementacao.

---

### Task 3: Implement The Generic Controller

**Files:**
- Create: `src/client/interactions/InteractionController.luau`

**Interfaces:**
- Consumes `interactionTypes`, `Players.LocalPlayer`, `Workspace`, `CollectionService` e `ContextActionService`.
- Produces `new(probeConfig: ProbeConfig?) -> Controller` e uma instancia default com os mesmos metodos publicos.
- The default production probe uses `radius = 3` and `forwardOffset = 2.5`.

- [ ] **Step 1: Definir estado, defaults e registro de handlers**

Manter em cada instancia apenas:

```lua
local started = false
local enabled = true
local target: Instance? = nil
local handlers: { [string]: interactionTypes.InteractionHandler } = {}
```

Copiar a configuracao recebida para defaults nomeados. `register` deve substituir o handler do mesmo tipo, permitindo que a composicao registre o dominio antes ou depois de `start()`.

- [ ] **Step 2: Implementar a resolucao da raiz interagivel**

Para cada `BasePart` retornada pela busca, subir pelos pais. Ao visitar cada instancia:

1. Se possuir `Interactable`, aceitar somente `Model` ou `BasePart`.
2. Ler `InteractionType` e aceitar somente `Door` ou `Pickup`.
3. Retornar a primeira raiz valida.
4. Para candidatos parcialmente configurados, emitir warning once com `GetFullName()`.
5. Para `InteractionType`, `ItemId` ou tag antiga `Door` sem o contrato novo, emitir o warning correspondente.
6. Para paredes, piso e geometria sem esses metadados, continuar subindo sem warning.

Usar uma tabela por instancia e codigo de warning para que a mesma configuracao nao seja reportada a cada `F`. Limpar essa tabela em `stop()` para que um novo lifecycle possa diagnosticar novamente uma fixture recriada.

- [ ] **Step 3: Implementar a busca e a selecao deterministica**

No processamento de `F`, localizar o personagem e `HumanoidRootPart`. Se qualquer um faltar, definir `target = nil` e retornar `Enum.ContextActionResult.Sink`.

Calcular o centro exatamente assim:

```lua
local center = root.Position + root.CFrame.LookVector * config.forwardOffset
```

Criar `OverlapParams` com `FilterType = Enum.RaycastFilterType.Exclude` e `FilterDescendantsInstances = { character }`. Chamar:

```lua
local parts = Workspace:GetPartBoundsInRadius(center, config.radius, params)
```

Para cada parte, resolver a raiz e guardar, por raiz, a menor distancia `(part.Position - center).Magnitude`. Depois escolher a raiz com menor distancia. Se nao houver raiz valida, limpar `target`. O primeiro resultado do engine deve permanecer em caso de empate; nao adicionar um segundo criterio de tuning.

- [ ] **Step 4: Implementar dispatch e warnings de handler**

Depois de selecionar a raiz, guardar `target`, ler `InteractionType` e procurar o handler. Se nao houver handler, emitir um warning once contendo o tipo e `target:GetFullName()` e nao chamar nada. Se houver handler, chamar:

```lua
handler.interact(target)
```

O callback deve processar somente `Enum.UserInputState.Begin` e retornar `Enum.ContextActionResult.Sink` em todos os outros estados.

- [ ] **Step 5: Implementar binding, habilitacao e cleanup**

Usar uma constante de acao, por exemplo:

```lua
local ACTION_NAME = "DungeonInteraction"
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value
```

`start()` deve bindar uma vez somente quando `enabled == true`. `setEnabled(false)` deve desbindar, limpar `target` e impedir dispatch. `setEnabled(true)` deve bindar novamente somente se `started == true`. `stop()` deve desbindar, limpar alvo, warnings e qualquer recurso de debug, mesmo se ja estiver parado.

Nao consultar `DialogueController`; a prioridade maior do binding do dialogo e o mecanismo de bloqueio.

- [ ] **Step 6: Manter o debug opcional sem indicador de gameplay**

Migrar a esfera existente para este modulo somente atras de uma guarda local explicita e desabilitada, por exemplo `local DEBUG_ENABLED = false`. Quando habilitada manualmente, ela pode atualizar apenas a representacao visual em `Heartbeat`; a funcao de deteccao nunca deve ser chamada por essa conexao. Ao parar, desconectar e destruir a esfera.

Em producao e nos testes, nenhuma esfera deve aparecer com a guarda desabilitada.

- [ ] **Step 7: Expor a instancia default e executar os testes**

Expor uma factory e os metodos da instancia default:

```lua
local defaultController = createController(nil)

return {
    new = createController,
    start = defaultController.start,
    stop = defaultController.stop,
    register = defaultController.register,
    setEnabled = defaultController.setEnabled,
    isEnabled = defaultController.isEnabled,
    getTarget = defaultController.getTarget,
}
```

Executar:

```bash
selene --config selene.roblox.toml src/client/interactions
selene --config selene.roblox-tests.toml tests/client/interactions
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
rojo build -o /tmp/dungeon-game-canve-interaction-foundation-test.rbxlx test.project.json
```

No Studio, rodar o runner client e confirmar `failed == 0`. Repetir a suite client em uma segunda sessao Play limpa, conforme `AGENTS.md`, parando Play entre as sessoes e confirmando que bindings, fixtures e conexoes temporarias desapareceram.

- [ ] **Step 8: Inspecionar o worktree sem staging**

Executar:

```bash
git status --short
git diff --check
```

Confirmar que somente os cinco arquivos deste plano foram alterados alem de mudancas preexistentes do usuario. Nao executar commit.

## Handoff

O Plano 2 pode consumir `InteractionController.register("Door", DoorController)` e `InteractionController.start()` sem alterar o contrato deste plano. O Plano 3 deve registrar `PickupController` antes do mesmo `start()` e nao deve criar um segundo binding de `F`.

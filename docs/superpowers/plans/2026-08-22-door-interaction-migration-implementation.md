# Door Interaction Migration Implementation Plan

> **For agentic workers:** Use the implementation workflow selected by the user. Steps use checkbox (`- [ ]`) syntax for tracking. Do not create commits; the user explicitly requested that this worktree remain uncommitted.

**Goal:** Migrar portas para o contrato `Interactable`/`InteractionType` e transformar `DoorController` em um handler consumido pelo `InteractionController`, preservando as regras atuais de unlock, enter, dialogo e transicao.

**Architecture:** O servidor continuara dono de toda validacao e mutacao de portas. O `DoorService` passara a validar o contrato comum, enquanto o cliente recebera uma raiz selecionada pelo controller generico e executara somente a decisao de fluxo e o feedback local. O bootstrap client-side registrara o handler de portas no controller criado pelo Plano 1.

**Tech Stack:** Luau `--!strict`, Roblox `CollectionService`, `RemoteFunction`, `ContextActionService`, `DialogueController`, `InventoryController`, `TransitionController`, TestEZ no Roblox Studio, Rojo `7.7.0`, Selene `0.29.0` e luau-lsp `1.69.0`.

## Global Constraints

- Este plano depende de `src/shared/interactions/interactionTypes.luau` e `src/client/interactions/InteractionController.luau` do Plano 1.
- A tag comum e `Interactable` e o atributo comum e `InteractionType = "Door"`.
- A tag legada `Door` pode permanecer para ferramentas existentes, mas nao sera requisito de deteccao nem de validacao runtime.
- `DoorService` continua autoridade server-side para porta, distancia, lado, concorrencia, unlock, enter e inventario.
- O cliente envia apenas `{ door = doorModel, action = "unlock" | "enter" }` para `InteractDoor`.
- A chave nunca e consumida e `Locked` continua sendo alterado somente pelo servidor.
- `DoorController` nao tera binding de input, busca volumetrica, alvo proprio ou dependencia de estado de dialogo.
- `DialogueController` continua registrando `F` em `Enum.ContextActionPriority.High.Value + 1`; o controller generico permanece abaixo nessa prioridade.
- A geometria e as regras atuais do `DoorService` devem ser preservadas, incluindo o eixo local ja usado pelo `Center`, a margem de saida e a altura do root.
- `StudioDoorScene.luau` fica fora do escopo: nao alterar, integrar, testar ou usar como fixture.
- Nao criar specs de UI ou da cena de Studio.
- Todos os modulos e specs permanecem `--!strict`; nao usar `--!nocheck`, ignores amplos ou tipos globais para esconder diagnosticos.
- Fixtures que criam Instances, tags, conexoes ou estado mutavel devem ser isoladas em `beforeEach` e limpas em `afterEach`.
- Nao editar `Packages/` ou `DevPackages/`.
- Nao usar `git add`, `git commit` ou qualquer operacao de staging nesta implementacao.

## File Map

| Arquivo | Responsabilidade |
|---|---|
| `src/server/utils/DoorModelInitializer.luau` | Aplicar tag e atributo do contrato comum, mantendo tag legada |
| `src/server/doors/DoorService.luau` | Revalidar o contrato comum e preservar a autoridade de portas |
| `src/client/doors/DoorController.luau` | Handler client-side de unlock, enter, dialogos e transicao |
| `tests/server/doors/DoorService.spec.luau` | Cobertura da validacao e mutacao server-side |
| `tests/client/doors/DoorController.spec.luau` | Cobertura do handler sem input ou deteccao |
| `src/client/init.client.luau` | Registrar handler de portas no controller generico |

---

### Task 1: Update Door Fixtures And Server Contract Tests

**Files:**
- Modify: `tests/server/doors/DoorService.spec.luau`
- Use: `src/shared/doors/doorTypes.luau`
- Use: `src/shared/interactions/interactionTypes.luau`

**Interfaces:**
- Consumes `DoorService.invoke(player, request)` e `InteractDoor.OnServerInvoke` existentes.
- Produces fixtures com a arvore `Model [Interactable, InteractionType = "Door"] -> Doorway -> Center`.
- Mantains the existing fake `ItemUseService` and inventory helpers.

- [ ] **Step 1: Atualizar o helper de porta para o contrato novo**

Adicionar o modulo `interactionTypes` e alterar `createDoor` para, por padrao, aplicar:

```lua
CollectionService:AddTag(door, interactionTypes.INTERACTABLE_TAG)
door:SetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE, interactionTypes.DOOR_TYPE)
```

Manter uma opcao explicita para omitir a tag comum ou o atributo, alem das opcoes atuais de `Doorway`, `Center`, `Locked` e `RequiredItemId`. A tag antiga deve ser aplicada somente quando o teste estiver cobrindo compatibilidade da ferramenta legada.

- [ ] **Step 2: Adicionar casos de validacao do contrato comum**

Acrescentar casos que verifiquem:

1. Uma porta com tag `Interactable`, tipo `Door` e `Doorway/Center` continua sendo aceita.
2. Um modelo apenas com tag `Door` retorna `invalid_door`.
3. Um modelo sem tag `Interactable` retorna `invalid_door` mesmo que tenha `InteractionType = "Door"`.
4. Um modelo com `InteractionType = "Pickup"` retorna `invalid_door`.
5. Um modelo com tipo ausente retorna `invalid_door`.
6. A porta fora do `Workspace`, a estrutura ausente e os atributos de porta invalidos preservam as razoes existentes.

Nao remover os casos existentes de distancia, lado ambiguo, estado, unlock, enter e concorrencia.

- [ ] **Step 3: Rodar o spec antes da implementacao do service**

Executar no projeto de testes:

```bash
selene --config selene.roblox-tests.toml tests/server/doors
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
```

Iniciar Play limpo e rodar no DataModel `Server`:

```lua
return require(game.ServerScriptService.TestEZRunner).run()
```

Esperado: os novos casos falham porque o service ainda exige a tag legada `Door` e ignora `InteractionType`.

---

### Task 2: Migrate The Door Model Initializer

**Files:**
- Modify: `src/server/utils/DoorModelInitializer.luau`

**Interfaces:**
- Consumes `interactionTypes.INTERACTABLE_TAG` e `interactionTypes.INTERACTION_TYPE_ATTRIBUTE`.
- Produces portas reconfiguradas com o contrato comum e a tag legada preservada.
- Does not change `StudioDoorScene.luau` or any runtime scene creation.

- [ ] **Step 1: Importar o contrato compartilhado**

Adicionar o require de `ReplicatedStorage.Shared.interactions.interactionTypes` ao lado de `doorTypes`. Manter `doorTypes` para nomes e atributos especificos de portas.

- [ ] **Step 2: Aplicar o tipo e as tags durante a inicializacao**

Depois de aplicar `Locked` e `RequiredItemId`, adicionar:

```lua
model:SetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE, interactionTypes.DOOR_TYPE)
CollectionService:AddTag(model, interactionTypes.INTERACTABLE_TAG)
CollectionService:AddTag(model, doorTypes.DOOR_TAG)
```

A ordem deve garantir que o modelo saia do initializer com `Doorway.Center`, `LockedDialogue`, atributos de porta e ambos os contratos. Nao remover a tag antiga, pois ferramentas existentes ainda podem consulta-la.

- [ ] **Step 3: Rodar lint do initializer**

Executar:

```bash
selene --config selene.roblox.toml src/server/utils/DoorModelInitializer.luau
```

Esperado: exit code `0`. A validacao manual do plugin ou do Studio nao faz parte deste plano; apenas o contrato produzido pelo modulo deve ser preservado.

---

### Task 3: Implement Common Door Validation And Preserve Server Rules

**Files:**
- Modify: `src/server/doors/DoorService.luau`

**Interfaces:**
- Consumes `interactionTypes`, `doorTypes`, `ItemUseService` e `remotes.InteractDoor`.
- Produces `DoorService.new(itemUseService): Service` com `start()` e `stop()` idempotentes e `invoke()` que revalida cada pedido.
- Keeps the existing `DoorActionResult`, unlock behavior, teleport and per-door lock semantics.

- [ ] **Step 1: Adicionar o require do contrato comum**

Importar `ReplicatedStorage.Shared.interactions.interactionTypes`. Nao substituir `doorTypes`, pois ele continua sendo a fonte das constantes especificas de porta.

- [ ] **Step 2: Alterar a validacao estrutural da porta**

Na funcao privada que valida a porta, exigir nesta ordem:

1. `door:IsDescendantOf(Workspace)`.
2. `CollectionService:HasTag(door, interactionTypes.INTERACTABLE_TAG)`.
3. `door:GetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE) == interactionTypes.DOOR_TYPE`.
4. `Doorway` como `BasePart` direto e `Center` como `Attachment` direto.
5. `Locked` como boolean e `RequiredItemId` como string.
6. Se `Locked == true`, `RequiredItemId` nao vazio, existente no catalogo e com capability `unlock`.

O retorno deve continuar usando `invalid_door` para instancia, parent, tag, tipo ou estrutura invalidos e `invalid_config` para atributos/configuracao de porta invalidos. A tag antiga `Door` nao deve ser consultada nessa validacao.

- [ ] **Step 3: Remover a dependencia runtime da tag legada**

Eliminar a validacao ou descoberta que trate `doorTypes.DOOR_TAG` como requisito. `start()` pode manter somente o binding de `InteractDoor`; nao criar cache de portas nem mudar o contrato por causa da tag antiga. Cada pedido deve revalidar a instancia atual.

- [ ] **Step 4: Preservar unlock, enter e concorrencia**

Manter o fluxo existente:

```lua
if request.action == "unlock" then
    -- valida Locked, usa ItemUseService e define Locked = false
end

-- enter continua rejeitando porta locked e calculando o lado pelo Center
```

Nao mover regra de inventario para o controller generico. Nao consumir a chave. Nao alterar o eixo de calculo, a tolerancia server-side, a margem de saida, a altura ou a orientacao ja exercitados pelos testes existentes.

- [ ] **Step 5: Rodar a suite server-side**

Executar:

```bash
selene --config selene.roblox.toml src/server/doors/DoorService.luau
selene --config selene.roblox-tests.toml tests/server/doors
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
```

No DataModel `Server`, rodar:

```lua
return require(game.ServerScriptService.TestEZRunner).run()
```

Esperado: `failed == 0`, callback `InteractDoor` instalado uma vez, callback removido por `stop()` e nenhum teste de unlock consumindo a chave.

---

### Task 4: Convert DoorController Into A Handler

**Files:**
- Modify: `src/client/doors/DoorController.luau`
- Modify: `tests/client/doors/DoorController.spec.luau`

**Interfaces:**
- Consumes `DoorRequest`, `DoorActionResult`, `InventoryController.getState`, `DialogueController.show`, `TransitionController.run` e `InteractionHandler`.
- Produces `DoorController.new(dependencies)` e uma instancia default com `interact(target: Instance) -> ()`.
- Does not expose `start`, `stop` or `getTarget`.

- [ ] **Step 1: Substituir a tabela de dependencias**

Manter apenas as dependencias de dominio:

```lua
export type Dependencies = {
    getInventory: () -> InventoryState?,
    invokeDoor: (request: DoorRequest) -> DoorActionResult,
    dialogue: {
        show: (text: string, callback: ((nil, string) -> ())?) -> (),
    },
    transition: {
        run: (request: () -> DoorActionResult, callback: (result: DoorActionResult) -> ()) -> boolean,
    },
}
```

Remover `dialogue.getState`, pois a prioridade do `DialogueController` impede que o handler seja chamado durante um dialogo ativo.

- [ ] **Step 2: Remover input, deteccao e debug da porta**

Remover imports e estado relacionados a `ContextActionService`, `Players`, `RunService`, `CollectionService`, probe, esfera, `target`, `scan` e `findDoorInSphere`. A deteccao e o debug opcional pertencem ao `InteractionController` do Plano 1.

- [ ] **Step 3: Preservar a decisao de dominio em `interact`**

Implementar o handler com a sequencia:

1. Retornar sem efeito se `target` nao for `Model`.
2. Se `Locked == false`, chamar `transition.run` com `InteractDoor({ door = target, action = "enter" })`.
3. Se `Locked == true`, procurar localmente um item com `itemId == RequiredItemId`.
4. Com item, chamar `InteractDoor({ door = target, action = "unlock" })`.
5. Mostrar `Porta destrancada` somente em sucesso com `action = "unlock"`.
6. Sem item, ler `LockedDialogue` e mostrar `StringValue`s filhos diretos ordenados por `Name`.
7. Avancar para a proxima mensagem somente com `reason == "completed"`; cancelamento encerra a sequencia.
8. Usar `doorTypes.FALLBACK_LOCKED_MESSAGE` se a pasta estiver ausente, vazia ou sem valores nao vazios.
9. Em resposta `missing_item` do unlock ou do enter, mostrar o dialogo de porta trancada; para `locked`, `already_unlocked`, `busy` e `invalid_config`, nao iniciar outra acao.

O handler nao deve escrever `Locked`, `RequiredItemId`, `InteractionType` ou qualquer outro atributo.

- [ ] **Step 4: Adaptar o spec client-side para chamadas diretas**

Remover o helper que pressionava `F`, os personagens e os testes de esfera. Manter fixtures de modelos com atributos de porta e criar dependencias fake para capturar requests, dialogos e transicoes.

Cobrir:

1. `interact` rejeita uma instancia que nao seja `Model`.
2. Unlock com item envia somente `{ door = model, action = "unlock" }`.
3. Unlock bem-sucedido mostra `Porta destrancada` e nao inicia enter no mesmo input.
4. Sem item, mensagens sao ordenadas, encadeadas e nenhum remoto e chamado.
5. Pasta ausente, vazia ou com valores vazios usa o fallback.
6. Cancelamento nao mostra a mensagem seguinte.
7. Porta aberta usa `TransitionController` e envia somente `enter`.
8. Respostas stale ou falhas server-side nao causam request adicional.

Nao manter um teste que exija `DoorController` consultar `DialogueController.getState`; essa responsabilidade foi removida.

- [ ] **Step 5: Rodar a suite client-side**

Executar:

```bash
selene --config selene.roblox.toml src/client/doors/DoorController.luau
selene --config selene.roblox-tests.toml tests/client/doors
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
```

No DataModel `Client`, rodar:

```lua
return require(game.Players.LocalPlayer.PlayerScripts.TestEZClientRunner).run()
```

Esperado: `failed == 0` e nenhuma acao de input registrada pelo `DoorController`.

---

### Task 5: Register The Door Handler In The Production Bootstrap

**Files:**
- Modify: `src/client/init.client.luau`

**Interfaces:**
- Consumes a instancia default de `InteractionController` e o handler default de `DoorController`.
- Produces o primeiro bootstrap integrado: portas usam `F` pelo controller generico.
- Leaves the pickup registration seam for Plan 3.

- [ ] **Step 1: Requerer o controller generico**

Adicionar:

```lua
local InteractionController = require(script.interactions.InteractionController)
```

Manter os requires de `DoorController`, `DialogueController`, `InventoryController` e `TransitionController` existentes.

- [ ] **Step 2: Substituir o start do DoorController**

Depois de iniciar inventario, dialogo e transicao, registrar e iniciar o controller:

```lua
InteractionController.register("Door", DoorController)
InteractionController.start()
```

Remover `DoorController.start()`. Nao criar outro binding de `F`. O Plano 3 acrescentara `InteractionController.register("Pickup", PickupController)` imediatamente antes do mesmo `start()`.

- [ ] **Step 3: Verificar a composicao sem iniciar o entrypoint no test place**

Executar:

```bash
selene --config selene.roblox.toml src/client/init.client.luau
rojo build -o /tmp/dungeon-game-canve-door-bootstrap.rbxlx default.project.json
```

Esperado: build normal concluido, `DoorController` sem binding proprio e `InteractionController` resolvido no projeto normal. O projeto de testes continua sem mapear ou iniciar `init.client.luau`.

---

### Task 6: Cross-Check And Handoff

**Files:**
- Verify: all files changed by Tasks 1-5
- Do not modify: `src/server/doors/StudioDoorScene.luau`

- [ ] **Step 1: Executar verificacoes estaticas do plano**

Executar:

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
  src/server/inventory src/server/items src/server/pickups src/server/doors src/server/player \
  src/client/camera src/client/doors src/client/dialogue src/client/interactions \
  src/client/inventory src/client/pickups src/client/player src/client/ui \
  tests
```

Esperado: exit code `0` sem supressions novas.

- [ ] **Step 2: Executar os runners em uma sessao de teste limpa**

Iniciar Play no projeto de testes e confirmar `failed == 0` nos runners server e client. Parar Play e limpar conexoes antes de qualquer nova rodada. A repeticao completa em duas sessoes e feita no Plano 3, conforme `AGENTS.md`.

- [ ] **Step 3: Inspecionar o worktree sem staging**

Executar:

```bash
git status --short
git diff --check
```

Confirmar que nenhuma alteracao foi feita em `StudioDoorScene`, que o spec de design e `AGENTS.md` preexistentes permanecem intactos e que nao ha operacao de staging ou commit.

## Handoff

O Plano 3 deve adicionar `PickupController` ao mesmo `InteractionController` antes do `start()` existente, sem reintroduzir input em `DoorController` e sem alterar as regras de `DoorService`.

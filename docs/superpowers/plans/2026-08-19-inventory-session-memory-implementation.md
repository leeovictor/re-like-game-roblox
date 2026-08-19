# Inventário Volátil por Sessão Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remover a persistência do inventário e manter um inventário vazio e autoritativo em memória durante cada sessão do jogador.

**Architecture:** `InventoryService` será o único proprietário dos snapshots por `Player`. Ao entrar, ele criará `InventoryStore.defaultInventory()`, notificará o cliente e carregará o personagem; ao sair, descartará o estado sem executar salvamento. Os adaptadores de persistência e o código JSON serão removidos, enquanto a API de mutações e os remotes permanecerão inalterados.

**Tech Stack:** Luau `--!strict`, Roblox Players/RemoteEvent/RemoteFunction, TestEZ no Roblox Studio, Rojo, Selene e `luau-lsp`.

## Global Constraints

- Manter `--!strict` nos módulos Luau e não usar `--!nocheck`, ignores amplos ou `typeErrors: false`.
- Preservar imports baseados em `script` e os contratos dos módulos de produção.
- Os testes devem ser executados somente pelo TestEZ no Roblox Studio, sem adicionar testes de UI.
- Usar o DataModel real para validar inicialização de `Players`, remotes e `LoadCharacterAsync`.
- O estado deve ser descartado ao sair do jogador e ao reiniciar o servidor; não criar fallback de persistência.
- Não alterar as mudanças existentes e não relacionadas em `src/server/init.server.luau` referentes a pickups e à cena de portas.
- Não editar `Packages/` ou `DevPackages/`.

---

### Task 1: Migrar o inventário para memória de sessão

**Files:**
- Modify: `src/server/inventory/InventoryService.luau`
- Modify: `src/server/init.server.luau:3-8,25-26` somente para remover imports e injeção de persistência; preservar o restante do arquivo, inclusive alterações não relacionadas já presentes.
- Modify: `src/server/inventory/InventoryStore.luau:236-470` removendo serialização JSON e helpers usados exclusivamente por ela.
- Modify: `tests/server/inventory/InventoryStore.spec.luau` removendo os casos de serialização/desserialização/JSON e mantendo os testes de estado e mutações.
- Modify: `docs/inventory-architecture.md` removendo o subsistema e os fluxos de persistência e documentando estado volátil por sessão.
- Delete: `src/server/inventory/persistence/MemoryPersistence.luau`
- Delete: `src/server/inventory/persistence/DataStorePersistence.luau`
- Delete: `tests/server/inventory/MemoryPersistence.spec.luau`

**Interfaces:**
- Consumes: `InventoryStore.defaultInventory`, `InventoryStore.copyState`, `Players.PlayerAdded`, `Players.PlayerRemoving`, `InventoryChanged` e `GetInventory` existentes.
- Produces: `InventoryService.new(): Service` sem argumento; a API de `Service` restante mantém as assinaturas atuais de mutação, consulta e `start`.

- [ ] **Step 1: Add the regression assertion for removed persistence API**

No final de `tests/server/inventory/InventoryStore.spec.luau`, antes do teste de capability `equip`, adicionar um caso que falhe enquanto os métodos JSON ainda existirem:

```lua
it("does not expose persistence serialization", function()

	local store = InventoryStore :: any
	expect(store.serialize).to.equal(nil)
	expect(store.deserialize).to.equal(nil)
end)
```

Manter o `describe` e o `return function` existentes; não adicionar fixtures globais ou estado mutável compartilhado.

- [ ] **Step 2: Run the focused server suite and verify the regression fails**

Servir o projeto de testes e executar o runner no DataModel `Server`:

```bash
rojo serve test.project.json
```

No Roblox Studio conectado à sessão `RE Like Test`, executar:

```lua
require(game.ServerScriptService.TestEZRunner).run()
```

Resultado esperado antes da implementação: a nova asserção falha porque `InventoryStore.serialize` e `InventoryStore.deserialize` ainda estão expostos. Os testes JSON existentes podem continuar passando neste ponto; a falha esperada é especificamente a asserção de ausência.

- [ ] **Step 3: Replace asynchronous persistence loading with synchronous session initialization**

Em `src/server/inventory/InventoryService.luau`:

1. Remover o tipo privado `Persistence` e as constantes `loadBackoffSeconds` e `loadFailureMessage`.
2. Alterar a assinatura para `function InventoryService.new(): Service`.
3. Remover `loadingPlayers`, `playerGenerations`, `loadPlayer`, `beginLoad` e todo o retry com `pcall`, `task.wait`, `Kick` e `LoadCharacterAsync` pós-carregamento.
4. Substituir esses fluxos por um inicializador síncrono com proteção contra duplicação:

```lua
local function initializePlayer(player: Player): ()
	if loadedStates[player] ~= nil then
		return
	end

	local snapshot = InventoryStore.defaultInventory()
	loadedStates[player] = snapshot
	inventoryChanged:FireClient(player, copyState(snapshot))
	if player.Parent ~= nil then
		player:LoadCharacterAsync()
	end
end
```

5. Substituir `removePlayer` por uma limpeza direta:

```lua
local function removePlayer(player: Player): ()
	loadedStates[player] = nil
end
```

6. Em `service:start`, manter `Players.CharacterAutoLoads = false`, conectar `PlayerAdded` a `initializePlayer`, conectar `PlayerRemoving` a `removePlayer` e inicializar jogadores já presentes com `Players:GetPlayers()`.
7. Não alterar `applyMutation`, `applyUseMutations`, `getSnapshot` ou o callback `getInventory.OnServerInvoke` além do necessário para compilar sem a dependência removida.

- [ ] **Step 4: Remove persistence selection from server composition**

Em `src/server/init.server.luau`, remover apenas:

```lua
local MemoryPersistence = require(script.inventory.persistence.MemoryPersistence)
local DataStorePersistence = require(script.inventory.persistence.DataStorePersistence)
```

E substituir:

```lua
local persistence = if RunService:IsStudio() then MemoryPersistence.new() else DataStorePersistence.new()
local inventoryService = InventoryService.new(persistence)
```

por:

```lua
local inventoryService = InventoryService.new()
```

Manter `RunService`, pois o arquivo ainda o utiliza para `mapPickupDefinitions`, e preservar exatamente os comentários e alterações existentes sobre pickups e `StudioDoorScene`.

- [ ] **Step 5: Remove serialization implementation and obsolete tests**

Em `src/server/inventory/InventoryStore.luau`, remover `escapeString`, `jsonValue`, `parseJson`, `InventoryStore.serialize` e `InventoryStore.deserialize`. Remover também `hexadecimalValue` e `encodeUtf8`, que são usados somente pelo parser JSON. Manter `isFinite`, pois ela continua sendo usada por validação de atributos e quantidades.

Em `tests/server/inventory/InventoryStore.spec.luau`, remover os casos que cobrem serialização, round-trip, escapes Unicode, surrogates, números JSON, whitespace JSON e desserialização de estados inválidos. Preservar os testes de `defaultInventory`, cópia, adição/remoção, quantidades, atributos, equipagem e capability do catálogo, além da nova asserção de ausência da API JSON.

- [ ] **Step 6: Delete obsolete persistence modules and update architecture documentation**

Excluir os três arquivos listados no cabeçalho da task. Não substituir `MemoryPersistence` por outro módulo.

Em `docs/inventory-architecture.md`:

- remover o subgrafo `PERSIST`, suas classes e as arestas `load / save`;
- atualizar `InventoryService` para “mantém estado volátil por jogador, aplica mutações e replica snapshots”;
- reescrever o fluxo de carregamento para indicar que `PlayerAdded` cria um estado vazio e carrega o personagem imediatamente após a notificação inicial;
- substituir a seção “Persistência” por uma seção de “Estado de sessão” explicando que o estado é descartado ao sair ou reiniciar o servidor;
- remover os caminhos dos arquivos na pasta `persistence`;
- manter inalterados os fluxos de pickup, uso de item, autoridade server-side e contratos dos remotes.

- [ ] **Step 7: Run the server tests and validate the session behavior in Play**

Executar novamente no DataModel `Server`:

```lua
require(game.ServerScriptService.TestEZRunner).run()
```

Esperado: `failed == 0`, incluindo a asserção de que a API de serialização não existe. Em seguida, iniciar uma rodada limpa de Play e verificar no DataModel `Server` que `InventoryService` inicia sem erro; no DataModel `Client`, confirmar que o cliente recebe snapshot vazio e que o personagem é carregado. Fazer uma segunda rodada limpa para confirmar que o inventário começa vazio novamente após reiniciar a sessão.

Também verificar que a saída não contém chamadas ou erros de DataStore e que `PlayerRemoving` não tenta salvar estado.

- [ ] **Step 8: Run static verification and search for stale references**

Executar exatamente:

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
  src/server/inventory src/server/items src/server/pickups \
  src/client/camera src/client/inventory src/client/pickups src/client/player src/client/ui \
  tests
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

Depois, confirmar que não existem referências stale em código de produção,
testes ou documentação de arquitetura/runtime:

```bash
git grep -n -E 'DataStore|MemoryPersistence|DataStorePersistence|persistence:|loadBackoff|InventoryStore\.(serialize|deserialize)' -- src tests docs/inventory-architecture.md
```

Esperado: nenhuma saída. Referências históricas na especificação e no plano não entram nesta busca.

- [ ] **Step 9: Commit only the implementation files**

Antes de commitar, revisar `git status`, `git diff` e `git diff --cached`. Adicionar somente os arquivos desta task, sem incluir a alteração pré-existente e não relacionada de `src/server/init.server.luau` além das linhas de persistência modificadas:

```bash
git add -- \
  src/server/inventory/InventoryService.luau \
  src/server/inventory/InventoryStore.luau \
  src/server/init.server.luau \
  tests/server/inventory/InventoryStore.spec.luau \
  docs/inventory-architecture.md \
  src/server/inventory/persistence/MemoryPersistence.luau \
  src/server/inventory/persistence/DataStorePersistence.luau \
  tests/server/inventory/MemoryPersistence.spec.luau
git diff --cached --check
git commit -m "refactor: keep inventory in session memory"
```

Como `src/server/init.server.luau` já contém alterações não relacionadas antes desta task, não usar `git add` do arquivo inteiro sem revisar os hunks. Antes do commit, remover do índice qualquer hunk de pickups ou portas e manter somente a remoção dos dois imports de persistência e a troca para `InventoryService.new()`. Confirmar com:

```bash
git diff --cached -- src/server/init.server.luau
```

O diff staged desse arquivo não pode conter os comentários ou alterações de pickups/portas. O commit deve conter somente a migração do inventário e a documentação/testes correspondentes; não usar `git add .`.

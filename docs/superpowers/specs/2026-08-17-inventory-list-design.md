# Design: Listagem de Inventário (somente leitura)

Data: 2026-08-17
Status: Aprovado para planejamento

## Objetivo

Permitir que o cliente liste os itens do inventário do jogador. O inventário é
autoritativo no servidor e persistido em Roblox DataStore em produção. Durante
o desenvolvimento no Studio, a persistência é substituída por um store em
memória com itens seed, para teste rápido sem DataStore.

Escopo explícito: **somente listar**. Não há pickup, uso, descarte, trade ou
qualquer mutação em jogo nesta etapa.

## Decisões travadas

| Tema | Decisão |
|---|---|
| Autoridade | Servidor é dono do estado; cliente só replica e lê |
| Persistência | `DataStoreService` em produção; store em memória no Studio |
| Arquitetura | Camadas: lógica pura + backend de persistência injetável + serviço + controller |
| Notificação | `sleitnick/signal@2.0.3` (Wally) para `changed` no controller |
| React | Hook `useInventory()` (sem Context por enquanto) |
| Load | Gate no load: bloqueia spawn até carregar; kick após retries no DataStore |
| Session lock | Fora de escopo (YAGNI; `UpdateAsync` + autosave mitigam no futuro) |
| Save | Apenas best-effort no `PlayerRemoving`; sem autosave/save-por-mudança (não há mutação) |
| Seed | Store em memória devolve inventário inicial com itens placeholder |

## Arquitetura e componentes

```
src/shared/inventory/items.luau                     tipos + catálogo de itens
src/shared/remotes.luau                             remotes: InventoryChanged, GetInventory
src/server/inventory/InventoryStore.luau            lógica pura: serialize/deserialize + defaultInventory
src/server/inventory/persistence/DataStorePersistence.luau  load/save real (UserId)
src/server/inventory/persistence/MemoryPersistence.luau     tabela em memória + seed
src/server/inventory/InventoryService.luau          orquestra: gate, remotes, save no leave
src/server/init.server.luau                         escolhe backend por RunService:IsStudio()
src/client/inventory/InventoryController.luau       réplica + Signal + remotes
src/client/inventory/useInventory.luau              hook React
src/client/ui/App.luau                              renderiza lista; nil = "Carregando..."
tests/server/inventory/InventoryStore.spec.luau     serialize/deserialize/seed
tests/server/inventory/MemoryPersistence.spec.luau  seed + persistência no mapa
```

### Responsabilidades

- **`items.luau`** (shared): tipos `ItemId`, `ItemDef`, `InventoryState` e o
  catálogo `items` (id, nome, empilhável). Única fonte da verdade de quais ids
  existem.
- **`InventoryStore`** (server, puro): serializa/deserializa `InventoryState`
  para JSON com campo `version` (migração futura) e produz o inventário inicial
  (`defaultInventory`) a partir do catálogo. Sem dependência de APIs Roblox →
  testável no Lune.
- **`DataStorePersistence`** (server): interface `load(userId)` / `save(userId, state)`.
  Chave = `tostring(userId)`; usa `DataStoreService:GetDataStore("PlayerInventory")`
  e `UpdateAsync` para gravação atômica.
- **`MemoryPersistence`** (server, puro): mesma interface; guarda em uma tabela
  `userId -> InventoryState`. No primeiro acesso de um userId, devolve
  `InventoryStore.defaultInventory()` (seed). Sem APIs Roblox → testável no Lune.
- **`InventoryService`** (server): no `PlayerAdded`, carrega via backend com
  retries (5 tentativas, backoff), faz gate no load (kick em falha definitiva),
  dispara `InventoryChanged` com o snapshot e expõe `GetInventory` (invoke
  retorna o estado atual em memória). No `PlayerRemoving`, `save` best-effort.
- **`InventoryController`** (client): `start()` conecta `InventoryChanged` e
  invoca `GetInventory`; mantém `_state` (nil = carregando) e expõe
  `getState()`, `changed: Signal` e `stop()`. Cada snapshot novo é uma referência
  nova (imutabilidade) para o React re-renderizar.
- **`useInventory`** (client): hook que lê `getState()` e assina `changed`,
  chamando `setState` a cada notificação.

### Interface de persistência

```lua
export type Persistence = {
    load: (self: Persistence, userId: number) -> InventoryState?,
    save: (self: Persistence, userId: number, state: InventoryState) -> (),
}
```

O backend é injetado em `InventoryService` no `init.server.luau`:
`RunService:IsStudio()` → `MemoryPersistence.new()`, senão
`DataStorePersistence.new()`.

## Fluxo de dados

```
Servidor: PlayerAdded
  load via backend (DataStore com retries | memória com seed)
  ├─ sucesso → estado em memória; fire InventoryChanged(snapshot)
  └─ falha   → kick (após retries)
  PlayerRemoving → save best-effort (somente no backend DataStore faz I/O real)

Cliente: init.client.luau
  controller:start()
    ├─ snapshot = GetInventory:InvokeServer()   → _state = snapshot; changed:Fire(snapshot)
    └─ InventoryChanged:Connect(→ _state = nova ref; changed:Fire)
  App via useInventory() → re-render em cada changed; nil enquanto carrega
```

Race entre `InvokeServer` e `InventoryChanged`: irrelevante, pois o estado é
autoritativo no servidor e o "último snapshot vence".

## Modelo de dados

```lua
export type ItemId = string
export type ItemDef = {
    id: ItemId,
    name: string,
    stackable: boolean,
}
export type InventoryState = {
    version: number,           -- schema; hoje 1
    items: { ItemId },         -- lista de ids de itens
}
```

Catálogo inicial (placeholder, tema dungeon):

```lua
items = {
    torch =   { id = "torch",   name = "Tocha",   stackable = true },
    ration =  { id = "ration",  name = "Ração",   stackable = true },
    crystal = { id = "crystal", name = "Cristal", stackable = false },
}
```

Seed (`defaultInventory`) usa a seleção fixa `{ "torch", "ration", "crystal" }`.

## Tratamento de erros

- Load DataStore: 5 retries com backoff; falha total → `Kick` com mensagem
  "Falha ao carregar dados" (evita sobrescrever save com estado vazio).
- Save no `PlayerRemoving`: best-effort; se falhar, re-tenta em `task.spawn`
  na janela curta antes do desconectar.
- Cliente: `_state == nil` tratado na UI como "Carregando inventário...".

## Testes

- **Lune** (`lune run test`):
  - `InventoryStore.spec.luau`: serialize/deserialize redondo (com `version`),
    defaultInventory contém os ids do catálogo, round-trip JSON estável.
  - `MemoryPersistence.spec.luau`: primeiro acesso gera seed; segundo acesso
    devolve o mesmo estado; `save` atualiza o mapa.
- **Integração (Studio via Rojo)**: gate no load, snapshot no cliente, UI
  listando itens com o backend em memória.

## Fora de escopo (futuro)

Pickup/uso/descarte, trade, equipamento, autosave, save-por-mudança, session
lock, migração de schema (o campo `version` já prepara), Context do React para
múltiplas telas.

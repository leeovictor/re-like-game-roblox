# Arquitetura do Sistema de Inventário

Este documento descreve a arquitetura implementada atualmente em `src/`, sem
propor alterações de comportamento.

## Visão Geral

O servidor é a autoridade do inventário. O cliente recebe snapshots somente
para leitura e envia pedidos de uso por remotes Roblox. O estado é representado
por instâncias concretas de itens, enquanto o catálogo compartilhado define os
metadados e as capacidades disponíveis.

```mermaid
flowchart TB
    subgraph CLIENT["Cliente · StarterPlayerScripts.Client"]
        INITC["init.client.luau"]
        CONTROLLER["InventoryController<br/>estado replicado + Signal"]
        HOOK["useInventory.luau<br/>hook React"]
        APP["App.luau<br/>lista do inventário"]
        NOTIFY["PickupNotificationController<br/>+ usePickupNotification"]
    end

    subgraph SHARED["Shared · ReplicatedStorage.Shared"]
        CATALOG["catalog.luau<br/>ItemDefinition + capacidades"]
        TYPES["items.luau<br/>ItemInstance + InventoryState v2"]
        REMOTES["remotes.luau<br/>InventoryChanged · GetInventory<br/>UseItem · PickupCollected"]
    end

    subgraph SERVER["Servidor · ServerScriptService.Server"]
        INITS["init.server.luau<br/>composição dos serviços"]
        INV["InventoryService<br/>estado autoritativo por Player"]
        STORE["InventoryStore<br/>validação + mutações puras<br/>serialização"]
        FACTORY["ItemInstanceFactory<br/>UID + instâncias validadas"]
        PICKUP["PickupService<br/>Part + ProximityPrompt"]
        USE["ItemUseService<br/>validação + lock + coordenação"]
        REGISTRY["ItemBehaviorRegistry<br/>behaviors por capability"]
    end

    subgraph PERSIST["Persistência"]
        MEMORY["MemoryPersistence<br/>Studio"]
        DATASTORE["DataStorePersistence<br/>produção · PlayerInventory"]
    end

    WORLD["Workspace<br/>Pickups / ProximityPrompt"]
    GAMEPLAY["Sistemas de gameplay<br/>vida · combate · portas<br/>consumidores externos"]

    INITC --> CONTROLLER
    INITC --> APP
    APP --> HOOK
    HOOK --> CONTROLLER

    CONTROLLER <-->|"GetInventory / InventoryChanged"| REMOTES
    CONTROLLER -. "UseItem" .-> REMOTES
    REMOTES -->|"PickupCollected"| NOTIFY

    REMOTES --> INV
    REMOTES --> USE
    INITS --> INV
    INITS --> FACTORY
    INITS --> REGISTRY
    INITS --> USE
    INITS --> PICKUP

    CATALOG --> TYPES
    CATALOG --> STORE
    CATALOG --> FACTORY
    CATALOG --> USE
    TYPES -. "payloads" .-> REMOTES
    TYPES --> INV
    TYPES --> USE

    INV --> STORE
    INV <-->|"load / save"| MEMORY
    INV <-->|"load / save"| DATASTORE

    WORLD -->|"Triggered(player)"| PICKUP
    PICKUP -->|"create(itemId, attrs, qty)"| FACTORY
    PICKUP -->|"addInstance(player, instance)"| INV
    INV -->|"snapshot novo"| REMOTES

    USE --> REGISTRY
    USE -->|"find + applyUseMutations"| INV
    USE -. "effect data" .-> GAMEPLAY

    classDef client fill:#18354a,stroke:#5bb6c9,color:#eef7f8
    classDef shared fill:#3d3424,stroke:#d6a756,color:#fff7e5
    classDef server fill:#273d32,stroke:#7ac28b,color:#effbf1
    classDef persist fill:#3a2f46,stroke:#bb91d6,color:#fbf4ff
    classDef external fill:#2d3037,stroke:#9298a3,color:#f0f2f5,stroke-dasharray:5 4

    class INITC,CONTROLLER,HOOK,APP,NOTIFY client
    class CATALOG,TYPES,REMOTES shared
    class INITS,INV,STORE,FACTORY,PICKUP,USE,REGISTRY server
    class MEMORY,DATASTORE persist
    class WORLD,GAMEPLAY external
```

## Componentes

| Componente | Responsabilidade atual |
| --- | --- |
| `shared/inventory/catalog.luau` | Catálogo declarativo com nome, categoria, regra de empilhamento e capacidades. |
| `shared/inventory/items.luau` | Tipos compartilhados de `ItemInstance`, `InventoryState`, pedidos e resultados de uso. |
| `shared/remotes.luau` | Cria ou reutiliza os remotes em `ReplicatedStorage.Remotes`. |
| `server/inventory/InventoryStore.luau` | Valida, copia e transforma estados sem mutação compartilhada; também serializa e desserializa JSON. |
| `server/inventory/InventoryService.luau` | Mantém o estado por jogador, carrega, salva, aplica mutações e replica snapshots. |
| `server/items/ItemInstanceFactory.luau` | Gera `uid`s e cria instâncias com quantidade e atributos básicos válidos. |
| `server/items/ItemBehaviorRegistry.luau` | Registra handlers server-side por capability. |
| `server/items/ItemUseService.luau` | Valida pedidos, encontra a instância compatível, impede uso concorrente e coordena mutações. |
| `server/pickups/PickupService.luau` | Cria pickups no mundo e transfere instâncias ao inventário após `ProximityPrompt.Triggered`. |
| `client/inventory/InventoryController.luau` | Mantém a réplica local e expõe o snapshot para a UI. |
| `client/inventory/useInventory.luau` | Faz a ponte entre o `Signal` do controller e o estado React. |
| `client/ui/App.luau` | Renderiza a lista de itens e a notificação de coleta. |

## Modelo de Dados

```lua
type ItemInstance = {
    uid: string,
    itemId: string,
    quantity: number?,
    attributes: { [string]: string | number | boolean }?,
}

type InventoryState = {
    version: number, -- atualmente 2
    items: { ItemInstance },
    equipped: { [string]: string }, -- slot -> uid
}
```

O `itemId` aponta para uma definição estática do catálogo. O `uid` identifica
uma instância concreta, permitindo que duas instâncias do mesmo tipo tenham
atributos diferentes. Itens empilháveis usam `quantity`.

## Fluxos Principais

### 1. Carregamento e sincronização inicial

```mermaid
sequenceDiagram
    participant P as Player
    participant S as InventoryService
    participant DB as Persistence
    participant R as Remotes
    participant C as InventoryController
    participant UI as App / React

    P->>S: PlayerAdded
    S->>DB: load(UserId) com retry/backoff
    DB-->>S: InventoryState ou nil
    S->>S: guarda snapshot autoritativo
    S-->>R: InventoryChanged:FireClient(snapshot)
    C->>R: GetInventory:InvokeServer()
    R-->>C: snapshot atual
    C->>UI: changed:Fire(snapshot)
    UI->>UI: renderiza inventário
```

Em `Studio`, `MemoryPersistence` é usado. Fora do `Studio`, o backend é
`DataStorePersistence`. O personagem só é carregado depois que o inventário
do jogador termina de carregar. Ao sair, `InventoryService` salva o snapshot
de forma best-effort.

### 2. Coleta de pickup

```mermaid
sequenceDiagram
    participant P as Player
    participant W as Workspace / ProximityPrompt
    participant PK as PickupService
    participant F as ItemInstanceFactory
    participant S as InventoryService
    participant R as Remotes
    participant UI as UI

    PK->>F: cria instância authored com uid
    P->>W: aproxima-se e aciona prompt
    W->>PK: Triggered(player)
    PK->>S: addInstance(player, instance)
    alt coleta aceita
        S->>S: InventoryStore valida e substitui estado
        S-->>R: InventoryChanged(snapshot)
        PK->>W: destrói Part
        PK-->>R: PickupCollected(itemId)
        R-->>UI: atualiza lista e notificação
    else coleta rejeitada
        S-->>PK: false
        PK->>W: reabilita prompt e preserva Part
    end
```

O cliente não solicita a coleta. A autoridade é o callback server-side do
`ProximityPrompt`.

### 3. Uso de item

```mermaid
sequenceDiagram
    participant UI as UI / sistema cliente
    participant C as InventoryController
    participant R as UseItem
    participant U as ItemUseService
    participant B as ItemBehaviorRegistry
    participant S as InventoryService
    participant G as Gameplay externo

    UI->>C: use(UseRequest)
    C->>R: InvokeServer(request)
    R->>U: valida request e contexto
    U->>B: resolve capability
    U->>S: find instância compatível
    U->>B: canUse / use
    B-->>U: efeito + mutações declaradas
    U->>S: applyUseMutations atomicamente
    S-->>U: sucesso ou falha
    U-->>R: UseResult
    R-->>C: UseResult
    U-.->G: sistemas concretos aplicam efeitos de domínio
```

`ItemUseService` mantém um lock por jogador, revalida a instância e só aplica
as mutações depois que o behavior retorna dados de resultado. O payload do
cliente não define valores de efeito.

### 4. Persistência

```mermaid
flowchart LR
    SERVICE["InventoryService"] -->|"load / save"| SELECT{"RunService:IsStudio()?"}
    SELECT -->|sim| MEMORY["MemoryPersistence<br/>tabela em memória"]
    SELECT -->|não| DATA["DataStorePersistence<br/>DataStoreService"]
    DATA --> SERIAL["InventoryStore<br/>serialize / deserialize"]
    MEMORY --> COPY["InventoryStore.copyState"]
```

## Autoridade e Limites

- O estado autoritativo fica privado dentro de `InventoryService`.
- `InventoryStore` não depende de APIs Roblox e opera como lógica pura.
- O cliente não altera o inventário diretamente.
- `InventoryChanged` representa snapshots persistíveis; `PickupCollected`
  representa o evento transitório da coleta.
- O catálogo não contém funções nem comportamentos executáveis.
- Behaviors concretos de vida, combate, portas e outros domínios são externos ao
  núcleo do inventário.

## Localização no Projeto

```text
src/shared/inventory/catalog.luau
src/shared/inventory/items.luau
src/shared/remotes.luau

src/server/init.server.luau
src/server/inventory/InventoryStore.luau
src/server/inventory/InventoryService.luau
src/server/inventory/persistence/MemoryPersistence.luau
src/server/inventory/persistence/DataStorePersistence.luau
src/server/items/ItemInstanceFactory.luau
src/server/items/ItemBehaviorRegistry.luau
src/server/items/ItemUseService.luau
src/server/pickups/PickupService.luau

src/client/init.client.luau
src/client/inventory/InventoryController.luau
src/client/inventory/useInventory.luau
src/client/pickups/PickupNotificationController.luau
src/client/pickups/usePickupNotification.luau
src/client/ui/App.luau
```

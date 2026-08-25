# Arquitetura do Sistema de Inventário

Este documento descreve a arquitetura client-side implementada atualmente em
`src/`. O inventário é volátil e existe somente durante a sessão do cliente.

## Visão Geral

```text
InventoryController local
  -> InventoryStore shared
  -> estado vazio da sessão

PickupManager
  -> pickups authored
  -> InventoryController.addInstance
  -> sinal local collected

PickupInteraction
  -> GameplayEvents.item_collected
  -> ObjectiveController
```

`InventoryController` permanece ativo durante respawns e começa vazio em uma
nova sessão. Não há save, checkpoint ou persistência entre sessões nesta etapa.

## Componentes

| Componente | Responsabilidade |
| --- | --- |
| `shared/inventory/catalog.luau` | Catálogo declarativo, regras de empilhamento e capacidades. |
| `shared/inventory/items.luau` | Tipos de itens e estado versão 2. |
| `shared/inventory/InventoryStore.luau` | Validação, cópia profunda e mutações puras. |
| `shared/inventory/ItemInstanceFactory.luau` | Criação validada de instâncias e UIDs. |
| `client/inventory/InventoryController.luau` | Estado local da sessão, `addInstance` e sinal `changed`. |
| `client/pickups/PickupManager.luau` | Registro, validação e coleta de pickups authored. |
| `client/pickups/PickupInteraction.luau` | Adapta pickups ao `InteractionController` e publica o evento semântico. |
| `client/pickups/PickupNotificationController.luau` | Converte o sinal local de coleta em estado para a UI. |
| `client/doors/DoorManager.luau` | Consulta o inventário local para desbloquear portas sem consumir itens. |
| `client/events/GameplayEvents.luau` | Barramento local de eventos semânticos. |

## Pickups Authored

Um pickup válido é uma `BasePart` ou `Model` descendente de `Workspace` com:

```text
tag: Interactable
InteractionType: "Pickup"
ItemId: string não vazia
Quantity: number opcional
```

`PickupManager` registra o pickup, cria sua `ItemInstance` uma única vez,
desabilita `ProximityPrompt`s descendentes e coleta apenas após revalidar a
configuração e a distância do personagem. A falha de inserção preserva o
objeto no mapa. Pickups gerados, spawn aleatório e `pendingGenerated` estão
fora desta migração.

## Eventos E UI

Após `InventoryController.addInstance` retornar sucesso, o manager destrói o
pickup e emite `collected`. `PickupInteraction` então publica:

```lua
GameplayEvents.emit({ name = "item_collected", itemId = itemId })
```

O `ObjectiveController` e a notificação assinam fontes locais independentes.
A UI permanece inalterada, incluindo as ações mock existentes em `App.luau`.

## Localização

```text
src/shared/inventory/catalog.luau
src/shared/inventory/items.luau
src/shared/inventory/InventoryStore.luau
src/shared/inventory/ItemInstanceFactory.luau

src/client/inventory/InventoryController.luau
src/client/inventory/useInventory.luau
src/client/pickups/PickupManager.luau
src/client/pickups/PickupInteraction.luau
src/client/pickups/PickupNotificationController.luau
src/client/pickups/usePickupNotification.luau
src/client/events/GameplayEvents.luau
src/client/ui/App.luau
```

O servidor mantém somente serviços ainda necessários, como
`CharacterLightService`; não há runtime server-side de inventário, uso ou
coleta de pickups.

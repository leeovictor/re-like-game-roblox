# Sistema de Combate Client-Side Implementation Plan



> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar o combate client-side da handgun com equipamento, mira inicial por auto aim, giro manual, disparo semiautomatico, recarga temporizada, dano em inimigos e bloqueio externo persistente.

**Architecture:** `CombatController` sera dono dos bindings e de um unico loop de `PreRender`. `CombatService` sera uma instancia com estado de mira, recarga, movement locks internos e contador de bloqueios externos. `InventoryController` sera convertido para instancia e continuara sendo a fonte local de equipamento e municao; `EnemyController` fornecera candidatos ativos e aplicara dano validado.

**Tech Stack:** Luau strict, Roblox `ContextActionService`, `RunService.PreRender`, `Workspace:Raycast`, `Humanoid:TakeDamage`, React/ReactRoblox, Rojo 7.7.0, Selene 0.29.0 e luau-lsp 1.69.0.

## Global Constraints

- O runtime continuara sendo client-side, sem remotes novos.
- O slot operacional da arma sera `equipped.weapon` e somente uma arma podera estar equipada por vez.
- Uma handgun sem `loadedAmmo` iniciara com o pente cheio.
- O disparo sera semiautomatico, um tiro por clique, somente enquanto Mouse Right estiver pressionado.
- A aquisicao automatica ocorrera uma vez no inicio da mira e nao acompanhara o inimigo.
- `A` e `D` girarao manualmente o personagem durante a mira.
- `R` somente iniciara recarga enquanto o jogador estiver mirando.
- A recarga manual e automatica usara duracao fixa e bloqueara movimento.
- A recarga sera um estado separado da mira; durante a recarga nao sera possivel mirar.
- Soltar Mouse Right durante a recarga nao cancelara a recarga.
- Se Mouse Right continuar pressionado quando a recarga terminar, uma nova mira com nova aquisicao sera iniciada.
- Sistemas externos usarao somente `acquireLock()` para bloquear todo o combate durante um periodo.
- `acquireLock()` encerrara mira ou recarga ativa e retornara um `release()` idempotente.
- Nao havera `cancel()` separado, parametro de tipo, razao ou lock externo especifico por acao.
- `EnemyController` validara o alvo e chamara `Humanoid:TakeDamage`; morte, reacao e remocao visual do inimigo ficam fora do escopo.
- A camada visual, modelo de arma, animacoes, sons, efeitos e HUD de municao ficam fora do escopo.
- O `InventoryController` alterado seguira `docs/controller-service-pattern.md`, com estado por instancia e lifecycle idempotente.
- Nao criar nem alterar testes unitarios existentes, mesmo que contratos anteriores fiquem incompatíveis.
- Nao ler ou modificar arquivos da arvore de testes durante a implementacao.
- Nao usar Roblox MCP sem permissao explicita do usuario.
- Nao fazer commit da spec, deste plano ou da implementacao, conforme `AGENTS.md`.
- Manter `--!strict` nos novos modulos e nao usar `--!nocheck`, ignores amplos ou `typeErrors: false`.
- Nao editar `Packages/` ou `DevPackages/`.
- Ao terminar cada task, gerar o sourcemap e rodar o typecheck `luau-lsp` antes de avancar para a proxima task.

## LSP Checkpoint Obrigatorio

Este checkpoint deve ser executado ao final de cada task, inclusive depois da
Task 7. O sourcemap deve ser regenerado antes da analise para que imports,
tipos e caminhos novos sejam verificados no estado atual da producao.

```bash
rojo sourcemap --include-non-scripts default.project.json --output /tmp/dungeon-game-canve-sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --sourcemap /tmp/dungeon-game-canve-sourcemap.json --formatter gnu \
  src/shared \
  src/server/player \
  src/client/camera \
  src/client/cinematics \
  src/client/combat \
  src/client/dialogue \
  src/client/doors \
  src/client/enemies \
  src/client/events \
  src/client/interactions \
  src/client/inventory \
  src/client/objectives \
  src/client/pickups \
  src/client/player \
  src/client/ui
```

O resultado esperado e nenhum diagnostico nos modulos de producao. Nao incluir
a arvore de testes nesta analise.

---

## File Map

### Novos arquivos

- `src/client/combat/CombatConfig.luau` - tuning fixo da handgun e vinculo com a municao.
- `src/client/combat/CombatService.luau` - regras, estados, alvo, tiro, recarga e bloqueio externo.
- `src/client/combat/CombatController.luau` - bindings de input e loop de atualizacao.

### Arquivos de producao alterados

- `src/client/inventory/InventoryController.luau` - conversao para instancia e mutacoes de equipamento/municao.
- `src/client/inventory/useInventory.luau` - receber a instancia do inventario.
- `src/client/ui/App.luau` - receber a instancia e tornar `equipar` funcional.
- `src/client/init.client.luau` - composition root do inventario e combate.
- `src/client/pickups/PickupManager.luau` - usar chamadas de instancia no inventario.
- `src/client/doors/DoorManager.luau` - usar chamadas de instancia no inventario.
- `src/client/cinematics/MachineRoomCinematicController.luau` - usar chamadas de instancia no inventario.
- `src/shared/input/ActionPriorities.luau` - prioridade de combate abaixo de dialogo.
- `src/client/enemies/EnemyController.luau` - candidatos ativos e aplicacao de dano validada.
- `src/client/enemies/types.luau` - contratos necessarios para a API publica do inimigo/controller.

Nao alterar arquivos de teste, `test.project.json`, assets authored, `TankController` ou os estados existentes de inimigo, exceto os contratos de producao estritamente necessarios.

---

### Task 1: Converter o inventario para instancia e mutacoes atomicas

**Files:**
- Modify: `src/client/inventory/InventoryController.luau`
- Modify: `src/client/inventory/useInventory.luau`
- Modify: `src/client/pickups/PickupManager.luau`
- Modify: `src/client/doors/DoorManager.luau`
- Modify: `src/client/cinematics/MachineRoomCinematicController.luau`
- Modify: `src/client/ui/App.luau`
- Modify: `src/client/init.client.luau`

**Interfaces:**
- Consumes: `InventoryStore.copyState`, `addInstance`, `findInstance`, `updateAttributes`, `removeQuantity` e `equip`; tipos `items.ItemInstance` e `items.InventoryState`.
- Produces: `InventoryController.new(): InventoryController` com `start`, `stop`, `getState`, `addInstance`, `equip`, `getEquipped`, `updateAttributes`, `consumeLoadedAmmo`, `reloadWeapon` e sinal `changed` por instancia.

- [ ] **Step 1: Criar o contrato por instancia e remover o estado global**

Substituir o `changed`, `state`, `started` e `controller` unicos no escopo do
modulo por uma classe criada em `new()`. O contrato deve usar `self` em todos os
metodos:

```luau
local InventoryController = {}
InventoryController.__index = InventoryController

export type InventoryController = {
    changed: ChangedSignal,
    start: (self: InventoryController) -> (),
    stop: (self: InventoryController) -> (),
    getState: (self: InventoryController) -> items.InventoryState?,
    addInstance: (self: InventoryController, instance: items.ItemInstance) -> boolean,
    equip: (self: InventoryController, uid: string) -> boolean,
    getEquipped: (self: InventoryController, slot: string) -> items.ItemInstance?,
    updateAttributes: (self: InventoryController, uid: string, attributes: items.ItemAttributes) -> boolean,
    consumeLoadedAmmo: (self: InventoryController, weaponUid: string) -> boolean,
    reloadWeapon: (
        self: InventoryController,
        weaponUid: string,
        ammoUid: string,
        amount: number,
        loadedAmmo: number
    ) -> boolean,
}
```

`new()` deve criar um `Signal` e um `state = nil` novos por instancia. Nao
reutilizar tabela mutavel entre chamadas de `new()`.

- [ ] **Step 2: Migrar `start`, `stop`, `getState` e `addInstance`**

Implementar `InventoryController.new()` com `started = false`, `state = nil` e
`changed = Signal.new()`. Preservar o comportamento aprovado:

```luau
function InventoryController.new(): InventoryController
    local self = setmetatable({
        changed = (Signal.new() :: any) :: ChangedSignal,
        started = false,
        state = nil :: items.InventoryState?,
    }, InventoryController)
    return (self :: any) :: InventoryController
end

function InventoryController.start(self: InventoryController): ()
    if self.started then
        return
    end
    self.started = true
    self.state = InventoryStore.defaultInventory()
end
```

`stop()` deve ser idempotente, marcar `started = false` e limpar `state`.
`getState()` deve retornar `self.state`. `addInstance()` deve rejeitar chamadas
antes de `start()`, aplicar `InventoryStore.addInstance`, substituir o estado e
disparar `self.changed:Fire(updated)` somente em sucesso.

- [ ] **Step 3: Implementar equipamento no slot unico `weapon`**

Em `equip(self, uid)`, localizar a instancia atual e consultar
`items[instance.itemId]`. Rejeitar quando o item nao existir, nao tiver
capability `equip`, nao tiver categoria `weapon`, ou quando o controller nao
estiver iniciado.

Usar a operacao pura existente com o slot fixo:

```luau
local updated = InventoryStore.equip(self.state, "weapon", uid)
if updated == nil then
    return false
end
self.state = updated
self.changed:Fire(updated)
return true
```

Equipar uma segunda arma deve substituir `equipped.weapon`; nao criar outro
slot nem manter duas referencias equipadas.

- [ ] **Step 4: Implementar `getEquipped` e `updateAttributes`**

`getEquipped(self, slot)` deve ler o UID em `self.state.equipped[slot]` e
retornar `InventoryStore.findInstance(self.state, uid)`, que ja devolve uma
copia da instancia. Retornar `nil` quando o controller estiver parado, o slot
estiver vazio ou o UID nao existir.

`updateAttributes` deve chamar `InventoryStore.updateAttributes`, substituir o
estado e disparar `changed` uma vez em sucesso. O metodo deve rejeitar estado
inativo ou resultado `nil` sem mutar o estado atual.

- [ ] **Step 5: Implementar consumo de uma unidade carregada**

Adicionar um helper local que copie todos os atributos da arma, alterando
somente `loadedAmmo`. `consumeLoadedAmmo` deve:

1. localizar `weaponUid`;
2. ler `attributes.loadedAmmo` como numero inteiro maior que zero;
3. criar uma copia dos atributos com `loadedAmmo - 1`;
4. usar `InventoryStore.updateAttributes`;
5. publicar um unico snapshot novo.

Retornar `false` sem mutacao quando a instancia nao existir, nao possuir
`loadedAmmo` valido ou ja estiver vazia.

- [ ] **Step 6: Implementar recarga atomica de arma e pilha**

`reloadWeapon(weaponUid, ammoUid, amount, loadedAmmo)` deve validar numeros
inteiros positivos para `amount`, numero inteiro nao negativo para
`loadedAmmo`, a existencia da arma e da pilha, `weapon.itemId == "handgun"`,
`ammo.itemId == "handgun_ammo"` e quantidade suficiente na pilha.

Aplicar as duas transformacoes em variaveis temporarias e publicar somente a
ultima:

```luau
local withLoadedAmmo = InventoryStore.updateAttributes(
    self.state,
    weaponUid,
    mergedWeaponAttributes
)
if withLoadedAmmo == nil then
    return false
end

local updated = InventoryStore.removeQuantity(withLoadedAmmo, ammoUid, amount)
if updated == nil then
    return false
end

self.state = updated
self.changed:Fire(updated)
return true
```

Se a segunda operacao falhar, preservar o estado inicial e nao disparar
`changed`. Quando a quantidade chegar a zero, `removeQuantity` devera remover a
pilha conforme o comportamento ja existente do store.

- [ ] **Step 7: Atualizar o hook e consumidores para chamadas de instancia**

Alterar `useInventory` para receber o controller:

```luau
local function useInventory(controller: InventoryControllerModule.InventoryController)
    local inventory, setInventory = React.useState(controller:getState())

    React.useEffect(function()
        local connection = controller.changed:Connect(function(snapshot)
            setInventory(snapshot)
        end)
        return function()
            connection:Disconnect()
        end
    end, { controller })

    return inventory
end
```

Atualizar `PickupManager`, `DoorManager` e
`MachineRoomCinematicController` para usar `inventory:addInstance(...)` e
`inventory:getState()` com `:`. Remover chamadas operacionais ao modulo
`InventoryController` importado diretamente.

- [ ] **Step 8: Criar a instancia no composition root sem ainda conectar combate**

Em `src/client/init.client.luau`, trocar:

```luau
InventoryController.start()
```

por:

```luau
local inventoryController = InventoryController.new()
inventoryController:start()
```

Passar essa mesma instancia para `PickupManager`, `DoorManager`,
`MachineRoomCinematicController` e `App`. Adicionar `inventoryController` às
props tipadas de `App` e chamar `useInventory(props.inventoryController)`.
Manter a acao mock `equipar` nesta task; a chamada real sera feita na Task 6.

- [ ] **Step 9: Rodar verificacao estatica da task**

Executar:

```bash
selene --config selene.roblox.toml src/client/inventory src/client/pickups src/client/doors src/client/cinematics src/client/ui
```

Esperado: nenhum diagnostico nos modulos de producao alterados. Nao executar
nem alterar specs unitarias.

- [ ] **Step 10: Rodar o LSP antes de avancar**

Executar integralmente o `LSP Checkpoint Obrigatorio` definido no inicio deste
plano. O sourcemap deve ser regenerado depois de concluir a Task 1.

Esperado: nenhum diagnostico novo nos modulos de producao envolvidos na Task 1.

---

### Task 2: Criar a configuracao fixa da handgun

**Files:**
- Create: `src/client/combat/CombatConfig.luau`

**Interfaces:**
- Consumes: nenhum modulo de runtime.
- Produces: configuracao `CombatConfig[weaponItemId]` com o contrato `WeaponConfig`.

- [ ] **Step 1: Criar o modulo strict e seu tipo exportado**

Criar o modulo sem estado mutavel de runtime:

```luau
--!strict

export type WeaponConfig = {
    itemId: string,
    ammoItemId: string,
    magazineSize: number,
    damage: number,
    shotCooldown: number,
    acquisitionRadius: number,
    shotRange: number,
    reloadDuration: number,
    aimTurnSpeed: number,
}

local CombatConfig: { [string]: WeaponConfig } = {
    handgun = {
        itemId = "handgun",
        ammoItemId = "handgun_ammo",
        magazineSize = 6,
        damage = 25,
        shotCooldown = 0.35,
        acquisitionRadius = 30,
        shotRange = 80,
        reloadDuration = 1.5,
        aimTurnSpeed = 2.5,
    },
}

return CombatConfig
```

Nao ler dano, capacidade, alcance, cadencia ou duracao de pickups. A handgun
continua sendo criada pelo pickup com `ItemId` e sem atributos de tuning.

- [ ] **Step 2: Rodar lint do modulo**

Executar:

```bash
selene --config selene.roblox.toml src/client/combat/CombatConfig.luau
```

- [ ] **Step 3: Rodar o LSP antes de avancar**

Executar integralmente o `LSP Checkpoint Obrigatorio` definido no inicio deste
plano. O sourcemap deve ser regenerado depois de concluir a Task 2.

Esperado: nenhum diagnostico novo nos modulos de producao envolvidos na Task 2.

---

### Task 3: Expor candidatos ativos e dano validado no `EnemyController`

**Files:**
- Modify: `src/client/enemies/types.luau`
- Modify: `src/client/enemies/EnemyController.luau`

**Interfaces:**
- Consumes: lista de `EnemiesTypes.Enemy` criada pelo controller.
- Produces: `getActiveEnemies(self) -> { EnemiesTypes.Enemy }` e
  `applyDamage(self, enemy, amount) -> boolean`.

- [ ] **Step 1: Adicionar os metodos ao contrato tipado**

Em `EnemyController` adicionar:

```luau
getActiveEnemies: (self: EnemyController) -> { types.Enemy },
applyDamage: (self: EnemyController, enemy: types.Enemy, amount: number) -> boolean,
```

Manter `start`, `stop`, `enemies` e `heartbeatConnection` existentes. Atualizar
`types.Enemy` somente se o typechecker exigir um campo adicional para a
validacao; nao alterar a maquina de estados do inimigo.

- [ ] **Step 2: Criar o predicado privado de inimigo ativo**

Adicionar um helper que exija todos os seguintes invariantes:

```luau
local function isActive(enemy: types.Enemy): boolean
    local humanoid = enemy.humanoid
    local root = enemy.root
    return not enemy.destroyed
        and enemy.model.Parent ~= nil
        and humanoid ~= nil
        and root ~= nil
        and root:IsDescendantOf(enemy.model)
        and humanoid.Health > 0
end
```

O helper deve ser usado para impedir dano em objetos destruidos, removidos ou
com vida zero. Nao remover o inimigo da lista nem criar estado de morte.

- [ ] **Step 3: Implementar `getActiveEnemies` como snapshot**

Percorrer `self.enemies`, inserir em uma tabela nova somente os inimigos para
os quais `isActive` retorna `true`, e retornar essa tabela. Nao devolver uma
referencia que permita ao combate substituir a lista interna.

- [ ] **Step 4: Implementar `applyDamage` com validacao e protecao**

Validar `amount` como numero finito maior que zero e validar o inimigo com
`isActive`. Como seguranca adicional, confirmar que a instancia recebida e uma
das entradas atuais de `self.enemies` antes de chamar `TakeDamage`.

Proteger a chamada:

```luau
local ok = pcall(function()
    humanoid:TakeDamage(amount)
end)
return ok
```

Nao criar feedback visual, transicao de estado ou comportamento de morte. O
retorno `true` significa apenas que a chamada de dano foi aceita sem erro.

- [ ] **Step 5: Rodar lint da task**

Executar:

```bash
selene --config selene.roblox.toml src/client/enemies
```

- [ ] **Step 6: Rodar o LSP antes de avancar**

Executar integralmente o `LSP Checkpoint Obrigatorio` definido no inicio deste
plano. O sourcemap deve ser regenerado depois de concluir a Task 3.

Esperado: nenhum diagnostico novo nos modulos de producao envolvidos na Task 3.

---

### Task 4: Implementar o `CombatService`

**Files:**
- Create: `src/client/combat/CombatService.luau`

**Interfaces:**
- Consumes: `InventoryController.InventoryController`,
  `EnemyController.EnemyController`, `TankController.MovementController` e
  `CombatConfig`.
- Produces: `CombatService.new(dependencies)` com `start`, `stop`, `update`,
  `beginAim`, `endAim`, `shoot`, `requestReload`, `setTurnInput` e
  `acquireLock`.

- [ ] **Step 1: Declarar os tipos e o estado por instancia**

Criar os contratos:

```luau
export type Dependencies = {
    inventory: InventoryControllerModule.InventoryController,
    enemies: EnemyControllerModule.EnemyController,
    movement: TankController.MovementController,
}

export type CombatState = "neutral" | "aiming" | "reloading"

export type CombatService = {
    state: CombatState,
    started: boolean,
    start: (self: CombatService) -> (),
    stop: (self: CombatService) -> (),
    update: (self: CombatService, deltaTime: number) -> (),
    beginAim: (self: CombatService) -> (),
    endAim: (self: CombatService) -> (),
    shoot: (self: CombatService) -> boolean,
    requestReload: (self: CombatService) -> boolean,
    setTurnInput: (self: CombatService, left: boolean, right: boolean) -> boolean,
    acquireLock: (self: CombatService) -> (() -> ()),
}
```

`new(dependencies)` deve criar por instancia `state`, `started`, `aimHeld`,
`turnLeft`, `turnRight`, `target`, `nextShotAt`, `reloadElapsed`,
`reloadWeaponUid`, `reloadGeneration`, `externalLockCount`,
`externalLockGeneration`, os dois movement releases e a conexao do inventario.
Nenhuma dessas tabelas ou closures pode existir como estado operacional global.

- [ ] **Step 2: Implementar helpers de arma e atributos**

Criar helpers privados para:

- obter `inventory:getEquipped("weapon")`;
- buscar `CombatConfig[instance.itemId]`;
- aceitar somente a configuracao da `handgun` nesta versao;
- ler `loadedAmmo` como inteiro em `0..magazineSize`;
- copiar os atributos da instancia sem descartar atributos nao relacionados.

Quando `loadedAmmo` estiver ausente, usar uma copia dos atributos com
`loadedAmmo = config.magazineSize` e chamar `inventory:updateAttributes`. Se o
valor existir mas for invalido, tratar a arma como indisponivel para tiro e
recarga; nao normalizar silenciosamente um valor authored invalido.

- [ ] **Step 3: Implementar movement locks internos**

Criar helpers privados `releaseAimMovementLock` e
`releaseReloadMovementLock`, ambos idempotentes. O estado `aiming` deve possuir
um release retornado por `movement:acquireMovementLock()`; o estado `reloading`
deve possuir outro release independente.

A transicao para recarga deve sempre seguir esta ordem:

```text
limpar target
liberar aim movement lock
incrementar reloadGeneration
zerar reloadElapsed
capturar reloadWeaponUid
adquirir reload movement lock
state = "reloading"
```

O reload lock permanece ate conclusao, falha ou `acquireLock()` externo.

- [ ] **Step 4: Implementar o bloqueio externo persistente**

`acquireLock()` deve abortar qualquer mira ou recarga ativa antes de incrementar
`externalLockCount`. O release deve capturar a geracao e um booleano local:

```luau
function service:acquireLock(): () -> ()
    self.externalLockCount += 1
    abortActiveAction(self)
    local acquiredGeneration = self.externalLockGeneration
    local released = false

    return function()
        if released then
            return
        end
        released = true
        if acquiredGeneration ~= self.externalLockGeneration then
            return
        end
        self.externalLockCount -= 1
    end
end
```

`abortActiveAction` deve limpar `target`, zerar o estado para `neutral`,
invalidar `reloadGeneration` e liberar os movement locks internos. Deve
preservar `aimHeld` para permitir nova mira quando o ultimo lock for liberado.

`stop()` deve marcar `started = false`, incrementar
`externalLockGeneration`, zerar o contador, abortar qualquer acao, liberar
movement locks e impedir que releases antigos afetem uma nova sessao.

- [ ] **Step 5: Implementar entrada e saida da mira**

`beginAim()` deve primeiro marcar `aimHeld = true`. Se o service estiver parado,
bloqueado externamente ou recarregando, nao iniciar o estado. Quando houver uma
arma valida e o estado for `neutral`:

1. adquirir o aim movement lock;
2. definir `state = "aiming"`;
3. limpar qualquer target anterior;
4. executar uma unica tentativa de aquisicao;
5. orientar o personagem somente se um alvo visivel for encontrado.

`endAim()` deve marcar `aimHeld = false`. Se o estado for `aiming`, limpar o
target, definir `neutral` e liberar o aim movement lock. Se o estado for
`reloading`, nao cancelar nem liberar o reload lock.

- [ ] **Step 6: Implementar aquisicao inicial com distancia e linha de visao**

Usar `enemies:getActiveEnemies()`, o root atual de `CharacterRoot.get()` e a
configuracao da handgun. Ordenar uma copia por distancia ate o root do player,
descartar candidatos acima de `acquisitionRadius` e testar cada candidato com
raycast:

```luau
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { character }

local offset = enemy.root.Position - playerRoot.Position
local result = workspace:Raycast(playerRoot.Position, offset, params)
if result ~= nil and result.Instance:IsDescendantOf(enemy.model) then
    self.dependencies.movement:setLookVector(offset)
    self.target = enemy
    return
end
```

Se um candidato estiver atras de uma parede, testar o proximo. Se nenhum passar,
manter `state = "aiming"` para permitir mira manual. Depois dessa funcao nao
executar nova aquisicao ate uma nova entrada em mira.

- [ ] **Step 7: Implementar giro manual A/D**

`setTurnInput(left, right)` deve armazenar os dois valores por instancia e
retornar `true` quando o combate estiver capturando A/D (`aiming`, `reloading`
ou bloqueado externamente), e `false` no estado `neutral` sem lock.

No `update(deltaTime)`, girar somente quando `state == "aiming"` e nao houver
lock externo:

```luau
local sign = if self.turnRight then 1 elseif self.turnLeft then -1 else 0
if sign ~= 0 then
    local root = CharacterRoot.get()
    if root ~= nil then
        local direction = CFrame.Angles(
            0,
            sign * config.aimTurnSpeed * deltaTime,
            0
        ):VectorToWorldSpace(root.CFrame.LookVector)
        self.dependencies.movement:setLookVector(direction)
    end
end
```

Nao atualizar target nem procurar outro inimigo ao girar.

- [ ] **Step 8: Implementar tiro semiautomatico e raycast de impacto**

`shoot()` deve retornar `false` sem mutar quando o service nao estiver iniciado,
estiver bloqueado, nao estiver em `aiming`, nao houver handgun valida,
`loadedAmmo == 0` ou `os.clock() < nextShotAt`.

Quando valido:

1. chamar `inventory:consumeLoadedAmmo(weaponUid)`;
2. definir `nextShotAt = os.clock() + config.shotCooldown`;
3. obter `CharacterRoot.get()`;
4. raycastar `root.CFrame.LookVector * config.shotRange`, excluindo o character;
5. localizar se o primeiro impacto pertence a um item de
   `enemies:getActiveEnemies()`;
6. chamar `enemies:applyDamage(enemy, config.damage)` quando houver inimigo;
7. retornar `true` mesmo quando o tiro nao atingir inimigo.

Se o alvo ficar invalido entre o raycast e a aplicacao, nao aplicar dano, mas
manter municao consumida. Nao fazer tracking do target inicial.

- [ ] **Step 9: Implementar inicio e conclusao da recarga**

Criar helper `hasReserveAmmo(config)` que procura no snapshot uma instancia com
`itemId == config.ammoItemId` e `quantity > 0`.

`requestReload()` deve retornar `false` fora de `aiming`, sem Mouse Right
pressionado (`aimHeld == false`), com bloqueio externo, arma ausente, pente
cheio ou sem reserva. Em sucesso, iniciar o estado separado `reloading` e
retornar `true`.

Depois de cada tiro, se `loadedAmmo == 0` e houver reserva, iniciar a mesma
recarga automaticamente sem exigir `R`.

No `update`, enquanto `reloading`, somar `deltaTime` e, ao atingir
`config.reloadDuration`:

1. validar `reloadWeaponUid == inventory:getEquipped("weapon").uid`;
2. calcular `amount = min(magazineSize - loadedAmmo, reserveQuantity)`;
3. escolher a primeira pilha compativel;
4. chamar `inventory:reloadWeapon(...)`;
5. limpar os campos da operacao;
6. incrementar `reloadGeneration` para invalidar callbacks antigos;
7. definir `state = "neutral"`;
8. liberar o reload movement lock;
9. se `aimHeld` continuar verdadeiro e nao houver bloqueio externo, iniciar nova
   mira e nova aquisicao no mesmo update ou no proximo ciclo.

Se a arma tiver sido trocada, a transferencia nao ocorre e o lock ainda deve
ser liberado. A implementacao deve usar somente o loop do controller, sem
coroutine por tiro ou recarga.

- [ ] **Step 10: Implementar reacao a mudancas do inventario**

Em `start()`, conectar `inventory.changed` por closure e verificar tambem a
arma ja equipada naquele momento para inicializar `loadedAmmo` ausente.

Quando o snapshot mudar:

- manter mira se o mesmo UID continuar equipado e valido;
- abortar mira se a handgun equipada for removida ou substituida;
- abortar recarga sem transferir municao se `reloadWeaponUid` deixar de ser o
  UID equipado;
- nao abortar apenas porque `loadedAmmo` ou uma pilha de municao mudou por uma
  mutacao feita pelo proprio service.

`stop()` deve desconectar essa observacao.

- [ ] **Step 11: Rodar lint do service**

Executar:

```bash
selene --config selene.roblox.toml src/client/combat/CombatService.luau
```

- [ ] **Step 12: Rodar o LSP antes de avancar**

Executar integralmente o `LSP Checkpoint Obrigatorio` definido no inicio deste
plano. O sourcemap deve ser regenerado depois de concluir a Task 4.

Esperado: nenhum diagnostico novo nos modulos de producao envolvidos na Task 4.

---

### Task 5: Implementar `CombatController` e prioridades de input

**Files:**
- Create: `src/client/combat/CombatController.luau`
- Modify: `src/shared/input/ActionPriorities.luau`

**Interfaces:**
- Consumes: `CombatService.CombatService`.
- Produces: `CombatController.new({ combat = combatService })` com `start()` e
  `stop()`, bindings idempotentes e um loop de `PreRender`.

- [ ] **Step 1: Ajustar prioridades compartilhadas**

Manter movimento e interacao em `Enum.ContextActionPriority.High.Value`, adicionar
combate acima deles e mover dialogo acima do combate:

```luau
local ActionPriorities = {
    MOVEMENT = Enum.ContextActionPriority.High.Value,
    INTERACTION = Enum.ContextActionPriority.High.Value,
    COMBAT = Enum.ContextActionPriority.High.Value + 1,
    DIALOGUE = Enum.ContextActionPriority.High.Value + 2,
}
```

Assim, os bindings de A/D do dialogo continuam vencendo os bindings de A/D do
combate, que vencem o movimento normal.

- [ ] **Step 2: Declarar estado e dependencias do controller**

Criar:

```luau
export type Dependencies = {
    combat: CombatServiceModule.CombatService,
}

export type CombatController = {
    start: (self: CombatController) -> (),
    stop: (self: CombatController) -> (),
}
```

O construtor deve armazenar a dependencia e criar por instancia os booleans
`leftDown` e `rightDown`, as conexoes e `started`.

- [ ] **Step 3: Criar callbacks de Mouse Right, Mouse Left e R**

Usar nomes de action unicos e closures que capturem `self`. Os callbacks devem
encaminhar:

```luau
Mouse Right Begin -> combat:beginAim()
Mouse Right End/Cancel -> combat:endAim()
Mouse Left Begin -> combat:shoot()
R Begin -> combat:requestReload()
```

As acoes de mouse e R devem retornar `Enum.ContextActionResult.Sink` para
impedir duplicacao por outros handlers. Ignorar estados `Change` e chamadas
apos `stop()`.

- [ ] **Step 4: Criar callbacks de A/D com passagem para movimento normal**

Manter `leftDown` e `rightDown` no controller. Em cada Begin/End/Cancel,
atualizar o booleano correspondente e chamar:

```luau
local captured = self.dependencies.combat:setTurnInput(
    self.leftDown,
    self.rightDown
)
return if captured
    then Enum.ContextActionResult.Sink
    else Enum.ContextActionResult.Pass
```

No estado neutro sem lock, `Pass` permite que o `TankController` continue
recebendo A/D. Durante mira, recarga ou bloqueio externo, `Sink` impede o giro
ou movimento normal.

- [ ] **Step 5: Implementar lifecycle e loop unico**

`start()` deve retornar quando ja iniciado, limpar os booleans, registrar cinco
bindings com `ContextActionService:BindActionAtPriority` e conectar uma unica
conexao:

```luau
self.renderConnection = RunService.PreRender:Connect(function(deltaTime)
    self.dependencies.combat:update(deltaTime)
end)
```

`stop()` deve marcar `started = false`, desconectar `PreRender`, chamar
`UnbindAction` para as cinco acoes, zerar os booleans e enviar
`setTurnInput(false, false)`. Nao chamar metodos de instancia como callbacks
diretos sem closure.

- [ ] **Step 6: Rodar lint da task**

Executar:

```bash
selene --config selene.roblox.toml src/client/combat src/shared/input
```

- [ ] **Step 7: Rodar o LSP antes de avancar**

Executar integralmente o `LSP Checkpoint Obrigatorio` definido no inicio deste
plano. O sourcemap deve ser regenerado depois de concluir a Task 5.

Esperado: nenhum diagnostico novo nos modulos de producao envolvidos na Task 5.

---

### Task 6: Integrar combate, equipamento real e composition root

**Files:**
- Modify: `src/client/init.client.luau`
- Modify: `src/client/ui/App.luau`

**Interfaces:**
- Consumes: `InventoryController` da Task 1, `EnemyController` existente com
  API da Task 3, `CombatService` da Task 4 e `CombatController` da Task 5.
- Produces: runtime iniciado com as mesmas instancias compartilhadas entre UI,
  pickups, portas, cinematicas e combate.

- [ ] **Step 1: Importar os modulos de combate**

Adicionar no composition root:

```luau
local CombatService = require(script.combat.CombatService)
local CombatController = require(script.combat.CombatController)
```

Manter `TankController` e `EnemyController` como instancias compostas; nao
importar um controller operacional de dentro do service.

- [ ] **Step 2: Criar e iniciar o service e o controller**

Depois de `tankController`, `enemyController` e `inventoryController` estarem
criados e iniciados, compor:

```luau
local combatService = CombatService.new({
    inventory = inventoryController,
    enemies = enemyController,
    movement = tankController,
})
combatService:start()

local combatController = CombatController.new({
    combat = combatService,
})
combatController:start()
```

Iniciar o service antes do controller garante que a observacao do inventario e
o estado inicial de `loadedAmmo` estejam prontos antes de receber input. O
`App` deve receber `inventoryController` por props. Nao criar binding de input
adicional no `App` para combate.

- [ ] **Step 3: Tornar `equipar` funcional na UI**

Na montagem das opcoes de cada item, manter `handgun = { "equipar" }`. No
callback existente de `onActivated`, preservar o fechamento do menu e adicionar:

```luau
if label == "equipar" then
    props.inventoryController:equip(instance.uid)
elseif label == "descartar" then
    setConfirmationItemUid(instance.uid)
end
```

O marcador `equipped` ja e derivado de `inventory.equipped`; apos o `changed`, a
UI deve refletir o slot `weapon` sem novo estado local. Nao criar acao de
desequipar, menu novo, indicador de municao ou feedback visual.

- [ ] **Step 4: Conferir que todos os consumidores usam a mesma instancia**

Revisar o composition root e confirmar que nenhum destes recebe o modulo
`InventoryController` diretamente:

```text
PickupManager
DoorManager
MachineRoomCinematicController
App/useInventory
CombatService
```

Todos devem receber `inventoryController`. Nao registrar o service em um
singleton ou locator global; futuras acoes externas devem receber a referencia
por composicao e chamar `combatService:acquireLock()`.

- [ ] **Step 5: Rodar lint de toda a producao alterada**

Executar:

```bash
selene --config selene.roblox.toml src
```

- [ ] **Step 6: Rodar o LSP antes de avancar**

Executar integralmente o `LSP Checkpoint Obrigatorio` definido no inicio deste
plano. O sourcemap deve ser regenerado depois de concluir a Task 6.

Esperado: nenhum diagnostico novo nos modulos de producao envolvidos na Task 6.

---

### Task 7: Validar imports, tipos, build e invariantes estaticos

**Files:**
- Verify: todos os arquivos de producao listados no File Map.

**Interfaces:**
- Consumes: projeto Rojo normal e os contratos implementados nas Tasks 1-6.
- Produces: producao lintada, typecheck Roblox sem diagnosticos novos e build
  normal valido, sem execucao de specs unitarias ou Roblox MCP.

- [ ] **Step 1: Verificar chamadas antigas do inventario**

Executar uma busca somente em `src/` para localizar acessos operacionais que
ainda usem o modulo como singleton:

```bash
rg -n "InventoryController\.(start|stop|getState|addInstance|equip)" src
```

O resultado esperado e vazio. Tambem verificar que cada chamada de instancia
usa `:` e que `useInventory` recebe a instancia por props.

- [ ] **Step 2: Gerar sourcemap do projeto normal**

Executar:

```bash
rojo sourcemap --include-non-scripts default.project.json --output /tmp/dungeon-game-canve-sourcemap.json
```

Usar o sourcemap gerado na analise, sem criar arquivo de suporte versionado no
repositorio.

- [ ] **Step 3: Rodar o typecheck somente dos modulos de producao envolvidos**

Executar na ordem indicada. Este e o mesmo `LSP Checkpoint Obrigatorio` ja
executado ao fim das Tasks 1 a 6 e deve ser repetido como validacao final:

```bash
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --sourcemap /tmp/dungeon-game-canve-sourcemap.json --formatter gnu \
  src/shared \
  src/server/player \
  src/client/camera \
  src/client/cinematics \
  src/client/combat \
  src/client/dialogue \
  src/client/doors \
  src/client/enemies \
  src/client/events \
  src/client/interactions \
  src/client/inventory \
  src/client/objectives \
  src/client/pickups \
  src/client/player \
  src/client/ui
```

Esperado: nenhum diagnostico novo nos modulos de producao. Nao incluir a arvore
de testes nesta analise.

- [ ] **Step 4: Construir o projeto normal**

Executar:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
```

Esperado: build concluido com o diretorio `src/client/combat` incluido no
place normal. Nao editar o arquivo de saida nem o DataModel por MCP.

- [ ] **Step 5: Verificar invariantes de lifecycle e lock no codigo**

Revisar estaticamente estes pontos antes de considerar o plano concluido:

- `InventoryController.new()` cria estado e `Signal` novos por instancia;
- `CombatService.new()` cria contador e geracao de locks novos por instancia;
- `CombatService:acquireLock()` aborta mira/recarga antes de bloquear e retorna
  release idempotente;
- `release()` antigo nao altera uma nova geracao apos `stop()`;
- aim lock e reload lock sao liberados em todos os caminhos de transicao;
- recarga nao continua apos troca da arma;
- Mouse Right End nao cancela recarga;
- Mouse Right pressionado apos recarga concluida inicia nova aquisicao;
- tiro consome uma unidade mesmo sem impacto;
- dano so e aplicado por `EnemyController:applyDamage`;
- `A`/`D` retornam `Pass` em neutro e `Sink` em mira, recarga ou lock externo;
- dialogo permanece acima do combate em `ActionPriorities`.

- [ ] **Step 6: Conferir a arvore de trabalho sem staging ou commit**

Executar:

```bash
git diff --check
git status --short
```

Confirmar que apenas os arquivos de producao previstos e este plano/spec
aparecem como alterados ou novos. Nao executar `git add`, `git commit`,
`git reset` ou comandos destrutivos.

## Handoff de implementacao

Executar as tasks na ordem 1 a 7. Cada task deve terminar com seu lint e sem
alterar a arvore de testes. O trabalho nao inclui execucao via Roblox MCP; uma
validacao manual no Studio somente deve ser feita depois mediante pedido
explicito do usuario.

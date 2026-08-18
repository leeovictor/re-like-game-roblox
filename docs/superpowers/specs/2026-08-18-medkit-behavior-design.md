# Design: Comportamento de Cura do Medkit

Data: 2026-08-18  
Status: Aprovado na conversa; aguardando revisão do documento

## Objetivo

Completar o primeiro fluxo jogável de uso de item consumível: o jogador coleta
um `medkit`, abre o inventário, pressiona `Usar`, recebe `+25 HP` no próprio
personagem e perde a instância consumida do inventário.

O servidor permanece autoritativo sobre a posse do item, as condições de uso,
o valor da cura, a vida do personagem e o resultado enviado ao cliente.

## Decisões

- O medkit cura `25` pontos fixos, definidos no servidor.
- A primeira versão só permite `target = "self"`.
- Um medkit não pode ser usado com a vida cheia.
- O item não é consumido quando o personagem, o `Humanoid` ou a cura não estão
  disponíveis.
- O valor enviado pelo cliente, incluindo um possível `context.healAmount`, é
  ignorado.
- O inventário continua sendo salvo no padrão atual, durante `PlayerRemoving`.
  Não haverá autosave nesta mudança.
- A UI dispara o uso e exibe o resultado, mas nunca altera o inventário ou a
  vida localmente.

## Arquitetura

O comportamento de item continua separado do sistema de domínio:

```text
MedkitBehavior
  valida contexto e condições
  retorna consumeInstance + efeito declarativo

ItemUseService
  valida a requisição
  encontra e revalida a instância
  coordena a mutação do inventário
  encaminha o efeito ao serviço de domínio

HealthService
  localiza o Humanoid server-side
  verifica Health e MaxHealth
  aplica a cura limitada ao MaxHealth
```

### HealthService

Criar `src/server/health/HealthService.luau` como o único módulo que altera a
vida do personagem para este caso. O serviço deverá expor operações equivalentes
na intenção a:

```lua
canApplyHeal(player, amount) -> (boolean, string?)
applyHeal(player, amount) -> (boolean, number?, string?)
```

`canApplyHeal` verifica:

- `amount` é positivo, finito e definido pelo servidor;
- o jogador ainda possui `Character`;
- existe um `Humanoid`;
- `Health < MaxHealth`.

`applyHeal` repete a validação necessária, calcula:

```lua
actualAmount = math.min(amount, humanoid.MaxHealth - humanoid.Health)
```

e atribui o novo valor a `Humanoid.Health`. O resultado pode informar a
quantidade efetivamente aplicada, que será menor que `25` quando o jogador
estiver parcialmente ferido.

O serviço não conhece inventário, remotes ou `ItemBehaviorRegistry`.

### MedkitBehavior

Criar `src/server/items/MedkitBehavior.luau`. O comportamento será construído
com uma dependência de `HealthService` e registrado para a capability `heal`:

```lua
behaviorRegistry:register("heal", MedkitBehavior.new(healthService))
```

`canUse` deve aceitar somente contexto com `target == "self"` e delegar a
verificação de personagem/vida ao `HealthService` com o valor fixo `25`.

`use` não deve alterar `Humanoid.Health`. Quando a validação estiver aprovada,
deve retornar somente dados:

```lua
{
    success = true,
    consumeInstance = true,
    effect = {
        kind = "heal",
        amount = 25,
    },
}
```

O catálogo continua declarando que `medkit` possui as capabilities `consume` e
`heal`; ele não conterá funções nem o valor de cura executável.

### Efeito e consistência

O tipo de efeito atual é um mapa de atributos genéricos. A implementação deve
adicionar a convenção `kind = "heal"` e preservar `amount` como dado retornado
ao cliente.

Para evitar consumir o item quando a cura não puder ser aplicada, o fluxo de
uso deve validar o efeito antes de confirmar o novo estado do inventário. A
operação de mutação pode receber uma callback de confirmação server-side:

1. `InventoryService` constrói e valida o estado candidato sem publicá-lo.
2. `ItemUseService` solicita ao `HealthService` a aplicação do efeito.
3. Se o serviço de saúde rejeitar, o estado candidato é descartado.
4. Se a cura for aplicada, `InventoryService` publica o estado candidato e
   dispara `InventoryChanged`.

A atribuição do estado candidato é uma operação local sem outra validação que
possa falhar. Assim, a cura e o consumo permanecem coordenados sem transferir a
autoridade para o cliente. O callback deve ser executado no máximo uma vez por
uso.

## Contratos de rede

O cliente usará o remoto existente `Remotes.UseItem` com:

```lua
{
    capability = "heal",
    context = {
        target = "self",
    },
    itemUid = instance.uid,
}
```

O cliente não envia a quantidade de cura e não deve identificar a instância
somente por `itemId`.

O resultado de sucesso terá a forma conceitual:

```lua
{
    success = true,
    itemUid = "medkit-instance-uid",
    consumed = true,
    effect = {
        kind = "heal",
        amount = 25,
        appliedAmount = 25,
    },
}
```

O snapshot atualizado do inventário chegará separadamente por
`InventoryChanged`. A UI deve confiar nesse snapshot para remover a linha do
medkit.

## UI

Atualizar `src/client/ui/App.luau` para renderizar uma ação `Usar` em instâncias
consumíveis compatíveis com `heal`.

- Passar o `uid` da instância para `InventoryController.use`.
- Usar `Activated` no botão para suportar mouse e gamepad.
- Impedir cliques repetidos enquanto a chamada está pendente.
- Mostrar o `reason` retornado quando `success` for falso.
- Não remover o item nem alterar HP no cliente.

O `InventoryController` já encapsula `UseItem:InvokeServer` e não precisa de um
novo remoto. A UI pode usar o catálogo para decidir quais linhas exibem ação,
mas essa decisão é apenas de apresentação; o servidor continua validando a
capability.

## Resultados de erro

Os comportamentos devem usar motivos estáveis:

| Motivo | Condição | Item consumido |
|---|---|---|
| `invalid_request` | payload malformado | não |
| `item_not_found` | uid ausente ou item removido | não |
| `not_compatible` | alvo diferente de `self` ou item sem capability | não |
| `already_full` | `Health >= MaxHealth` | não |
| `player_unavailable` | personagem/Humanoid ausente | não |
| `operation_in_progress` | uso concorrente do mesmo jogador | não |
| `mutation_failed` | estado do inventário não pôde ser confirmado | não |
| `use_failed` | erro inesperado protegido pelo serviço | não |

## Testes

Adicionar testes Lune para as partes testáveis sem um jogo Roblox completo:

- `HealthService`: aceita personagem ferido, limita a cura ao `MaxHealth`,
  rejeita vida cheia e rejeita Humanoid ausente.
- `MedkitBehavior`: aceita somente `target = "self"`, retorna `25`, marca a
  instância para consumo e não altera o estado do fake de saúde durante `use`.
- `ItemUseService`: registra e resolve `heal`, consome uma instância após a
  aplicação do efeito, preserva a instância quando a saúde rejeita a cura e
  bloqueia dois usos concorrentes.
- `InventoryService`/fake de inventário: não publica estado quando a callback de
  efeito falha e publica somente depois de uma aplicação aceita.
- UI: dispara `InventoryController.use` com o `uid` correto, bloqueia chamadas
  pendentes e exibe erro sem fabricar um snapshot local.

## Critérios de sucesso

No Studio:

1. O jogador coleta o pickup de medkit.
2. O medkit aparece no inventário.
3. Com o personagem ferido, `Usar` aplica `+25 HP` ou a quantidade restante até
   `MaxHealth`.
4. A instância desaparece após o sucesso e a UI recebe um novo snapshot.
5. Com a vida cheia, o servidor retorna `already_full` e o item permanece.
6. Um cliente que enviar outro valor de cura não consegue alterar o resultado.

## Fora do escopo

- Cura de outro jogador.
- Cura por percentual.
- Valor de cura configurável por atributo da instância.
- Cooldown do medkit.
- Animação, som e partículas.
- Autosave após cada uso.

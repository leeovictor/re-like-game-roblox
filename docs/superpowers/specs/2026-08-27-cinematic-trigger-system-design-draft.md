# Rascunho: Sistema Generico de Triggers de Cinematic

Data: 2026-08-27
Status: Rascunho para discussao; sem implementacao

## Objetivo

Permitir que varias cinematics sejam disparadas por diferentes tipos de trigger
sem criar um controller especifico para cada cena. Uma nova cinematic deve ser
adicionada principalmente como uma definicao declarativa de trigger, condicoes e
timeline.

## Problema atual

`MachineRoomCinematicController` combina quatro responsabilidades:

- localizar uma Part especifica;
- escutar `Touched`;
- verificar a posse do `access_card`;
- descrever e executar uma timeline especifica.

Esse formato exige um novo modulo e novas conexoes no `init.client.luau` para
cada cinematic semelhante.

## Arquitetura proposta

Separar o sistema em tres camadas:

1. `CinematicDirector`: controla definicoes, condicoes, estado de execucao e
   chama `CinematicController.play(timeline)`.
2. `CinematicDefinitions`: contem as cinematics como dados declarativos.
3. `CinematicTriggerSources`: fornece adapters para diferentes fontes de
   eventos e converte cada uma para uma chamada comum de disparo.

O director nao deve conhecer detalhes de `Touched`, `ProximityPrompt` ou
`GameplayEvents`. Cada adapter deve conhecer somente a fonte que implementa.

```text
Workspace Part.Touched ---------+
ProximityPrompt.Triggered ------+--> TriggerSource --> CinematicDirector
GameplayEvents.subscribe -------+                         |
Manual director:trigger(id) ----+                         v
                                                   CinematicController.play
```

## Definicao de uma cinematic

As definicoes devem usar um tipo discriminado para o trigger:

```lua
{
    id = "machine-room-power",
    trigger = {
        kind = "touch",
        path = "MachineRoomCinematicTrigger",
    },
    requiredItemId = "access_card",
    once = true,
    timeline = {
        -- etapas da cinematic
    },
}
```

Uma cinematic acionada por evento de gameplay poderia ser definida assim:

```lua
{
    id = "facility-entrance-after-door",
    trigger = {
        kind = "gameplay-event",
        event = "door_entered",
        fields = {
            doorKey = "facility_entrance",
        },
    },
    once = true,
    timeline = {
        -- etapas da cinematic
    },
}
```

Uma cinematic acionada por prompt usaria a mesma infraestrutura:

```lua
{
    id = "terminal-intro",
    trigger = {
        kind = "proximity-prompt",
        path = "Facility.Terminal.Prompt",
    },
    timeline = {
        -- etapas da cinematic
    },
}
```

## Tipos de trigger

### `touch`

Resolve uma `BasePart` por caminho relativo ao `Workspace` e escuta
`BasePart.Touched`. O adapter deve ignorar partes que nao pertencem ao
personagem local.

### `proximity-prompt`

Resolve um `ProximityPrompt` por caminho e escuta sua ativacao pelo jogador
local. O adapter deve entregar somente ativacoes do jogador local.

### `gameplay-event`

Assina `GameplayEvents` e dispara quando o nome do evento e os campos definidos
coincidem. Esse tipo permite iniciar cinematics depois de portas, pickups,
objetivos ou outras acoes do jogo.

### `manual`

Nao cria uma conexao Roblox. O gameplay chama explicitamente:

```lua
director:trigger("boss-intro")
```

Esse tipo cobre eventos que ja possuem um controller proprio ou que exigem
validacao especial antes do disparo.

## Contrato dos adapters

Cada fonte de trigger deve expor um lifecycle comum:

```lua
export type TriggerSource = {
    start: (self: TriggerSource, fire: () -> ()) -> (),
    stop: (self: TriggerSource) -> (),
}
```

O `start` registra as conexoes necessarias e chama `fire` quando sua fonte
disparar. O `stop` deve desconectar todas as conexoes criadas pelo adapter.

O director pode manter um registro por tipo:

```lua
director:registerSource("touch", TouchTriggerSource)
director:registerSource("proximity-prompt", ProximityPromptTriggerSource)
director:registerSource("gameplay-event", GameplayEventTriggerSource)
director:registerSource("manual", ManualTriggerSource)
```

Adicionar um novo tipo de trigger deve exigir apenas um novo adapter e seu
registro no composition root, sem alterar o nucleo de execucao ou as timelines.

## Responsabilidades do director

- Validar cada definicao ao iniciar.
- Criar e iniciar o adapter correspondente.
- Resolver condicoes comuns, como `requiredItemId`.
- Rejeitar uma definicao com trigger desconhecido sem impedir as demais.
- Chamar `cinematic:play(definition.timeline)`.
- Marcar a definicao como executada somente quando `play()` retornar `true`.
- Respeitar `once = true` por sessao do cliente.
- Desconectar todos os adapters em `stop()`.
- Interromper a cinematic ativa em `stop()`.

O director nao deve duplicar a validacao, o preload, o bloqueio de movimento,
os efeitos ou a limpeza que ja pertencem ao `CinematicController`.

## Condicoes

A primeira versao deve suportar condicoes declarativas pequenas:

- `requiredItemId`: exige que o item exista no inventario local;
- `once`: impede repeticao depois do primeiro `play()` aceito.

Condicoes futuras podem ser adicionadas como uma uniao discriminada, por
exemplo `requiredObjective` ou `requiredEvent`, sem transformar cada definicao
em uma funcao arbitraria. Funcoes customizadas devem ser evitadas ate existir
uma necessidade concreta, pois dificultam validacao e autoria.

## Lifecycle e concorrencia

O fluxo esperado e:

```text
idle
  -> start adapters
  -> trigger recebido
  -> validar condicoes
  -> CinematicController.play
  -> marcar once, se aplicavel
  -> aguardar o fim controlado pelo CinematicController
  -> receber novos triggers
```

Enquanto uma cinematic estiver em preload ou execucao, o
`CinematicController` continuara rejeitando outra execucao. O director nao
deve criar uma fila implicitamente. Se uma tentativa for rejeitada, a
definicao nao deve ser marcada como executada.

Se uma cinematic falhar depois que `play()` foi aceita, o comportamento de
limpeza continua sendo responsabilidade do `CinematicController`. O director
nao deve tentar reconstruir ou reverter manualmente efeitos de uma timeline.

## Composicao

`init.client.luau` deve criar uma unica instancia:

```lua
local cinematicDirector = CinematicDirector.new({
    cinematic = cinematicController,
    inventory = InventoryController,
})

cinematicDirector:start(CinematicDefinitions)
```

O modulo especifico `MachineRoomCinematicController.luau` deixaria de ser
necessario. A cinematic da sala de maquinas passaria para
`CinematicDefinitions.luau` junto com as futuras cinematics.

## Resolucao de caminhos

Os caminhos de instances devem ser relativos ao `Workspace` e separados por
pontos:

```text
MachineRoomCinematicTrigger
FacilityEntrance.DoorTest
```

O resolver deve rejeitar segmentos vazios, caminhos iniciados ou terminados
com ponto e qualquer tentativa de subir na hierarquia. Cada adapter deve
validar o tipo final esperado, como `BasePart` ou `ProximityPrompt`.

## Erros e diagnostico

- Trigger ausente: emitir `warn` com o ID da cinematic e ignorar essa
  definicao.
- Trigger de tipo incorreto: emitir `warn` e ignorar essa definicao.
- Condicao nao satisfeita: nao emitir erro; aguardar um disparo posterior.
- Timeline rejeitada: preservar o comportamento e o diagnostico do
  `CinematicController`.
- Adapter com falha ao iniciar: emitir `warn` sem impedir outros adapters.

## Escopo inicial

Incluir:

- director generico;
- definicoes declarativas;
- adapters `touch`, `gameplay-event` e `manual`;
- condicoes `requiredItemId` e `once`;
- lifecycle idempotente de start e stop;
- reutilizacao do `CinematicController` existente.

Deixar para uma etapa posterior:

- registro dinamico via `CollectionService` e Attributes;
- fila ou concorrencia entre cinematics;
- triggers autoritativos do servidor;
- predicados arbitrarios em definicoes;
- skip, pause ou sincronizacao multiplayer.

## Arquivos previstos

### Novos arquivos

- `src/client/cinematics/CinematicDirector.luau`
- `src/client/cinematics/CinematicDefinitions.luau`
- `src/client/cinematics/CinematicTriggerSources.luau`

### Arquivos alterados

- `src/client/cinematics/CinematicController.luau`, somente se forem
  necessarios tipos ou helpers publicos;
- `src/client/init.client.luau`, para compor uma unica instancia;
- `src/client/cinematics/MachineRoomCinematicController.luau`, removido depois
  da migracao da definicao.

## Decisao em aberto

Se o numero de triggers crescer bastante, avaliar tags `CinematicTrigger` para
descoberta automatica das Parts. A timeline continuaria em Lua, enquanto a
Part carregaria apenas um `CinematicId`. Essa evolucao deve ser feita somente
quando a quantidade de configuracao manual no composition root justificar a
complexidade adicional.

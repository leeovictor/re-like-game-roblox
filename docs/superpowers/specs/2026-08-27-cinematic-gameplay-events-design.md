# Design: Eventos de Gameplay para Cinematics

Data: 2026-08-27
Status: Design aprovado pelo usuario; spec aguardando revisao escrita

## Objetivo

Fazer o sistema client-side de cinematics publicar eventos no barramento
`GameplayEvents` durante a execucao de uma timeline. Os eventos permitirao que
outros sistemas, especialmente o `ObjectiveController`, reajam ao inicio e ao
fim de uma cinematic identificando qual timeline foi executada.

A timeline deixara de ser uma lista direta de steps. O formato oficial passara a
ser um objeto com um identificador estavel e uma lista de steps:

```luau
export type Timeline = {
    id: string,
    steps: { TimelineStep },
}
```

## Decisoes aprovadas

| Tema | Decisao |
|---|---|
| Evento de inicio | `cinematic_started` |
| Evento de termino | `cinematic_play_ended` |
| Campo identificador | `timelineId: string` |
| Inicio do evento | Depois do preload e da aquisicao do lock, ao entrar em `playing` |
| Termino do evento | Conclusao normal, interrupcao por `stop()` ou falha durante `playing` |
| Falha no preload | Nao emite evento |
| Cancelamento durante preload | Nao emite evento |
| API de eventos | `CinematicController` faz `require` direto de `GameplayEvents` |
| Dependencias do controller | Nao recebe `GameplayEvents` em `Dependencies` |
| Formato de timeline | Somente `{ id, steps }`; a lista antiga nao e mais aceita |
| ID da timeline existente | `generator-power-off` |
| Testes unitarios | Nenhum teste sera criado ou alterado |
| Autoridade | Exclusivamente client-side |

## Contrato de GameplayEvents

`src/client/events/GameplayEvents.luau` recebera dois novos nomes no tipo
`EventName` e duas novas variantes no tipo `GameplayEvent`:

```luau
{ name: "cinematic_started", timelineId: string }
{ name: "cinematic_play_ended", timelineId: string }
```

Os eventos serao publicados usando o modulo existente, sem criar um barramento
novo e sem adicionar uma dependencia de runtime ao controller:

```luau
local GameplayEvents = require(script.Parent.Parent.events.GameplayEvents)
GameplayEvents.emit({
    name = "cinematic_started",
    timelineId = timeline.id,
})
```

O controller protegera a chamada de emissao para que uma falha em um subscriber
nao interrompa a execucao nem pule a limpeza de camera, movimento ou audio. A
falha sera registrada com `warn` e nao alterara o resultado da cinematic.

## Formato e validacao da Timeline

O `CinematicController` continuara validando tabelas externas em runtime antes
de fazer cast para os tipos estritos. A validacao da raiz passara a exigir:

- `id` como string nao vazia;
- `steps` como tabela nao vazia com indices numericos contiguos;
- nenhum campo adicional na raiz.

As regras existentes continuarao sendo aplicadas aos steps dentro de
`timeline.steps`:

- cada step deve ser uma tabela;
- `frame` deve ser inteiro finito e igual ao indice sequencial;
- `duration` deve ser finita e maior ou igual a zero;
- `effects` deve ser uma tabela numerica contigua, podendo ser vazia;
- campos desconhecidos devem invalidar a timeline;
- efeitos e seus atributos devem seguir o contrato ja existente;
- shots desconhecidos e IDs de audio fora do formato aceito devem ser
  rejeitados.

Os diagnosticos passarao a usar o caminho `timeline.steps[...]` para distinguir
erros no envelope da timeline de erros nos steps. Uma timeline invalida nao
altera camera, movimento, preload, audio ou eventos.

`preload()` e `play()` usarao o mesmo validator. O resultado validado mantera o
`id` e os steps normalizados, e a coleta de IDs de som continuara sendo feita
durante a validacao.

O formato anterior, em que a propria raiz era a lista de steps, nao sera aceito
nem convertido. Os consumers de producao serao migrados para o novo formato.

## Lifecycle dos eventos

Cada chamada aceita por `play()` continuara reservando uma execucao e passando
pelos estados `preloading` e `playing`. O ID da timeline sera armazenado junto
da execucao atual para que todos os caminhos usem o mesmo valor.

### Inicio

O fluxo sera:

```text
play(timeline)
  -> valida { id, steps }
  -> reserva execucao
  -> preload automatico
  -> acquireMovementLock
  -> state = "playing"
  -> emit cinematic_started(timeline.id)
  -> executa timeline.steps
```

O evento sera emitido uma vez, antes do primeiro efeito do primeiro step. A
chamada de `play()` ainda retornara antes da conclusao do preload automatico,
como no contrato atual.

Nenhum evento de inicio sera emitido quando:

- a timeline for invalida;
- o controller estiver ocupado;
- o preload automatico falhar;
- a execucao for cancelada durante `preloading`;
- a aquisicao do lock falhar antes da entrada em `playing`.

### Termino

Uma execucao que entrou em `playing` emitira exatamente um
`cinematic_play_ended`, com o mesmo `timelineId`, depois da limpeza aplicavel.

O evento sera emitido nos seguintes caminhos:

- conclusao normal de todos os steps;
- `stop()` enquanto a execucao estiver em `playing`;
- falha de handler de efeito;
- falha durante a espera ou outro erro de execucao depois de entrar em
  `playing`.

O evento nao sera emitido quando a execucao ainda estiver em `preloading` ou
quando o preload falhar antes do inicio efetivo. O encerramento deve ser
idempotente para impedir eventos duplicados por uma task invalidada ou por uma
limpeza concorrente.

A ordem de encerramento sera:

1. marcar a execucao como inativa;
2. liberar o lock de movimento, quando existir;
3. limpar o override da camera;
4. interromper sons somente em interrupcao ou falha;
5. emitir `cinematic_play_ended` com o ID capturado.

Falhas de subscribers nao impedirao nenhuma dessas etapas.

## Integracao com ObjectiveController

`src/client/objectives/ObjectiveController.luau` passara a suportar
`timelineId` em `EventFilter`:

```luau
export type EventFilter = {
    event: GameplayEvents.EventName,
    doorKey: string?,
    itemId: string?,
    areaKey: string?,
    timelineId: string?,
}
```

A validacao de filtros reconhecera `cinematic_started` e
`cinematic_play_ended` como eventos conhecidos, aceitara `timelineId` como
campo permitido e exigira uma string nao vazia quando o campo estiver presente.

O matching comparara `timelineId` com o campo correspondente do evento. Assim,
um objetivo podera ser ativado ao fim de uma timeline:

```luau
startsWhen = {
    event = "cinematic_play_ended",
    timelineId = "generator-power-off",
}
```

As definicoes de objetivos existentes nao serao alteradas. O nome correto do
campo e `startsWhen`, conforme o contrato atual de `ObjectiveDefinition`.

## Consumers de Timeline

`src/client/cinematics/MachineRoomCinematicController.luau` sera atualizado
para encapsular os steps existentes:

```luau
local TIMELINE: CinematicController.Timeline = {
    id = "generator-power-off",
    steps = {
        -- steps atuais da cinematic
    },
}
```

A chamada a `cinematic:play(TIMELINE)` sera preservada. Nenhum outro consumer de
`Timeline` foi encontrado no codigo de producao.

## Arquivos envolvidos

### Arquivos alterados

- `src/client/events/GameplayEvents.luau`
  - adicionar nomes e payloads dos eventos cinematicos;
- `src/client/cinematics/CinematicController.luau`
  - atualizar `Timeline`;
  - validar o envelope `{ id, steps }`;
  - executar `timeline.steps`;
  - armazenar o ID da execucao;
  - emitir os eventos nos pontos do lifecycle;
- `src/client/cinematics/MachineRoomCinematicController.luau`
  - migrar a timeline para o novo envelope;
  - usar o ID `generator-power-off`;
- `src/client/objectives/ObjectiveController.luau`
  - adicionar `timelineId` aos filtros;
  - reconhecer e comparar os eventos cinematicos.

### Arquivos que nao serao alterados

- `src/client/init.client.luau`;
- `src/client/objectives/ObjectiveConfig.luau`;
- `tests/`;
- `src/server/`;
- `src/shared/remotes.luau`;
- `Packages/` e `DevPackages/`.

## Erros e compatibilidade

O comportamento de rejeicao do `CinematicController` continuara retornando
`false` e emitindo `warn` para timelines invalidas. A nova raiz sera validada
antes de qualquer efeito, preload ou evento.

Nao havera camada de compatibilidade para a lista de steps antiga. Isso torna o
contrato de autoria inequivoco e garante que toda cinematic que possa emitir
eventos possua um ID explicito.

As specs unitarias existentes que ainda constroem a forma antiga da timeline
nao serao modificadas conforme a decisao do usuario. Portanto, elas podem falhar
apos a migracao e nao serao usadas como criterio de sucesso desta alteracao.

## Verificacao

Nenhum teste unitario sera criado ou editado. A verificacao estatica e de build
devera confirmar que o codigo de producao usa o contrato novo:

```bash
selene --config selene.roblox.toml src
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --definitions @testez=typecheck/testez.d.luau \
  --sourcemap test-sourcemap.json --formatter gnu \
  src/shared \
  src/server/player \
  src/client/camera src/client/cinematics src/client/doors \
  src/client/dialogue src/client/inventory src/client/objectives \
  src/client/pickups src/client/player src/client/ui \
  tests
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

O typecheck devera incluir os novos campos dos eventos, do filtro e da
timeline. Os builds Rojo devem continuar funcionando. A execucao das suites
TestEZ existentes pode reportar falhas relacionadas ao formato antigo e nao
sera usada para justificar uma alteracao nos testes.

## Fora de escopo

- alterar ou criar testes unitarios;
- adicionar uma dependencia `GameplayEvents` em `CinematicController.Dependencies`;
- criar um novo modulo de eventos cinematicos;
- alterar a composicao em `init.client.luau`;
- adicionar novas cinematics alem da migracao do `MachineRoomCinematicController`;
- adicionar fila, sincronizacao multiplayer ou eventos server-side;
- alterar o formato ou comportamento dos efeitos existentes;
- alterar definicoes existentes de objetivos.

## Criterios de sucesso

- `Timeline` possui o formato `{ id: string, steps: { TimelineStep } }`.
- A timeline `generator-power-off` e aceita e executa seus steps atuais.
- Uma timeline invalida nao emite eventos nem inicia efeitos.
- `cinematic_started` e emitido somente ao entrar efetivamente em `playing`.
- `cinematic_play_ended` e emitido uma vez apos conclusao, interrupcao ou falha
  durante `playing`.
- Falha de preload ou cancelamento durante preload nao emite eventos.
- Ambos os eventos carregam o `timelineId` correto.
- `ObjectiveController` aceita filtros por `timelineId` para os dois eventos.
- Nenhuma alteracao e feita nos testes unitarios existentes.
- Lint, typecheck e builds Rojo passam para o codigo de producao alterado.

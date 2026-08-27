# Cinematic Gameplay Events Implementation Plan

**Goal:** Atualizar o sistema client-side de cinematics para usar timelines com ID, publicar eventos de inicio e termino e permitir que objetivos filtrem esses eventos por `timelineId`.

**Architecture:** `CinematicController` continuara sendo responsavel pela validacao, lifecycle, execucao e limpeza da timeline. Ele fara `require` direto de `GameplayEvents` e emitira eventos protegidos contra falhas de subscribers, sem adicionar uma dependencia de runtime ao controller. `ObjectiveController` consumira os novos eventos pelo filtro existente, enquanto `MachineRoomCinematicController` migrara sua definicao para o envelope `{ id, steps }`.

**Tech Stack:** Luau `--!strict`, Roblox Studio DataModel, `GameplayEvents`, TestEZ existente sem alteracoes, Rojo 7.7.0, Selene 0.29.0 e `luau-lsp` 1.69.0.

## Global Constraints

- Manter `--!strict` em todos os modulos alterados.
- Usar somente a plataforma Roblox nas analises de typecheck de `src` e `tests`.
- Fazer `require` direto de `GameplayEvents` em `CinematicController`; nao adicionar `events` em `CinematicController.Dependencies`.
- Aceitar somente o novo formato `Timeline = { id: string, steps: { TimelineStep } }`; nao converter a lista antiga.
- Emitir `cinematic_started` somente depois do preload, da aquisicao do lock e da entrada efetiva em `playing`.
- Emitir `cinematic_play_ended` uma vez para conclusao, interrupcao ou falha depois de `playing`.
- Nao emitir eventos para timeline invalida, controller ocupado, falha de preload ou cancelamento durante `preloading`.
- Usar `timelineId` como campo do payload e dos filtros de objetivos.
- Usar `generator-power-off` como ID da timeline da sala de maquinas.
- Nao alterar ou criar arquivos em `tests/`, mesmo que as specs antigas usem a lista de steps anterior.
- Nao alterar `src/client/init.client.luau`, `src/client/objectives/ObjectiveConfig.luau` ou `src/server`.
- Nao alterar `Packages/` ou `DevPackages/`.
- Nao fazer `git add`, `git commit`, `git amend` ou qualquer outra operacao de commit.
- Usar `apply_patch` para todas as edicoes manuais.

---

## File Map

- `src/client/events/GameplayEvents.luau`: contrato discriminado dos eventos de gameplay.
- `src/client/cinematics/CinematicController.luau`: tipo `Timeline`, validator, execucao e emissao dos eventos.
- `src/client/cinematics/MachineRoomCinematicController.luau`: consumer da timeline da sala de maquinas.
- `src/client/objectives/ObjectiveController.luau`: filtros e matching por `timelineId`.
- `docs/superpowers/specs/2026-08-27-cinematic-gameplay-events-design.md`: spec aprovada que deve permanecer alinhada ao codigo.
- `tests/`: somente leitura durante a implementacao; nenhum arquivo sera editado.

## Task 1: Extend the Gameplay Event Contract

**Files:**
- Modify: `src/client/events/GameplayEvents.luau:6-20`
- Do not modify: `tests/client/events/GameplayEvents.spec.luau`

**Interfaces:**
- Consumes: o contrato atual `EventName`, `GameplayEvent` e `GameplayEvents.emit`.
- Produces: os nomes `cinematic_started` e `cinematic_play_ended`, cada um com `timelineId: string`.

- [ ] **Step 1: Add the new event names to `EventName`**

Acrescente os dois literais ao union existente sem remover nenhum evento:

```luau
export type EventName =
    "door_blocked"
    | "door_unlocked"
    | "door_entered"
    | "item_collected"
    | "area_entered"
    | "switches_changed"
    | "cinematic_started"
    | "cinematic_play_ended"
```

- [ ] **Step 2: Add the discriminated payload variants**

Acrescente as variantes ao union `GameplayEvent`, preservando os campos dos
eventos existentes:

```luau
    | { name: "cinematic_started", timelineId: string }
    | { name: "cinematic_play_ended", timelineId: string }
```

Nao altere `emit`, `subscribe`, `SignalConnection` ou o estado do modulo.

- [ ] **Step 3: Verify the contract file without editing tests**

Run:

```bash
selene --config selene.roblox.toml src/client/events/GameplayEvents.luau
git diff --check
```

Expected: nenhum diagnostico de lint ou whitespace; o diff deve conter somente
o modulo de producao neste task.

## Task 2: Migrate CinematicController Timeline Processing

**Files:**
- Modify: `src/client/cinematics/CinematicController.luau:1-72,212-285,335-376,439-565,567-605`
- Do not modify: `tests/client/cinematics/CinematicController.spec.luau`

**Interfaces:**
- Consumes: `GameplayEvents.emit`, dependencias atuais de camera, movimento e som.
- Produces: `CinematicController.Timeline` com `id` e `steps`; eventos de lifecycle com `timelineId`; execucao exclusivamente sobre `timeline.steps`.

- [ ] **Step 1: Import GameplayEvents and update the exported timeline type**

Adicione o require junto dos imports client-side:

```luau
local GameplayEvents = require(script.Parent.Parent.events.GameplayEvents)
```

Substitua o tipo de lista direta:

```luau
export type Timeline = {
    id: string,
    steps: { TimelineStep },
}
```

Adicione `currentTimelineId: string?` ao tipo `Controller` para guardar o ID da
execucao reservada e permitir que `stop()` publique o mesmo ID somente quando a
execucao ja estiver em `playing`.

- [ ] **Step 2: Validate the new root envelope before inspecting steps**

Atualize `validateTimeline()` para seguir esta ordem:

1. rejeitar valores que nao sejam tabelas;
2. rejeitar campos de raiz diferentes de `id` e `steps` usando `unknownField`;
3. rejeitar `timeline.id` que nao seja string nao vazia;
4. calcular `contiguousLength(timeline.steps)` e rejeitar steps ausentes,
   vazios ou nao contiguos;
5. aplicar as validacoes atuais a cada `timeline.steps[index]`;
6. retornar uma tabela tipada com `id = value.id` e `steps` normalizados, junto
   da lista deduplicada de IDs de som.

A estrutura central deve ficar equivalente a:

```luau
local field = unknownField(value, { id = true, steps = true })
if field ~= nil then
    return nil, nil, "timeline has unknown field " .. field
end
if type(value.id) ~= "string" or value.id == "" then
    return nil, nil, "timeline.id must be a non-empty string"
end

local stepsLength, stepsError = contiguousLength(value.steps)
if stepsLength == nil then
    return nil, nil, "timeline.steps " .. (stepsError :: string)
end
if stepsLength == 0 then
    return nil, nil, "timeline.steps must not be empty"
end

local timeline: Timeline = {
    id = value.id,
    steps = {},
}
```

Mantenha as regras de `frame`, `duration`, `effects`, campos desconhecidos,
shots, efeitos e IDs de audio. Os erros de steps devem usar o caminho
`timeline.steps[index]`. Nao aceite nem normalize a forma antiga em que a raiz
era a lista de steps.

- [ ] **Step 3: Add a protected gameplay-event emission helper**

Crie um helper local proximo aos helpers de signals, com o contrato abaixo:

```luau
local function emitCinematicEvent(event: GameplayEvents.GameplayEvent): ()
    local ok, errorMessage = pcall(function()
        GameplayEvents.emit(event)
    end)
    if not ok then
        warn("CinematicController gameplay event failed: " .. tostring(errorMessage))
    end
end
```

A protecao deve impedir que uma excecao de subscriber interrompa cleanup,
sequenciamento ou a emissao do evento de termino.

- [ ] **Step 4: Carry the timeline ID through every execution path**

Atualize as assinaturas de `runExecution`, `finishNormally`,
`finishInterrupted` e qualquer helper de cleanup que precise do ID. O worker
deve operar sobre `timeline.steps`, nao sobre a raiz:

```luau
for _, step in timeline.steps do
    -- validacao de geracao, efeitos e espera permanecem nesta ordem
end
```

Defina `currentTimelineId = validatedTimeline.id` no momento em que `play()`
reserva a execucao. Limpe esse campo junto com `currentExecutionId` em todos os
paths que retornam ao estado `idle`.

- [ ] **Step 5: Emit cinematic_started at effective playback start**

No worker, mantenha o preload antes do lock e o lock antes do estado `playing`.
Depois de `self.state = "playing"`, emita exatamente:

```luau
emitCinematicEvent({
    name = "cinematic_started",
    timelineId = timeline.id,
})
```

Essa chamada deve ocorrer antes do primeiro efeito do primeiro step. Nao emita
durante `preload()`, durante a validacao, quando outra execucao estiver ativa,
se o preload falhar ou se o lock falhar antes de `playing`.

- [ ] **Step 6: Emit cinematic_play_ended on all post-start endings**

Depois de marcar a execucao como inativa e executar a limpeza aplicavel, emita:

```luau
emitCinematicEvent({
    name = "cinematic_play_ended",
    timelineId = timelineId,
})
```

Inclua a emissao em `finishNormally`, em `finishInterrupted` e no caminho de
`stop()` que observa `wasPlaying == true`. Nao inclua em `finishWithoutEffects`
quando ele tratar falha de preload, falha ao adquirir o lock ou cancelamento em
`preloading`.

Garanta que cada caminho emita no maximo uma vez. A task invalidada por
`stop()` nao pode emitir novamente depois que `stop()` publicar o evento.
Falhas de handlers, falhas de espera e outros erros ocorridos depois de
`playing` devem passar por `finishInterrupted` e publicar o ID capturado.

- [ ] **Step 7: Reset the new execution field in constructor and cleanup**

Inicialize `currentTimelineId = nil` em `CinematicController.new()` e limpe-o
em `finishNormally`, `finishInterrupted`, `finishWithoutEffects` e `stop()`.
Preserve a rejeicao de chamadas enquanto o estado for diferente de `idle` e o
comportamento atual de `playingChanged`.

- [ ] **Step 8: Run production lint and inspect the focused diff**

Run:

```bash
selene --config selene.roblox.toml src/client/cinematics/CinematicController.luau
git diff --check
git diff -- src/client/cinematics/CinematicController.luau
```

Expected: o modulo permanece strict, nao ha diagnosticos de lint e nenhum
arquivo de teste aparece no diff.

## Task 3: Migrate the Timeline Consumer and Objective Filters

**Files:**
- Modify: `src/client/cinematics/MachineRoomCinematicController.luau:30-87`
- Modify: `src/client/objectives/ObjectiveController.luau:10-15,81-95,123-142`
- Do not modify: `src/client/objectives/ObjectiveConfig.luau`

**Interfaces:**
- Consumes: `CinematicController.Timeline`, `GameplayEvents.EventName` e `GameplayEvents.GameplayEvent`.
- Produces: timeline `generator-power-off` e filtros de objetivo por `timelineId`.

- [ ] **Step 1: Wrap the machine-room steps in the new timeline envelope**

Conserve todos os steps, frames, duracoes e efeitos atuais. Altere somente o
envelope para:

```luau
local TIMELINE: CinematicController.Timeline = {
    id = "generator-power-off",
    steps = {
        -- os cinco steps existentes, sem alteracao de conteudo
    },
}
```

Mantenha a chamada `dependencies.cinematic:play(TIMELINE)` e o comportamento do
trigger, inventario, `triggered`, `start()` e `stop()`.

- [ ] **Step 2: Add timelineId to ObjectiveController.EventFilter**

Estenda o tipo sem remover os campos existentes:

```luau
export type EventFilter = {
    event: GameplayEvents.EventName,
    doorKey: string?,
    itemId: string?,
    areaKey: string?,
    timelineId: string?,
}
```

- [ ] **Step 3: Match cinematic events by timelineId**

No helper `matches`, adicione a comparacao de `filter.timelineId` com o campo
correspondente do evento, preservando o comportamento dos filtros atuais:

```luau
if filter.timelineId ~= nil then
    return (event :: any).timelineId == filter.timelineId
end
```

O filtro abaixo deve retornar `true` somente para o ID indicado:

```luau
{
    event = "cinematic_play_ended",
    timelineId = "generator-power-off",
}
```

- [ ] **Step 4: Validate the new event and filter field**

Atualize `knownEvents` em `validateFilter()` com:

```luau
cinematic_started = true,
cinematic_play_ended = true,
```

Inclua `timelineId = true` na tabela de campos permitidos. Para qualquer filtro
que contenha `timelineId`, exija string nao vazia, usando a mesma regra dos
campos de identificacao existentes. Filtros de eventos antigos devem continuar
validos sem `timelineId`.

- [ ] **Step 5: Verify no objective definitions or tests were changed**

Run:

```bash
selene --config selene.roblox.toml src/client/cinematics/MachineRoomCinematicController.luau src/client/objectives/ObjectiveController.luau
git diff --check
git diff --name-only -- tests src/client/objectives/ObjectiveConfig.luau
```

Expected: lint sem diagnosticos; o ultimo comando nao deve listar arquivos,
porque testes e `ObjectiveConfig.luau` permanecem intocados.

## Task 4: Run Static and Rojo Verification

**Files:**
- Inspect: `src/client/events/GameplayEvents.luau`
- Inspect: `src/client/cinematics/CinematicController.luau`
- Inspect: `src/client/cinematics/MachineRoomCinematicController.luau`
- Inspect: `src/client/objectives/ObjectiveController.luau`
- Generated: `test-sourcemap.json` may be refreshed by the prescribed command
- Do not modify: `tests/`

**Interfaces:**
- Consumes: os quatro modulos de producao alterados.
- Produces: evidencia de lint, typecheck e builds Rojo para o contrato novo.

- [ ] **Step 1: Run production lint**

Run:

```bash
selene --config selene.roblox.toml src
```

Expected: exit status `0` e nenhum diagnostico. Nao rode o lint de `tests/` como
parte desta mudanca para evitar tratar arquivos de teste intocados como alvo de
alteracao.

- [ ] **Step 2: Regenerate the test sourcemap**

Run:

```bash
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
```

Expected: o sourcemap e gerado sem erro e nenhum arquivo de producao ausente e
criado manualmente.

- [ ] **Step 3: Run the Roblox typecheck**

Run exatamente a analise prescrita para a plataforma Roblox:

```bash
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
```

Expected: nenhum diagnostico de tipo nos modulos de producao alterados. As
specs antigas podem continuar compilando como Luau, mas nao sao atualizadas nem
usadas como verificacao comportamental desta migracao.

- [ ] **Step 4: Build both Rojo projects**

Run:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

Expected: os dois builds completam sem erro; o build de producao inclui os
modulos client-side alterados e o build de teste continua mapeando a arvore
existente sem exigir novos arquivos de teste.

- [ ] **Step 5: Confirm the final worktree scope**

Run:

```bash
git diff --check
git status --short
git diff --name-only -- tests
```

Expected: nao ha erro de whitespace, somente os quatro modulos de producao e
este plano/spec podem aparecer como modificados ou nao rastreados, e o comando
de arquivos de teste nao lista nada. Nao fazer commit ao finalizar.

## Notes on Existing TestEZ Specs

As specs atuais de `CinematicController` constroem a timeline como uma lista
direta de steps. A decisao aprovada e exigir somente `{ id, steps }`, portanto
esses arquivos permanecerao sem alteracao e nao serao usados como criterio de
sucesso comportamental desta implementacao. O codigo de producao deve ser
validado por lint, typecheck, builds Rojo e inspecao manual dos quatro paths de
lifecycle descritos na Task 2.

# Design: Sistema de Cinematic Client-Side

Data: 2026-08-24
Status: Design aprovado pelo usuario; documento sem commit

## Objetivo

Criar um executor de cinematics que rode exclusivamente no cliente e receba uma
timeline declarativa por uma API explicita:

```lua
CinematicController.play(timeline)
```

O sistema deve executar etapas em ordem, aplicar efeitos no inicio de cada
etapa, aguardar a duracao configurada e avancar para a proxima etapa. A primeira
versao deve suportar somente troca instantanea de camera e sons locais one-shot.

O sistema nao deve usar `RemoteEvent`, `RemoteFunction` ou qualquer mutacao
autoritativa no servidor. O estado alterado pela cinematic e exclusivamente o
estado visual e de entrada local do jogador.

## Decisoes aprovadas

| Tema | Decisao |
|---|---|
| Gatilho | API local explicita `CinematicController.play(timeline)` |
| Modelo temporal | Lista sequencial de etapas |
| `frame` | Indice sequencial da etapa, sem representar tempo |
| `duration` | Duracao em segundos |
| Inicio da etapa | Todos os efeitos sao executados imediatamente, na ordem declarada |
| Avanco | O controller aguarda `duration` antes da proxima etapa |
| Concorrencia | Nova execucao e rejeitada enquanto houver preload ou cinematic ativa |
| Interrupcao | `stop()` invalida a execucao atual |
| Autoridade | Exclusivamente client-side, sem remotes |
| Controles | Desabilitados automaticamente durante a execucao e restaurados ao final |
| Camera | Shots existentes em `Workspace.CameraSystem.Shots` |
| Camera cinematic | Override integrado ao `CameraController` e ao `PreRender` existente |
| Restauracao da camera | Resolver novamente o shot de gameplay na posicao atual do jogador |
| Transicao de camera | Corte instantaneo, sem tween ou blending |
| Audio | `play-sound` one-shot local |
| Audio ID | Deve chegar normalizado como `rbxassetid://<numero>` |
| Preload | API explicita `preload(timeline)` e fallback automatico em `play()` |
| Perfis de modelo | Fora da primeira versao |
| Estado de portas | Fora da primeira versao |
| Commit da especificacao | Nao realizar commit deste documento |

## Fora de escopo

- `set-model-profile` e qualquer convencao de VFX, transparencia ou snapshot
  de propriedades de modelos.
- `change-door-state` e qualquer mutacao local ou autoritativa de portas.
- Comunicacao com o servidor para iniciar ou sincronizar a cinematic.
- Tracks independentes para camera, audio ou gameplay.
- Instantes absolutos com campo `at`.
- Tween, easing, blending ou interpolacao de shots.
- Loop, volume, playback speed ou posicionamento espacial configuravel no
  efeito `play-sound`.
- Skipping, pause, seek ou scrubbing da timeline.
- UI de cinematic ou specs de UI.
- Uma definicao de timeline especifica de gameplay; callers fornecem as tabelas.

## Formato da timeline

A timeline e uma lista numerica contigua de etapas. O formato inicial e:

```lua
local timeline = {
	{
		frame = 1,
		duration = 1,
		effects = {
			{
				name = "play-sound",
				attributes = {
					soundId = "rbxassetid://234123123",
				},
			},
		},
	},
	{
		frame = 2,
		duration = 2,
		effects = {
			{
				name = "set-camera-shot",
				attributes = {
					shot = "generator_shot",
				},
			},
		},
	},
}
```

### Regras de validacao

- A timeline deve ser uma tabela nao vazia.
- Cada etapa deve existir em uma posicao numerica contigua.
- `frame` deve ser um numero inteiro finito maior que zero.
- `frame` deve ser igual ao indice da etapa na lista.
- `duration` deve ser um numero finito maior ou igual a zero.
- `effects` deve ser uma tabela numerica contigua; pode ser vazia para
  representar uma pausa sem efeitos.
- Cada efeito deve ser uma tabela com `name` e, quando exigido, `attributes`.
- Campos desconhecidos na etapa, no efeito ou em `attributes` devem invalidar
  a timeline, evitando erros de digitacao silenciosos.
- O nome aceito nesta versao e somente `set-camera-shot` ou `play-sound`.
- `set-camera-shot` exige `attributes.shot` como string nao vazia e o shot deve
  existir na configuracao carregada pelo `CameraController`.
- `play-sound` exige `attributes.soundId` como string nao vazia no formato
  `rbxassetid://<numero>`.
- Uma timeline invalida nao pode alterar camera, controles, preload ou audio.

O validator sera executado tanto por `preload()` quanto por `play()`. A falha
retorna `false` e emite um `warn` com o caminho do campo invalido. O sistema nao
deve lancar uma execucao parcial por erro de autoria.

## API e composicao

`CinematicController.luau` sera um modulo client-side com um controller padrao
configurado pelo `init.client.luau` e uma funcao `new(dependencies)` para specs
e fixtures isoladas.

A API publica do modulo padrao sera:

```lua
CinematicController.configure(dependencies): ()
CinematicController.preload(timeline): boolean
CinematicController.play(timeline): boolean
CinematicController.stop(): ()
CinematicController.isPlaying(): boolean
```

`configure()` sera chamado uma vez pelo `init.client.luau` depois que os
controllers de camera e movimento estiverem disponiveis. A chamada deve montar
o controller padrao com estas dependencias:

- `camera.hasShot(shotId) -> boolean`;
- `camera.setCinematicShot(shotId) -> boolean`;
- `camera.clearCinematicShot() -> ()`;
- `movement.acquireMovementLock() -> release()`;
- `sound.preload(soundIds) -> boolean`;
- `sound.play(soundId, executionId) -> ()`;
- `sound.stop(executionId) -> ()`;
- `wait(duration) -> ()`.

`new(dependencies)` recebe as mesmas interfaces para permitir fakes de camera,
movimento, audio e espera nas specs. O objeto criado por `new()` tera os
metodos de operacao (`preload`, `play`, `stop` e `isPlaying`); `configure()` e
exclusiva do modulo padrao.

### `preload`

- Valida a timeline antes de preparar qualquer asset.
- So pode iniciar quando o controller estiver `idle`.
- Retorna `false` se houver preload ou execucao em andamento.
- Extrai os IDs unicos da timeline.
- Cria ou reutiliza templates locais de `Sound` por ID.
- Usa `ContentProvider:PreloadAsync()` nos templates ausentes.
- Aguarda o preload antes de retornar.
- Retorna `true` quando todos os IDs foram preparados.
- Em falha de carregamento, emite um aviso e retorna `false`.
- Nao desabilita controles e nao altera a camera.

O preload pode ser chamado manualmente pelo desenvolvedor antes do gameplay
disparar uma cinematic. O cache e compartilhado com o fallback automatico de
`play()`.

### `play`

- Valida a timeline de forma sincrona.
- Retorna `false` se a timeline for invalida ou se o controller nao estiver
  `idle`.
- Ao aceitar a chamada, retorna `true` e reserva a execucao atual.
- Prepara automaticamente somente os IDs de audio ausentes no cache.
- Mantem os controles disponiveis durante o preload automatico.
- Se o preload automatico falhar, abandona a execucao sem aplicar camera,
  controles ou efeitos e emite um aviso.
- Depois do preload, adquire o bloqueio de movimento e entra em `playing`.
- Executa as etapas em ordem, aplicando efeitos no inicio de cada uma.
- Aguarda `duration` depois dos efeitos antes de avancar.
- Ao finalizar a ultima etapa, executa a limpeza normal.

`isPlaying()` retorna `true` somente enquanto as etapas estao sendo executadas.
O estado `preloading` continua ocupado para fins de rejeicao de novas chamadas,
mesmo que `isPlaying()` retorne `false`.

### `stop`

- E seguro quando o controller esta `idle`.
- Invalida a geracao da execucao atual.
- Faz uma task antiga abandonar antes de executar qualquer efeito seguinte.
- Se a cinematic ja estiver em `playing`, libera o bloqueio de movimento.
- Remove o override cinematografico e solicita a restauracao do shot normal.
- Interrompe e destroi os sons da execucao interrompida.
- Se estiver em preload, nao tenta cancelar uma chamada de `PreloadAsync` que ja
  comecou; ignora seu resultado e pode manter o asset no cache.

## Arquitetura

```text
src/client/init.client.luau
  -> cria e inicia CameraController
  -> inicia TankController
  -> configura CinematicController com as dependencias reais

caller client-side
  -> CinematicController.play(timeline)
       -> validate timeline
       -> preload/cache de sons ausentes
       -> acquireMovementLock
       -> executa etapas sequenciais
            -> EffectRegistry["set-camera-shot"]
            -> EffectRegistry["play-sound"]
       -> clear cinematic camera override
       -> releaseMovementLock

CameraController.PreRender
  -> resolve shot normal do jogador
  -> se houver override cinematic, aplica o override
  -> aplica CFrame e FieldOfView
```

O nucleo do controller sera responsavel por validacao, estado, geracao,
sequenciamento e limpeza. O registro de efeitos sera responsavel apenas por
traduzir o nome e os atributos de um efeito para uma chamada de dependencia.

O nucleo nao deve conhecer detalhes de `Sound`, `ContentProvider` ou da
resolucao espacial da camera alem das interfaces injetadas.

## Integracao com CameraController

O `CameraController` atual ja e a autoridade do `PreRender`. O sistema de
cinematic nao criara uma segunda conexao de renderizacao nem escrevera
diretamente em `CurrentCamera` a partir de outro loop.

O controller de camera recebera uma API de override:

```lua
cameraController:hasShot(shotId): boolean
cameraController:setCinematicShot(shotId): boolean
cameraController:clearCinematicShot(): ()
```

O override sera um `cinematicShotId` separado do estado normal do jogador. O
`CameraController` tambem separara:

- `playerShotId`: ultimo shot de gameplay resolvido ou o shot padrao inicial;
- `currentShotId`: shot efetivamente aplicado na camera;
- `cinematicShotId`: override temporario, quando houver.

Em cada `PreRender`, o fluxo sera:

1. Resolver a zona atual do jogador.
2. Atualizar `playerShotId` quando houver uma zona correspondente.
3. Manter o ultimo shot normal quando o jogador estiver fora de zonas, seguindo
   o comportamento existente.
4. Escolher `cinematicShotId` quando o override existir; caso contrario, usar
   `playerShotId`.
5. Aplicar CFrame e FieldOfView somente quando o shot efetivo mudar.

`setCinematicShot()` valida o ID, guarda o override e faz o proximo ciclo do
`PreRender` aplicar o corte. `clearCinematicShot()` remove o override e faz o
controller aplicar novamente o shot normal resolvido a partir da posicao atual
do jogador. O shot cinematic nunca deve substituir `playerShotId`.

`stop()` do `CameraController` limpa os tres estados de shot, como ja limpa o
shot atual hoje.

## Integracao com controles

`TankController` recebera um bloqueio com dono e liberacao idempotente:

```lua
local release = TankController.acquireMovementLock()
release()
```

O movimento so sera permitido quando nao houver bloqueios ativos. A cinematic
adquire exatamente um bloqueio depois do preload e libera o mesmo bloqueio na
conclusao, no cancelamento ou em uma falha de handler.

O `DialogueController` usara o mesmo mecanismo: guardara a funcao de liberacao
enquanto um dialogo estiver aberto e a chamara ao fechar ou substituir o
dialogo. Isso impede que um sistema libere o movimento de outro sistema.

O metodo existente `setMovementEnabled` permanecera disponivel para os
consumidores legados, mas os fluxos de dialogo e cinematic usarao bloqueios
escopados. O loop de movimento considerara tanto o estado manual existente
quanto a contagem de bloqueios.

## Registro de efeitos

### `set-camera-shot`

- Executado no inicio da etapa.
- Exige somente `attributes.shot`.
- Faz um corte instantaneo para um shot ja carregado do `CameraController`.
- Nao altera o shot normal do jogador.
- Se aparecer varias vezes, o ultimo efeito executado na etapa sera o shot
  efetivo daquela etapa.
- O handler deve ser chamado dentro da geracao atual; uma task invalidada nao
  pode aplica-lo.

### `play-sound`

- Executado no inicio da etapa.
- Exige somente `attributes.soundId`.
- Usa `Looped = false` e valores padrao para as demais propriedades.
- Cria uma instancia de reproducao a partir do template cacheado.
- A instancia de reproducao e criada no cliente, parentada localmente e tocada
  com `Sound:Play()`, permitindo rastrear `Ended`, `Stop()` e `Destroy()`.
- Reproducoes da mesma timeline podem ocorrer simultaneamente.
- Cada instancia se destroi apos `Ended`.
- `stop()` interrompe somente as instancias pertencentes a sua geracao.
- Ao terminar naturalmente, uma instancia que ainda esteja tocando pode
  concluir; o fim da timeline nao corta um one-shot em andamento.

O `CinematicSoundPlayer` mantera templates por `soundId` e instancias ativas
associadas a um token de execucao. Templates permanecem no cache entre
cinematics; instancias de reproducao nao permanecem.

## Estados e limpeza

Os estados possiveis sao:

```text
idle -> preloading -> playing -> idle
idle -> preloading -> idle       (falha ou cancelamento)
playing -> idle                  (conclusao, falha ou stop)
```

Cada execucao tera uma geracao monotonicamente crescente. O worker deve
verificar a geracao:

- antes de iniciar a execucao;
- depois do preload;
- antes de cada etapa;
- depois de cada espera;
- antes de cada efeito.

A limpeza normal e a limpeza de erro/cancelamento devem ser idempotentes e
seguir a mesma ordem:

1. Marcar a execucao como inativa.
2. Invalidar a geracao quando aplicavel.
3. Liberar o bloqueio de movimento da cinematic.
4. Remover o override da camera.
5. Restaurar o shot de gameplay atual pelo `CameraController`.
6. Parar e destruir os sons somente quando a execucao foi interrompida ou
   falhou.

Nenhuma limpeza deve chamar diretamente um efeito de restauracao da timeline.
Os efeitos `disable_char_controls` e `restore-player-camera-shot` nao serao
aceitos pelo validator.

## Arquivos envolvidos

### Novos arquivos

- `src/client/cinematics/CinematicController.luau`
- `src/client/cinematics/CinematicSoundPlayer.luau`
- `tests/client/cinematics/CinematicController.spec.luau`
- `tests/client/cinematics/CinematicSoundPlayer.spec.luau`

### Arquivos alterados

- `src/client/camera/CameraController.luau`: override cinematic e separacao do
  shot normal do jogador.
- `src/client/player/TankController.luau`: bloqueios de movimento escopados.
- `src/client/dialogue/DialogueController.luau`: uso do bloqueio escopado.
- `src/client/init.client.luau`: configuracao do controller cinematic padrao.
- `test.project.json`: mapeamento da arvore `src/client/cinematics` e das specs.

Nao havera alteracoes em `src/server`, em `src/shared/remotes.luau` ou no
contrato das portas.

## Testes

### CinematicController

- Aceita uma timeline valida com etapas sequenciais.
- Rejeita timeline vazia, frame fora de ordem, duracao negativa ou nao finita.
- Rejeita effects com buracos, atributos ausentes ou campos desconhecidos.
- Rejeita shots inexistentes.
- Rejeita `soundId` que nao esteja normalizado.
- Rejeita `set-model-profile`, `change-door-state` e outros nomes desconhecidos.
- Executa todos os efeitos no inicio de cada etapa e registra as duracoes na
  ordem esperada usando uma espera injetada.
- Avanca imediatamente depois de uma etapa com `duration = 0`.
- Rejeita uma segunda chamada durante preload ou execucao.
- Faz preload automatico de IDs ausentes antes de adquirir o bloqueio.
- Usa o cache quando o mesmo ID aparece novamente.
- Nao altera camera ou controles durante preload.
- Restaura camera e movimento apos conclusao normal.
- Restaura camera e movimento apos `stop()`.
- Impede efeitos posteriores de uma task invalidada.
- Limpa camera, movimento e sons quando um handler falha.

### CameraController

- Mantem o shot cinematic aplicado em ciclos consecutivos de `PreRender`.
- Nao substitui o shot normal do jogador pelo override cinematic.
- Atualiza o shot normal enquanto o override esta ativo.
- Ao limpar o override, restaura o shot correspondente a posicao atual do
  jogador.
- Mantem o ultimo shot normal fora de zonas.
- Rejeita um shot cinematic inexistente.
- Limpa o override em `stop()`.

### TankController e DialogueController

- Dois bloqueios ativos mantem o movimento desabilitado.
- Liberar um bloqueio nao libera o outro.
- Liberar o mesmo bloqueio duas vezes nao altera a contagem novamente.
- Fechar um dialogo durante uma cinematic nao libera o movimento cinematic.
- Encerrar a cinematic enquanto um dialogo esta aberto mantem o movimento
  bloqueado pelo dialogo.

### CinematicSoundPlayer

- Deduplica IDs no preload.
- Reutiliza o template de um ID ja preparado.
- Cria instancias one-shot rastreaveis.
- Destroi instancias apos `Ended`.
- `stop()` interrompe e destroi somente os sons da execucao indicada.
- Mantem templates no cache depois da execucao.

As specs usarao dependencias falsas para scheduler, camera, movimento e audio
quando a verificacao nao exigir o DataModel real. Fixtures que criarem
Instances ou conexoes serao destruidas em `afterEach`. Nao serao adicionadas
specs de UI.

## Criterios de sucesso

- Um caller client-side consegue disparar `CinematicController.play(timeline)`.
- Uma nova cinematic e rejeitada enquanto outra estiver em preload ou execucao.
- Efeitos sao executados no inicio das etapas e na ordem declarada.
- `duration` e respeitada em segundos entre etapas.
- O primeiro uso de um som nao introduz atraso dentro da timeline quando o
  preload manual ou automatico termina com sucesso.
- `set-camera-shot` permanece aplicado apesar do `PreRender` existente.
- Ao terminar ou interromper, os controles sao restaurados e a camera volta ao
  shot de gameplay resolvido pela posicao atual.
- Falhas nao deixam o jogador preso sem controle nem com override de camera.
- Nenhuma alteracao exige servidor ou altera o estado dos demais jogadores.
- `set-model-profile` e `change-door-state` continuam explicitamente fora do
  contrato inicial.
- Selene, typecheck, builds Rojo e as suites TestEZ passam sem falhas.

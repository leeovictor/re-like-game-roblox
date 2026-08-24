# Design: Migracao do TankController para Instancias

Data: 2026-08-24  
Status: Design aprovado em conversa; aguardando revisao do usuario; sem commit

## Objetivo

Refatorar `TankController` para ser construido como uma instancia, removendo o
estado runtime mantido na tabela retornada diretamente por `require`.

O uso principal sera:

```luau
local tankController = TankController.new()

tankController:start()
local release = tankController:acquireMovementLock()
release()
tankController:stop()
```

A migracao sera completa. Nao havera fachada singleton, aliases estaticos ou
compatibilidade temporaria para chamadas sem instancia.

## Decisoes aprovadas

| Tema | Decisao |
|---|---|
| Construcao | `TankController.new()` sem argumentos |
| Dependencias | Controllers/services usam `new(dependencies)` com tabela nomeada |
| Estado | Todo estado mutavel do TankController pertence a cada instancia |
| Metodos | Metodos de instancia usam `:` e declaram `self` |
| TankControlMath | Continua sendo importado diretamente como modulo puro interno |
| DialogueController | Tambem sera convertido para instancia |
| CameraController | Construcao sera padronizada para tabela nomeada |
| Composicao | `init.client.luau` cria e conecta as instancias |
| Defaults | Nao havera controllers default com dependencias ocultas |
| Compatibilidade | Nenhuma API singleton sera mantida |
| Specs e plano | Nao realizar commit do spec nem do plano de implementacao |
| UI | Atualizar `App` e `useDialogue`, mas nao criar specs de UI |

## API e ciclo de vida

### TankController

`TankController.new()` retorna uma instancia com os metodos:

- `:start()` inicia os bindings de entrada e a conexao `PreRender`.
- `:stop()` desconecta recursos, restaura o humanoid e invalida locks antigos.
- `:acquireMovementLock()` cria um lock com liberacao idempotente.
- `:handleInput(actionName, inputState)` permanece publico para as specs e para
  o encaminhamento dos callbacks de input.

`new()` nao inicia conexoes nem altera o personagem. `start` e `stop` continuam
idempotentes. Entradas, contagem e geracao de locks, conexoes, humanoid ativo,
velocidade original, rotacao original e direcao controlada nao podem ser
compartilhados entre instancias.

Os callbacks registrados no `ContextActionService` capturam a instancia e
encaminham a chamada para `self:handleInput(...)`. Isso evita passar um metodo
de instancia sem o receptor correto.

### DialogueController

O controller recebera uma dependencia nomeada:

```luau
local dialogueController = DialogueController.new({
	movement = tankController,
})
```

O estado do dialogo, `Signal`, callback ativo, lock de movimento e geracao
passarao a ser criados por instancia. Os metodos `:start()`, `:stop()`,
`:getState()`, `:show()` e `:ask()` usarao `self`.

O modulo nao importara `TankController` para obter um singleton operacional. A
dependencia de movimento sera armazenada e chamada como
`self.dependencies.movement:acquireMovementLock()`.

## Dependencias e convencoes

Controllers e services com estado runtime devem seguir estas regras:

- Criar estado runtime em `new`, nunca em variaveis mutaveis no escopo do
  modulo.
- Usar `new(dependencies)` com tabela nomeada para dependencias de runtime.
- Usar `new()` quando o controller nao possuir dependencias externas.
- Armazenar dependencias na instancia e declarar seus contratos por tipos.
- Usar metodos com `:` e `self` para toda operacao de instancia.
- Encaminhar callbacks por closure quando o callback precisar preservar a
  instancia.
- Deixar a composicao de instancias no composition root, atualmente
  `src/client/init.client.luau`.
- Nao importar outro controller/service concreto somente para obter seu
  singleton.
- Permitir imports diretos de modulos puros internos, como `TankControlMath`.
- Tornar `start` e `stop` idempotentes e liberar conexoes, tarefas e recursos.
- Criar fixtures isoladas nas specs e limpar recursos em `afterEach`.

Essas regras serao documentadas em `docs/controller-service-pattern.md` e
referenciadas no `AGENTS.md` para orientar alteracoes futuras pelo OpenCode.

O `CameraController` atual continuara fora de uma migracao comportamental, mas
sua construcao sera alinhada ao mesmo formato:

```luau
CameraController.new({
	cameraMapReader = CameraMapReader,
})
```

Somente a assinatura e os call sites serao ajustados. `CameraResolver`, estado
de camera e ciclo de vida permanecem inalterados.

## Composicao do bootstrap

`init.client.luau` sera o composition root e seguira esta responsabilidade:

1. Criar `CameraController` com `cameraMapReader` nomeado.
2. Criar `TankController` e iniciar camera e movimento.
3. Criar `DialogueController` com `movement = tankController` e inicia-lo.
4. Criar `CinematicController` com a mesma instancia de movimento.
5. Criar `DoorController` com callback explicito para `dialogueController:show`.
6. Criar `DialogueInteractionController` com callback explicito para
   `dialogueController:show`.
7. Registrar os handlers criados no `InteractionController`.
8. Renderizar `App` recebendo `dialogueController` por props.

`useDialogue(controller)` tambem recebera a instancia. A composicao de
callbacks usara closures, por exemplo:

```luau
show = function(text, callback)
	dialogueController:show(text, callback)
end
```

`DoorController` e `DialogueInteractionController` deixarao de criar e
exportar controllers default baseados em imports ocultos. Seus consumidores
devem usar `new(dependencies)`.

## Arquivos envolvidos

### Alterados em producao

- `src/client/player/TankController.luau`: mover estado e helpers para a
  instancia e adicionar `new()`.
- `src/client/dialogue/DialogueController.luau`: remover estado global, adicionar
  `new(dependencies)` e receber movimento explicitamente.
- `src/client/camera/CameraController.luau`: aceitar dependencies nomeadas para
  `cameraMapReader`.
- `src/client/cinematics/CinematicController.luau`: usar a instancia de
  movimento com chamadas `:` e remover referencias operacionais sem `self`.
- `src/client/doors/DoorController.luau`: remover dependencia default de
  `DialogueController`.
- `src/client/dialogue/DialogueInteractionController.luau`: remover dependencia
  default de `DialogueController`.
- `src/client/dialogue/useDialogue.luau`: aceitar o controller como argumento.
- `src/client/ui/App.luau`: receber o controller por props e passa-lo ao hook.
- `src/client/init.client.luau`: construir, conectar e registrar as instancias.
- `AGENTS.md`: referenciar o guia de controllers/services.

### Alterados em testes

- `tests/client/player/TankController.spec.luau`: criar instancia por fixture e
  usar chamadas com `:`.
- `tests/client/dialogue/DialogueController.spec.luau`: criar TankController e
  DialogueController por fixture, com limpeza em `afterEach`.
- `tests/client/camera/CameraController.spec.luau`: usar dependencies nomeadas.
- Specs de cinematic que usam fakes de movimento: alinhar os fakes ao contrato
  de metodos com `self`.
- Specs de handlers que dependam de defaults: construir dependencies explicitas.

### Novo documento de instrucoes

- `docs/controller-service-pattern.md`: padrao prescritivo para construcao,
  dependencias, metodos, callbacks, lifecycle, composition root e specs.

Nao serao alterados `src/shared/player/TankControlMath.luau`, codigo server,
remotes, tuning de movimento ou specs de UI.

## Testes e criterios de sucesso

### TankController

- `new()` cria uma instancia funcional.
- `start` repetido nao duplica bindings nem conexoes.
- `stop` remove bindings e restaura a velocidade original.
- Dois controllers nao compartilham locks, entradas ou conexoes.
- Dois locks mantem o movimento bloqueado ate o ultimo release.
- Liberar o mesmo lock duas vezes nao altera a contagem novamente.
- Um lock antigo nao afeta uma nova geracao depois de `stop`.

### DialogueController e consumidores

- Cada fixture cria um controller de dialogo ligado ao TankController correto.
- Fechar dialogo libera somente o lock criado por ele.
- O estado e o `Signal` de uma instancia nao vazam para outra.
- Door e dialogue interaction chamam a instancia fornecida no bootstrap.
- `useDialogue` observa o `Signal` da instancia recebida.

### CameraController

- O construtor aceita a tabela nomeada `cameraMapReader`.
- O comportamento de shots, override e restauracao nao muda.

### Validacao do repositorio

Executar os comandos oficiais de lint, sourcemap, typecheck e build definidos
no `AGENTS.md`. O typecheck deve incluir os diretorios de producao e testes
alterados por esta migracao, incluindo `src/client/camera`,
`src/client/dialogue`, `src/client/cinematics`, `src/client/doors`,
`src/client/player` e `src/client/ui`.

Depois das alteracoes, executar Play limpo no Roblox Studio e confirmar
`failed == 0` nos resultados TestEZ client e server. Tambem procurar chamadas
operacionais restantes como `TankController.start()` ou
`TankController.acquireMovementLock()`.

## Fora de escopo

- Injetar servicos Roblox como `Players`, `RunService` ou
  `ContextActionService`.
- Alterar a logica de movimento, tuning, locks ou `TankControlMath` alem da
  adaptacao necessaria para estado por instancia.
- Refatorar o `CameraController` alem da assinatura nomeada do construtor.
- Criar um lifecycle manager ou alterar o bootstrap para esse modelo.
- Adicionar compatibilidade para a API singleton antiga.
- Criar specs de UI.
- Alterar codigo server, remotes ou contratos de gameplay.
- Fazer commit deste spec ou do plano de implementacao.

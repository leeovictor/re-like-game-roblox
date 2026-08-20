# Character Lights Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Criar uma lanterna replicada para todos os jogadores e uma luz frontal curta que simule a reflexao no corpo de cada personagem.

**Architecture:** Um novo `CharacterLightService` server-side acompanha `PlayerAdded` e `CharacterAdded`, criando as luzes diretamente no `HumanoidRootPart`. O `TankController` client-side nao sera alterado, pois continua responsavel apenas pelo movimento e pela orientacao.

**Tech Stack:** Luau `--!strict`, Roblox `Players`, `Instance`, `SpotLight`, `PointLight`, `Attachment` e Rojo.

## Global Constraints

- As luzes devem ser criadas no servidor para serem visiveis para todos os jogadores.
- O `SpotLight` deve ser filho direto do `HumanoidRootPart`.
- O `PointLight` deve ser filho de um `Attachment` dentro do `HumanoidRootPart`.
- As luzes devem permanecer habilitadas enquanto o personagem existir.
- As propriedades das luzes e a posicao do attachment devem ser constantes locais no proprio service.
- O setup deve ser idempotente e recriar as luzes no respawn sem duplicatas.
- Nao criar nem alterar testes unitarios para esta funcionalidade.
- Manter `--!strict` e os imports baseados em `script` existentes.
- Nao fazer commit durante a execucao deste plano.

---

### Task 1: Criar o servico de iluminacao por personagem

**Files:**
- Create: `src/server/player/CharacterLightService.luau`
- Test: nenhum arquivo de teste novo, conforme requisito do usuario

**Interfaces:**
- Consumes: `Players.PlayerAdded`, `Players:GetPlayers()`, `Player.CharacterAdded` e `HumanoidRootPart` como `BasePart`.
- Produces: `CharacterLightService.new(): Service`, com `service:start()` e `service:stop()`.

- [ ] **Step 1: Declarar o contrato do service e as constantes de configuracao**

Manter o arquivo em `--!strict`, importar apenas `Players` e declarar o tipo publico:

```luau
export type Service = {
    start: (self: Service) -> (),
    stop: (self: Service) -> (),
}
```

No topo do modulo, antes da implementacao, declarar nomes reservados e todos os
valores ajustaveis:

```luau
local SPOTLIGHT_NAME = "TankFlashlight"
local BODY_LIGHT_ATTACHMENT_NAME = "TankLightAttachment"
local BODY_LIGHT_NAME = "TankBodyLight"

local CHARACTER_ROOT_WAIT_SECONDS = 5

local SPOTLIGHT_ENABLED = true
local SPOTLIGHT_COLOR = Color3.fromRGB(255, 244, 214)
local SPOTLIGHT_BRIGHTNESS = 3
local SPOTLIGHT_RANGE = 32
local SPOTLIGHT_ANGLE = 70
local SPOTLIGHT_SHADOWS = true
local SPOTLIGHT_FACE = Enum.NormalId.Front

local BODY_LIGHT_ENABLED = true
local BODY_LIGHT_COLOR = Color3.fromRGB(255, 244, 214)
local BODY_LIGHT_BRIGHTNESS = 0.8
local BODY_LIGHT_RANGE = 5
local BODY_LIGHT_SHADOWS = false
local BODY_LIGHT_ATTACHMENT_POSITION = Vector3.new(0, 0.5, -1.5)
```

Os valores sao pontos de partida configuraveis; a posicao frontal usa `Z`
negativo no espaco local do root.

- [ ] **Step 2: Implementar a localizacao segura do root**

Criar uma funcao local `getRoot(character: Model): BasePart?` que procure o
filho `HumanoidRootPart`, valide `IsA("BasePart")` e retorne `nil` para
personagens incompletos.

Criar uma funcao local `setupCharacter(character: Model): ()` que:

1. Retorne se o service nao estiver iniciado.
2. Use `FindFirstChild("HumanoidRootPart")` e, se necessario,
   `WaitForChild("HumanoidRootPart", CHARACTER_ROOT_WAIT_SECONDS)`.
3. Valide que o resultado e `BasePart`, que o root ainda e filho do personagem
   e que o service continua iniciado.
4. Configure as tres instancias somente depois dessas validacoes.

O callback deve poder aguardar o root sem bloquear o bind geral de jogadores;
inicie `setupCharacter` com `task.spawn` quando chamado por `CharacterAdded` ou
para o personagem atual.

- [ ] **Step 3: Criar ou reutilizar as instancias sem duplicatas**

Implementar a configuracao idempotente no `HumanoidRootPart`:

1. Procurar o filho `TankFlashlight`; destruir apenas esse filho se a classe
   nao for `SpotLight`; criar `Instance.new("SpotLight")` se estiver ausente.
2. Aplicar sempre `Name`, `Enabled`, `Color`, `Brightness`, `Range`, `Angle`,
   `Shadows` e `Face` usando as constantes `SPOTLIGHT_*`, depois parentear no
   root.
3. Procurar `TankLightAttachment`; destruir apenas esse filho se a classe nao
   for `Attachment`; criar `Instance.new("Attachment")` se estiver ausente.
4. Aplicar `Name` e `Position = BODY_LIGHT_ATTACHMENT_POSITION`, depois
   parentear no root.
5. Procurar `TankBodyLight` dentro do attachment; destruir apenas esse filho
   se a classe nao for `PointLight`; criar `Instance.new("PointLight")` se
   estiver ausente.
6. Aplicar `Name`, `Enabled`, `Color`, `Brightness`, `Range` e `Shadows` usando
   as constantes `BODY_LIGHT_*`, depois parentear no attachment.

Ao reutilizar uma instancia, reaplicar todas as propriedades para que uma
configuracao antiga nao sobreviva a um reinicio do service.

- [ ] **Step 4: Implementar `new`, `start` e `stop` com ciclo de vida completo**

Dentro de `CharacterLightService.new`, manter `started`, uma conexao de
`PlayerAdded`, uma conexao de `PlayerRemoving` e um mapa
`{ [Player]: RBXScriptConnection }` para `CharacterAdded`.

Implementar `bindPlayer(player: Player)` assim:

```luau
characterConnections[player] = player.CharacterAdded:Connect(function(character)
    task.spawn(setupCharacter, character)
end)

if player.Character ~= nil then
    task.spawn(setupCharacter, player.Character)
end
```

Em `start`:

1. Retornar se `started` ja for `true`.
2. Definir `started = true`.
3. Conectar `Players.PlayerAdded` a `bindPlayer`.
4. Conectar `Players.PlayerRemoving` para desconectar e remover a conexao do
   jogador que saiu.
5. Percorrer `Players:GetPlayers()` e chamar `bindPlayer` para jogadores ja
   presentes.

Em `stop`:

1. Retornar se o service nao estiver iniciado.
2. Desconectar e limpar `PlayerAdded` e `PlayerRemoving`.
3. Desconectar cada conexao de `CharacterAdded` e limpar o mapa.
4. Definir `started = false`.

Retornar a tabela do service e nao criar objetos fora do personagem. Os
objetos devem acompanhar o ciclo de vida do `HumanoidRootPart`.

- [ ] **Step 5: Rodar lint do novo modulo**

Run:

```bash
selene --config selene.roblox.toml src/server/player/CharacterLightService.luau
```

Expected: o comando termina sem diagnosticos. Se o lint aceitar apenas um
diretorio, executar `selene --config selene.roblox.toml src` e confirmar que
nenhum diagnostico novo aparece no modulo.

### Task 2: Integrar o service no entrypoint server

**Files:**
- Modify: `src/server/init.server.luau:3-20`
- Modify: `test.project.json:25-39`
- Test: nenhum arquivo de teste novo ou alterado

**Interfaces:**
- Consumes: `script.player.CharacterLightService` e o contrato
  `CharacterLightService.new()` produzido pela Task 1.
- Produces: inicializacao server-side das luzes durante o boot do jogo.

- [ ] **Step 1: Importar e instanciar o service**

Adicionar ao bloco de imports de `src/server/init.server.luau`:

```luau
local CharacterLightService = require(script.player.CharacterLightService)
```

Criar a instancia junto dos outros services:

```luau
local characterLightService = CharacterLightService.new()
```

- [ ] **Step 2: Iniciar o service no boot do servidor**

Chamar `characterLightService:start()` durante a inicializacao normal, depois
da criacao dos services e antes do fim do arquivo. Nao adicionar remote, evento
compartilhado ou mudanca em `TankController`.

- [ ] **Step 3: Mapear o modulo no projeto de testes**

Adicionar o subdiretorio server ao bloco `ServerScriptService.Server` de
`test.project.json`, sem mapear `src/server/init.server.luau`:

```json
"player": {
  "$path": "src/server/player"
}
```

Colocar essa entrada junto de `inventory`, `items`, `pickups` e `doors`. Isso
torna o modulo disponivel no sourcemap e no build de testes, mas nao inicia o
entrypoint de producao nem altera o runner TestEZ.

- [ ] **Step 4: Verificar o build server-side**

Run:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
```

Expected: build concluido sem erro, com `Server.player.CharacterLightService`
presente no DataModel gerado.

### Task 3: Executar verificacao estatica

**Files:**
- Modify: nenhum arquivo adicional
- Test: nao executar nem criar testes unitarios novos

**Interfaces:**
- Consumes: o service integrado e o projeto de testes existente.
- Produces: evidencia de lint, typecheck e builds.

- [ ] **Step 1: Rodar lint dos fontes**

Run:

```bash
selene --config selene.roblox.toml src
```

Expected: nenhum diagnostico no codigo de producao.

- [ ] **Step 2: Gerar sourcemap e rodar typecheck Roblox**

Run exatamente na ordem:

```bash
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --definitions @testez=typecheck/testez.d.luau \
  --sourcemap test-sourcemap.json --formatter gnu \
  src/shared \
  src/server/inventory src/server/items src/server/pickups src/server/player \
  src/client/camera src/client/inventory src/client/pickups src/client/player src/client/ui \
  tests
```

Expected: typecheck sem erros. Nao incluir `src/server/init.server.luau` na
analise, conforme o mapeamento do projeto de testes.

- [ ] **Step 3: Construir os projetos default e de testes**

Run:

```bash
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

Expected: ambos os builds terminam sem erro.

## Self-review do plano

- A visibilidade para todos e coberta pela criacao server-side na Task 1 e pela
  integracao na Task 2.
- O parent de cada instancia, a orientacao frontal e a posicao configuravel
  estao cobertos pelos passos 1 e 3 da Task 1.
- Respawn, jogadores existentes, novos jogadores, idempotencia e cleanup de
  conexoes estao cobertos pelo ciclo de vida da Task 1.
- A configuracao local inclui todas as propriedades visuais pedidas e a
  posicao do attachment.
- A restricao de nao criar testes unitarios e nao fazer commit aparece nas
  restricoes globais e nas tarefas.
- Nao ha placeholders, marcadores incompletos ou etapas que dependam de nomes
  nao definidos.

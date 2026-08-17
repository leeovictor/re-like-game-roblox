# Client Sphere Grid Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Criar no cliente uma matriz 10 x 20 com 200 esferas centralizadas na origem, apoiadas em `Y = 1`, que mudam de cor independentemente a cada segundo.

**Architecture:** Um módulo `SphereGridController` no cliente será responsável por criar a pasta `Workspace.ClientSphereGrid`, gerar as 200 `Part`s e manter referências locais para atualizar suas cores. `src/client/init.client.luau` iniciará o controlador junto dos sistemas de câmera, inventário e UI existentes; nenhuma comunicação com o servidor será adicionada.

**Tech Stack:** Luau strict, Roblox `Instance`, `Workspace`, `Random.new`, `task.wait`, Rojo e React/ReactRoblox já existentes no projeto.

## Global Constraints

- A lógica será executada no cliente, sem replicação pelo servidor.
- A matriz terá exatamente 10 linhas por 20 colunas, totalizando 200 esferas.
- O diâmetro será 2 studs e a distância entre centros será 4 studs.
- A matriz será centralizada na origem, com `Y = 1`.
- As esferas serão `Anchored = true` e `CanCollide = false`.
- Apenas `Workspace.ClientSphereGrid` poderá ser limpo ou alterado pelo controlador.
- Os módulos Luau devem manter `--!strict` e não usar `--!nocheck`.
- Imports Roblox devem seguir a árvore Rojo e o padrão baseado em `script` do projeto.
- `Packages/` é gerado e não deve ser editado.

---

### Task 1: Criar o controlador local da matriz

**Files:**
- Create: `src/client/SphereGridController.luau`
- Test: verificação manual no Roblox Studio; o módulo depende de `Workspace` e `Instance` e não é adequado ao loader Lune sem criar um mock Roblox completo.

**Interfaces:**
- Produces: `SphereGridController.start(): ()`, que cria a matriz e inicia a atualização contínua de cores.

- [ ] **Step 1: Criar o módulo strict com constantes explícitas**

Adicionar `--!strict`, obter `Workspace` com `game:GetService("Workspace")` e declarar as constantes `ROW_COUNT = 10`, `COLUMN_COUNT = 20`, `SPACING = 4`, `SPHERE_DIAMETER = 2` e `HEIGHT = 1`.

Declarar uma tabela local de referências como `{ BasePart }` e retornar uma tabela com o método público `start`.

- [ ] **Step 2: Implementar a obtenção da pasta de destino**

Dentro de uma função local `getOrCreateContainer(): Folder`, procurar `Workspace:FindFirstChild("ClientSphereGrid")`. Se o resultado for uma `Folder`, reutilizá-lo. Se não existir, criar uma `Folder`, definir `Name = "ClientSphereGrid"` e usar `Parent = Workspace`.

Se existir um objeto com o mesmo nome que não seja `Folder`, removê-lo com `Destroy()` antes de criar a pasta correta. Não procurar nem remover objetos fora dessa pasta.

- [ ] **Step 3: Implementar a limpeza controlada**

Adicionar uma função local `clearContainer(container: Folder): ()` que percorre `container:GetChildren()` e chama `Destroy()` em cada filho. Essa função deve ser chamada antes da criação das esferas e deve resetar a tabela local de referências.

- [ ] **Step 4: Implementar a criação e centralização da matriz**

Adicionar uma função local `createSphere(container: Folder, row: number, column: number): BasePart` que:

```lua
local x = (column - 10.5) * SPACING
local z = (row - 5.5) * SPACING

local sphere = Instance.new("Part")
sphere.Name = string.format("Sphere_%02d_%02d", row, column)
sphere.Shape = Enum.PartType.Ball
sphere.Size = Vector3.new(SPHERE_DIAMETER, SPHERE_DIAMETER, SPHERE_DIAMETER)
sphere.Position = Vector3.new(x, HEIGHT, z)
sphere.Anchored = true
sphere.CanCollide = false
sphere.CanTouch = false
sphere.CanQuery = false
sphere.Parent = container
```

O método de criação deve atribuir uma cor inicial e retornar a esfera. Uma função local `createGrid(container: Folder): { BasePart }` deve executar `row = 1..ROW_COUNT` e `column = 1..COLUMN_COUNT`, inserir cada retorno na tabela e produzir exatamente 200 referências.

- [ ] **Step 5: Implementar cores aleatórias independentes**

Criar um `Random.new()` local e uma função `randomColor(): Color3` que retorne:

```lua
return Color3.new(random:NextNumber(), random:NextNumber(), random:NextNumber())
```

Adicionar uma função `updateColors(spheres: { BasePart }): ()` que percorre todas as referências e atribui `sphere.Color = randomColor()`. A função deve gerar uma cor nova dentro do loop de cada esfera, sem compartilhar uma única cor para o ciclo inteiro.

- [ ] **Step 6: Iniciar a atualização periódica sem loop ocupado**

No método `SphereGridController.start`, obter a pasta, limpar seu conteúdo, criar a grade, atribuir a cor inicial e iniciar uma tarefa:

```lua
task.spawn(function()
    while container.Parent ~= nil do
        task.wait(1)
        updateColors(spheres)
    end
end)
```

O loop deve esperar antes da primeira atualização periódica, manter `container.Parent ~= nil` como condição de vida e não criar uma segunda tarefa se `start` for chamado novamente durante a mesma inicialização. Como o controlador é iniciado uma vez por `init.client.luau`, não adicionar APIs de parada ou estado global além do necessário para essa proteção.

- [ ] **Step 7: Rodar lint do módulo**

Run: `selene --config selene.roblox.toml src/client/SphereGridController.luau`

Expected: nenhum diagnóstico de lint.

### Task 2: Integrar o controlador à inicialização do cliente

**Files:**
- Modify: `src/client/init.client.luau`

**Interfaces:**
- Consumes: `script.SphereGridController`, com `start(): ()` produzido pela Task 1.
- Produces: inicialização automática da matriz quando o script cliente iniciar.

- [ ] **Step 1: Adicionar o require sem alterar os sistemas existentes**

Adicionar próximo aos outros requires locais:

```lua
local SphereGridController = require(script.SphereGridController)
```

Não mover nem remover a inicialização existente de câmera, debugger, inventário ou UI.

- [ ] **Step 2: Iniciar a matriz uma vez**

Adicionar `SphereGridController.start()` antes da criação do `PlayerGui` ou imediatamente após `InventoryController.start()`. A chamada deve ocorrer uma única vez no fluxo de inicialização.

- [ ] **Step 3: Rodar lint e typecheck Roblox**

Run: `selene --config selene.roblox.toml src`

Expected: nenhum diagnóstico de lint.

Run:

```bash
rojo sourcemap --include-non-scripts default.project.json --output sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --sourcemap sourcemap.json --formatter gnu src
```

Expected: análise concluída sem erros de tipo nos arquivos alterados.

### Task 3: Verificar a árvore e o comportamento no Studio

**Files:**
- Modify: nenhum arquivo adicional.
- Verify: `default.project.json`, `src/client/SphereGridController.luau` e `src/client/init.client.luau`.

**Interfaces:**
- Consumes: a integração concluída nas Tasks 1 e 2.
- Produces: evidência de que a matriz é empacotada e executada corretamente no ambiente Roblox.

- [ ] **Step 1: Gerar o build Rojo**

Run: `rojo build -o /tmp/dungeon-game-canve.rbxlx`

Expected: build concluído sem erro e o arquivo `.rbxlx` criado.

- [ ] **Step 2: Conferir a matriz no Roblox Studio**

Executar o jogo no Roblox Studio e confirmar:

- `Workspace.ClientSphereGrid` existe no cliente.
- A pasta contém exatamente 200 `Part`s.
- Existem 10 linhas e 20 colunas.
- As posições X vão de `-38` a `38` e Z de `-18` a `18`.
- Todas as esferas têm `Y = 1`, tamanho `2 x 2 x 2`, estão ancoradas e não colidem.
- A primeira cor aparece imediatamente.
- Após cada intervalo de um segundo, cada esfera pode mudar para uma cor diferente das demais.
- Ao reiniciar o cliente, não há uma segunda matriz acumulada dentro da pasta.

- [ ] **Step 3: Executar a suíte existente para detectar regressões**

Run: `lune run test`

Expected: todos os testes existentes passam. A suíte não testa diretamente o módulo visual porque ele depende do DataModel Roblox real, mas deve permanecer sem regressões.

- [ ] **Step 4: Commitar somente os arquivos da funcionalidade**

Antes do commit, revisar `git status`, `git diff` e `git diff --check`. Não incluir alterações preexistentes ou arquivos gerados.

```bash
git add src/client/SphereGridController.luau src/client/init.client.luau
git commit -m "feat: adiciona matriz de esferas no cliente"
```

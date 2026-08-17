# Matriz de Esferas no Cliente

## Objetivo

Criar 200 esferas visualmente no cliente Roblox, organizadas em uma matriz de 10 linhas por 20 colunas, centralizada na origem do mapa. Cada esfera deve mudar para uma cor aleatória independente a cada segundo.

## Decisões

- A lógica será executada no cliente, sem replicação pelo servidor.
- Cada jogador terá sua própria matriz e sua própria sequência de cores.
- A matriz ficará centralizada em `Vector3.new(0, 1, 0)`.
- O diâmetro de cada esfera será de 2 studs.
- A distância entre os centros será de 4 studs.
- As esferas serão ancoradas e não terão colisão.
- As esferas ficarão em uma pasta `Workspace.ClientSphereGrid`.

## Arquitetura

Será criado `src/client/SphereGridController.luau`. O módulo será responsável por:

1. Obter ou criar a pasta `ClientSphereGrid` no `Workspace`.
2. Limpar os filhos dessa pasta antes de gerar uma nova matriz.
3. Criar as 200 `Part`s com `Shape = Ball`, tamanho `Vector3.new(2, 2, 2)` e propriedades visuais/físicas apropriadas.
4. Manter as referências das esferas em uma tabela.
5. Atualizar as cores usando um `Random.new()` local e uma rotina que aguarda um segundo entre as atualizações.

`src/client/init.client.luau` importará e iniciará o controlador junto dos demais sistemas do cliente.

## Posicionamento

Para uma coluna `column` de 1 a 20 e uma linha `row` de 1 a 10, a posição será calculada por:

```lua
local x = (column - 10.5) * 4
local z = (row - 5.5) * 4
local position = Vector3.new(x, 1, z)
```

Assim, os centros ocuparão X de -38 a 38 e Z de -18 a 18, com espaçamento uniforme e centro geométrico na origem.

## Fluxo de cores

Uma cor inicial será atribuída durante a criação de cada esfera. Depois, uma rotina contínua aguardará `task.wait(1)` e atribuirá uma nova cor aleatória a cada referência da tabela. A cor será gerada por esfera, dentro do loop de atualização, garantindo independência entre elas.

## Robustez

- A pasta de destino será criada caso não exista.
- Apenas o conteúdo da pasta `ClientSphereGrid` será removido; nenhuma outra parte do mapa será alterada.
- O loop não usará espera zero nem ficará ocupado entre atualizações.
- O módulo manterá `--!strict` e os imports seguirão o padrão baseado em `script` do projeto.
- Se o controlador ganhar uma rotina de encerramento, ela deverá interromper a atualização e limpar as referências locais.

## Verificação

- Lint Roblox: `selene --config selene.roblox.toml src`.
- Typecheck Roblox com `rojo sourcemap` e `luau-lsp`, conforme `AGENTS.md`.
- Build Rojo: `rojo build -o /tmp/dungeon-game-canve.rbxlx`.
- Verificação no Roblox Studio: confirmar 200 esferas, layout 10 x 20, posição centralizada, altura Y = 1, ausência de colisão e mudança independente de cor a cada segundo.

# Camera System Plugin

## Objetivo

Facilitar a autoria de shots e zonas de camera fixa no Roblox Studio. O designer
deve conseguir criar e editar volumes 3D usando as ferramentas nativas do
Studio, capturar shots a partir da camera atual e testar o mapa sem calcular
manualmente `CFrame` ou `Vector3`.

As instancias persistidas no mapa serao a unica fonte de verdade. O plugin
gerencia essas instancias durante a autoria e o runtime le a configuracao uma
unica vez no inicio do cliente.

## Decisoes

- A ferramenta sera um plugin leve dentro do Roblox Studio.
- O plugin nao implementara gizmos proprios de mover, escalar ou girar.
- Shots e zonas serao `Part`s persistidos no `Workspace`.
- O runtime nao observara alteracoes durante o playtest.
- O resolver continuara usando a primeira zona correspondente.
- A ordem das zonas sera mantida pelo plugin e persistida no atributo `Order`.
- A configuracao invalida fara o runtime falhar explicitamente, sem usar
  configuracao parcial.
- Nao havera arquivo Luau gerado para representar shots ou zonas.

## Estrutura Persistida

```text
Workspace
└── CameraSystem [Folder]
    ├── Shots [Folder]
    │   ├── Entrance [Part]
    │   └── Center [Part]
    └── Zones [Folder]
        ├── EntranceZone [Part]
        └── CenterZone [Part]
```

### CameraSystem

`Workspace.CameraSystem` e um `Folder` com o atributo:

- `DefaultShotId`: `string`, nome do shot usado fora de todas as zonas.

Ele tambem contem os folders `Shots` e `Zones`. O plugin cria a estrutura se
ela ainda nao existir.

### Shots

Cada filho direto de `CameraSystem.Shots` e um `Part` com:

- Nome unico, usado como `ShotId`.
- `CFrame` com a posicao e a orientacao da camera.
- Atributo `FieldOfView`, do tipo `number`.
- `Anchored = true`.
- `CanCollide = false`.
- `CanTouch = false`.
- `CanQuery = false`.
- Aparencia padronizada pelo plugin para facilitar a selecao.

O plugin desenha um marker orientado pelo `LookVector` para indicar a direcao
do shot. Markers auxiliares de preview ficam fora de `Shots` e nao fazem parte
da configuracao do runtime.

### Zones

Cada filho direto de `CameraSystem.Zones` e um `Part` com:

- Nome unico, usado como `ZoneId`.
- `CFrame` com centro, posicao e rotacao do volume.
- `Size` com as dimensoes do volume 3D.
- Atributo `ShotId`, do tipo `string`.
- Atributo `Order`, do tipo `number`.
- `Anchored = true`.
- `CanCollide = false`.
- `CanTouch = false`.
- `CanQuery = false`.
- Transparencia e cor padronizadas pelo plugin.

`Order` representa a ordem da lista de zonas, nao um novo conceito de
prioridade. O plugin atualiza os valores quando uma zona e movida para cima ou
para baixo. O runtime ordena por esse atributo antes de montar a configuracao,
evitando depender da ordem nao garantida de `GetChildren()`.

## Fluxo Do Plugin

O plugin cria uma toolbar e um `DockWidget` chamado `Camera System`. O painel
tem listas de shots e zonas, selecao sincronizada com o Studio e comandos para
as operacoes principais.

### Shots

- `New Shot` solicita um nome, captura `workspace.CurrentCamera.CFrame` e
  `FieldOfView`, cria o `Part` e o seleciona.
- `Capture Camera` copia a camera atual para o shot selecionado.
- `Apply To Camera` copia o shot selecionado para a camera do Studio.
- O shot pode ser movido e girado diretamente com as ferramentas nativas.
- O FOV pode ser alterado no painel ou pelo atributo no Explorer.
- A lista permite selecionar um shot sem procura manual no Explorer.

### Zones

- `New Zone` solicita um nome e cria uma caixa 3D com tamanho inicial
  editavel.
- A zona pode ser movida, escalada e girada com as ferramentas nativas.
- O painel mostra o `ShotId` atual.
- `Assign Shot` associa a zona selecionada ao shot escolhido.
- A lista exibe as zonas na ordem de resolucao.
- Controles de mover para cima e para baixo atualizam `Order`.

### Operacoes Do Studio

- Alteracoes feitas pelo plugin usam `ChangeHistoryService` para suportar
  Undo/Redo.
- A selecao feita no painel atualiza `Selection` do Studio.
- A selecao feita no viewport atualiza o item ativo no painel quando o plugin
  estiver aberto.
- O painel mostra erros de autoria, mas a validacao do runtime continua sendo
  a barreira final antes de iniciar a camera.

## Runtime

Um modulo separado, `CameraMapReader`, le `Workspace.CameraSystem` uma vez e
converte as instancias para o formato puro usado pelo `CameraResolver`:

```lua
{
    defaultShotId = "Center",
    shots = {
        Center = {
            cframe = ...,
            fieldOfView = 55,
        },
    },
    zones = {
        {
            id = "CenterZone",
            volume = {
                cframe = ...,
                size = ...,
            },
            shotId = "Center",
        },
    },
}
```

O fluxo de inicializacao passa a ser:

```text
init.client.luau
    -> CameraMapReader.read(Workspace.CameraSystem)
        -> CameraConfig.Config
            -> CameraController
            -> CameraDebugger
```

O `CameraResolver` continua independente de `Workspace`, preservando o
comportamento de volumes rotacionados e os testes unitarios existentes.

A configuracao estatica atual nao sera usada pelo runtime. O modulo de camera
continuara fornecendo os tipos `Shot`, `Zone`, `Volume` e `Config`, enquanto os
fixtures dos testes serao definidos nos proprios testes.

## Validacao E Falhas

O leitor deve falhar explicitamente se:

- `CameraSystem`, `Shots` ou `Zones` nao existir.
- `DefaultShotId` estiver ausente ou apontar para um shot inexistente.
- Um filho direto de `Shots` ou `Zones` nao for um `BasePart`.
- Um shot nao tiver `FieldOfView` numerico entre 1 e 120.
- Uma zona nao tiver `ShotId` string.
- Uma zona referenciar um shot inexistente.
- Uma zona tiver algum eixo de `Size` menor ou igual a zero.
- Uma zona tiver `Order` ausente ou invalido.

As mensagens devem incluir o caminho ou nome da instancia relevante, por
exemplo:

```text
CameraSystem: zona "NorthGalleryZone" referencia ShotId inexistente "NorthGallery"
```

O cliente nao deve iniciar o controller com uma configuracao parcial.

## Testes E Verificacao

- Manter os testes comportamentais do `CameraResolver`.
- Adicionar testes para a conversao e validacao dos dados persistidos.
- Cobrir shot padrao ausente ou inexistente.
- Cobrir zona com `ShotId` inexistente.
- Cobrir FOV invalido e tamanho de zona nao positivo.
- Cobrir ordenacao por `Order`.
- Cobrir zonas rotacionadas.
- Executar `lune run test`.
- Executar os dois comandos de lint separados para Roblox e Lune.
- Executar os dois typechecks separados conforme `AGENTS.md`.
- Executar `rojo build -o /tmp/dungeon-game-canve.rbxlx`.

## Fora Do Escopo Inicial

- Hot reload da configuracao durante o playtest.
- Deteccao ou proibicao de sobreposicao entre zonas.
- Prioridade numerica independente da ordem da lista.
- Gizmos de transformacao proprios.
- Geracao automatica de arquivo Luau.
- Migracao automatica dos valores existentes em `CameraConfig.luau`.

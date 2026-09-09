# Design: Sistema de Documentos Narrativos

Data: 2026-09-09  
Status: Aprovado pelo usuario para planejamento

## Objetivo

Adicionar uma mecanica narrativa client-side na qual o jogador coleta documentos
espalhados pelo mapa, le o conteudo em um leitor paginado e pode reler os
documentos coletados por uma aba propria dentro do inventario.

Documentos sao um dominio separado de itens do inventario. O estado e volatil,
existe somente durante a sessao atual e nao usa remotes, DataStore ou qualquer
persistencia server-side.

## Decisoes aprovadas

| Tema | Decisao |
| --- | --- |
| Dominio | Controller e estado separados do inventario de itens |
| Autoridade | Somente client-side |
| Persistencia | Nenhuma; segue o estado volatil atual do inventario |
| Modelo do mapa | Tag `Interactable`, atributo `InteractionType = Document` e atributo `DocumentId` |
| Coleta | Tecla `E` pelo `InteractionController` |
| Coleta fisica | Modelo valido desaparece imediatamente do mapa |
| Momento do registro | O ID e registrado antes/ao abrir a leitura |
| Catalogo | Tabela client-side indexada pelo ID |
| Conteudo | Uma ou mais paginas com texto RichText |
| Leitura inicial | Sempre inicia na pagina 1 |
| Navegacao | `A` volta, `D` avanca; sem circulacao |
| Finalizacao | `D` na ultima pagina fecha o leitor |
| Cancelamento | Botao direito do mouse fecha o leitor em qualquer pagina |
| Input durante leitura | Somente `A`, `D` e botao direito do mouse ficam disponiveis |
| Movimento | Bloqueado enquanto o leitor estiver aberto |
| Inventario | Aba `DOCUMENTOS` dentro do painel existente |
| Ordem da lista | Ordem em que os documentos foram coletados |
| Indicador | Somente indicador de pagina, sem dicas de teclado |
| Tipografia | `Enum.Font.RobotoMono`, igual ao dialogo |
| Background | Overlay escurecido e mundo desfocado |
| Testes unitarios | Fora do escopo; nenhum arquivo em `tests/` sera alterado |

## Abordagens consideradas

### Controller de documentos separado (escolhida)

O sistema tera um catalogo de dados, um controller da colecao, um controller do
leitor e uma interacao que adapta o mapa ao dominio. A aba do inventario apenas
consulta a colecao e abre o leitor.

Essa abordagem preserva a separacao entre itens jogaveis e conteudo narrativo,
evita alterar o schema de `InventoryState` e permite evoluir o leitor sem
acoplar seu ciclo de vida ao inventario de itens.

### Documentos dentro de `InventoryState`

Uma alternativa seria adicionar `documents: { string }` ao snapshot do
inventario. Isso reduziria a quantidade de hooks visiveis na UI, mas misturaria
itens e registros narrativos, exigiria alterar o store compartilhado e mudaria
validacao, copia e contratos de inventario sem necessidade.

### Reutilizacao do `DialogueController`

Outra alternativa seria representar cada pagina como uma mensagem de dialogo.
Isso reutilizaria parte do input, mas acoplaria dois dominios com semanticas
diferentes e dificultaria o overlay blur, a abertura pela aba e o estado de
pagina. Nao sera usado.

## Arquitetura

```text
src/client/documents/DocumentData.luau
  tipos e catalogo client-side de documentos

src/client/documents/DocumentsController.luau
  IDs coletados na sessao, ordem, validacao e sinal changed

src/client/documents/DocumentReaderController.luau
  documento aberto, pagina atual, input e lifecycle do leitor

src/client/documents/DocumentInteraction.luau
  handler do InteractionController para alvos do tipo Document

src/client/documents/useDocuments.luau
  hook React para a colecao

src/client/documents/useDocumentReader.luau
  hook React para o leitor ativo

src/shared/interactions/interactionTypes.luau
  tipo e constantes do contrato Document

src/client/InputManager.luau
  contexto DocumentContext com A, D e botao direito do mouse

src/client/ui/App.luau
  abas do inventario, lista e overlay do leitor

src/client/init.client.luau
  cria, inicia, registra e conecta os controllers
```

O bootstrap inicializara os controllers antes de registrar o handler `Document`
no `InteractionController`. O `App` recebera as dependencias dos controllers,
assim como ja recebe os controllers de dialogo, inventario e cinematics.

Os modulos client-side que dependerem de outros modulos client-side usarao
caminhos absolutos a partir de
`StarterPlayer.StarterPlayerScripts.Client`. Tipos e constantes compartilhados
continuarao em `ReplicatedStorage.Shared`.

## Modelo de dados

`DocumentData.luau` exportara:

```lua
export type DocumentPage = {
    content: string,
}

export type Document = {
    id: string,
    displayName: string,
    pages: { DocumentPage },
}
```

O catalogo sera uma tabela indexada pelo ID:

```lua
local documents: { [string]: Document } = {
    ["november-report"] = {
        id = "november-report",
        displayName = "Relatorio de Novembro",
        pages = {
            { content = "<b>Relatorio...</b>" },
            { content = "Pagina seguinte..." },
        },
    },
}
```

O conteudo e authored e sera exibido com `RichText = true`. O estado da
colecao armazenara somente IDs ordenados:

```lua
type DocumentsState = {
    collectedIds: { string },
}
```

O estado do leitor sera:

```lua
type DocumentReaderState = {
    document: Document,
    pageIndex: number,
}
```

O catalogo continua sendo a fonte da verdade do conteudo; a colecao nao
duplicara paginas ou nomes.

## `DocumentsController`

O controller tera estado independente por instancia e seguira o padrao de
controllers client-side existente. Sua API conceitual sera:

```lua
new(): DocumentsController
start(self): ()
stop(self): ()
getCollected(self): { string }
has(self, id: string): boolean
getDocument(self, id: string): Document?
collect(self, id: string): Document?
```

Tambem expora um sinal `changed` para atualizar a aba do inventario.

`collect` validara o ID no catalogo, rejeitara IDs ja coletados e, quando
valido, adicionara o ID ao final da lista e publicara um novo snapshot. O
conteudo retornado sera usado pelo handler para abrir a pagina inicial.

`start` e `stop` serao idempotentes. `stop` limpara a lista da sessao e o
controller iniciara vazio em uma nova sessao.

## Contrato dos alvos do mapa

Um alvo authored valido tera a forma:

```text
DocumentModel ou DocumentPart
|-- CollectionService tag: "Interactable"
|-- atributo InteractionType = "Document"
|-- atributo DocumentId = "november-report"
```

O tipo `Document` sera adicionado ao contrato de interacao compartilhado. O
`InteractionController` resolvera a raiz marcada, como ja faz para modelos de
outros tipos, e chamara `DocumentInteraction`.

O handler devera:

1. Confirmar que a raiz e `Model` ou `BasePart`.
2. Ler e validar `DocumentId`.
3. Confirmar que o ID existe no catalogo.
4. Confirmar que o ID ainda nao foi coletado.
5. Registrar o documento no `DocumentsController`.
6. Destruir a raiz fisica do mapa.
7. Abrir o leitor na pagina 1.

O modelo so sera destruido depois da validacao e do registro bem-sucedido. Um
ID ausente, vazio ou desconhecido gera `warn` com o caminho completo do alvo e
mantem o modelo no mapa. O mesmo motivo nao sera reportado repetidamente para o
mesmo alvo.

Uma segunda ocorrencia do mesmo ID nao sera registrada novamente. O modelo
duplicado permanecera no mapa e podera gerar um warning de autoria, evitando
que uma configuracao duplicada seja silenciosamente tratada como uma nova
coleta.

## `DocumentReaderController`

O reader tera uma unica leitura ativa. Sua API conceitual sera:

```lua
new(dependencies): DocumentReaderController
start(self): ()
stop(self): ()
getState(self): DocumentReaderState?
open(self, documentId: string): boolean
nextPage(self): ()
previousPage(self): ()
close(self): ()
```

`open` resolvera o ID no catalogo, iniciara sempre com `pageIndex = 1`,
publicara o estado e trocara o `InputManager` para `DocumentContext`. Abrir
outro documento substituira a leitura atual e reiniciara na primeira pagina.

`previousPage` nao reduz o indice abaixo de 1. `nextPage` avanca enquanto
existir uma pagina seguinte; quando estiver na ultima pagina, fecha o leitor.
`close` fecha sem alterar a colecao.

Ao fechar ou parar, o controller publicara `nil` e restaurara o `PlayContext`.
A camada de UI removera o blur ao observar o estado vazio. Cleanup e callbacks
antigos nao poderao alterar uma leitura posterior.

## Input e bloqueio de gameplay

O `InputManager` recebera o contexto `DocumentContext` com:

```text
PreviousPage -> A
NextPage     -> D
Close        -> MouseRightButton
```

Ao trocar de `PlayContext` para `DocumentContext`, os bindings de movimento,
combate e interacao deixam de produzir estados ativos. O jogador para de se
mover no ciclo normal do `PlayerController`.

O binding de `Tab` existente no `App` continuara registrado, mas ignorara o
input enquanto `useDocumentReader()` retornar estado ativo. Assim o painel nao
podera ser aberto ou alternado por baixo do leitor.

Nao havera input de digitacao de dialogo para documentos: cada pagina e exibida
completa imediatamente.

## Inventario e UI

O painel atual do inventario ganhara duas abas:

```text
[ ITENS ] [ DOCUMENTOS ]
```

O estado da aba sera local ao `App`.

Na aba `DOCUMENTOS`:

- cada ID coletado sera resolvido no catalogo;
- cada linha exibira `displayName`;
- as linhas manterao a ordem de coleta;
- clicar em uma linha chamara `reader.open(documentId)`;
- o painel sera fechado ao iniciar a leitura;
- uma colecao vazia exibira uma mensagem vazia, sem slots falsos.

O `useDocuments` assinara o sinal do `DocumentsController`. O `useDocumentReader`
assinara o estado do reader. A arvore React continuara centralizada em
`App.luau`; controllers nao criarao `ScreenGui`, `Frame` ou `TextLabel`.

## Overlay do leitor

Enquanto houver `DocumentReaderState`:

- um overlay ocupara toda a tela;
- o mundo ficara escurecido e desfocado com um `BlurEffect` client-side;
- um painel central exibira a pagina atual;
- o texto usara `RichText = true`;
- a fonte sera `Enum.Font.RobotoMono`, igual a do dialogo;
- o texto sera quebrado e alinhado para leitura;
- o painel mostrara somente o indicador `PAGINA N/M`;
- nao serao mostradas dicas textuais de teclado;
- o HUD e o inventario ficarao atras do overlay;
- ao fechar, o overlay e o blur serao removidos.

O blur sera uma responsabilidade da camada visual, ativado conforme o estado do
reader, e nao uma responsabilidade do controller de dominio. Isso mantem o
controller testavel por contrato sem criar instancias de UI.

## Validacao e warnings

O catalogo sera validado durante o acesso ao documento. Cada entrada precisa de
ID, nome de exibicao, pelo menos uma pagina e `content` string. Entradas
invalidas nao serao abertas e gerarao warning claro.

Modelos do mapa com tag `Interactable` e `InteractionType = "Document"` que nao satisfizerem o contrato nao serao
destruidos. A mensagem de warning identificara o caminho completo do alvo e o
motivo da falha.

Nao havera remotes, DataStore, persistencia, autoridade server-side ou eventos
de gameplay para documentos nesta etapa.

## Arquivos previstos

Criar:

- `src/client/documents/DocumentData.luau`
- `src/client/documents/DocumentsController.luau`
- `src/client/documents/DocumentReaderController.luau`
- `src/client/documents/DocumentInteraction.luau`
- `src/client/documents/useDocuments.luau`
- `src/client/documents/useDocumentReader.luau`

Modificar:

- `src/shared/interactions/interactionTypes.luau`
- `src/client/InputManager.luau`
- `src/client/init.client.luau`
- `src/client/ui/App.luau`

Nao modificar:

- qualquer arquivo em `tests/`;
- `InventoryState`, `InventoryStore` ou `InventoryController` para adicionar
  documentos;
- scripts server-side;
- remotes ou DataStore.

## Verificacao

Nenhum teste unitario sera criado ou alterado. A pasta `tests/` sera preservada.

A verificacao estatica e de build sera:

```bash
selene --config selene.roblox.toml src
selene --config selene.roblox-tests.toml tests
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --definitions @testez=typecheck/testez.d.luau \
  --sourcemap test-sourcemap.json --formatter gnu \
  src/shared \
  src/client/camera src/client/documents src/client/inventory \
  src/client/interactions src/client/player src/client/ui \
  tests
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

No Roblox Studio, a validacao manual devera confirmar:

- `E` coleta o modelo valido;
- o modelo desaparece imediatamente;
- o reader abre na pagina 1;
- movimento, combate, interacao e `Tab` ficam bloqueados;
- `A` nao circula na primeira pagina;
- `D` avanca entre paginas;
- `D` na pagina final fecha o reader;
- o botao direito do mouse fecha em qualquer pagina;
- o documento aparece na aba `DOCUMENTOS` na ordem correta;
- a leitura pela aba usa o mesmo reader;
- o overlay e o blur aparecem e desaparecem corretamente;
- IDs invalidos permanecem no mapa e geram warning.

## Fora de escopo

- Persistencia entre sessoes.
- Estado server-side ou validacao server-side.
- Documentos como `ItemInstance`.
- Imagens, anexos ou assets nos documentos.
- Busca, filtros ou ordenacao manual na aba.
- Animacao de virada de pagina.
- Efeito de datilografia.
- Dicas de controles no overlay.
- Alteracoes ou novos testes unitarios.

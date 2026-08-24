# Design: Componentes de UI do Inventário

Data: 2026-08-23  
Status: Design aprovado em conversa; aguardando revisão da especificação

## Objetivo

Criar três componentes reutilizáveis para a próxima evolução visual do
inventário:

1. `ConfirmationModal`, para confirmar ações irreversíveis como descartar um
   item.
2. `DropdownMenu`, para exibir ações ao lado do slot selecionado.
3. `InventorySlot`, para representar posições ocupadas, vazias e equipadas.

Nesta etapa, os componentes serão integrados ao `App` com dados mockados. A UI
não implementará descarte, equipamento, uso, novos remotes ou qualquer outra
mutação de gameplay.

## Contexto atual

O cliente recebe o inventário por `useInventory()`. Cada snapshot possui uma
lista de `ItemInstance`, com `uid`, `itemId`, `quantity` e atributos opcionais,
além do mapa `equipped`, que associa posições a `uid`s equipados.

O catálogo atual pode resolver o nome visual de um item, mas suas
`capabilities` estão em evolução e não serão usadas para definir ações nesta
entrega. A tabela de ações mockadas ficará na camada pai da UI e será facilmente
substituível quando o novo sistema de capabilities estiver definido.

O `App` atual alterna o painel usando a tecla `T`. Esse comportamento será
preservado, pois a troca do atalho não faz parte deste trabalho.

## Decisões aprovadas

| Tema | Decisão |
| --- | --- |
| Escopo | Somente UI e integração local com o snapshot existente |
| Componentes | Três módulos separados em `src/client/ui/` |
| Orquestração | `App` mantém o estado de menu e modal |
| Reutilização | Ações chegam ao slot por props; o slot não as decide |
| Grade | Seis posições visíveis, em três colunas por duas linhas |
| Slot vazio | Mantém o quadrado, sem texto e sem menu |
| Item | Exibe o nome como placeholder, sem imagem |
| Equipado | Label `equipado` quando o `uid` está em `inventory.equipped` |
| Dropdown | Overlay flutuante ao lado do slot, sem ocupar espaço |
| Dropdown aberto | Um único por vez; outro slot troca o menu atual |
| Seleção de ação | Fecha o dropdown antes de executar o callback |
| Modal | Controlado pelo pai e fechado somente por `não` ou `sim` |
| Visual | Paleta escura translúcida, bordas roxas e tipografia clara |
| Ações | Dados mockados explícitos por `itemId` na camada de UI |
| Servidor | Nenhuma alteração em controllers, remotes ou serviços |
| Testes de UI | Fora do escopo, conforme as instruções do repositório |

## Abordagens consideradas

### Estado centralizado no `App` (escolhida)

O `App` controla o `uid` selecionado, a visibilidade do modal, as posições dos
overlays e os callbacks. Os três componentes são visuais e recebem contratos
explícitos por props.

Essa abordagem garante um único menu aberto, simplifica a troca entre slots e
mantém as decisões de ações fora do `InventorySlot`.

### Estado interno em cada slot

Cada slot controlaria seu próprio dropdown e parte da confirmação. Essa opção
reduziria o estado no `App`, mas dificultaria garantir um único overlay ativo e
coordenar a confirmação entre slots.

### Gerenciador global de overlays

Um contexto ou serviço controlaria todos os menus e modais da interface. A
solução poderia atender outras telas no futuro, mas adicionaria infraestrutura
sem necessidade para esta primeira integração.

## Arquitetura

```text
src/client/ui/ConfirmationModal.luau
src/client/ui/DropdownMenu.luau
src/client/ui/InventorySlot.luau
src/client/ui/App.luau
```

O `App` continuará sendo montado pelo entrypoint existente. Nenhum módulo novo
será colocado em `shared`, pois os dados de ações são temporários e não formam
um contrato entre cliente e servidor.

O estado local do `App` terá estas responsabilidades:

- guardar o `uid` do item cujo menu está aberto;
- guardar o item que aguarda confirmação de descarte;
- limpar o menu ao selecionar uma ação;
- trocar o menu quando outro slot ocupado for pressionado;
- limpar uma seleção cujo `uid` não exista mais no snapshot recebido;
- construir os callbacks mockados antes de passá-los ao slot.

## Contratos dos componentes

Os módulos seguirão o padrão atual de componentes React em Luau e permanecerão
em `--!strict`.

### `InventorySlot`

Recebe uma representação visual opcional do item, o estado de equipamento, a
lista de ações já resolvida pelo pai e um callback de ativação.

```text
item: { name: string, quantity: number? }?
equipped: boolean
actions: { { label: string, onActivated: () -> () } }
onActivated: (() -> ())?
```

Quando `item` for `nil`, renderiza somente o estado vazio e não registra uma
interação de abertura. Quando houver item, exibe nome, quantidade opcional e a
label `equipado` quando `equipped` for verdadeiro. O componente não consulta o
catálogo, não interpreta capabilities e não monta ações por conta própria.

### `DropdownMenu`

Recebe uma lista pronta de opções e uma posição calculada pelo pai.

```text
visible: boolean
options: { { label: string, onActivated: () -> () } }
position: UDim2
```

Renderiza um painel vertical de botões quando `visible` for verdadeiro. Cada
botão chama o callback que recebeu. O fechamento acontece porque o callback do
`App` atualiza o estado controlado; o componente não precisa conhecer o slot
ativo nem as regras da ação.

### `ConfirmationModal`

Recebe o texto e os callbacks de decisão.

```text
visible: boolean
message: string
confirmLabel: string
cancelLabel: string
onConfirm: () -> ()
onCancel: () -> ()
```

O texto padrão usado pela integração será `Deseja descartar o item?`, com os
rótulos `não` e `sim`. O modal terá overlay de tela inteira, bloqueará a
interface abaixo dele e não terá fechamento por clique externo, `Escape` ou
qualquer outro caminho.

## Dados mockados e fluxo

O fluxo de renderização será:

```text
useInventory()
  -> snapshot nil: mostra "Carregando inventário..."
  -> snapshot pronto: prepara seis posições
       -> resolve o nome no catálogo
       -> verifica inventory.equipped pelos valores de uid
       -> consulta a tabela local de ações mockadas por itemId
       -> renderiza InventorySlot
       -> renderiza DropdownMenu na camada de overlay, se selecionado
       -> renderiza ConfirmationModal, se necessário
```

A tabela mockada será explícita e ficará no `App`. Ela poderá conter entradas
com listas diferentes para demonstrar que as opções dependem do item, sem
atribuir essa responsabilidade ao slot. Por exemplo, o mock pode representar
um medkit com `usar` e `descartar`, uma handgun com `equipar` e `descartar` e
um item de munição apenas com `descartar`. Esses valores são fixtures visuais,
não regras definitivas de gameplay e poderão ser trocados sem alterar os
componentes.

Os callbacks mockados terão este comportamento:

- `usar`: fecha o dropdown e não altera estado do inventário;
- `equipar`: fecha o dropdown e não altera estado do inventário;
- `descartar`: fecha o dropdown e abre o modal;
- `não`: fecha o modal;
- `sim`: fecha o modal sem remover o item.

O nome do item continuará vindo do catálogo atual porque isso já é uma
responsabilidade de apresentação existente. Se o `itemId` não for encontrado,
o texto usará o próprio `itemId` como fallback.

A grade preparará seis posições. As posições sem uma instância correspondente
receberão `item = nil`. Não será introduzida uma propriedade de capacidade no
snapshot. A primeira versão não terá paginação nem tratamento especial para
inventários com mais de seis instâncias.

## Posicionamento dos overlays

A grade e a camada de overlays serão irmãs dentro do painel de inventário. A
camada de overlays ocupará o mesmo contêiner, terá fundo transparente e ficará
acima da grade por `ZIndex`.

O `App` calculará a posição do dropdown a partir da posição da célula
selecionada. O menu abrirá ao lado do slot, preferindo o lado disponível na
tela, e ficará alinhado ao topo do slot. Como está fora do `UIGridLayout`, sua
presença não moverá os demais slots nem mudará o tamanho do painel.

O modal será irmão do painel de inventário dentro do `ScreenGui`, com `ZIndex`
superior a todos os elementos da tela. Assim, continuará funcional quando o
painel do inventário estiver visível e também poderá ser controlado sem alterar
o snapshot.

## Estados visuais

### Slot vazio

- quadrado visível na grade;
- fundo mais discreto que o slot ocupado;
- sem nome, quantidade ou label;
- sem callback de abertura.

### Slot ocupado

- fundo com maior contraste;
- nome centralizado e truncado quando necessário;
- quantidade junto ao nome quando informada;
- botão de ativação para abrir as ações fornecidas pelo pai.

### Slot equipado

- adiciona a label `equipado` sobreposta no canto superior;
- usa um fundo contrastante na label para preservar a leitura.

### Dropdown

- fundo escuro translúcido;
- borda roxa;
- lista vertical de botões;
- `ZIndex` acima dos slots;
- nenhuma alteração no layout da grade.

### Modal

- overlay escurecido sobre o `ScreenGui`;
- painel central com a mensagem de confirmação;
- dois botões horizontais, `não` e `sim`;
- apenas os callbacks desses botões encerram o modal.

## Tratamento de estados e limites

- Enquanto o inventário estiver carregando, a UI não exibirá seis slots vazios
  como se o inventário estivesse vazio.
- Um item desconhecido não interromperá a renderização; usará `itemId` como
  nome.
- Um item sem entrada no mock de ações poderá ser exibido sem abrir dropdown.
- Um slot vazio nunca abrirá menu.
- Um snapshot novo que não contenha o `uid` selecionado fará o `App` limpar o
  dropdown ativo.
- A confirmação não removerá itens e não chamará `InventoryController.use`.
- A tabela mockada não será publicada em `ReplicatedStorage` e não será tratada
  como validação de segurança.
- Nenhuma ação será considerada concluída no gameplay nesta etapa.

## Arquivos previstos

- Criar `src/client/ui/ConfirmationModal.luau`.
- Criar `src/client/ui/DropdownMenu.luau`.
- Criar `src/client/ui/InventorySlot.luau`.
- Modificar `src/client/ui/App.luau` para trocar a lista textual pela grade,
  controlar overlays e fornecer as ações mockadas.
- Não modificar `src/shared/inventory/catalog.luau`, preservando também as
  alterações não relacionadas que já existem no worktree.
- Não modificar `src/shared/inventory/items.luau`.
- Não modificar controllers, remotes, serviços ou entrypoints.

## Verificação

Não serão criadas specs para os componentes ou para `App`, pois as instruções
do repositório mantêm specs de UI fora do escopo desta migração. A validação
será estática e manual no Studio.

### Verificação estática

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
  src/server/inventory src/server/items src/server/pickups src/server/player \
  src/client/camera src/client/inventory src/client/pickups src/client/player src/client/ui \
  tests
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

### Verificação manual no Studio

- abrir e fechar o painel com a tecla `T`;
- confirmar que o painel contém três colunas e duas linhas;
- confirmar que posições sem item continuam visíveis;
- confirmar que um item mostra seu nome e quantidade quando aplicável;
- confirmar que um item equipado mostra `equipado`;
- confirmar que slot vazio não abre menu;
- clicar em um slot ocupado e verificar que o dropdown flutua ao lado sem
  mover a grade;
- clicar em outro slot e verificar que o dropdown troca de posição;
- selecionar uma ação e verificar que o dropdown fecha;
- selecionar `descartar` e verificar que o modal aparece;
- confirmar que o modal só fecha por `não` ou `sim`;
- confirmar que `sim` não altera o inventário nesta etapa;
- confirmar que um item desconhecido ainda pode mostrar seu `itemId` como nome.

## Fora de escopo

- redesenho ou substituição do sistema de `capabilities`;
- execução real de usar, equipar ou descartar;
- novos `RemoteEvent`s ou `RemoteFunction`s;
- validação server-side de ações;
- alteração de `InventoryState` ou do catálogo;
- imagens ou ícones de itens;
- drag-and-drop, seleção múltipla, paginação ou scroll;
- animações, sons ou histórico de menus;
- fechamento do modal por clique externo ou `Escape`;
- specs de UI.

# Design: Grafo de Objetivos com Subobjetivos

Data: 2026-08-23
Status: Aprovado pelo usuario para especificacao

## Objetivo

Evoluir o sistema client-side de objetivos event-driven para representar a
campanha como um grafo direcionado de objetivos. Cada objetivo sera um no com
transicoes de saida explicitas. Uma transicao conclui o no de origem e ativa o
no de destino.

O sistema tambem devera permitir que um objetivo contenha uma lista de
subobjetivos. O objetivo pai permanecera ativo enquanto qualquer subobjetivo
estiver pendente e concluira automaticamente quando todos forem concluidos.

O progresso continuara valido somente durante a sessao atual. O controller
continuara client-side, sem persistencia, remotes proprios ou servico de
objetivos no servidor.

## Decisoes aprovadas

| Tema | Decisao |
|---|---|
| Modelo | Grafo direcionado centrado nos nos |
| Ativacao | `initial` ou uma transicao de entrada |
| Transicao | Conclui a origem e ativa o destino |
| Caminhos | Somente transicoes de objetivos atualmente ativos podem disparar |
| Historico | Todos os eventos da sessao sao registrados, inclusive antes da ativacao de um no |
| Bifurcacao | Um no pode ter varias transicoes de saida |
| Convergencia | Um no pode ter varias transicoes de entrada |
| Paralelismo | O runtime mantem um conjunto de objetivos ativos e permite objetivos paralelos |
| Subobjetivos | Um nivel de filhos por objetivo, concluido com regra AND |
| Transicao interna | `subobjectives_completed` e uma condicao interna do controller |
| Objetivo terminal | Pode nao ter transicoes e usa uma condicao propria de conclusao |
| Evento de porta | Manter `door_blocked` e `door_entered` |
| Porta de teste | `DoorKey = "facility_test_door"` conclui `explore_facility` |
| UI | Mostrar objetivos da fronteira atual e checklist de subobjetivos |
| Notificacao | Notificar somente objetivos que permanecerem ativos apos o processamento |
| Compatibilidade | Substituir `startsWhen` e `requires`; nao manter dois modelos de configuracao |
| Testes de UI | Permanecem fora do escopo dos specs TestEZ |

## Grafo da campanha atual

O grafo inicial sera configurado com quatro objetivos:

```text
find_exit
  -- door_blocked(facility_entrance) --> find_medallions
  -- door_entered(facility_entrance) --> explore_facility

find_medallions
  -- subobjectives_completed --> access_facility

access_facility
  -- door_entered(facility_entrance) --> explore_facility

explore_facility
  -- door_entered(facility_test_door) --> concluido
```

`door_blocked` significa que a interacao com a porta foi bloqueada por falta do
item compativel. `door_entered` significa que a transicao de entrada terminou
com sucesso. Os dois eventos nao representam duas propriedades simultaneas da
mesma tentativa de interacao.

Se o jogador encontrar o cartao antes de interagir com
`facility_entrance`, `door_blocked` nao sera emitido. Quando
`door_entered(facility_entrance)` ocorrer, `find_exit` seguira diretamente para
`explore_facility`; `find_medallions` e `access_facility` permanecerao inativos.

## Estrutura de dados

### Definicoes de objetivos

Cada objetivo tera `id`, `text` e uma ou mais formas de progresso:

```lua
{
    id = "find_exit",
    text = "Encontre a saida",
    initial = true,
    transitions = {
        {
            to = "find_medallions",
            when = {
                event = "door_blocked",
                doorKey = "facility_entrance",
            },
        },
        {
            to = "explore_facility",
            when = {
                event = "door_entered",
                doorKey = "facility_entrance",
            },
        },
    },
}
```

Uma transicao sempre tera:

- `to`: ID existente do no de destino;
- `when`: filtro de evento ou trigger interno.

Uma definicao sem `initial` sera alcancada por uma transicao de entrada. Uma
definicao pode ter varias transicoes de entrada, como `explore_facility` no
grafo atual.

### Subobjetivos

Um objetivo composto tera uma lista de filhos de um unico nivel:

```lua
{
    id = "find_medallions",
    text = "Encontre os medalhoes",
    subobjectives = {
        {
            id = "silver_medallion",
            text = "Medalhao prata",
            completesWhen = {
                event = "item_collected",
                itemId = "silver_medallion",
            },
        },
        {
            id = "gold_medallion",
            text = "Medalhao ouro",
            completesWhen = {
                event = "item_collected",
                itemId = "gold_medallion",
            },
        },
    },
    transitions = {
        {
            to = "access_facility",
            when = {
                type = "subobjectives_completed",
            },
        },
    },
}
```

Os subobjetivos nao sao nos independentes do grafo e nao possuem transicoes.
Eles possuem seu proprio status e uma condicao de conclusao declarativa ou
`completeIf`. O pai so podera seguir a transicao interna quando todos os
filhos estiverem concluidos.

Subobjetivos aninhados dentro de subobjetivos nao farao parte desta versao.

### Objetivos terminais

Um objetivo sem transicoes de saida podera ter uma condicao propria de
conclusao:

```lua
{
    id = "explore_facility",
    text = "Explore a instalacao",
    completesWhen = {
        event = "door_entered",
        doorKey = "facility_test_door",
    },
}
```

Essa condicao conclui o objetivo sem ativar outro no. O evento da porta de
teste sera publicado pela mesma infraestrutura de portas quando a porta for
adicionada ao mapa com o atributo `DoorKey` correspondente.

`completeIf` continuara disponivel como escape hatch somente para uma condicao
que nao possa ser expressa por um filtro simples. A funcao recebera fatos
somente para leitura e nao podera emitir eventos ou alterar estados.

### Modos de conclusao

Para evitar duas fontes de verdade, cada objetivo usara exatamente um modo de
conclusao:

- objetivo com transicoes: conclui quando uma transicao de saida dispara;
- objetivo composto: conclui quando a transicao `subobjectives_completed`
  dispara;
- objetivo terminal: conclui com `completesWhen` ou `completeIf`.

Um objetivo nao podera misturar transicoes de progresso com
`completesWhen`/`completeIf`. Um objetivo composto nao podera declarar uma
condicao propria diferente da conclusao dos filhos.

## Processamento do controller

### Estado interno

O controller mantera:

```text
definitions: todas as definicoes do grafo
definitionById: indice por ID
facts: historico de eventos da sessao
statuses: inactive, active ou completed por objetivo
subobjectiveStatuses: status dos filhos dos objetivos compostos
visibleIds: fronteira publicada para a UI
```

O conjunto de objetivos ativos nao sera representado por um unico ID. Isso
permite objetivos paralelos quando transicoes de objetivos ativos diferentes ou
varios objetivos iniciais forem validos ao mesmo tempo.

### Inicio da sessao

`start()` devera:

1. Validar toda a configuracao antes de mutar o estado de progresso.
2. Inicializar todos os objetivos como `inactive`.
3. Assinar o `GameplayEvents` event source.
4. Ativar os objetivos com `initial = true`.
5. Sincronizar os subobjetivos usando todos os fatos conhecidos.
6. Processar transicoes e conclusoes ate chegar a um ponto fixo.
7. Publicar o estado e a notificacao dos objetivos que permanecerem ativos.

`start()` sera idempotente. `stop()` desconectara a assinatura, limpará os
fatos e os estados da sessao, e tambem sera idempotente.

### Processamento de eventos

Quando um evento chegar:

1. O evento sera adicionado ao historico de fatos.
2. Subobjetivos ativos serao atualizados se o evento satisfizer suas condicoes.
3. Cada objetivo ativo sera avaliado contra suas transicoes de saida.
4. A transicao compativel concluira o objetivo de origem e ativara seu destino.
5. Um objetivo recem-ativado sera avaliado contra todo o historico, nao apenas
   contra o evento atual.
6. Se um objetivo composto tiver todos os filhos concluidos, sua transicao
   `subobjectives_completed` sera processada.
7. Objetivos terminais serao avaliados por `completesWhen` ou `completeIf`.
8. O ciclo sera repetido enquanto houver ativacoes ou conclusoes novas.
9. A fronteira visivel e os sinais serao publicados uma vez com o resultado
   final do lote.

Somente transicoes que saem de objetivos atualmente ativos poderao modificar o
caminho. Um fato antigo pode satisfazer uma transicao depois que seu objetivo
for ativado, mas nunca ativa um no inativo por conta propria.

### Bifurcacao, convergencia e paralelismo

Dentro de um objetivo, uma configuracao valida nao tera duas transicoes que
possam aceitar o mesmo trigger. O validator devera rejeitar filtros identicos
ou sobrepostos para o mesmo evento. O processamento usara a ordem declarada
como defesa adicional, mas uma configuracao ambigua nao sera aceita.

Um evento pode disparar no maximo uma transicao por objetivo ativo. O mesmo
evento pode disparar transicoes de objetivos ativos diferentes, permitindo
objetivos paralelos.

Um destino com varias arestas de entrada sera ativado de forma idempotente.
Se ja estiver ativo ou concluido, nao sera recriado nem reativado.

### Fatos fora de ordem

Eventos de coleta recebidos antes da ativacao de `find_medallions` continuarao
em `facts`.

Quando `find_medallions` for ativado:

- um medalhao previamente coletado sera exibido como concluido;
- o outro permanecera pendente;
- se os dois ja tiverem sido coletados, o pai concluira imediatamente;
- a transicao `subobjectives_completed` seguira para `access_facility` no
  mesmo processamento;
- objetivos intermediarios concluídos imediatamente nao serao notificados.

O mesmo mecanismo sera usado para uma condicao terminal cujo evento tenha
ocorrido antes de o objetivo ser ativado.

### Exemplo dos dois caminhos

Sem o cartao, o fluxo sera:

```text
start
  -> find_exit ativo
door_blocked(facility_entrance)
  -> find_exit concluido
  -> find_medallions ativo
item_collected(silver_medallion)
  -> silver_medallion concluido
item_collected(gold_medallion)
  -> gold_medallion concluido
  -> find_medallions concluido
  -> access_facility ativo
  -> access_facility concluido
  -> explore_facility ativo
  -> explore_facility concluido
```

Com o cartao encontrado antes da porta, o fluxo sera:

```text
item_collected(access_card)
  -> fato registrado; find_exit continua ativo
  -> find_exit concluido
  -> explore_facility ativo
  -> explore_facility concluido
```

## Contratos de tipos

O controller devera substituir o contrato de ativacao anterior por tipos
equivalentes a estes:

```lua
export type EventFilter = {
    event: GameplayEvents.EventName,
    doorKey: string?,
    itemId: string?,
    areaKey: string?,
}

export type TransitionTrigger = EventFilter | {
    type: "subobjectives_completed",
}

export type Transition = {
    to: string,
    when: TransitionTrigger,
}

export type SubobjectiveDefinition = {
    id: string,
    text: string,
    completesWhen: EventFilter?,
    completeIf: ((facts: Facts) -> boolean)?,
}

export type ObjectiveDefinition = {
    id: string,
    text: string,
    initial: boolean?,
    transitions: { Transition }?,
    subobjectives: { SubobjectiveDefinition }?,
    completesWhen: EventFilter?,
    completeIf: ((facts: Facts) -> boolean)?,
}
```

`startsWhen` e `requires` serao removidos da configuracao. A existencia de uma
transicao de entrada sera a unica forma nao inicial de alcancar um objetivo.

As views publicadas para React terao filhos opcionais:

```lua
export type SubobjectiveView = {
    id: string,
    text: string,
    completed: boolean,
}

export type ObjectiveView = {
    id: string,
    text: string,
    completed: boolean,
    subobjectives: { SubobjectiveView }?,
}
```

## Validacao

O validator devera falhar antes do progresso quando encontrar:

- lista de definicoes vazia ou sem objetivo inicial;
- ID de objetivo vazio ou duplicado;
- texto de objetivo vazio;
- destino de transicao inexistente;
- no nao inicial e inalcançavel a partir de um objetivo inicial;
- ciclo no grafo;
- transicao sem trigger valido;
- evento desconhecido ou campo incompatível com o payload;
- duas transicoes sobrepostas saindo do mesmo no;
- objetivo com transicoes e uma conclusao propria simultaneamente;
- objetivo sem transicoes e sem `completesWhen`/`completeIf`;
- objetivo composto sem filhos;
- subobjetivo com ID duplicado dentro do pai;
- subobjetivo com texto vazio;
- subobjetivo sem exatamente uma condicao de conclusao;
- subobjetivo com transicoes ou outros subobjetivos;
- objetivo composto sem uma transicao `subobjectives_completed`;
- objetivo composto com transicao interna duplicada ou condicao de conclusao
  concorrente.

O grafo sera aciclico nesta primeira versao. Repeticao de etapas, reset parcial
e reentrada em nos concluidos exigiriam uma semantica de ciclo diferente e
ficam fora deste escopo.

## Integracao com a UI

`useObjectives` continuara assinando `ObjectiveController.changed`, mas seus
tipos serao atualizados para transportar subobjetivos.

`App.luau` renderizara uma linha do objetivo pai e linhas indentadas dos seus
filhos. O painel continuara visivel somente quando o inventario estiver
aberto.

Regras de exibicao:

- objetivos ativos aparecem na fronteira atual;
- filhos aparecem dentro do pai;
- filhos concluidos recebem marcacao propria;
- o pai permanece pendente enquanto qualquer filho estiver pendente;
- ao seguir para o proximo no, o pai concluido sai da fronteira;
- um objetivo terminal concluido permanece visivel como concluido;
- objetivos intermediarios concluídos imediatamente por fatos antigos nao
  aparecem como uma sequencia de estados transitorios.

`useObjectiveNotification` continuara recebendo um lote de objetivos, mas o
lote conterá somente objetivos que permanecerem ativos depois do ponto fixo.
Subobjetivos nao gerarao notificacoes individuais.

## Arquivos e limites de implementacao

### Alterar

- `src/client/objectives/ObjectiveController.luau`: substituir gates e
  dependencias pelo processamento de transicoes e subobjetivos;
- `src/client/objectives/ObjectiveConfig.luau`: declarar o grafo da campanha e
  a porta de teste `facility_test_door`;
- `src/client/objectives/useObjectives.luau`: atualizar views com filhos;
- `src/client/objectives/useObjectiveNotification.luau`: atualizar os tipos das
  views;
- `src/client/ui/App.luau`: renderizar checklist de subobjetivos;
- `tests/client/objectives/ObjectiveController.spec.luau`: substituir os casos
  do modelo antigo pelos testes do grafo e dos filhos.

### Preservar

- `src/client/events/GameplayEvents.luau` e o contrato de eventos existente;
- `src/client/events/PickupEventBridge.luau`;
- publicacao de eventos do `DoorController`;
- ordem de inicializacao do controller e do bridge;
- estado de inventario e regras de autoridade server-side.

Nao serao criados publishers novos, remotes de progresso, persistencia,
editor visual ou specs da arvore React.

## Testes

Os specs continuarao sendo ModuleScripts `--!strict` executados pelo TestEZ no
DataModel real. Fixtures de fontes de eventos e conexoes serao isoladas em
`beforeEach` e limpas em `afterEach`.

O `ObjectiveController` devera testar:

- objetivo inicial ativo;
- transicao direta para `explore_facility` por `door_entered`;
- transicao alternativa por `door_blocked`;
- dois subobjetivos ativos dentro de `find_medallions`;
- conclusao dos medalhoes em qualquer ordem;
- transicao apenas depois dos dois subobjetivos;
- um medalhao coletado antes da ativacao do pai;
- os dois medalhoes coletados antes da ativacao do pai;
- cartao coletado antes da porta e escolha do caminho direto;
- fato sem transicao no objetivo atualmente ativo nao alterando o caminho;
- conclusao de `explore_facility` por `facility_test_door`;
- conclusao terminal sem destino posterior;
- convergencia de varias entradas para um mesmo objetivo;
- objetivos paralelos em um mesmo evento;
- fatos historicos satisfazendo transicoes de nos recem-ativados;
- destinos inexistentes, nos inalcançaveis e ciclos;
- transicoes ambíguas e triggers internos invalidos;
- subobjetivos invalidos;
- lifecycle idempotente de `start()` e `stop()`.

Nao serao adicionados specs de UI. O layout aninhado sera verificado
manualmente no Roblox Studio.

## Verificacao

Depois da implementacao, executar:

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
  src/client/camera src/client/inventory src/client/pickups src/client/player \
  src/client/doors src/client/dialogue src/client/events src/client/interactions \
  src/client/objectives src/client/ui \
  tests
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

No Roblox Studio, a sessao Play de testes devera ser reiniciada depois das
alteracoes. O resultado esperado e `failed == 0` nos runners client e server.
O fluxo manual devera cobrir os dois caminhos do grafo e a porta com
`DoorKey = "facility_test_door"`.

## Fora de escopo

- ciclos ou reentrada em objetivos concluidos;
- subobjetivos recursivos;
- editor visual de grafos;
- persistencia de progresso;
- sincronizacao server-side;
- novos tipos concretos de eventos alem dos publishers existentes;
- efeitos arbitrarios nas transicoes;
- specs de UI React.

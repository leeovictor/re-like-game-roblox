# Design: Sistema de Objetivos Event-Driven

Data: 2026-08-22  
Status: Aprovado pelo usuario para especificacao

## Objetivo

Adicionar um sistema client-side para que o jogador acompanhe o objetivo
principal e seu avanco durante a gameplay. O sistema sera orientado por eventos
de gameplay e configurado em codigo por uma tabela que o game designer possa
editar sem alterar os controllers de portas, pickups ou a UI.

O progresso sera valido somente durante a sessao atual. Respawn nao reinicia os
objetivos e nao havera persistencia entre servidores ou sessoes.

O objetivo atual ficara escondido durante a gameplay normal e sera exibido no
canto superior direito quando o jogador abrir o inventario. Quando um ou mais
objetivos novos forem ativados, um aviso aparecera no canto superior direito
por tres segundos e um som sera reproduzido uma vez para o lote.

## Decisoes aprovadas

| Tema | Decisao |
|---|---|
| Autoridade | Controller client-side, sem servico de objetivos no servidor |
| Escopo do progresso | Sessao atual; nao reinicia no respawn e nao persiste entre sessoes |
| Entrada | Eventos semanticos publicados por sistemas de gameplay |
| Acoplamento | Publishers nao importam nem conhecem o `ObjectiveController` |
| Barramento | Um barramento geral local, sem fila, persistencia ou remotes proprios |
| Objetivos ativos | Um ou varios; objetivos paralelos sao suportados |
| Dependencias | Um objetivo pode exigir varios objetivos concluidos |
| Ordem dos eventos | Eventos anteriores sao registrados e podem satisfazer etapas futuras |
| Condicoes comuns | Filtros declarativos de evento |
| Condicoes especiais | Funcao opcional `completeIf` para regras compostas |
| Porta sem chave | Publica `door_blocked` |
| Porta destrancada com chave | Publica `door_unlocked` somente apos sucesso |
| Entrada por porta aberta | Publica `door_entered` somente apos sucesso |
| Coleta | `item_collected` vem da confirmacao existente `PickupCollected` |
| Identificador de porta | Atributo estavel `DoorKey`, sem fallback para o nome do Model |
| Lista no inventario | Mostra objetivos da etapa atual, inclusive concluidos com marcacao |
| Aviso | Um unico aviso por lote de novos objetivos, por tres segundos |
| Audio | Uma reproducao por lote; ID configuravel e inicialmente vazio |
| UI | App React continua sendo o unico dono da arvore visual |
| Testes de UI | Fora do escopo dos specs TestEZ |

## Abordagens consideradas

### Fluxo hardcoded nos controllers

Portas e pickups chamariam funcoes especificas, como `startFindCard()` ou
`completeMedallion()`. Essa abordagem teria pouco codigo inicial, mas faria o
gameplay conhecer a campanha e dificultaria objetivos paralelos, dependencias e
novos fluxos. Foi rejeitada.

### Grafo declarativo client-side com fatos da sessao

Um barramento local distribui eventos sem conhecer consumidores. O
`ObjectiveController` registra os eventos, ativa objetivos, testa dependencias e
publica o estado para o React. A maior parte das regras fica em tabelas; uma
funcao opcional cobre condicoes compostas. Esta e a abordagem aprovada.

### Servico de objetivos no servidor

O servidor manteria o progresso e replicaria snapshots ao cliente. Essa
abordagem seria adequada para multiplayer, persistencia ou protecao contra
alteracoes client-side, mas adicionaria remotes, sincronizacao e estado
duplicado sem necessidade para este jogo single-player. Foi rejeitada.

## Arquitetura

```text
src/client/events/GameplayEvents.luau
  barramento local de eventos semanticos

src/client/events/PickupEventBridge.luau
  converte PickupCollected em item_collected

src/client/objectives/ObjectiveConfig.luau
  definicoes editaveis pelo game designer

src/client/objectives/ObjectiveController.luau
  fatos, ativacao, conclusao, dependencias e sinais

src/client/objectives/useObjectives.luau
  ponte do estado persistente para React

src/client/objectives/useObjectiveNotification.luau
  ponte do lote transitorio e temporizador de tres segundos

src/client/ui/App.luau
  painel de objetivos e aviso no ScreenGui existente
```

O `DoorController` publicara eventos pelo barramento, mas nao importara o
`ObjectiveController`. O adaptador de pickup escutara o remoto
`PickupCollected`, que ja e disparado pelo servidor somente apos uma coleta
confirmada, e publicara o evento client-side correspondente. O
`ObjectiveController` sera apenas um dos assinantes do barramento; outros
sistemas poderao assinar os mesmos eventos sem modificar os publishers.

O barramento tera uma API minima conceitual:

```lua
GameplayEvents.emit({
    name = "door_blocked",
    doorKey = "main_exit",
})

local connection = GameplayEvents.subscribe(function(event)
    -- O consumidor decide se o evento importa.
end)
```

O barramento usara um unico sinal tipado e nao armazenara historico. O
`ObjectiveController` armazenara os fatos da sessao de forma privada. A
publicacao sera sincrona e cada assinante recebera o evento sem que o publisher
precise conhecer sua identidade.

## Eventos de Gameplay

Os eventos iniciais serao semanticos e separados por resultado. Todos os
eventos de porta que puderem satisfazer objetivos terao um `doorKey` string.

```text
door_blocked
  Porta trancada e jogador sem item compativel.
  Payload: { name = "door_blocked", doorKey = string }

door_unlocked
  InteractDoor retornou sucesso para a acao unlock.
  Payload: { name = "door_unlocked", doorKey = string }

door_entered
  A transicao terminou e InteractDoor retornou sucesso para enter.
  Payload: { name = "door_entered", doorKey = string }

item_collected
  PickupCollected foi recebido depois de InventoryService:addInstance ter
  retornado sucesso.
  Payload: { name = "item_collected", itemId = string }
```

### Publicacao por DoorController

O controller continuara coordenando inventario, remoto, dialogo e transicao.
Somente depois de determinar o resultado semantico ele publicara o evento:

1. Porta trancada sem item local: publica `door_blocked` e mostra o dialogo.
2. Porta trancada com item: chama `InteractDoor`.
3. Unlock aceito pelo servidor: publica `door_unlocked`.
4. Unlock rejeitado por falta do item: publica `door_blocked` e mostra o dialogo.
5. Porta ja destrancada: executa a transicao.
6. Entrada aceita: publica `door_entered`.
7. Distancia, configuracao, concorrencia ou outro erro: nao publica evento de
   progresso.

Uma porta sem `DoorKey` ou com valor vazio continuara funcionando para o
gameplay de porta, mas o controller emitira um warning e nao publicara evento
que possa ser filtrado por objetivos. O nome do Model nunca sera usado como
fallback, pois `DoorKey` deve continuar estavel mesmo que a organizacao visual
do mapa mude.

O `DoorController` recebera a funcao de emissao como dependencia. O default
usara `GameplayEvents.emit`; os testes poderao fornecer um spy.

### Publicacao por PickupCollected

O `PickupEventBridge` conectara `remotes.PickupCollected.OnClientEvent` e
publicara `item_collected` com o `itemId` recebido. O
`PickupNotificationController` continuara podendo consumir o mesmo remoto para
mostrar a notificacao existente. Nenhum evento de objetivo sera inferido pela
comparacao de snapshots do inventario.

Eventos recebidos pelo barramento nao sao reenviados ao servidor. O sistema de
objetivos e feedback de uma campanha single-player; as regras de porta e
inventario continuam com a validacao server-side existente.

## Configuracao dos Objetivos

`ObjectiveConfig.luau` retornara uma lista de definicoes com IDs unicos. A
estrutura conceitual sera:

```lua
{
    id = "find_access_card",
    text = "Encontre o cartao de acesso",
    startsWhen = {
        event = "door_blocked",
        doorKey = "cave_exit",
    },
    completesWhen = {
        event = "item_collected",
        itemId = "access_card",
    },
}
```

Os campos de ativacao serao:

- `initial = true`: inicia no comeco da sessao.
- `startsWhen`: inicia quando um evento compativel existir nos fatos.
- `requires`: inicia quando todos os IDs listados estiverem concluidos.

Quando mais de uma condicao de ativacao for declarada, todas serao exigidas.
Na configuracao normal, o objetivo inicial usara `initial`, uma etapa acionada
por evento usara `startsWhen` e uma etapa de convergencia usara `requires`.

As condicoes de conclusao serao:

- `completesWhen`: filtro declarativo para eventos simples.
- `completeIf`: funcao opcional que retorna `boolean` e consulta os fatos.

Somente uma das duas sera permitida em cada objetivo. A funcao nao podera
publicar eventos, ativar objetivos ou alterar o estado diretamente.

### Fluxo de porta e cartao

```lua
{
    id = "find_exit",
    text = "Ache uma saida",
    initial = true,
    completesWhen = {
        event = "door_blocked",
        doorKey = "cave_exit",
    },
},
{
    id = "find_access_card",
    text = "Encontre o cartao de acesso",
    startsWhen = {
        event = "door_blocked",
        doorKey = "cave_exit",
    },
    completesWhen = {
        event = "item_collected",
        itemId = "access_card",
    },
},
{
    id = "access_facility",
    text = "Acesse a instalacao",
    requires = {
        "find_access_card",
    },
    completesWhen = {
        event = "door_entered",
        doorKey = "facility_entrance",
    },
}
```

O primeiro objetivo sera concluido somente por `door_blocked`, nao por
`door_unlocked`. Assim, encontrar o cartao antes de tentar a porta nao conclui
o primeiro objetivo, mas o fato de coleta sera preservado e a etapa do cartao
sera pulada quando for ativada.

### Objetivos paralelos

O mesmo `startsWhen` podera ativar varias definicoes:

```lua
{
    id = "find_gold_medallion",
    text = "Encontre o medalhao de ouro",
    startsWhen = {
        event = "door_blocked",
        doorKey = "main_exit",
    },
    completesWhen = {
        event = "item_collected",
        itemId = "gold_medallion",
    },
},
{
    id = "find_silver_medallion",
    text = "Encontre o medalhao de prata",
    startsWhen = {
        event = "door_blocked",
        doorKey = "main_exit",
    },
    completesWhen = {
        event = "item_collected",
        itemId = "silver_medallion",
    },
},
{
    id = "open_main_exit",
    text = "Abra a saida principal",
    requires = {
        "find_gold_medallion",
        "find_silver_medallion",
    },
    completesWhen = {
        event = "door_entered",
        doorKey = "main_exit",
    },
}
```

Os dois medalhoes serao ativados no mesmo processamento e permanecerao na
lista. Depois do primeiro item, seu objetivo ficara marcado como concluido e o
segundo continuara pendente. Depois do segundo, `open_main_exit` sera ativado e
o conjunto anterior sera retirado da lista atual.

### Condicoes compostas

Uma regra que dependa de mais de um fato podera usar `completeIf`:

```lua
{
    id = "restore_power",
    text = "Restabeleca a energia",
    startsWhen = {
        event = "area_entered",
        areaKey = "generator_room",
    },
    completeIf = function(facts)
        local switches = facts:latest("switches_changed")
        return facts:hasEvent("item_collected", { itemId = "fuse" })
            and switches ~= nil
            and switches.switchesOn >= 3
    end,
}
```

`completeIf` sera avaliada quando o objetivo for ativado e depois de cada novo
evento enquanto ele estiver ativo. Portanto, tanto coletar o fusivel depois do
terceiro interruptor quanto ativar o terceiro interruptor depois de coletar o
fusivel podera concluir a etapa.

O objeto `facts` sera somente leitura. Ele oferecera consulta de ocorrencia de
eventos e consulta do ultimo payload de um tipo de evento. Os eventos de item,
porta e futuros eventos de gameplay poderao ser consultados sem que o
`ObjectiveController` precise expor tabelas mutaveis.

## Motor de Progresso

O estado do controller tera a forma conceitual:

```lua
{
    objectives = {
        {
            id = "find_gold_medallion",
            text = "Encontre o medalhao de ouro",
            completed = true,
        },
        {
            id = "find_silver_medallion",
            text = "Encontre o medalhao de prata",
            completed = false,
        },
    },
}
```

O controller tambem mantera internamente o status de todos os IDs, os fatos da
sessao e a conexao com o barramento. A lista publicada sera somente a etapa
atual, nao o historico completo da campanha.

Depois de iniciar ou receber um evento, o controller executara um processamento
ate chegar a um ponto fixo:

1. Registrar o evento nos fatos, quando houver um evento novo.
2. Ativar definicoes cujos gates de ativacao estejam satisfeitos.
3. Avaliar `completesWhen` e `completeIf` dos objetivos ativos.
4. Marcar objetivos satisfeitos como concluidos.
5. Reavaliar dependencias e ativar objetivos que agora possam iniciar.
6. Repetir ate que nenhuma ativacao ou conclusao adicional ocorra.
7. Retirar da lista atual objetivos concluidos substituidos por um novo conjunto.
8. Publicar o estado e, se houver objetivos novos ainda ativos, publicar um
   unico lote de notificacao.

O processamento ate ponto fixo e necessario para o caso em que um objetivo e
ativado ja satisfeito por um evento anterior. Um objetivo intermediario pode
ser concluido imediatamente, e o proximo objetivo ativo sera o unico incluido
no aviso.

O barramento nao fara replay. O replay necessario para objetivos fora de ordem
sera feito pelo registro privado de fatos do controller. `start()` sera
idempotente; `stop()` desconectara assinaturas e limpara o estado da sessao para
que uma nova execucao comece com os objetivos iniciais.

## Integracao com a UI

`App.luau` continuara usando o `ScreenGui` `DungeonGui` existente. A abertura do
inventario continuara sendo controlada pela tecla `T` e pelo estado
`inventoryVisible` ja existente.

### Painel persistente

Quando `inventoryVisible` for `true`, o App renderizara um painel de objetivos
no canto superior direito. Quando for `false`, esse painel nao sera renderizado.

O painel:

- mostrara todos os objetivos da etapa atual;
- mostrara objetivos paralelos simultaneamente;
- mantera objetivos concluidos ate a ativacao do proximo conjunto;
- usara uma marcacao distinta para concluido e pendente;
- usara fundo escuro translúcido, borda roxa e texto claro, seguindo o
  inventario existente;
- usara largura limitada, `AutomaticSize` e `TextWrapped` para telas menores.

### Aviso transitorio

O controller tera um sinal separado para o lote de objetivos que permanecerem
ativos depois de uma ativacao. `useObjectiveNotification()` substituira o lote
anterior e removera o aviso apos tres segundos, usando uma geracao para impedir
que um timer antigo remova um aviso novo.

O aviso sera colocado no topo da mesma coluna do painel, com espacamento para
nao sobrepor a lista quando o inventario estiver aberto. Se houver um objetivo,
mostrara a mensagem de novo objetivo e seu texto. Se houver varios, mostrara
todos os textos no mesmo bloco.

Objetivos concluidos imediatamente por fatos antigos nao entrarao no aviso. Se
uma cadeia inteira for pulada, o aviso mostrara somente o proximo objetivo que
permanecer ativo.

### Audio

O `ObjectiveController` tocara um som uma vez quando publicar um lote de novos
objetivos. O modulo tera uma constante substituivel:

```lua
local OBJECTIVE_SOUND_ID = ""
```

Com a string vazia, nenhum `Sound` sera criado ou reproduzido. Depois que o
asset for escolhido, o designer alterara somente essa constante. Um lote com
dois objetivos toca uma vez, nao uma vez por linha.

O som sera local e nao sera persistido. O controller criara um unico `Sound` em
`SoundService` quando `OBJECTIVE_SOUND_ID` nao estiver vazio, reutilizara esse
objeto para cada lote e o destruira no `stop()`, seguindo o padrao de lifecycle
dos controllers de audio do cliente.

## Validacao e tratamento de erros

As definicoes serao validadas antes de o controller iniciar o progresso. A
configuracao sera invalida quando tiver:

- IDs duplicados;
- dependencias que nao existem;
- ciclos de dependencia;
- nenhum gate de ativacao (`initial`, `startsWhen` ou `requires`);
- nenhuma condicao de conclusao (`completesWhen` ou `completeIf`);
- `completesWhen` e `completeIf` juntos;
- evento ou filtro incompatível com o payload conhecido;
- textos vazios ou IDs de evento vazios.

Configuracao invalida falhara cedo com mensagem que identifique o ID do
objetivo. O controller nao iniciara parcialmente nem publicara estado ambiguo.

Eventos sem assinantes serao descartados pelo barramento. Eventos de gameplay
que nao correspondem ao objetivo ativo continuarao registrados para poderem
satisfazer etapas futuras. Um evento repetido nao concluira novamente um
objetivo que ja esteja concluido.

## Arquivos previstos

- Criar `src/client/events/GameplayEvents.luau`.
- Criar `src/client/events/PickupEventBridge.luau`.
- Criar `src/client/objectives/ObjectiveConfig.luau`.
- Criar `src/client/objectives/ObjectiveController.luau`.
- Criar `src/client/objectives/useObjectives.luau`.
- Criar `src/client/objectives/useObjectiveNotification.luau`.
- Modificar `src/client/doors/DoorController.luau` para publicar resultados e
  aceitar o `DoorKey`.
- Modificar `src/shared/doors/doorTypes.luau` para declarar o atributo
  `DoorKey`.
- Modificar `src/client/init.client.luau` para iniciar o bridge e o controller.
- Modificar `src/client/ui/App.luau` para renderizar painel e aviso.
- Modificar `test.project.json` para mapear `events` e `objectives` no projeto
  de testes.
- Criar specs client-side para o barramento e o `ObjectiveController`.
- Adaptar o spec de `DoorController` para verificar eventos publicados por
  dependencia injetada.

Nao sera necessario modificar o servico de objetivos no servidor, criar remoto
novo para progresso, alterar `InventoryState` ou criar specs de UI.

## Testes

Os specs serao ModuleScripts `--!strict` executados pelo TestEZ no DataModel
real. Fixtures de Instances e conexoes serao criadas em `beforeEach` e limpas em
`afterEach`.

### GameplayEvents

- publica evento para assinantes;
- permite varios assinantes;
- desconecta assinantes sem receber eventos posteriores;
- nao retém ou reenvia eventos por conta propria.

### ObjectiveController

- inicia o objetivo inicial e publica o lote inicial;
- registra conclusao por `completesWhen`;
- filtra `doorKey` e `itemId` corretamente;
- ignora eventos incompatíveis para o objetivo atual sem perder o fato;
- conclui uma etapa quando o evento ocorreu antes de sua ativacao;
- pula automaticamente uma etapa ja satisfeita;
- ativa dois objetivos pelo mesmo evento;
- mantém um objetivo paralelo concluido visivel enquanto outro esta pendente;
- ativa a etapa que exige varios objetivos somente depois de todos concluirem;
- avalia `completeIf` com as condicoes chegando em ordens diferentes;
- publica um unico lote para varias ativacoes;
- nao republica conclusoes ja processadas;
- valida IDs, dependencias, ciclos e condicoes ausentes;
- executa `start()` e `stop()` de forma idempotente e reseta uma nova sessao.

### DoorController

Com um emissor injetado, os testes verificarao:

- porta trancada sem item publica `door_blocked`;
- unlock aceito publica `door_unlocked`;
- entrada aceita publica `door_entered`;
- erro de porta nao publica progresso;
- evento usa `DoorKey`, sem usar o nome do Model como identificador.

O bridge de `PickupCollected` tera um teste do contrato de conversao usando uma
fonte de evento local controlada pelo teste. A entrega real de
`RemoteEvent:FireClient` sera verificada no checkpoint server-to-client do
Roblox Studio e nao sera simulada por um runner client.

## Verificacao

Executar os checks estaticos e builds:

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
  src/server/inventory src/server/items src/server/pickups src/server/doors src/server/player \
  src/client/camera src/client/doors src/client/dialogue src/client/events \
  src/client/interactions src/client/inventory src/client/objectives \
  src/client/pickups src/client/player src/client/ui \
  tests
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

No Roblox Studio, iniciar uma sessao Play limpa do projeto de testes e confirmar
`failed == 0` nos resultados server e client. Repetir o fluxo com Play parado
entre as sessoes e confirmar que conexoes e fixtures temporarias foram limpas.

Na verificacao manual do jogo, confirmar:

- o objetivo inicial aparece por tres segundos ao iniciar;
- o aviso inicial toca o som quando `OBJECTIVE_SOUND_ID` estiver configurado;
- com inventario fechado, a lista persistente nao aparece;
- ao abrir o inventario, a lista aparece no canto superior direito;
- uma porta trancada sem chave publica `door_blocked`;
- uma porta trancada com chave publica `door_unlocked`, nao `door_blocked`;
- uma porta aberta atravessada publica `door_entered`;
- o cartao encontrado antes da porta e reconhecido sem deixar objetivo obsoleto;
- dois medalhoes aparecem como objetivos paralelos em um unico aviso;
- o primeiro medalhao fica marcado enquanto o segundo continua pendente;
- depois dos dois medalhoes, somente o objetivo da saida principal permanece;
- o aviso novo substitui o anterior e desaparece apos tres segundos.

## Fora de escopo

- servico de objetivos no servidor;
- persistencia de objetivos ou sincronizacao entre sessoes;
- multiplayer ou compartilhamento de progresso entre jogadores;
- fila ou historico visual de avisos;
- editor visual de campanhas;
- descoberta automatica de eventos sem publisher explicito;
- indicador visual de alvo de interacao;
- selecao do asset de audio;
- alteracao do schema persistivel `InventoryState`;
- specs da arvore React ou de layout visual;
- integracao de novos tipos concretos de gameplay alem dos publishers previstos.

# Design: Sistema de Combate Client-Side

Data: 2026-08-28  
Status: Design consolidado; aguardando revisao do usuario  
Escopo: combate client-side da handgun, equipamento, municao, mira e bloqueio externo

## Objetivo

Criar a primeira versao do sistema de combate client-side do jogo, integrada ao
inventario local e ao sistema client-side de inimigos.

O sistema devera permitir que o jogador:

- equipe uma handgun possuida no inventario;
- mantenha no maximo uma arma equipada no slot `weapon`;
- entre em mira com Mouse Right;
- adquira automaticamente o inimigo mais proximo apenas no inicio da mira;
- gire manualmente enquanto mira usando `A` e `D`;
- dispare um tiro por clique em Mouse Left;
- aplique dano no inimigo atingido;
- consuma a municao carregada da arma;
- recarregue com `R` somente enquanto estiver mirando;
- recarregue automaticamente quando o pente ficar vazio;
- bloqueie movimento durante mira e recarga;
- permita que sistemas externos bloqueiem todo o combate durante uma acao.

O runtime continuara sendo client-side, sem remotes novos. Essa decisao e
adequada ao jogo single-player atual e nao representa uma fronteira de
seguranca para multiplayer competitivo.

## Decisoes aprovadas

| Tema | Decisao |
|---|---|
| Arquitetura | `CombatController` para input e loop; `CombatService` para regras |
| Autoridade | Client-side, sem remotes novos |
| Equipamento | Inventario local, slot unico `weapon` |
| Troca de arma | Equipar outra arma substitui a anterior no slot |
| Arma inicial | Handgun inicia com o pente cheio quando nao possui `loadedAmmo` |
| Disparo | Semiautomatico, um tiro por clique |
| Pre-condicao de tiro | Mouse Right pressionado e handgun equipada |
| Mira automatica | Uma tentativa no inicio da mira, sem tracking |
| Mira manual | `A` e `D` giram o personagem durante a mira |
| Recarga manual | `R`, somente durante a mira |
| Recarga automatica | Inicia quando `loadedAmmo` chega a zero e existe reserva |
| Recarga durante mira | Estado separado; ao entrar, a mira termina |
| Movimento durante recarga | Sempre bloqueado |
| Saida da mira durante recarga | Recarga continua ate concluir |
| Retomada apos recarga | Se Mouse Right ainda estiver pressionado, nova mira e aquisicao iniciam |
| Cancelamento externo | Somente bloqueio persistente por `acquireLock()` |
| Remocao do bloqueio | Funcao `release()` retornada por `acquireLock()` |
| Dano no inimigo | `EnemyController` valida e chama `Humanoid:TakeDamage` |
| Morte/reacao do inimigo | Fora do escopo desta versao |
| Camada visual | Fora do escopo; sem modelo de arma ou animacoes novas |
| Testes unitarios | Fora do escopo; nao criar nem alterar specs unitarias |
| Roblox MCP | Fora do escopo desta implementacao, salvo permissao explicita |

## Arquitetura

```text
InventoryController
  -> posse, equipamento, atributos da arma e municao

CombatController
  -> bindings de input
  -> estado de teclas A/D e Mouse Right
  -> loop de atualizacao
  -> encaminhamento para CombatService

CombatService
  -> estado aiming/reloading
  -> movement locks internos
  -> bloqueios externos persistentes
  -> aquisicao inicial de alvo
  -> raycast de tiro
  -> cooldown, consumo e recarga

EnemyController
  -> candidatos ativos
  -> validacao do alvo
  -> aplicacao de dano
```

O composition root sera `src/client/init.client.luau`. Ele criara as instancias
e fornecera referencias explicitas. Nenhum controller criara um singleton
operacional importando outro controller.

### `CombatService`

`CombatService` sera uma instancia de runtime criada com dependencias nomeadas:

```luau
local combatService = CombatService.new({
    inventory = inventoryController,
    enemies = enemyController,
    movement = tankController,
})
```

O service sera responsavel por:

- resolver a handgun equipada;
- inicializar o pente de uma handgun nova com `magazineSize`;
- iniciar e encerrar a mira;
- adquirir um alvo somente na entrada da mira;
- atualizar a rotacao manual durante a mira;
- validar e executar um tiro;
- controlar o cooldown semiautomatico;
- iniciar recarga manual ou automatica;
- concluir recarga depois da duracao configurada;
- adquirir e liberar movement locks internos;
- adquirir e manter bloqueios externos persistentes;
- invalidar operacoes de recarga interrompidas;
- reagir a troca ou remocao da arma equipada.

O service tera lifecycle proprio:

```luau
combatService:start()
combatService:stop()
```

`start()` sera idempotente e observara `InventoryController.changed`. `stop()`
desconectara a observacao, encerrara mira ou recarga, liberara os locks internos,
limpara o estado e invalidara releases de geracoes anteriores.

O contrato operacional do service incluira:

```luau
start(self) -> ()
stop(self) -> ()
update(self, deltaTime) -> ()
beginAim(self) -> ()
endAim(self) -> ()
shoot(self) -> boolean
requestReload(self) -> boolean
setTurnInput(self, left, right) -> ()
acquireLock(self) -> (() -> ())
```

`beginAim()` e `endAim()` atualizarao tambem o fato de Mouse Right estar
pressionado. Assim, um input iniciado enquanto houver bloqueio externo nao sera
perdido: a mira podera ser retomada quando o ultimo lock for liberado, desde que
o botao continue pressionado.

### `CombatController`

`CombatController` recebera o service por dependencia:

```luau
local combatController = CombatController.new({
    combat = combatService,
})
```

Ele registrara Mouse Right, Mouse Left, `R`, `A` e `D`, e encaminhara as acoes
por closures que preservam a instancia do controller. Uma unica conexao de
`PreRender` chamara `combatService:update(deltaTime)`.

O controller nao implementara dano, alvo, municao ou regras de recarga. Seu
estado ficara limitado aos inputs atuais e aos recursos de input/lifecycle.

### Composicao

A ordem geral de composicao sera:

1. criar e iniciar `InventoryController`;
2. criar e iniciar `EnemyController` e `TankController` conforme a composicao atual;
3. criar `CombatService` com inventario, inimigos e movimento;
4. iniciar `CombatService`;
5. criar e iniciar `CombatController`;
6. fornecer `inventoryController` e o service necessario para a UI e futuros sistemas.

O `EnemyController` continuara recebendo sua dependencia de movimento existente.
O combate nao importara `Enemy` ou `TankController` para obter instancias
operacionais ocultas.

## Configuracao da handgun

Criar `src/client/combat/CombatConfig.luau` com tuning centralizado. Os valores
iniciais serao:

```text
magazineSize = 6
damage = 25
shotCooldown = 0.35 segundos
acquisitionRadius = 30 studs
shotRange = 80 studs
reloadDuration = 1.5 segundos
aimTurnSpeed = 2.5 radianos por segundo
```

A configuracao tambem declarara o vinculo da arma com a municao:

```text
handgun -> handgun_ammo
```

Esses valores serao simples de ajustar no modulo, mas nao serao lidos de
pickups. O pickup continua fornecendo apenas `ItemId` e `Quantity` conforme o
contrato atual.

## Inventario e equipamento

### Conversao para instancia

O `InventoryController` atual mantem estado e sinal em escopo de modulo. Como
sera alterado para suportar equipamento e municao, ele sera convertido para uma
instancia conforme `docs/controller-service-pattern.md`.

Cada instancia tera seu proprio:

- estado do inventario;
- sinal `changed`;
- lifecycle;
- conexoes e recursos de runtime.

O estado continuara usando `InventoryState` com `items` e `equipped`. O slot
operacional da handgun sera sempre `equipped.weapon`.

### API operacional

O contrato da instancia incluira as operacoes existentes e estas operacoes de
combate/equipamento:

```luau
start(self) -> ()
stop(self) -> ()
getState(self) -> InventoryState?
addInstance(self, instance) -> boolean
equip(self, uid) -> boolean
getEquipped(self, slot) -> ItemInstance?
updateAttributes(self, uid, attributes) -> boolean
consumeLoadedAmmo(self, weaponUid) -> boolean
reloadWeapon(self, weaponUid, ammoUid, amount, loadedAmmo) -> boolean
```

`equip(uid)` devera:

1. localizar a instancia no estado atual;
2. exigir capability `equip` e categoria `weapon`;
3. chamar a operacao pura de equipamento do `InventoryStore` no slot `weapon`;
4. substituir a arma anterior, se existir;
5. substituir o estado e disparar `changed` somente em sucesso.

Nao existira mais de uma arma equipada simultaneamente. O inventario nao
conhecera dano, alcance, cadencia ou duracao de recarga.

`reloadWeapon(...)` sera uma mutacao atomica observavel: o controller usara
operacoes puras temporarias para atualizar `loadedAmmo` e remover a quantidade
da pilha de municao; somente publicara o novo estado quando ambas as operacoes
forem validas. Uma falha nao deixara metade da recarga aplicada.

`consumeLoadedAmmo(...)` reduzira `loadedAmmo` em uma unidade e retornara
`false` se a arma nao existir, nao estiver carregada ou nao possuir um valor
valido.

### Munição carregada

`loadedAmmo` sera um atributo mutavel da instancia da handgun. Capacidade,
dano, alcance e cadencia permanecerao em `CombatConfig`.

Quando uma handgun equipada nao possuir `loadedAmmo`, o `CombatService` tratara
isso como uma arma nova e escrevera `magazineSize` no atributo. Assim, uma arma
recem-coletada inicia com o pente cheio sem colocar tuning de combate no pickup.
Uma arma que ja possua `loadedAmmo` preservara seu valor ao ser reequipada.

Ao iniciar, o service tambem verificara a arma que ja estiver equipada para
aplicar essa inicializacao caso o equipamento tenha ocorrido antes do seu
lifecycle comecar.

As pilhas de `handgun_ammo` continuarao sendo instancias stackable com
`quantity`. A recarga procurara uma pilha compativel com `itemId`, transferira
somente o espaco restante do pente e removera a pilha quando sua quantidade
chegar a zero.

### UI

`App` recebera `inventoryController` por props e `useInventory` recebera a
instancia em vez de importar um controller global. `PickupManager`,
`DoorManager` e `MachineRoomCinematicController` receberao e usarao a mesma
instancia composta.

A acao mock `equipar` da handgun sera substituida pela chamada real a
`inventoryController:equip(instance.uid)`. Nao havera redesign da UI, indicador
de municao, menu novo ou apresentacao visual da arma nesta etapa.

## Estados do combate

Os estados de combate serao mutuamente exclusivos:

```text
neutral
  -> aiming
  -> reloading
  -> neutral ou aiming
```

Tambem existira um contador independente de bloqueios externos. O bloqueio nao
sera um estado de mira ou recarga; ele e uma condicao que impede todos os
estados operacionais.

### `neutral`

- Mouse Left nao dispara;
- `R` nao inicia recarga;
- `A` e `D` permanecem disponiveis para o movimento normal;
- nao existe alvo adquirido;
- nao existe movement lock de combate.

### `aiming`

Ao receber Mouse Right Begin, o service devera:

1. ignorar a entrada se houver bloqueio externo;
2. ignorar a entrada se ja estiver mirando ou recarregando;
3. resolver a handgun equipada;
4. adquirir o aim movement lock;
5. marcar `aiming = true`;
6. tentar uma unica aquisicao de alvo;
7. orientar o personagem para o alvo se um alvo visivel for encontrado.

Se nao houver arma ou alvo, o jogador ainda podera permanecer em mira manual
quando a arma for valida. A ausencia de alvo nao encerra a mira.

Enquanto estiver mirando:

- Mouse Left podera executar um tiro;
- `R` podera iniciar uma recarga;
- `A` e `D` girarao o personagem;
- o aim movement lock impedira deslocamento normal;
- nenhuma nova busca de alvo sera realizada automaticamente.

Ao receber Mouse Right End, o service devera registrar que o botao nao esta mais
pressionado. Se estiver em `aiming`, devera limpar o alvo, marcar a mira como
inativa e liberar o aim movement lock. Se estiver em `reloading`, devera apenas
manter a recarga em andamento; o reload movement lock nao sera liberado antes
da conclusao.

### `reloading`

Ao iniciar uma recarga valida, manual ou automatica, o service devera:

1. encerrar a mira, se ativa;
2. descartar o alvo adquirido;
3. liberar o aim movement lock;
4. capturar a identidade da arma e uma nova geracao de recarga;
5. adquirir o reload movement lock;
6. marcar `reloading = true`;
7. aguardar `reloadDuration` usando o loop do controller.

Durante a recarga:

- Mouse Right nao inicia nem mantém mira;
- Mouse Left nao dispara;
- `R` nao reinicia a operação;
- `A` e `D` nao giram o personagem;
- o reload movement lock bloqueia o movimento;
- a recarga continua se Mouse Right for solto.

Ao terminar a duracao, o service devera validar que a mesma arma continua
equipada e entao chamar `reloadWeapon(...)`. Em seguida, devera limpar a
operacao, liberar o reload movement lock e:

- entrar novamente em `aiming` e adquirir um novo alvo se Mouse Right ainda
  estiver pressionado;
- permanecer em `neutral` se Mouse Right estiver solto.

Se a arma tiver sido removida ou substituida durante a recarga, a transferencia
nao sera aplicada. O lock sera liberado e a nova arma nao herdara a operacao
antiga.

## Bloqueio externo persistente

O `CombatService` expora somente este mecanismo para sistemas externos:

```luau
local release = combatService:acquireLock()
-- nenhuma acao de combate pode iniciar ou continuar
release()
```

`acquireLock()` devera:

1. incrementar um contador por instancia;
2. encerrar imediatamente mira ou recarga ativa;
3. liberar os movement locks internos correspondentes;
4. invalidar a geracao de qualquer recarga pendente;
5. retornar uma funcao `release()` idempotente.

Enquanto o contador for maior que zero:

- Mouse Right nao inicia nem retoma mira;
- Mouse Left nao dispara;
- `R` nao inicia recarga;
- `A` e `D` nao giram o personagem;
- nenhuma operacao de combate ativa pode continuar.

O release do ultimo bloqueio torna o combate elegivel novamente. Se Mouse Right
continuar pressionado, a mira sera retomada no ciclo seguinte e fara uma nova
aquisicao. Caso contrario, o service permanecera neutro.

Nao havera `cancel()` separado, parametros de tipo, razoes ou locks especificos
por acao. O cancelamento de uma acao e uma consequencia de adquirir o bloqueio
persistente. A remocao do bloqueio ocorre somente pelo `release()` retornado.

O contador e a geracao serao criados em `new()` e pertencerao a instancia. Um
release antigo nao podera desbloquear uma nova geracao depois de `stop()`.

Um evento futuro de ataque inimigo podera receber uma referencia composta para
o service e executar:

```luau
local release = combatService:acquireLock()
-- ataque do inimigo
release()
```

O `EnemyController` nao importara o `CombatService` para fazer isso.

## Aquisicao de alvo

`CombatService` solicitara ao `EnemyController` os inimigos ativos no momento da
entrada em mira. Um inimigo candidato devera:

- continuar registrado no controller;
- nao estar destruido;
- possuir root valido;
- possuir `Humanoid.Health > 0`;
- estar dentro de `acquisitionRadius`.

Os candidatos serao ordenados pela distancia ao root do personagem. Para cada
candidato, o service executara um raycast entre o personagem e o root do
inimigo, excluindo o character do jogador. O primeiro candidato cujo root/model
seja o impacto visivel sera escolhido.

Uma parede ou outro objeto bloqueando o caminho elimina aquele candidato, mas
nao impede a tentativa com candidatos posteriores. Se nenhum candidato passar
no raycast, a mira manual continuara disponivel.

Depois da escolha, o personagem sera orientado uma vez para a posicao atual do
root inimigo. O service nao acompanhara a movimentacao do inimigo e nao
alterara o alvo quando `A` ou `D` forem usados.

## Disparo e dano

Mouse Left Begin executara no maximo um tiro e seguira esta ordem:

1. exigir estado `aiming` e ausencia de bloqueio externo;
2. resolver a handgun equipada;
3. exigir `loadedAmmo > 0`;
4. exigir que o cooldown esteja liberado;
5. consumir uma unidade de `loadedAmmo`;
6. atualizar o proximo instante permitido de tiro;
7. executar um raycast no `LookVector` atual do personagem por `shotRange`;
8. resolver se o primeiro impacto pertence a um inimigo ativo;
9. chamar `EnemyController:applyDamage(enemy, damage)` quando houver alvo.

O tiro consome municao mesmo quando acerta o cenario ou nao encontra inimigo.
Se a aplicacao de dano falhar por o alvo ter deixado de ser valido, o tiro e a
municao continuam consumidos, pois o disparo ja ocorreu.

O `EnemyController:applyDamage` devera validar que a instancia recebida pertence
a sua lista ativa e que seu humanoid ainda e valido antes de chamar
`Humanoid:TakeDamage`. Ele nao implementara estado de morte, reacao, efeitos
visuais ou remocao do modelo nesta versao.

Depois do ultimo tiro:

- se houver `handgun_ammo` disponivel, iniciar `reloading` automaticamente;
- se nao houver reserva, permanecer em mira com o pente vazio ate o jogador
  sair da mira ou obter municao.

## Recarga

Uma recarga manual somente sera aceita quando:

- Mouse Right estiver pressionado;
- o estado for `aiming`;
- existir handgun equipada;
- `loadedAmmo` for menor que `magazineSize`;
- existir uma pilha `handgun_ammo` com quantidade positiva.

Uma recarga automatica usara as mesmas validacoes de arma, espaco e reserva,
mas sera disparada pelo consumo da ultima unidade carregada. Se nao houver
municao reserva, nenhuma recarga sera iniciada.

O service controlara `reloadElapsed` ou um deadline em seu loop, sem criar uma
coroutine por recarga. A identidade da arma e a geracao da operacao serao
capturadas no inicio. Uma operacao invalidada nao podera aplicar municao quando
seu tempo original terminar.

## Prioridade de input

O combate usara `ContextActionService` para conseguir interceptar `A` e `D`
durante a mira e devolver o controle ao movimento fora dela.

`ActionPriorities` recebera uma prioridade de combate acima de movimento e
abaixo de dialogo. O dialogo continuara vencendo o combate para que seus
bindings de `A` e `D` funcionem durante uma conversa.

O comportamento esperado sera:

| Contexto | A/D | Mouse Right | Mouse Left | R |
|---|---|---|---|---|
| Neutro | Movimento normal | Inicia mira | Ignorado | Ignorado |
| Mira | Rotacao manual | Mantem mira | Um tiro | Inicia recarga |
| Recarga | Consumido/bloqueado | Ignorado | Ignorado | Ignorado |
| Lock externo | Consumido/bloqueado | Ignorado | Ignorado | Ignorado |
| Dialogo | Dialogo vence | Sem combate | Sem combate | Sem combate |

## Alteracoes de producao

### Novos arquivos

- `src/client/combat/CombatConfig.luau`
- `src/client/combat/CombatService.luau`
- `src/client/combat/CombatController.luau`

### Arquivos alterados

- `src/client/inventory/InventoryController.luau`: converter para instancia e
  adicionar equipamento, municao e mutacoes atomicas;
- `src/client/inventory/useInventory.luau`: receber controller por argumento;
- `src/client/ui/App.luau`: receber inventario por props e substituir a acao
  mock de equipar;
- `src/client/init.client.luau`: compor e iniciar inventario e combate, e
  fornecer as referencias corretas aos consumidores;
- `src/client/pickups/PickupManager.luau`: usar a instancia de inventario com
  chamadas de instancia;
- `src/client/doors/DoorManager.luau`: usar a instancia de inventario;
- `src/client/cinematics/MachineRoomCinematicController.luau`: usar a instancia
  de inventario;
- `src/shared/input/ActionPriorities.luau`: adicionar prioridade de combate e
  preservar dialogo acima dela;
- `src/client/enemies/EnemyController.luau`: expor candidatos ativos e aplicar
  dano validado;
- `src/client/enemies/types.luau`: atualizar contratos exportados do controller
  e inimigo quando necessario.

`InventoryStore` compartilhado continuara sendo o dono das transformacoes puras
de estado. Nao serao introduzidos remotes, servicos server-side de combate,
assets visuais novos ou alteracoes de tuning do inimigo.

## Tratamento de falhas

- Sem handgun equipada: ignorar mira, tiro e recarga.
- Handgun removida durante mira: encerrar mira e liberar o lock.
- Handgun substituida durante recarga: invalidar a recarga sem transferir
  municao.
- Sem alvo na aquisicao: permanecer em mira manual.
- Alvo bloqueado por parede: ignorar o candidato e tentar o proximo.
- Sem municao carregada: nao disparar; iniciar recarga automatica somente se
  houver reserva.
- Sem reserva: permanecer com o pente vazio, sem recarga e sem erro fatal.
- Tiro sem impacto em inimigo: consumir municao normalmente.
- Inimigo invalido no momento do dano: nao aplicar dano, mas manter o disparo
  consumido.
- Falha de mutacao do inventario: nao concluir a recarga e liberar o lock;
  nenhum estado parcial sera publicado.
- `start()` ou `stop()` repetidos: nao duplicar bindings, conexoes ou locks.
- Release repetido: nao alterar o contador novamente.
- Release antigo depois de `stop()`: nao desbloquear uma nova geracao.

Falhas normais de pre-condicao serao no-op observaveis pelo estado do combate;
nao exigirao warnings nem feedback visual nesta etapa. Erros inesperados em
operacoes de inventario ou DataModel deverao ser protegidos para nao deixar
locks presos.

## Validacao fora de testes unitarios

Nao serao criados nem alterados testes unitarios existentes, mesmo que contratos
anteriores fiquem incompatíveis.

A validacao de codigo planejada para a implementacao ficara limitada a:

- lint dos arquivos de producao alterados;
- typecheck Roblox dos diretorios de producao envolvidos;
- builds dos projetos Rojo normal e de teste, sem iniciar ou modificar specs;
- revisao estatica de imports, prioridades, lifecycle e chamadas operacionais.

Nenhuma validacao via Roblox MCP sera executada sem pedido explicito do usuario.

## Fora de escopo

- modelo de arma nas maos;
- animacoes de equipar, mirar, disparar ou recarregar;
- sons, particulas, muzzle flash, hit marker ou HUD de municao;
- dano ou autoridade server-side;
- remotes de combate;
- estado de morte, reacao, stun ou remocao visual do inimigo;
- tracking continuo de alvo;
- troca automatica de alvo;
- tiro sem mira;
- disparo automatico ao segurar Mouse Left;
- mais de uma arma equipada;
- tipos ou parametros de bloqueio externo;
- cancelamento momentaneo separado do bloqueio persistente;
- persistencia de inventario;
- testes unitarios novos ou alterados;
- redesign da UI;
- uso do Roblox MCP sem permissao explicita.

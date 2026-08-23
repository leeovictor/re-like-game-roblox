# Design: Animacao da Notificacao de Objetivos

Data: 2026-08-23
Status: Aprovado pelo usuario

## Objetivo

Adicionar uma animacao simples ao aviso de novos objetivos. Ao ser disparado,
o aviso deve aguardar um segundo antes de aparecer, entrar com fade in, ficar
visivel e sair com fade out. O comportamento deve continuar restrito ao aviso
de objetivos existente no `App` React.

## Decisoes aprovadas

| Tema | Decisao |
|---|---|
| Espera inicial | 1 segundo invisivel antes de montar o aviso |
| Fade in | 0,5 segundo |
| Permanencia | 5 segundos completamente visivel |
| Fade out | 0,5 segundo |
| Animacao | `TweenService` aplicado pelo `App` |
| Estado | `useObjectiveNotification` continua controlando o ciclo da notificacao |
| Repeticao | Um novo lote invalida o ciclo anterior e reinicia a espera; nao ha fila |
| Elementos animados | Texto, fundo e `UIStroke` |
| Testes de UI | Verificacao manual no Roblox Studio; sem specs TestEZ de UI |

## Sequencia temporal

Para cada lote inicial ou ativado:

```text
0.0s - 1.0s   ausente/invisivel
1.0s - 1.5s   fade in
1.5s - 6.5s   completamente visivel
6.5s - 7.0s   fade out
7.0s          lote removido da arvore React
```

Os cinco segundos de permanencia sao contados depois que o fade in termina.
Isso preserva a duracao de exibicao aprovada e torna o fade out observavel
antes da remocao.

## Abordagens consideradas

### Animacao no `App` com `TweenService` e ref

O hook controla a espera, a substituicao do lote e a remocao depois do ciclo.
O `App` recebe um ref do `TextLabel`, cria tweens para o label e seu
`UIStroke`, e cancela os tweens no cleanup do efeito. Esta e a abordagem
aprovada porque e a menor mudanca, preserva o `App` como dono da arvore visual e
segue o padrao de tween existente em `TransitionController`.

### Fases de animacao expostas pelo hook

O hook retornaria estados como `waiting`, `entering`, `visible` e `exiting`, e
o `App` converteria essas fases em propriedades de transparencia. Esta opcao
centralizaria todos os tempos, mas aumentaria o contrato do hook e exigiria
mais sincronizacao entre estado React e propriedades visuais.

### Controller visual separado

Um controller criaria uma GUI imperativa fora do `App` e executaria os tweens
diretamente. Embora ofereca controle baixo nivel, criaria uma segunda arvore
visual e contrariaria a arquitetura atual do cliente.

## Arquitetura e fluxo de dados

### Temporizacao compartilhada

Criar um pequeno modulo de temporizacao em `src/client/objectives/` com os
quatro valores aprovados: atraso de entrada, duracao do fade in, permanencia
visivel e duracao do fade out. O hook e o `App` usarao os mesmos valores para
que a remocao do estado ocorra depois que o tween de saida terminar.

### Hook `useObjectiveNotification`

O hook continuara retornando `{ ObjectiveView }?` e nao alterara o contrato do
`ObjectiveController`.

- O estado inicial sera `nil`, mesmo quando ja existir um lote inicial.
- O lote inicial sera publicado depois do atraso de um segundo.
- Ao receber `activated`, o hook incrementara a geracao, invalidara callbacks
  pendentes, removera o lote atualmente mostrado e agendara o novo lote para
  depois de um segundo.
- Depois de montar o lote, o hook o removera somente apos o fade in, os cinco
  segundos visiveis e o fade out.
- O guard de `active` e `notificationGeneration` impedira que timers de um
  lote antigo atualizem o estado depois de uma substituicao ou desmontagem.

O comportamento continua sendo de substituicao, como no hook atual: se varios
lotes chegarem proximos, somente o lote mais recente sera exibido.

### `App`

O efeito da notificacao sera executado quando um lote existir:

1. O `TextLabel` sera montado com texto, fundo e stroke totalmente
   transparentes.
2. Um tween de 0,5 segundo levara o label para os valores visiveis atuais:
   `TextTransparency = 0`, `BackgroundTransparency = 0.08` e
   `UIStroke.Transparency = 0.25`.
3. Apos cinco segundos de permanencia, um tween de 0,5 segundo levara as tres
   propriedades para transparencia total.
4. O cleanup cancelara os tweens e invalidara o callback de fade out.

O ref sera usado apenas para acessar a instancia criada pelo React. O texto,
o layout, o painel de objetivos, a notificacao de pickups e as demais
funcionalidades da tela permanecerao inalterados.

## Concorrencia e limpeza

Um novo lote durante a espera ou durante a exibicao cancela efetivamente o
ciclo anterior: o hook invalida seus timers e o efeito do `App` cancela os
tweens associados ao label antigo. O novo label inicia um ciclo completo com
um segundo de espera. Nenhum callback antigo podera limpar o novo lote.

Se o componente for desmontado, o efeito marcara seu ciclo como inativo e
cancelara os tweens restantes. Se o `UIStroke` nao puder ser encontrado, o
label ainda sera animado; a ausencia do stroke nao impedira o aviso de
aparecer.

## Arquivos previstos

- Criar `src/client/objectives/ObjectiveNotificationTiming.luau` com os tempos
  compartilhados.
- Modificar `src/client/objectives/useObjectiveNotification.luau` para aplicar
  a espera inicial, a duracao sincronizada e os guards de geracao.
- Modificar `src/client/ui/App.luau` para aplicar os tweens ao label e ao
  `UIStroke`.
- Nao modificar `ObjectiveController`, `ObjectiveConfig`, publishers de eventos
  ou a notificacao de pickups.

## Validacao

Os specs TestEZ de UI permanecem fora do escopo conforme as instrucoes do
repositorio. A validacao sera manual no Roblox Studio, disparando uma
notificacao inicial e uma ativacao posterior e observando a sequencia completa.

Tambem serao executados:

- `selene --config selene.roblox.toml src`
- `selene --config selene.roblox-tests.toml tests`
- sourcemap e typecheck Roblox conforme `AGENTS.md`
- build de `default.project.json`
- build de `test.project.json`
- Play limpo no Studio para confirmar espera, entrada, permanencia, saida e
  substituicao sem efeitos atrasados

## Fora do escopo

- Animar a lista permanente de objetivos do inventario.
- Alterar duracoes da notificacao de pickups.
- Adicionar fila, persistencia ou novos eventos de objetivos.
- Adicionar specs de renderizacao ou testes de UI ao TestEZ.

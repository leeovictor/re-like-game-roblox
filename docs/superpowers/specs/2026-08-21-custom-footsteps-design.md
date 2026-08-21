# Design: Passos Customizados do Personagem

Data: 2026-08-21
Status: Aprovado pelo usuario para especificacao

## Objetivo

Substituir o som padrao de passos do personagem por um conjunto configuravel
de audios customizados. Os passos devem ser ouvidos apenas pelo jogador local,
soar somente enquanto o personagem se move no chao e evitar uma sequencia
perceptivelmente repetitiva.

## Decisoes aprovadas

| Tema | Decisao |
|---|---|
| Audibilidade | Os passos sao locais e audiveis apenas pelo jogador dono do personagem |
| Integracao | Novo controlador em `src/client/player/FootstepController.luau` |
| Configuracao | IDs ficam em `src/client/player/FootstepConfig.luau` |
| Som padrao | Destruir `HumanoidRootPart.Running` ao configurar cada personagem |
| Recriacao do padrao | Nenhum watcher sera necessario; o jogo atual nao recria `Running` |
| Instancias | Uma instancia `Sound` por asset ID, criada uma vez por personagem |
| Reproducao | As instancias configuradas sao reutilizadas; nenhuma instancia nova por passo |
| Variacao | Nunca selecionar o mesmo audio duas vezes seguidas quando houver alternativas |
| Pitch | Variar `PlaybackSpeed` dentro de uma faixa configuravel |
| Volume | Variar `Volume` dentro de uma faixa configuravel |
| Chao | Nao tocar quando `Humanoid.FloorMaterial` for `Air` |
| Movimento | Nao tocar parado; a cadencia usa a velocidade real do `Humanoid` |
| Controle | `TankController` continua responsavel apenas pelo movimento |
| Materiais | Sons por material do chao ficam fora do escopo |

## Arquitetura

```text
Client.init
  -> FootstepController.start
       -> Player.CharacterAdded
            -> HumanoidRootPart
                  -> destroi Running
                 -> cria Footstep_1 ... Footstep_N
       -> Humanoid.Running
       -> RunService.PreRender
```

O `FootstepController` acompanha o personagem local e mantem as conexoes
necessarias para o personagem atual. Ao receber um novo personagem, ele espera
o `HumanoidRootPart`, procura o som padrao chamado `Running` e o destroi. Em
seguida cria os sons customizados como filhos do mesmo root, mantendo o audio
3D na origem do personagem sem criar objetos replicados pelo servidor.

`src/client/player/FootstepConfig.luau` exportara uma lista de IDs e os limites
de variacao. A lista tera tamanho definido pelo conteudo da configuracao, sem
limite de tres a oito audios. Uma lista vazia desabilitara a reproducao sem
gerar erro; uma lista com um unico audio continuara funcionando, repetindo o
unico candidato.

## Reproducao e variacao

Cada asset tera uma instancia `Sound` persistente, com nomes reservados como
`Footstep_1`, `Footstep_2` e assim por diante. As instancias serao configuradas
com `SoundId`, `Looped = false` e as propriedades espaciais definidas pelo
controlador. O conjunto podera ser pre-carregado antes da primeira reproducao
para reduzir atraso audivel.

Em cada passo, o controlador:

1. descarta candidatos que sejam iguais ao audio escolhido anteriormente,
   exceto quando houver apenas um candidato;
2. sorteia uma instancia restante;
3. sorteia `PlaybackSpeed` e `Volume` dentro das faixas da configuracao;
4. aplica os valores na instancia escolhida e chama `Play`.

O intervalo entre passos sera calculado a partir da velocidade recebida pelo
evento `Humanoid.Running`, usando uma velocidade de referencia e limites para
evitar intervalos extremos. O acumulador de tempo sera atualizado no ciclo de
renderizacao. Um passo so sera permitido quando a velocidade estiver acima do
limiar de movimento e o material do chao nao for `Air`.

## Ciclo de vida

1. `start` retorna sem duplicar conexoes quando ja estiver iniciado.
2. O controlador conecta `Players.LocalPlayer.CharacterAdded` e configura o
   personagem atual, se existir.
3. A configuracao limpa conexoes do personagem anterior antes de configurar o
   novo personagem.
4. O `Running` existente e destruido antes da criacao dos sons customizados.
5. As instancias dos passos pertencem ao personagem e serao destruidas junto
   com ele no respawn.
6. `stop` desconecta eventos, interrompe os sons customizados e limpa o estado
   de selecao e cadencia.

O controlador sera iniciado em `src/client/init.client.luau` junto dos demais
controladores de jogador. Nenhuma mudanca sera feita no servidor, em remotes ou
no contrato compartilhado.

## Configuracao inicial

O modulo de configuracao tera valores para:

- `soundIds`;
- faixa de `PlaybackSpeed`;
- faixa de `Volume`;
- velocidade de referencia;
- intervalo minimo e maximo entre passos;
- propriedades de audibilidade 3D, como `RollOffMode`,
  `RollOffMinDistance` e `RollOffMaxDistance`.

Os IDs reais dos audios serao preenchidos pelo usuario depois. O modulo nao
devera embutir um numero fixo de assets nem depender de nomes externos.

## Verificacao

A validacao sera feita em Roblox Studio com Play limpo, verificando:

- o `Running` original nao existe depois que o personagem inicia;
- o personagem parado nao toca passos;
- passos nao tocam durante queda ou no ar;
- o movimento continuo produz passos em cadencia coerente;
- dois passos consecutivos nao usam o mesmo audio quando ha alternativas;
- pequenas variacoes de pitch e volume sao aplicadas;
- o respawn recria o conjunto sem duplicacao;
- os sons customizados permanecem locais ao jogador;
- nao ha erros no Output.

Tambem serao executados o lint Selene, o typecheck Roblox e os builds dos
projetos default e de testes conforme o fluxo do repositorio. Nao sera criada
uma suite de UI; testes unitarios adicionais so serao necessarios se a
implementacao extrair logica pura reutilizavel.

## Criterios de sucesso

- Cada personagem local ativo possui uma instancia `Sound` por ID configurado.
- `HumanoidRootPart.Running` e destruido durante a configuracao do personagem.
- Os passos customizados sao audiveis apenas pelo jogador local.
- Nenhum passo e iniciado parado ou sem chao.
- O audio anterior nao e escolhido novamente de forma consecutiva quando ha
  mais de uma opcao.
- A quantidade de audios pode ser alterada somente editando `soundIds`.
- O `TankController` continua funcionando sem mudanca no controle de input.
- O respawn limpa o estado anterior e configura os sons uma unica vez.

## Fora de escopo

- Sons diferentes por material do chao.
- Passos audiveis para outros jogadores.
- Marcadores de animacao ou substituicao de animacoes.
- Particulas, decals ou efeitos visuais de poeira.
- Interface para editar IDs durante o jogo.
- Alteracoes no servidor ou em remotes.

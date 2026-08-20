# Design: Iluminacao do Tank Controller

Data: 2026-08-20
Status: Aprovado pelo usuario para especificacao

## Objetivo

Adicionar uma iluminacao de lanterna a cada personagem controlado pelo tank
controller. A lanterna deve ser visivel para todos os jogadores e permanecer
ligada enquanto o personagem existir. Uma segunda luz, posicionada pouco a
frente do personagem, deve simular a reflexao da lanterna no proprio corpo.

## Decisoes aprovadas

| Tema | Decisao |
|---|---|
| Visibilidade | As luzes sao criadas no servidor e replicadas para todos |
| Estado | `SpotLight` e `PointLight` permanecem sempre habilitadas |
| Lanterna | `SpotLight` parentado diretamente no `HumanoidRootPart` |
| Reflexao | `PointLight` parentado em um `Attachment` dentro do `HumanoidRootPart` |
| Direcao | O spotlight usa a face frontal do `HumanoidRootPart` |
| Posicao da reflexao | O attachment usa uma posicao local configuravel no modulo |
| Configuracao | Propriedades das luzes ficam em constantes locais do service |
| Controle | `TankController` continua responsavel apenas pelo movimento |
| Testes | Nao criar testes unitarios novos para essa funcionalidade |

## Arquitetura

```text
Server.init
  -> CharacterLightService.start
       -> Players.PlayerAdded
       -> Player.CharacterAdded
            -> HumanoidRootPart
                 -> TankFlashlight (SpotLight)
                 -> TankLightAttachment (Attachment)
                      -> TankBodyLight (PointLight)
```

O novo modulo `src/server/player/CharacterLightService.luau` sera um service
com `start` e `stop`, seguindo o padrao dos services existentes. Ao iniciar,
ele conecta novos jogadores e personagens, alem de configurar personagens que
ja estejam presentes. Cada personagem recebe um conjunto de luzes criado pelo
servidor, garantindo replicacao para os demais clientes.

O `src/client/player/TankController.luau` nao sera usado para criar as luzes:
objetos criados por ele no cliente nao seriam replicados para todos. O modulo
continuara cuidando apenas dos inputs, da orientacao e do movimento do tanque.

## Configuracao

As constantes ficam no topo de `CharacterLightService.luau`, proximas da
criacao dos objetos, para permitir ajuste visual sem alterar o fluxo do
service. O conjunto inclui:

- `SPOTLIGHT_ENABLED`
- `SPOTLIGHT_COLOR`
- `SPOTLIGHT_BRIGHTNESS`
- `SPOTLIGHT_RANGE`
- `SPOTLIGHT_ANGLE`
- `SPOTLIGHT_SHADOWS`
- `SPOTLIGHT_FACE`
- `BODY_LIGHT_ENABLED`
- `BODY_LIGHT_COLOR`
- `BODY_LIGHT_BRIGHTNESS`
- `BODY_LIGHT_RANGE`
- `BODY_LIGHT_SHADOWS`
- `BODY_LIGHT_ATTACHMENT_POSITION`

Os valores iniciais serao uma luz branca levemente quente, com alcance e
brilho maiores no `SpotLight`, alcance curto e brilho menor no `PointLight`, e
o attachment deslocado no eixo frontal local do root, usando coordenadas
negativas em `Z`.

## Ciclo de vida

1. `start` retorna imediatamente se o service ja estiver iniciado.
2. Para cada jogador, o service conecta `CharacterAdded` e configura o
   personagem atual, se houver.
3. Ao receber um personagem, o service localiza o `HumanoidRootPart` e cria ou
   reutiliza os objetos reservados pelos nomes `TankFlashlight`,
   `TankLightAttachment` e `TankBodyLight`.
4. Se o service for iniciado novamente sobre o mesmo personagem, a operacao e
   idempotente e nao cria duplicatas.
5. `stop` desconecta as conexoes de jogadores e personagens e marca o service
   como parado. Os objetos pertencem ao personagem e acompanham sua destruicao
   no respawn.

Se o root ainda nao existir quando o personagem for recebido, a configuracao
aguarda o `HumanoidRootPart`. Se o personagem for removido durante essa espera,
o setup nao deve deixar conexoes ou instancias fora do personagem. Objetos com
os nomes reservados serao reutilizados apenas quando tiverem a classe esperada;
um objeto conflitante com o mesmo nome pode ser substituido pelo service.

## Integracao

Em `src/server/init.server.luau`, exigir o novo modulo, criar sua instancia e
chamar `start` junto dos demais services do servidor. Nenhum remote ou mudanca
no contrato compartilhado sera necessario.

## Verificacao

Nao serao adicionados testes unitarios. A validacao da mudanca sera feita por:

- lint Selene nos fontes existentes;
- typecheck Roblox nos diretorios cobertos pelo projeto de teste;
- builds dos projetos default e de testes com Rojo.

## Criterios de sucesso

- Cada personagem ativo possui exatamente um conjunto das tres instancias
  reservadas para iluminacao.
- O `SpotLight` e filho direto do `HumanoidRootPart` e acompanha sua frente.
- O `PointLight` e filho do `Attachment`, que e filho do `HumanoidRootPart`.
- As duas luzes iniciam habilitadas e sao visiveis para todos os jogadores.
- A posicao do attachment e todas as propriedades visuais relevantes podem
  ser ajustadas alterando constantes no modulo.
- O respawn recria o conjunto sem duplicacao.
- O `TankController` continua funcionando sem alterar seu controle de input.

## Fora de escopo

- Alternar a lanterna por tecla ou outro input.
- Interface ou configuracao em atributos do personagem.
- Remotes para solicitar a criacao das luzes.
- Alteracoes na matematica ou no ciclo de input do `TankController`.
- Novos testes unitarios para a funcionalidade.

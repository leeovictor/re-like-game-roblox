# Design: Ultimo Shot Fora das Zonas da Camera

Data: 2026-08-20
Status: Aprovado pelo usuario para especificacao

## Objetivo

Evitar que o sistema de camera aplique o shot padrao quando o jogador atravessa
um espaco entre zonas. Fora de uma zona, o controller deve manter o ultimo shot
que estava ativo. O shot padrao continua sendo usado somente quando o controller
ainda nao aplicou nenhum shot, como na inicializacao fora de qualquer zona.

## Decisoes aprovadas

| Tema | Decisao |
|---|---|
| Estado temporal | Mantido pelo `CameraController`, usando `currentShotId` existente |
| Resultado fora de zona | `CameraResolver:resolve` retorna `nil` |
| Fallback inicial | `config.defaultShotId` quando ainda nao ha shot ativo |
| Fallback apos zona | `currentShotId` permanece ativo fora de todas as zonas |
| Reinicializacao | `stop()` limpa `currentShotId`; uma nova inicializacao pode usar o padrao |
| Configuracao | Nenhum atributo, shot ou tipo de zona novo |

## Arquitetura

```text
CameraController.update
  -> CameraResolver.resolve(position)
       -> shotId da primeira zona que contem a posicao
       -> nil quando nenhuma zona contem a posicao
  -> escolhe shot da zona, currentShotId ou defaultShotId
  -> aplica CFrame/FOV somente quando o shot efetivo muda
```

O resolver continua responsavel apenas pela consulta espacial e pela ordem das
zonas. O controller continua responsavel pelo shot aplicado e passa a tratar a
ausencia de zona sem sobrescrever seu estado atual.

## Alteracoes de contrato

Em `src/shared/camera/CameraResolver.luau`:

- Alterar o tipo de retorno de `resolve` para `CameraConfig.ShotId?`.
- Manter o retorno do `shotId` da zona quando houver uma zona correspondente.
- Substituir o retorno de `config.defaultShotId` por `nil` quando nao houver zona.
- Manter todas as validacoes de configuracao existentes.

Em `src/client/camera/CameraController.luau`:

- Guardar o resultado do resolver como `zoneShotId`.
- Escolher `zoneShotId or self.currentShotId or self.config.defaultShotId`.
- Continuar validando a existencia do shot antes de aplica-lo.
- Nao alterar o comportamento de `start`, `stop`, `Focus`, CFrame ou FOV fora
  dessa decisao.

## Fluxos

### Inicializacao fora das zonas

1. O resolver retorna `nil`.
2. `currentShotId` ainda e `nil`.
3. O controller escolhe `config.defaultShotId`.
4. O shot padrao e aplicado e passa a ser o shot atual.

### Entrada em uma zona

1. O resolver retorna o `shotId` da zona.
2. O controller compara com `currentShotId`.
3. Se for diferente, aplica CFrame e FOV da zona.
4. O novo shot passa a ser `currentShotId`.

### Saida para um espaco sem zona

1. O resolver retorna `nil`.
2. O controller encontra `currentShotId` preenchido.
3. O controller escolhe o shot atual, sem aplicar o shot padrao.
4. CFrame, FOV e `currentShotId` permanecem inalterados.

### Parada e novo inicio

`stop()` continua limpando `currentShotId`. Se o controller for iniciado
novamente fora de uma zona, o fluxo de inicializacao usa o shot padrao, pois nao
existe um shot anterior naquela execucao.

## Testes

Em `tests/shared/camera/CameraResolver.spec.luau`:

- Atualizar o caso de posicao fora das zonas para esperar `nil`.
- Manter os casos de zona, fronteira compartilhada, rotacao, ordenacao e
  validacao de configuracao.

Em um novo teste client-side do `CameraController`:

- Criar uma configuracao com shot padrao e uma zona.
- Verificar que o controller inicia fora da zona usando o shot padrao.
- Mover o personagem para dentro da zona e verificar a troca para o shot da
  zona.
- Mover o personagem para fora da zona e verificar que o ultimo shot continua
  ativo em vez do shot padrao.
- Parar o controller e limpar conexoes, estado de camera e fixtures no teardown.

## Criterios de sucesso

- Espacos entre zonas nao fazem a camera voltar ao shot padrao.
- O primeiro shot continua sendo o shot padrao quando nao ha zona ativa.
- Entrar em uma zona continua trocando para o shot configurado nela.
- O resolver nao passa a manter estado entre chamadas.
- Selene, typecheck, builds Rojo e suites TestEZ permanecem sem falhas.

## Fora de escopo

- Alterar a prioridade ou a ordenacao das zonas.
- Criar transicoes, interpolacoes ou blending entre shots.
- Persistir o ultimo shot entre reinicios ou sessoes.
- Alterar a autoria da configuracao em `Workspace.CameraSystem`.

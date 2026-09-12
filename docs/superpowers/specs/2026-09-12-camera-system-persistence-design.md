# Camera System: Dados Serializados e Parts Efemeras

Esta spec complementa `2026-08-17-camera-system-plugin-design.md`. Ela mantem o
objetivo e o fluxo do plugin, mas muda a fonte de verdade persistida e o ciclo
de vida das parts.

## Objetivo

Manter `Workspace.CameraSystem` limpo enquanto o editor do plugin esta
desativado. A configuracao autoral e persistida em
`Workspace.CameraSystem.Data` (um `StringValue` com JSON versionado) e as parts
de `Shots`/`Zones` passam a existir apenas enquanto o editor esta ativo (ou em
places legados que ainda nao foram normalizados).

## Fonte De Verdade

- `CameraSystem.Data` (`StringValue`, JSON com `version = 1`) e a fonte de
  verdade persistida.
- As parts de `Shots`/`Zones` sao artefatos efemeros de edicao.
- O runtime `CameraMapReader` prefere as parts quando existem (edicao/legado) e
  cai para `Data` quando as pastas estao vazias.
- O fallback legado de BaseParts permanece ate nao existir mais place no formato
  antigo.

## Estrutura Persistida

```text
Workspace
└── CameraSystem [Folder]              -- DefaultShotId [string]
    ├── Data [StringValue]              -- JSON versionado (fonte de verdade)
    ├── Shots [Folder]                  -- vazia fora do editor
    └── Zones [Folder]                  -- vazia fora do editor
```

Formato do JSON (`version = 1`):

```json
{
  "version": 1,
  "defaultShotId": "Center",
  "shots": [
    { "name": "Center", "cframe": [12 numeros], "fieldOfView": 55 }
  ],
  "zones": [
    { "name": "CenterZone", "cframe": [12 numeros], "size": [x, y, z], "shotId": "Center", "order": 1 }
  ]
}
```

O codec vive em `src/shared/camera/CameraSystemData.luau` e e compartilhado com
o plugin via mapeamento do Rojo (`CameraSystemData` e irmao da Folder `camera`).
O codec nao depende de `Workspace`: `capture` recebe a pasta raiz.

## Ciclo De Vida Do Plugin

- **Carga:** se `Workspace.CameraSystem` existir e for `Folder`, o plugin
  normaliza o estado inativo. Se houver parts, captura para `Data` e, somente em
  caso de sucesso, destroi as parts. Se a raiz nao existir, nada e criado.
- **Ativar o editor:** le `Data` quando as pastas estao sem `BasePart`,
  materializa as parts e padroniza a aparencia de edicao (`showParts`).
- **Desativar o editor:** desconecta listeners, limpa o preview, captura as
  parts para `Data`, destroi as parts e limpa a selecao do widget. Se a
  persistencia falhar, as parts permanecem e um `warn` e emitido.
- **Descarregar o plugin:** `destroyEditor` reutiliza `deactivateEditor`, entao
  o mesmo fluxo de persistencia/destruicao roda no `Unloading` e no fechamento
  do dock.

Validacao:

- Estrutural: no codec (`capture`/`decode`). Filho nao-`BasePart` em
  `Shots`/`Zones` e numero nao finito sao erros estruturais.
- Semantica: no `CameraMapReader` e em `CameraSystemModel.validate()` (FOV,
  `DefaultShotId`, referencia de `ShotId`, `Order`, `Size`).

## Fail-Safe

- `capture` e leniente com valores: grava `0`/`""` quando o atributo esta
  ausente ou invalido, para nao perder o estado.
- Falha estrutural mantem as parts (a remocao so acontece apos persistencia bem
  sucedida).
- Estado semanticamente invalido (ex.: zona sem `ShotId`) ainda e persistido e
  as parts sao removidas; o erro reaparece no widget/runtime ao rematerializar.

## Precedencia Do Reader

`CameraMapReader.read` segue a ordem:

1. Se houver `BasePart` direto em `Shots` ou `Zones`, le as parts via
   `CameraSystemData.capture` (fluxo legado/edicao).
2. Caso contrario, aguarda `CameraSystem.Data`
   (`rootFolder:WaitForChild(CameraSystemData.DATA_NAME)`), exige `StringValue`
   e decodifica.
3. `toRuntimeConfig` aplica a validacao semantica e devolve
   `CameraConfig.Config`.

A assinatura publica `read(rootName: string): CameraConfig.Config` e os tipos de
`CameraConfig` nao mudam.

## Waypoints E Undo

`materialize` e `destroyParts` registram waypoints no `ChangeHistoryService`,
como as demais mutacoes. Um undo pos-desativacao pode restaurar parts enquanto
`Data` existe; a proxima normalizacao (carga do plugin ou desativacao) resolve o
estado, preferindo as parts quando elas existirem.

## Fora De Escopo

- Persistencia via `plugin:SetSetting` (os dados sao por lugar).
- Materializar parts automaticamente ao iniciar o Play.
- Remover o fallback legado de BaseParts.
- Hot reload da configuracao durante o playtest.
- Migrar automaticamente configuracao de `CameraConfig.luau` estatico.
- Marker de versao embutido no proprio plugin: a versao e identificada pelo nome
  do arquivo arquivado.
- Politica de migracao quando `version` mudar: o `decode` rejeita versao
  desconhecida e a migracao fica para um plano futuro.

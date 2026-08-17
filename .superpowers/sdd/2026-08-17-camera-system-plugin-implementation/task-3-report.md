# Task 3 Report

## Implementacao

- Criado `plugin.project.json` como projeto Rojo separado, sem alterar
  `default.project.json`.
- Criado `plugin/camera/CameraSystemModel.luau` com `--!strict`.
- O modelo aceita `Workspace`, `Selection` e `ChangeHistoryService` injetados.
- A hierarquia `CameraSystem/Shots/Zones` e criada ou reutilizada sem remover
  filhos ou atributos existentes.
- Shots e zonas sao listados apenas quando sao filhos diretos `BasePart`, com
  ordenacao deterministica.
- Operacoes de criacao e mutacao persistida validam posse, atributos, FOV,
  tamanho e referencias, e registram waypoints antes e depois da mutacao.
- `validate()` acumula mensagens de erro sem lancar excecoes.

## Verificacao

Comandos executados a partir da raiz do repositorio:

```text
selene --config selene.roblox.toml plugin
```

Resultado: sucesso, `0 errors`, `0 warnings`, `0 parse errors`.

```text
luau-lsp analyze --platform roblox --settings typecheck/luau-lsp.roblox.json --base-luaurc typecheck/roblox.luaurc --definitions @roblox=typecheck/globalTypes.None.d.luau --formatter gnu plugin
```

Resultado: sucesso, sem diagnosticos de tipo. A saida informou que o sourcemap
foi desabilitado, conforme esperado para a arvore independente do plugin.

```text
rojo build plugin.project.json -o /tmp/camera-system-plugin.rbxmx
```

Resultado: sucesso, pacote gerado em `/tmp/camera-system-plugin.rbxmx`.

```text
```

Resultado: sucesso, sem whitespace errors.

## Testes

Nao foram adicionados testes ao repositorio porque o escopo da tarefa limita os
arquivos de implementacao e o modelo depende diretamente das APIs de instancia
do Roblox Studio. A verificacao executada foi lint, typecheck Roblox e build
Rojo do projeto separado.

## Concerns

- `plugin/init.plugin.luau`, preview e widget permanecem fora do escopo desta
  tarefa. Portanto, o build do projeto e valido, mas ainda nao representa um
  plugin executavel no Studio ate a implementacao do ponto de entrada.
- As definicoes Roblox versionadas nao expoem `SetWaypoint` nem `Selection:Set`;
  o modelo usa adapters tipados estreitos para essas APIs reais, sem alterar as
  definicoes globais.

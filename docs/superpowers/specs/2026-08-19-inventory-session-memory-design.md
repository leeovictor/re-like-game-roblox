# Inventário Volátil por Sessão

## Objetivo

Remover a persistência do inventário do jogador. O inventário deve existir
somente enquanto o jogador estiver conectado ao servidor; ao entrar, começa
vazio, e ao sair ou reiniciar o servidor é descartado.

## Decisão

O `InventoryService` será o proprietário do estado em memória por `Player`.
`InventoryService.new()` não receberá mais uma dependência de persistência.
Essa é a opção mais simples porque mantém a autoridade do inventário no serviço
e não preserva abstrações que deixaram de ter consumidores.

As alternativas rejeitadas são:

- manter `MemoryPersistence` como uma abstração sem DataStore, o que preservaria
  complexidade sem benefício atual;
- guardar o estado como atributos ou objetos no `Player`, o que misturaria o
  modelo de domínio com instâncias Roblox e aumentaria a superfície replicável.

## Arquitetura e Fluxo

`InventoryService` manterá uma tabela privada de snapshots por jogador e usará
`InventoryStore.copyState` para preservar o isolamento das referências.

No `PlayerAdded`, o serviço deverá:

1. criar `InventoryStore.defaultInventory()`;
2. guardar o estado em memória;
3. disparar `InventoryChanged` com uma cópia;
4. chamar `player:LoadCharacterAsync()`.

No `PlayerRemoving`, o serviço deverá remover o jogador da tabela, sem executar
qualquer operação de salvamento.

A API de mutações e consulta permanece inalterada, incluindo `addInstance`,
`removeQuantity`, `equip`, `getSnapshot` e o callback `GetInventory`. O cliente
continua recebendo snapshots por remotes, mas eles representam apenas o estado
da sessão atual.

O `init.server.luau` deverá construir o serviço diretamente e não selecionar
backend com `RunService`.

## Limpeza de Código

Remover:

- `src/server/inventory/persistence/MemoryPersistence.luau`;
- `src/server/inventory/persistence/DataStorePersistence.luau`;
- `tests/server/inventory/MemoryPersistence.spec.luau`;
- tipos, retry/backoff, carregamento assíncrono e salvamento de inventário em
  `InventoryService`;
- `InventoryStore.serialize` e `InventoryStore.deserialize`, incluindo o parser
  JSON e helpers usados somente por ele;
- testes de serialização, desserialização e JSON em
  `tests/server/inventory/InventoryStore.spec.luau`.

Atualizar `docs/inventory-architecture.md` para remover o subsistema de
persistência, as arestas de `load/save`, o fluxo de carregamento persistente e
as referências a dados persistíveis. A documentação deve descrever o estado
como volátil e limitado à sessão.

## Testes e Verificação

Os testes restantes de `InventoryStore` devem continuar cobrindo estado padrão,
cópia, mutações, equipagem, quantidades e validação de itens.

A verificação integrada deverá confirmar em duas rodadas limpas de Play no
Roblox Studio que:

- o jogador recebe um inventário vazio ao entrar;
- mutações do inventário funcionam durante a sessão;
- o personagem é carregado após a inicialização do estado;
- sair do jogador não tenta salvar dados nem produz erro de DataStore.

Também devem passar o lint, o typecheck Roblox e os builds dos projetos padrão
e de testes definidos em `AGENTS.md`.

## Critérios de Aceitação

- Nenhum código de produção ou documentação de arquitetura/runtime menciona
  `DataStore`, `MemoryPersistence`, `DataStorePersistence` ou operações
  `load/save` do inventário; esta especificação é o registro da mudança e pode
  mencionar os componentes removidos.
- O inventário não sobrevive à saída do jogador nem à reinicialização do
  servidor.
- A API de gameplay e os remotes existentes continuam funcionando sem
  alteração de contrato.
- Os testes, lint, typecheck e builds passam.

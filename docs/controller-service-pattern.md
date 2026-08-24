# Padrao de Controllers e Services

Este documento define o padrao para controllers e services com estado de
runtime no projeto Roblox. Consulte-o antes de criar ou alterar esses modulos.

## 1. Escopo e Modulos Puros

Um modulo puro transforma entradas em saidas sem manter estado de runtime. Ele
pode ser importado diretamente e usado como uma biblioteca compartilhada. Por
exemplo, `TankControlMath` e um modulo puro e pode ser importado diretamente
por `TankController`.

Um controller ou service coordena estado mutavel, conexoes, tarefas ou recursos
de uma sessao. Ele deve ser criado como uma instancia por meio de `new`, e o
estado de cada sessao deve pertencer a essa instancia.

## 2. Construcao e Dependencias

Use `new()` quando o controller nao possuir dependencias externas. Use
`new(dependencies)` quando possuir dependencias de runtime, sempre com uma
tabela nomeada:

```luau
local tankController = TankController.new()
local dialogueController = DialogueController.new({
	movement = tankController,
})
```

As dependencias devem ser armazenadas na instancia e ter contratos tipados.
Tipos compartilhados devem ser exportados pelo modulo dono e importados pelos
consumidores. Nao redeclare localmente um contrato que ja existe em outro
modulo.

## 3. Estado por Instancia

Todo estado mutavel de runtime deve ser criado em `new` e armazenado na
instancia. Nao mantenha em escopo de modulo estado como `started`, contadores,
geracoes, callbacks ativos, conexoes ou sinais que deveriam ser independentes
entre duas instancias.

Campos mutaveis de uma instancia nao devem ser compartilhados por meio de
tabelas reutilizadas entre chamadas de `new`.

## 4. Metodos e Callbacks

Metodos de instancia usam `:` e declaram `self` no contrato e na implementacao:

```luau
function TankController.start(self: TankController): ()
	-- inicia os recursos desta instancia
end

tankController:start()
```

Callbacks registrados em servicos Roblox devem usar closures quando precisam
preservar o receptor. Nao passe diretamente um metodo de instancia que espera
`self`:

```luau
ContextActionService:BindActionAtPriority(
	ACTION_FORWARD,
	function(actionName, inputState)
		return self:handleInput(actionName, inputState)
	end,
	false,
	priority,
	Enum.KeyCode.W
)
```

## 5. Lifecycle

`start` e `stop` devem ser idempotentes. Uma segunda chamada nao deve duplicar
bindings, conexoes ou tarefas. `stop` deve desconectar recursos criados pela
instancia, cancelar tarefas quando necessario, restaurar propriedades que ela
alterou e invalidar callbacks ou geracoes antigas.

## 6. Composition Root

O composition root cria as instancias, conecta suas dependencias e registra os
handlers. Atualmente, esse papel pertence a `src/client/init.client.luau`.

Controllers nao devem importar outro controller concreto apenas para obter um
singleton operacional. A composicao deve fornecer a instancia necessaria:

```luau
local tankController = TankController.new()
local dialogueController = DialogueController.new({
	movement = tankController,
})

local showDialogue = function(text, callback)
	dialogueController:show(text, callback)
end
```

O composition root deve preservar a ordem de inicializacao: crie as
dependencias antes dos consumidores, inicie os controllers antes de registrar
handlers que dependem deles e passe referencias explicitas para a UI.

## 7. Specs e Fixtures

Cada spec deve criar fixtures isoladas em `beforeEach`. Controllers, Instances,
conexoes e estado mutavel devem ser destruidos, parados ou desconectados em
`afterEach`. Nao reutilize uma instancia entre testes.

As assertions devem testar o contrato observavel, nao detalhes privados de
implementacao. Prefira fakes que sigam os contratos tipados e teste invariantes
de isolamento, lifecycle, callbacks e liberacao de recursos.

## 8. Anti-padroes

Evite os seguintes padroes:

- singleton oculto retornado diretamente por `require` para operacoes de runtime;
- controller default criado dentro de outro controller ou handler;
- lookup dinamico de outra dependencia durante a operacao;
- metodos passados como callbacks sem closure quando exigem `self`;
- estado mutavel global compartilhado entre instancias;
- injecao desnecessaria de servicos Roblox como `Players`, `RunService` ou
  `ContextActionService` quando a decisao do projeto e usa-los diretamente;
- redeclaracao local de tipos que ja sao exportados por um modulo dono.

Controllers existentes fora do escopo de uma migracao nao precisam ser
refatorados apenas para cumprir este documento. Ao alterar um controller, siga
este padrao para a parte modificada e preserve contratos de comportamento que
nao fazem parte da mudanca.

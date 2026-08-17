# Design: Arquitetura de Instâncias e Uso de Items

Data: 2026-08-17  
Status: Aprovado na conversa; aguardando revisão do documento

## Objetivo

Evoluir o protótipo de inventário, que hoje armazena somente uma lista de
`ItemId`, para suportar items concretos com atributos próprios e comportamentos
variados.

O sistema deverá suportar, entre outros exemplos:

- armas individuais com dano, capacidade e munição carregada diferentes;
- items de cura individuais com valores de cura diferentes;
- munição empilhável com quantidade;
- chaves ou outros items com atributos que restringem sua compatibilidade com
  um alvo;
- uso iniciado pela UI, como selecionar um kit médico e pressionar `Usar`;
- uso iniciado por uma interação do mundo, em que um sistema externo fornece o
  contexto e o inventário procura uma instância compatível.

O escopo é o modelo de dados, a arquitetura do inventário e os contratos de
consulta/uso. Sistemas de portas, vida, combate e equipamento serão consumidores
externos e não serão implementados nesta especificação.

## Contexto atual

O projeto já possui:

- `src/shared/inventory/items.luau` com catálogo e tipos básicos;
- `InventoryStore` com lógica pura, serialização e cópia imutável;
- `InventoryService` autoritativo por jogador, persistência e `InventoryChanged`;
- `PickupService` que adiciona um `itemId` ao inventário;
- `InventoryController` que replica snapshots para o cliente;
- UI que lista os `itemId`s do snapshot.

`torch`, `ration` e `crystal` são dados demonstrativos do protótipo básico e
não fazem parte do catálogo final. Não haverá requisito de compatibilidade ou
migração específica para esses items. O novo modelo poderá ser introduzido
diretamente com o schema final, mantendo `version` para futuras mudanças reais.

## Decisão arquitetural

Será usada uma abordagem híbrida:

1. o inventário armazena instâncias concretas;
2. o catálogo compartilhado declara capacidades e metadados estáticos;
3. atributos authored pelo mapa ficam na instância;
4. handlers server-side implementam as regras das capacidades;
5. `ItemUseService` coordena consultas, validação e uso;
6. sistemas de domínio aplicam os efeitos reais.

Essa abordagem evita dois extremos:

- código acoplado a cadeias de `if itemId == ...`;
- um interpretador totalmente data-driven que tentaria representar todas as
  regras de combate, cura e interação em dados genéricos.

O catálogo não conterá funções. Funções não serão serializadas, persistidas ou
replicadas como parte de `ItemDefinition`.

## Modelo de dados

### Definição estática

Uma definição identifica o tipo de item e declara os contratos de comportamento:

```lua
export type ItemDefinition = {
    id: ItemId,
    name: string,
    category: string,
    stackable: boolean,
    capabilities: { string },
}
```

Exemplos conceituais:

```lua
items["handgun"] = {
    id = "handgun",
    name = "Handgun",
    category = "weapon",
    stackable = false,
    capabilities = { "equip", "fire", "reload" },
}

items["handgun_ammo"] = {
    id = "handgun_ammo",
    name = "Munição de Handgun",
    category = "ammunition",
    stackable = true,
    capabilities = { "reload-ammo" },
}

items["medkit"] = {
    id = "medkit",
    name = "Kit Médico",
    category = "consumable",
    stackable = false,
    capabilities = { "consume", "heal" },
}

items["iron_key"] = {
    id = "iron_key",
    name = "Chave de Ferro",
    category = "key",
    stackable = false,
    capabilities = { "unlock" },
}
```

`category` é classificação geral para filtros e apresentação. `capabilities`
declara operações das quais o item pode participar. Nenhum dos dois executa a
operação.

### Instância concreta

O inventário persistirá instâncias, não somente IDs:

```lua
export type ItemAttribute = string | number | boolean
export type ItemAttributes = { [string]: ItemAttribute }

export type ItemInstance = {
    uid: string,
    itemId: ItemId,
    quantity: number?,
    attributes: ItemAttributes?,
}
```

Exemplos:

```lua
{
    uid = "handgun-007",
    itemId = "handgun",
    attributes = {
        damage = 18,
        magazineSize = 8,
        loadedAmmo = 5,
        ammoType = "handgun_ammo",
    },
}
```

```lua
{
    uid = "medkit-001",
    itemId = "medkit",
    attributes = {
        healAmount = 25,
    },
}
```

```lua
{
    uid = "handgun-ammo-stack-001",
    itemId = "handgun_ammo",
    quantity = 24,
}
```

```lua
{
    uid = "iron-key-042",
    itemId = "iron_key",
    attributes = {
        opensDoorId = "north-door",
    },
}
```

`uid` identifica o item concreto e será usado pela UI, pelo equipamento e pelas
operações de uso. Uma UI nunca deve identificar uma instância somente pelo
`itemId`, porque duas instâncias do mesmo tipo podem possuir atributos diferentes.

O estado persistido completo terá esta forma conceitual:

```lua
export type InventoryState = {
    version: number,
    items: { ItemInstance },
    equipped: { [string]: string },
}
```

`equipped` mapeia slots para `uid`s. O equipamento aponta para uma instância
concreta, não para um tipo de item.

### Empilhamento

Items empilháveis, como munição, usarão uma instância com `quantity`.

Items individuais, como armas, chaves e kits com atributos variáveis, não serão
empilhados.

Duas pilhas só poderão ser combinadas se forem equivalentes em `itemId` e em
todos os atributos relevantes. A primeira versão limitará o empilhamento a
items sem atributos variáveis, evitando ambiguidades. Items com valores authored
diferentes permanecerão em instâncias separadas.

### Atributos

Os atributos são dados da instância, não capacidades. A capacidade `heal`
declara que o item pode participar de uma cura; `healAmount` informa quanto
essa instância pode curar.

Handlers server-side validam os atributos que entendem, incluindo tipo, faixa e
compatibilidade. A factory pode validar tipos primitivos e regras básicas, mas
não deve conhecer a semântica completa de cada capacidade.

Inicialmente, os atributos podem ser replicados no snapshot para apresentação.
Se o jogo passar a ter atributos secretos, o estado poderá ser dividido em
projeções públicas e privadas sem alterar a identidade da instância.

## Componentes e responsabilidades

```text
src/shared/inventory/items.luau
  tipos, catálogo, categorias e capacidades

src/server/inventory/InventoryStore.luau
  operações puras, validação estrutural e serialização

src/server/inventory/InventoryService.luau
  estado autoritativo por jogador, persistência e replicação

src/server/items/ItemInstanceFactory.luau
  criação e validação inicial de instâncias do mundo

src/server/items/ItemBehaviorRegistry.luau
  registro de handlers server-side por capacidade

src/server/items/ItemUseService.luau
  consultas, validação final, concorrência e coordenação do uso

src/server/pickups/PickupService.luau
  transferência da instância criada no mapa para o inventário

src/server/<domain>/...
  aplicação de efeitos de vida, combate, equipamento ou outros domínios
```

### `InventoryStore`

Permanece sem dependências de APIs Roblox e continua testável no Lune. Deve
operar sobre instâncias e produzir novos estados em vez de mutar snapshots
compartilhados.

Operações conceituais:

```lua
addInstance(state, instance) -> InventoryState?
addQuantity(state, uid, quantity) -> InventoryState?
findInstance(state, uid) -> ItemInstance?
removeInstance(state, uid) -> InventoryState?
removeQuantity(state, uid, quantity) -> InventoryState?
equip(state, slot, uid) -> InventoryState?
serialize(state) -> string
deserialize(serialized) -> InventoryState?
```

Ele valida IDs conhecidos, quantidades, referências estruturais e cópias. Não
conhece jogadores, remotes, Humanoids, portas ou armas do mundo.

### `InventoryService`

É o dono do estado por jogador e do contrato de autoridade. Deve expor métodos
públicos para outros serviços, sem entregar a tabela privada de estados.

Operações conceituais:

```lua
addInstance(player, instance) -> boolean
addQuantity(player, itemId, quantity) -> boolean
find(player, query) -> ItemInstance?
removeInstance(player, uid) -> boolean
removeQuantity(player, uid, quantity) -> boolean
equip(player, uid, slot) -> boolean
getSnapshot(player) -> InventoryState?
```

Cada mutação bem-sucedida substitui o estado privado e replica um novo
`InventoryChanged`. O cliente nunca altera o inventário diretamente.

### `ItemInstanceFactory`

A factory será usada pelo servidor ao criar loot e pickups. Ela:

- valida que o `itemId` existe;
- gera um `uid` único;
- valida `quantity` básica;
- valida tipos primitivos dos atributos;
- rejeita combinações impossíveis de item empilhável/individual;
- retorna uma instância pronta para ser transferida ao inventário.

A factory não deve aceitar a instância completa enviada pelo cliente. Pickups
authored pelo mapa são criados no servidor e o cliente só interage com o objeto
já existente.

### `ItemBehaviorRegistry`

O registry associa capacidades a handlers:

```lua
register("heal", HealingHandler)
register("equip", EquipmentHandler)
register("reload", ReloadHandler)
register("unlock", UnlockCapabilityHandler)
```

Handlers são código server-side. Eles recebem a instância confiável, o jogador e
um contexto de uso. Não ficam armazenados no catálogo nem na persistência.

### `ItemUseService`

Coordena a intenção de uso, mas não implementa vida, combate ou portas. Ele:

1. encontra capacidades no catálogo;
2. localiza instâncias do jogador;
3. chama o handler para validar contexto e atributos;
4. impede operações concorrentes;
5. coordena a aplicação do efeito externo;
6. confirma a mutação do inventário;
7. retorna um resultado estável.

## Contrato de uso

O contrato aceita tanto uma instância escolhida pela UI quanto uma busca por
compatibilidade iniciada por um sistema do mundo:

```lua
export type UseContext = { [string]: unknown }

export type UseRequest = {
    capability: string,
    context: UseContext,
    itemUid: string?,
}

export type UseResult = {
    success: boolean,
    reason: string?,
    itemUid: string?,
    consumed: boolean?,
    effect: { [string]: unknown }?,
}
```

O nome `itemUid` representa um item preferido. Quando omitido, o serviço procura
uma instância compatível. Mesmo quando informado, o servidor deve revalidar a
instância e a capacidade.

### Consulta sem mutação

```lua
itemUseService:findCompatibleItem(player, {
    capability = "unlock",
    context = {
        targetId = "north-door",
    },
})
```

Essa consulta apenas filtra instâncias e chama `canUse`. Não remove items nem
aplica efeitos. O critério principal é a capacidade e a compatibilidade do
handler, não um `if` específico para cada `itemId`.

### Uso com item selecionado

Uma UI que selecionou um kit médico envia uma intenção equivalente a:

```lua
{
    itemUid = "medkit-001",
    capability = "heal",
    context = {
        target = "self",
    },
}
```

O cliente não envia `healAmount` nem a nova vida. O servidor lê `healAmount` da
instância, valida o estado atual do jogador e pede ao serviço de vida que aplique
o efeito.

### Uso por alvo do mundo

Uma interação do mundo pode fornecer somente:

```lua
{
    capability = "unlock",
    context = {
        targetId = "north-door",
    },
}
```

O sistema de portas não é implementado aqui. Ele apenas poderia usar o contrato
para perguntar se há uma instância compatível. A abertura e suas regras ficam no
domínio de portas.

### Handlers

Cada handler possui uma fase sem efeitos colaterais e uma fase de execução:

```lua
canUse(player, instance, context) -> (boolean, string?)
use(player, instance, context) -> UseResult
```

`canUse` verifica atributos, capacidade, contexto e pré-condições sem remover o
item ou aplicar efeitos. `use` é chamado somente depois da validação e coordena
o serviço de domínio apropriado.

Exemplos de dependências:

```text
HealingHandler  -> HealthService
EquipmentHandler -> EquipmentService
ReloadHandler -> WeaponService
```

O inventário fornece a posse e a mutação; o domínio fornece o efeito.

## Fluxos principais

### Pickup authored pelo mapa

```text
servidor cria ItemInstance com uid, itemId e atributos
  -> PickupService associa a instância ao pickup
  -> jogador interage com o pickup
  -> InventoryService:addInstance valida e transfere a instância
  -> pickup é destruído somente após sucesso
  -> InventoryChanged replica o snapshot
```

O pickup não interpreta `damage`, `healAmount` ou qualquer outro atributo. Ele
transporta uma instância criada e validada no servidor.

### Kit de cura pela UI

```text
cliente recebe snapshot
  -> jogador seleciona itemUid = medkit-001
  -> jogador pressiona Usar
  -> cliente envia UseRequest(capability = heal, target = self)
  -> servidor verifica posse, capacidade e atributos
  -> HealingHandler valida vida e calcula o efeito
  -> HealthService confirma a cura
  -> InventoryService remove medkit-001
  -> InventoryChanged replica novo snapshot
  -> UseResult e evento opcional informam o feedback
```

Se o jogador estiver com a vida cheia ou a instância não existir, nenhuma
mutação ocorre e o resultado contém uma razão estável, como
`player_at_full_health` ou `invalid_instance`.

### Recarga

```text
cliente ou sistema de arma solicita reload
  -> ItemUseService identifica arma e munição
  -> ReloadHandler valida ammoType e espaço disponível
  -> WeaponService confirma a transferência
  -> InventoryService atualiza loadedAmmo e reduz quantity
  -> snapshot atualizado é replicado
```

A munição só é removida depois que a arma aceita a recarga. Uma transferência
parcial reduz a pilha exatamente pela quantidade transferida.

## Consistência e concorrência

O uso deve ser uma operação autoritativa e revalidada no momento da mutação. Uma
consulta anterior não garante que o item ainda esteja disponível.

A primeira implementação usará um lock curto por jogador:

```text
receber UseRequest
  -> rejeitar ou aguardar se o jogador já está em uso
  -> validar instância, capacidade e contexto
  -> executar efeito de domínio
  -> confirmar mutações do inventário
  -> replicar snapshot
  -> liberar lock
```

Handlers não devem produzir mutações parciais. Serviços de domínio devem expor
operações que confirmem aceitação do efeito, como `tryHeal` ou `tryReload`. Um
sistema transacional genérico ou `UsePlan` fica reservado para quando surgirem
ações que exijam coordenação mais complexa.

## Persistência e validação

O schema persistido conterá:

- `version`;
- lista de `ItemInstance`s;
- `uid`, `itemId`, `quantity` e `attributes` válidos;
- estado mutável das instâncias;
- referências de equipamento.

Ao carregar, o servidor deve rejeitar o snapshot como inválido, sem normalizá-lo
silenciosamente, quando encontrar:

- `itemId` desconhecido;
- `uid` duplicado;
- quantidade zero, negativa ou incompatível;
- atributos com tipos inválidos;
- referências `equipped` para UIDs inexistentes.

Não haverá migração dos items demonstrativos atuais. O schema novo começa com
os items finais do jogo, e `version` prepara migrações futuras.

## Segurança e exposição ao cliente

O servidor é a fonte de verdade para dano, cura, munição, capacidades,
quantidades, posse e resultados. O cliente pode receber atributos para
apresentação, mas não pode alterá-los.

Um futuro sistema de atributos secretos poderá separar uma projeção pública da
representação privada sem mudar `uid` ou `itemId`.

O contrato de uso pode ser exposto por um `UseItem` `RemoteFunction`, adequado
para ações curtas que precisam de resposta imediata. `InventoryChanged` continua
sendo a notificação de estado, e eventos separados podem comunicar feedback
transitório como `ItemUsed`.

## Testes

### Lune

Testar `InventoryStore` e handlers com serviços falsos:

- adicionar e remover uma instância individual;
- preservar UID e atributos;
- criar e reduzir pilhas;
- remover pilha quando chega a zero;
- impedir quantidade negativa;
- impedir agrupamento de instâncias incompatíveis;
- copiar estado sem compartilhar tabelas;
- serializar e desserializar o schema final;
- rejeitar item IDs desconhecidos;
- curar usando o atributo da instância;
- não consumir item com vida cheia;
- rejeitar UID inexistente ou capacidade ausente;
- impedir consumo duplicado concorrente;
- recarregar somente com munição compatível;
- aplicar corretamente recarga parcial.

### Roblox Studio

Validar integração real para:

- criação server-side de pickups com atributos authored;
- transferência da instância para o inventário;
- replicação do novo snapshot;
- uso do kit pela requisição da UI;
- aplicação do efeito pelo sistema de domínio;
- remoção do item após sucesso;
- preservação do item após falha;
- rejeição de payloads adulterados pelo cliente;
- proteção contra duas requisições simultâneas;
- atualização do estado de armas e munição.

## Fora de escopo

- implementação de portas ou chaves no mundo;
- implementação de vida, combate ou armas;
- layout ou redesign da UI;
- catálogo final de items;
- animações, sons e feedback visual específico;
- crafting, trade ou descarte;
- durabilidade, upgrades e modificadores, embora o modelo possa acomodá-los;
- geração final de loot;
- atributos secretos, enquanto não houver necessidade concreta;
- sistema transacional genérico para efeitos distribuídos.

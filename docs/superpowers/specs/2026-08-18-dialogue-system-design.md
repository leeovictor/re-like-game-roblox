# Design: Sistema de Dialogo com Datilografia

Data: 2026-08-18  
Status: Aprovado pelo usuario para especificacao

## Objetivo

Adicionar ao cliente um sistema reutilizavel para exibir mensagens com efeito de
datilografia, perguntas com opcoes e composicao de sequencias por callbacks.

O sistema sera exclusivamente client-side. Ele nao recebera solicitacoes do
servidor nem definira uma API de sequencias; sistemas consumidores poderao
compor chamadas `show` e `ask` quando precisarem de um fluxo com varias etapas.

## Decisoes aprovadas

| Tema | Decisao |
|---|---|
| API | Controlador client-side com `show` e `ask` |
| Sequencias | Composicao por callbacks; sem API dedicada para sequencias |
| Concorrencia | Uma nova chamada substitui o dialogo ativo |
| Cancelamento por substituicao | Callback anterior recebe `nil, "replaced"` |
| Mensagem simples | `F` revela o restante; outro `F` fecha |
| Pergunta | `F` revela o restante; outro `F` confirma a opcao |
| Navegacao | Setas ou `W/S` |
| Cancelamento manual | `Esc` |
| Velocidade | Constante padrao no modulo, sem override por chamada |
| Opcoes | Lista de `{ id, text }` |
| Input durante dialogo | `F`, `Esc`, setas e `W/S` sao consumidos |
| Layout | Texto simples, centralizado horizontalmente na parte inferior |
| Crescimento | Sem altura maxima; novas linhas fazem o bloco crescer para cima |
| Visual das opcoes | Opcao selecionada indicada por `>` |
| Audio e animacoes | Fora de escopo nesta etapa |

## Arquitetura

```text
src/client/dialogue/DialogueController.luau
  API, estado, datilografia, input, substituicao e callbacks

src/client/dialogue/useDialogue.luau
  hook React que observa o estado do controlador

src/client/init.client.luau
  inicia o controlador uma vez

src/client/ui/App.luau
  renderiza o estado de dialogo junto da UI existente

test.project.json
  mapeia o diretorio dialogue para o projeto de testes

tests/client/dialogue/DialogueController.spec.luau
  testa o contrato e o lifecycle do controlador
```

O controlador seguira o padrao dos controladores client-side existentes: possui
`start()` e `stop()` idempotentes, um sinal `changed` e estado privado. Outros
sistemas importam o modulo do controlador e nao precisam conhecer React.

O `App.luau` continuara sendo o unico dono da arvore React. O hook inicia uma
assinatura do sinal ao montar e a desconecta ao desmontar. O controlador nao
criara `ScreenGui`, `Frame` ou `TextLabel` diretamente.

## API publica

```lua
local Dialogue = require(...)

Dialogue.show("Porta trancada", function(_, reason)
    -- reason: "completed", "cancelled" ou "replaced"
end)

Dialogue.ask("Usar Spade Key?", {
    { id = "yes", text = "Sim" },
    { id = "no", text = "Nao" },
}, function(optionId, reason)
    -- optionId e nil quando cancelado ou substituido
end)
```

Os tipos publicos serao equivalentes a:

```lua
export type DialogReason = "completed" | "cancelled" | "replaced"

export type DialogOption = {
    id: string,
    text: string,
}

export type ShowCallback = (value: nil, reason: DialogReason) -> ()
export type AskCallback = (optionId: string?, reason: DialogReason) -> ()

show: (text: string, callback: ShowCallback?) -> ()
ask: (text: string, options: { DialogOption }, callback: AskCallback) -> ()
```

O callback de `show` e opcional para mensagens independentes. O callback de
`ask` e obrigatorio, pois a escolha precisa ser entregue ao sistema que abriu a
pergunta. Ambos sao executados depois de o estado anterior ser limpo.

Uma sequencia nao possui formato especial. O consumidor compoe o proximo passo
no callback do passo atual:

```lua
Dialogue.show("Voce encontrou uma porta.", function(_, reason)
    if reason ~= "completed" then
        return
    end

    Dialogue.ask("Usar Spade Key?", {
        { id = "yes", text = "Sim" },
        { id = "no", text = "Nao" },
    }, function(optionId)
        if optionId == "yes" then
            Dialogue.show("A porta foi aberta.")
        end
    end)
end)
```

## Estado e datilografia

O estado exposto pelo sinal e pelo hook tera a forma conceitual:

```lua
{
    kind = "message" | "question",
    text = "Usar Spade Key?",
    visibleText = "Usar Spade",
    isTyping = true,
    options = {
        { id = "yes", text = "Sim" },
        { id = "no", text = "Nao" },
    },
    selectedIndex = 1,
}
```

`options` e `selectedIndex` serao usados apenas em perguntas. O hook retornara
`nil` quando nao houver dialogo ativo.

A datilografia usara uma constante de velocidade definida no modulo, inicialmente
`0.04` segundos por caractere. Nao havera opcao de alterar esse valor por
chamada nesta etapa. A contagem usara caracteres UTF-8 completos para preservar
acentos e outros caracteres multibyte.

O controlador mantera uma geracao interna por dialogo. A tarefa que revela os
caracteres verificara essa geracao antes de cada atualizacao e antes de concluir,
impedindo que uma mensagem substituida altere o estado novo.

## Fluxo de interacao

### Mensagem simples

1. `show` cria o estado com `isTyping = true`.
2. Os caracteres sao revelados gradualmente.
3. O primeiro `F` revela todo o texto imediatamente.
4. Com o texto completo, o proximo `F` fecha o dialogo.
5. O callback recebe `nil, "completed"`.

### Pergunta

1. `ask` cria o estado com a primeira opcao selecionada.
2. O texto da pergunta e revelado gradualmente.
3. Enquanto o texto esta sendo digitado, `F` revela o restante.
4. Quando o texto esta completo, as opcoes aparecem.
5. `Up` ou `W` move para a opcao anterior.
6. `Down` ou `S` move para a proxima opcao.
7. A selecao fica limitada a primeira e a ultima opcao; ela nao circula.
8. `F` confirma a opcao selecionada, fecha o dialogo e chama o callback com
   `optionId, "completed"`.
9. `Esc` fecha o dialogo e chama o callback com `nil, "cancelled"`.

Enquanto o dialogo estiver ativo, o controlador consumira `F`, `Esc`, `Up`,
`Down`, `W` e `S` pelo `ContextActionService`. Isso impede que `W/S` tambem
movimentem o tanque. O binding sera removido ao fechar, cancelar, substituir ou
parar o controlador.

## Substituicao e lifecycle

`show` e `ask` sempre substituem o dialogo ativo. A chamada nova so sera
processada depois de sua entrada ser validada.

Quando ocorre substituicao:

1. A geracao do dialogo atual e invalidada.
2. A tarefa de datilografia anterior deixa de poder emitir mudancas.
3. O estado atual e limpo.
4. O callback anterior recebe `nil, "replaced"`.
5. O novo estado e publicado e o novo dialogo comeca.

`start()` sera idempotente. `stop()` tambem sera idempotente; quando houver um
dialogo ativo, ele o cancelara com `nil, "cancelled"`, limpara o estado e
removera os bindings de input.

Callbacks antigos nao poderao modificar um dialogo posterior por meio de
atualizacoes internas do controlador. A composicao normal continua permitida:
um callback pode chamar `show` ou `ask` para iniciar a proxima etapa.

## Validacao e erros

As entradas serao validadas antes de substituir qualquer dialogo ativo:

- `show` exige texto string nao vazio.
- `ask` exige texto string nao vazio.
- `ask` exige ao menos uma opcao.
- Cada opcao exige `id` e `text` strings nao vazias.
- IDs de opcoes devem ser unicos dentro da pergunta.
- Uma chamada invalida gera erro sincrono e preserva o dialogo atual.

## Renderizacao

O `App.luau` renderizara um bloco de dialogo somente quando `useDialogue()`
retornar estado ativo.

- O bloco sera ancorado no centro horizontal e na parte inferior da tela.
- O texto usara quebra de linha e alinhamento central.
- O tamanho vertical sera automatico e nao tera altura maxima.
- A borda inferior permanecera fixa; novas linhas farao o conteudo crescer para
  cima.
- O visual sera transparente e simples, sem um painel decorativo complexo.
- Perguntas mostrarao o texto acima e uma linha de opcoes abaixo.
- A opcao selecionada tera o prefixo `>`.
- A fonte e as cores seguirao os valores ja usados pelo `App`.

Exemplo visual conceitual:

```text
                         Usar Spade Key?
                              > Sim    Nao
```

## Testes e verificacao

O novo spec client-side cobrira, sem testar a arvore visual React:

- contrato de `show` para mensagem simples;
- contrato de `ask` com IDs e textos;
- estado inicial de datilografia;
- reveal imediato quando o fluxo de input aciona `F`;
- fechamento e callback apos o segundo `F`;
- cancelamento por `Esc`;
- substituicao e callback com `nil, "replaced"`;
- selecao por setas e `W/S`;
- confirmacao da opcao e retorno do `optionId`;
- validacao de entradas invalidas sem destruir o dialogo ativo;
- lifecycle idempotente e remocao dos bindings no `stop()`.

Specs de UI permanecem fora do escopo da suite TestEZ atual. A verificacao
visual sera feita manualmente em Play no Roblox Studio.

As verificacoes estaticas e de build serao:

```bash
selene --config selene.roblox.toml src
selene --config selene.roblox-tests.toml tests
rojo sourcemap --include-non-scripts test.project.json --output test-sourcemap.json
luau-lsp analyze --platform roblox \
  --settings typecheck/luau-lsp.roblox.json \
  --base-luaurc typecheck/roblox.luaurc \
  --definitions @roblox=typecheck/globalTypes.None.d.luau \
  --definitions @testez=typecheck/testez.d.luau \
  --sourcemap test-sourcemap.json --formatter gnu \
  src/shared \
  src/server/inventory src/server/items src/server/pickups \
  src/client/camera src/client/dialogue src/client/inventory \
  src/client/pickups src/client/player src/client/ui \
  tests
rojo build -o /tmp/dungeon-game-canve.rbxlx default.project.json
rojo build -o /tmp/dungeon-game-canve-test.rbxlx test.project.json
```

No Roblox Studio, o fluxo manual devera confirmar duas execucoes completas de
Play, com parada entre elas, incluindo datilografia, `F`, `Esc`, navegacao,
bloqueio do movimento, crescimento vertical e substituicao.

## Fora de escopo

- API de sequencias ou branching declarativo;
- solicitacoes vindas do servidor;
- velocidade configuravel por chamada;
- sons de tecla ou efeitos de audio;
- animacoes de entrada e saida;
- limite de altura, scroll ou paginação;
- fila de dialogos;
- suporte a multiplos dialogos simultaneos;
- estilos visuais complexos ou editor de dialogos;
- specs da arvore visual React.

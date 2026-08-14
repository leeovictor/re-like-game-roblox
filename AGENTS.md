# AGENTS.md

## Imports com hífen no caminho

Pastas cujo nome contém hífen (ex.: `src/server/cave-engine/`) não podem ser
acessadas com a notação de ponto em Luau, pois `-` é interpretado como
subtração. Use acesso por colchetes:

```luau
-- Errado: script.cave_engine.CaveEngine
-- Errado: script.cave-engine.CaveEngine (parsing de subtração)
local CaveEngine = require(script["cave-engine"].CaveEngine)
```

Se a pasta destino não tiver hífen, a notação de ponto é preferida:

```luau
local Types = require(script.Parent.Parent.world.types)
```

Sempre confirme o nome exato do diretório em `default.project.json`/árvore de
`src/` antes de escrever um `require`.

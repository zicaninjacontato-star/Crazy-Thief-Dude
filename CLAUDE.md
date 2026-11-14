# Crazy Thief Dude — guia para sessões do Claude

Jogo de mundo aberto estilo GTA (cidade de Mauá low-poly) em JavaScript + Three.js **r128**, empacotado como APK Android (WebView).

## Arquitetura atual

- **Tudo vive em `game.html`** (~740 KB, ~4.200 linhas). Não há bundler, npm nem módulos.
- O arquivo tem ~36 blocos `<script type='text/game' class='gb'>`. O último `<script>` normal (boot/menu) carrega `three.min.js` e depois injeta os blocos `gb` **em ordem**, um a cada 200 ms, como scripts globais. Só então chama `requestAnimationFrame(loop)`.
- Cada bloco é uma "versão/patch" (v12c, v18...) empilhada sobre as anteriores. Blocos posteriores **sobrescrevem funções globais** dos anteriores (`update`, `loop`, `push`, `hitB`, `mini`, `setOutfit`, `boom`...). A ordem dos blocos é a ordem de execução — **não reordene**.
- Uma linha gigante (~283 KB) perto do fim é um JPEG em base64 (imagem do menu). Use `cut -c1-N` ao ler linhas; nunca despeje o arquivo inteiro.
- Estado global principal: `sc` (cena), `cam`, `rd` (renderer), `P` (jogador), `peds[]`, `vehs[]`, `solids[]` (AABBs de colisão; prédios têm `ms`=meshes, `hp`, `fall`), `parts[]`, `gren[]`, `trc[]`, `PAUSED`, `S` (tabela de veículos), `LODC` (distâncias de LOD).
- Build do APK: `.github/workflows/apk.yml` move `game.html` para `assets/`, baixa `three.min.js` r128 do cdnjs e roda Gradle. **`game.html` na raiz precisa continuar funcionando sozinho** até a migração para Vite estar completa e o workflow ser atualizado.
- `trailer/` + workflows `trailer*.yml`: captura de vídeo via Playwright; dependem de globais do jogo.

## O problema das ~40 camadas de `update()`

O `update(dt)` original está em `game.html` (bloco 1, "LOOP"). Quase todo bloco posterior faz:

```js
const _uX=update; update=function(dt){ _uX(dt); if(PAUSED)return; /* lógica nova */ };
```

Há ~40 dessas camadas (`_u`, `_u2`... `_uH`, `_up`...). Consequências:
- a ordem de execução é implícita (ordem dos blocos); algumas camadas rodam **antes** de chamar a anterior, outras depois;
- cada camada repete checagens de `PAUSED`/distância e varre `vehs`/`peds`/`solids` de novo;
- ~218 `try{}` engolem erros, então uma camada quebrada falha em silêncio;
- o mesmo padrão é usado em `loop`, `push`, `hitB`, `boom`, `mini` etc.

Ao mexer: procure **todas** as redefinições (`grep -n "update=function"`, `grep -n "NOME=function"`) antes de alterar uma função — a versão que vale é a última.

## Regras de materiais (Passo 2, já feito)

- `mat(cor)` devolve material **compartilhado** (cache `MC`). `tmat(cor, textura)` idem (cache `TMC`); `wallM(cor,a,b)` para paredes de prédio (caches `WMC`/`WTC`). `tm`, `mk`, `mk0` são apelidos deles.
- Materiais de cache têm `_sh=1`. **Nunca altere `mesh.material.color/opacity/transparent` direto**: chame `uq(mesh)` antes (clona se for compartilhado — copy-on-write). Ex.: `uq(m).material.opacity=.4`.
- Não crie `new T.MeshToonMaterial` em código novo; use as fábricas.
- O HUD de desempenho mostra `⚠N` se algum material do cache foi alterado indevidamente.

## Medição (Passo 0, já feito)

- HUD discreto no topo: `FPS · DC (draw calls) · mat · geo · tex`. `window.PERFHUD(0)` oculta; `window.PERF` expõe os números.
- Teste headless: servir `game.html` ao lado de `three.min.js` r128 (`npm pack three@0.128.0`, cdnjs é bloqueado no sandbox), abrir com Playwright, clicar `#bj`, esperar ~30 s, `PAUSED=false`, e ler `rd.info` / percorrer `sc`. O jogo começa pausado no menu.

Linha de base (Chromium headless, PC), depois do carregamento:

| Métrica | Original | Após Passo 2 |
|---|---|---|
| Materiais únicos | ~4.050 | ~980 |
| Texturas na GPU | ~214 | ~115 |
| Draw calls | ~1.300–1.400 | igual (cache não agrupa draw calls; isso vem nos passos 5–7) |
| Meshes | ~5.550 (2.050 são contornos `OLM`) | igual |
| Meshes por carro / pedestre | 22–28 / 22 | igual |

## LOD mesclado e contornos (Passo 7, feito) — dentro de `lod()` (bloco "LOD", ~linha 2140)

- `LODC` (global `window.LODC`): `po`/`vo` = contorno some de ped/veículo; **`pm:24` / `vm:38`** = ped/carro/moto acima dessa distância vira **1 mesh mesclada** (cor por vértice = cor do material × média da textura da face); **`wo:40`** = contornos do mundo (prédios/props) somem acima de 40 m da fachada. Histerese: volta ao modelo detalhado em `pm-4` / `vm-6`. `LODC.pm=LODC.vm=1e9` desliga a mesclagem.
- `lmOn(o)/lmOff(o)` (também em `window.LMX`): escondem as meshes originais (guardando quais estavam visíveis) e adicionam/removem a mesh mesclada como último filho de `o.g`. Membros (grupos filhos diretos de `g`) entram na pose de repouso. Perto da câmera o modelo é exatamente o original (rosto, janelas, rodas).
- A geometria mesclada é descartada em `lmOff` e em `sc.remove(g)` (wrapper em `sc.remove`). Se mexer em como entidades são removidas, mantenha isso, senão vaza GPU.
- Cuidados: o que mudar em `visible`/cor/material de uma entidade *enquanto ela está longe* só aparece quando ela volta ao modelo detalhado (ex.: arma sacada, pintura). `darken()` já funciona (a mesh mesclada também vira carvão). Ped em ragdoll nunca é mesclado.
- Só `t=='car'|'moto'` são mesclados; ônibus, avião, heli, tanque, barco, trem não.
- **Correção de diagnóstico:** o "contornos = ~40% dos draw calls" da primeira análise estava errado (foi medido com o jogo pausado, antes de o `lod()` rodar). Em jogo, o LOD antigo já escondia os contornos de ped/veículo; os do mundo eram ~5%.

Atribuição de draw calls medida (Chromium headless, jogo rodando, antes do Passo 7 → depois):

| Origem | Antes | Depois |
|---|---|---|
| Mundo (prédios etc., caixas com 6 materiais = 6 calls) | ~600 + 52 contorno | ~606 + 1 |
| Pedestres | ~304 | ~33 |
| Veículos | ~111 | ~28 |
| Instanced + jogador | ~96 | ~96 |
| **Total** | **~1.170 (picos 1.450–1.510)** | **~780 (picos ~900)** |

## Gargalos conhecidos (ordem de gravidade)

1. Draw calls ainda ~800–900 (alvo no celular: 150–300). **O mundo é agora ~78% do total**: prédios são `Mesh` com array de 6 materiais (`bld()`/`B()`), cada um custa até 6 draw calls. Próximo grande ganho = Passo 6 (chunks mesclados) ou, antes, prédios com 1 material/atlas.
2. ~~Contornos~~ (resolvido/pequeno, ver acima).
3. Cidade não mesclada em chunks; modelos de carro/ped *de perto* ainda têm ~12–22 meshes.
4. Rastros de bala, partículas, explosões criam meshes por evento; 47 `sc.remove` e nenhum `dispose()`.
5. Cadeia de `update` (acima); IA de todos os NPCs todo frame; colisão carro×carro O(n²); varreduras lineares em `solids` (1.800 itens) fora do `push()` (que já usa grade).
6. HUD escreve no DOM todo frame.
- Não são problema: sombras (desligadas), luzes (2), pixelRatio (0,9).

## Plano de refatoração (um passo por vez, medir antes/depois)

Estrutura-alvo: `/src/core` (Game, Renderer, Input, EventBus, Assets, Pool, rng), `/src/world` (City, ChunkManager, SpatialGrid, builders, Destruction), `/src/entities` (Player, Ped, Vehicle + models), `/src/systems` (Physics, Traffic, Ped, Police, Combat, FX, Camera, Audio, Mission, Save), `/src/ui` (HUD, Minimap, Menus), `/src/config`.

- [x] **0. Rede de segurança** — HUD de FPS/draw calls/materiais. (Falta: teste Playwright automatizado no CI.)
- [ ] **1. Vite + ES Modules** — extrair os blocos `gb` para arquivos na mesma ordem, ainda globais; atualizar `apk.yml` para buildar.
- [x] **2. Cache de materiais** — `mat`/`tmat`/`wallM` + `uq`.
- [ ] **3. Loop único** — achatar as ~40 camadas de `update` numa lista explícita `systems[]`, preservando a ordem.
- [ ] **4. `ui/HUD` e `Minimap`** — só escrever no DOM quando o valor mudar.
- [ ] **5. `FXSystem` com pool** — rastros, partículas, sangue, granadas via `InstancedMesh`; acabar com vazamentos.
- [ ] **6. `world/` em chunks mesclados + `SpatialGrid`** substituindo `solids[]` (API compatível).
- [x] **7. LOD mesclado de carro/pedestre + contornos do mundo só perto** (feito como LOD por distância; modelo de perto continua com várias meshes por ter textura por face).
- [ ] **8. `PhysicsSystem`** — colisão via grade, timestep fixo.
- [ ] **9. IA** — Traffic/Ped/Police com LOD por distância e pool de entidades.
- [ ] **10. Player e veículos especiais** (avião, heli, tanque, barco, trem; modos `FZ.mode`).
- [ ] **11. Missões, loja, garagem, save.**

Regra de ouro: nunca refatorar e mudar visual/jogabilidade no mesmo passo. A cada passo, rodar o teste headless (zero `pageerror`) e comparar as métricas da tabela.

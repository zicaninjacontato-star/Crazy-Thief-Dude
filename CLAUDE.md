# Crazy Thief Dude — guia para sessões do Claude

## ⛔ REGRA Nº 1 — NUNCA remover ou desativar mecânicas, modos gráficos, gore ou áudios existentes

**NUNCA remover ou desativar mecânicas, modos gráficos, gore ou áudios existentes.** Otimização de FPS **não** é motivo para tirar, simplificar ou desligar nada que o jogador usa: botões e menus, Estilo Gráfico (Cartoon/Realista), Renderização/Resolução/Textura/Densidade, Sangue, Gore, música do menu, sons, mapa fixo, saves. Se uma otimização muda o resultado visível ou o comportamento, ela está errada: corrija a otimização, não o jogo. Antes de qualquer commit, rode o checklist de verificação abaixo e compare com o Remaster.

## Qual é o jogo de verdade (leia antes de otimizar qualquer coisa)

- O produto do usuário é o **Remaster**: ramo `ccr-58105d15-gky879` (tag/APK `apk-remaster`, pacote Android `com.crazythiefdude.remaster`, workflow `apk-remaster.yml`). Ele tem **tudo** o que o usuário joga: Gore, Estilo Gráfico Realista/Cartoon, música desde o menu, áudio protegido, Editor de HUD, tubarão, praia, drive-by, Lotes 18–24 etc.
- O commit `5537943` (e a `main` antiga, até `9fd1cf3`) é uma base **anterior** a tudo isso. Uma sessão otimizou essa base antiga por engano; por isso a versão otimizada "perdeu" as mecânicas do Remaster. **Nada foi apagado de propósito** — a linha otimizada simplesmente nasceu sem elas.
- Por isso a `main` agora é o **merge** do Remaster com as otimizações (uma só linha de desenvolvimento). Antes de mexer: `git log --graph --oneline --all` e confirme que está trabalhando sobre o Remaster atual, não sobre uma base velha.
- Dois workflows rodam em **todo push**: `apk.yml` (pacote `com.crazythiefdude.game`, release `apk-latest`) e `apk-remaster.yml` (pacote `.remaster`, release `apk-remaster`, que é **apagada e recriada** a cada push).

## Checklist de verificação antes de commit (obrigatório)

Servir `game.html` com `three.min.js` r128 (`npm pack three@0.128.0`; cdnjs é bloqueado no sandbox) e rodar no Chromium/Playwright (`--use-gl=swiftshader`), clicar `#bj`, esperar ~26 s. Comparar **sempre** com o Remaster puro (`git show origin/ccr-58105d15-gky879:game.html`), nos dois estilos (`localStorage.maua_cfg='{"gfx":0}'` = cartoon; padrão = realista):

1. **Mapa idêntico:** hash de `solids` (x0,x1,z0,z1,h ×100, ordenado), posições de `peds` e `vehs` logo após carregar. Tem que bater com o Remaster. (Ver "Mapa fixo" abaixo.)
2. **Zero `pageerror`** no carregamento e em ~900 frames de combate (tiros, granadas, foguetes, explosões, mortes, carros destruídos, prédios caindo, `V18.restoreWorld()`).
3. **Menu e configurações:** `CFGUI.open()` lista 8 linhas e 19 opções (Textura, Resolução, Renderização, **Sangue**, **Gore**, Densidade, **Estilo Gráfico Cartoon/Realista**, Cheats); clicar cada opção altera `CFG` e grava `maua_cfg`; `#mnew`/`#mlod` visíveis; `MUS.mode==='menu'` e contexto de áudio `running`.
4. **Gore e sangue:** matar pedestres com `hurt()` e com tiro de espingarda (`shoot(W.shot)`) com Gore desligado/ligado cria os objetos esperados (pool + cena).
5. **Sem contaminação de material:** nenhum material do cache (`MC`/`WMC`/`TMC`) com cor/opacidade/transparência/shader diferentes do original, e nenhum `InstancedMesh` com material do cache.
6. **Comparação de pixels com o Remaster** (mesmos pontos de vista, LOD de entidades desligado: `LODC.pm=LODC.vm=1e9`): < 1% dos pixels com diferença >24.
7. **Perseguição → morte → hospital:** `crime(6,P.x,P.z)`, `J.y=1`, ~600 frames com `boom()` perto, esperar a morte e o respawn (o jogo chama `restoreWorld` sozinho). Depois do respawn: **prédios desanexados do v36 = ~0** (`[...OPT36.items.values()].filter(r=>r.det).length`), draw calls ≈ os de antes da perseguição, materiais únicos ≈ 1,1 mil, nenhum veículo "fantasma" (`_lm` obsoleto).
8. **Multidão:** 14 policiais + 8 viaturas a 6–24 m na frente da câmera com 3+ estrelas: draw calls devem ficar < ~700 (sem o orçamento de LOD eram ~990).
9. Só então medir draw calls (mesmas 8 posições do mapa) e atualizar as tabelas.

## Mapa fixo — não quebre (aprendido do jeito difícil)

O Remaster tem "mapa fixo": o gerador `R()` é **reiniciado a cada bloco** (`__rs(i)`, semente = hash(`MAPSEED`, índice do bloco)). Dois cuidados:

- **Não acrescente nem reordene blocos `gb` antes dos existentes** (o índice entra na semente). Blocos novos vão **no fim**, antes do script de boot.
- **O próprio Three.js gasta o gerador semeado:** cada `Material`, `Mesh`/`Object3D`, `Texture` e `BufferGeometry` criado chama `generateUUID()` = 4 sorteios de `Math.random`. Se uma otimização cria **menos ou mais objetos** durante o carregamento (`__sd` truthy), todo o mapa muda. Regras: onde você **evita** criar um objeto, gaste o mesmo (`BURN(n)`); onde cria objeto **a mais**, crie dentro de `QUIET(()=>...)`. Já estão aplicados em `mat/wallM/tmat` (cache hit = `BURN(1)`), `uq` (clone), pool `DBM`/`dbr`, `fx()` (cada puff era Mesh+Material: `BURN(1)` por puff; extras em `QUIET`), `LM` do LOD e na cópia de material do `InstancedMesh`.
- Como conferir: instrumentar `rn()` contando sorteios por bloco (remaster × mesclado) e comparar o hash de `solids`/`peds`/`vehs`. Blocos que só criam objetos e depois usam RNG próprio (ex.: v30 usa `rnd()` próprio, "não mexe na semente do mapa") toleram diferença de contagem.


Jogo de mundo aberto estilo GTA (cidade de Mauá low-poly) em JavaScript + Three.js **r128**, empacotado como APK Android (WebView).

## Arquitetura atual

- **Tudo vive em `game.html`** (~1,1 MB, ~7.400 linhas, ~55 blocos). Não há bundler, npm nem módulos. Além dos blocos `gb` há `<script>` normais no início (ex.: **`v30-pre`**, que define `window.GFX` — padrão **1 = realista**, salvo em `localStorage.maua_cfg.gfx` — e **troca `THREE.MeshToonMaterial` por uma subclasse de `MeshLambertMaterial`** no modo realista; áudio protegido `v34`; dedupe de escrita no HUD `v40`).
- O arquivo tem ~55 blocos `<script type='text/game' class='gb'>`. O último `<script>` normal (boot/menu) carrega `three.min.js` e depois injeta os blocos `gb` **em ordem**, um a cada 200 ms, como scripts globais. Só então chama `requestAnimationFrame(loop)`.
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

## Integração com as otimizações que o Remaster já trazia (v36, v37, v40, v44)

O Remaster já tinha otimizações próprias, feitas por outra sessão. **Mantenha todas** e não duplique o trabalho delas:

- **`v36` (agrupamento estático por setores, `OPT36`)** é o agrupador **principal** (cobre o que o meu Passo 6 fazia). Esconde as meshes originais na camada 31, guarda `visible/material/geometry/updateMatrix` com `defineProperty`, desanexa no `hitB`, trata grupos e vigia cores. O meu bloco de chunks (Passo 6) ficou como **fallback**: só roda se `OPT36` não estiver ativo (`console: 'chunks (passo 6): v36 ativo, fallback desligado'`).
- **`v36` varre todo `InstancedMesh` com `frustumCulled=false` e liga `frustumCulled=true`.** Os meus `DBM` (pool) e `fxI` (fumaça) têm geometria unitária na origem e **sumiriam** fora da origem; por isso levam `userData.fxp=1` e o laço do v36 os ignora. Qualquer `InstancedMesh` de efeito novo precisa disso.
- **`v37` (contornos sob demanda):** controla a visibilidade das meshes de contorno de setor (`userData.opt36`) e dos contornos de pedestres. O meu `wolScan` (contornos do mundo a < `LODC.wo`) ignora meshes `opt36`/`ckm`. No modo realista `OLM.visible=false` (sem contornos).
- **`v30` (realista)** só aplica o shader de mundo (`worldify`) a materiais **Lambert** já existentes e converte veículos/pedestres para Phong (`toPh`, `enhV`/`enhP`). Antes de worldificar uma mesh de topo, o v30 chama `uq(o)` (cópia própria do material compartilhado), senão o shader "vazaria" para outros usuários do mesmo material e os lotes ficavam pretos.
- **LOD mesclado (Passo 7):** não mescla meshes transparentes (sombra "blob" do v30, vidros) — ficam individuais. Material do LOD (`LM`) segue o estilo (Lambert no realista).
- Dano visual de prédios (Remaster) escurece `color` direto no material do prédio: é seguro porque o `hitB` base chama `uq()` antes (copy-on-write). **Não quebre essa ordem.**

## Regras de material compartilhado (consolidadas)

- `mat/tmat/wallM` devolvem material **compartilhado** (`_sh=1`). Para alterar cor/opacidade/transparência use `uq(mesh)` antes (clona; clone ganha `_own=1` e é descartado com `dispose()` em `sc.remove`).
- **Nunca** use material compartilhado em `InstancedMesh`: no r128 um material usado ao mesmo tempo por mesh instanciada com `instanceColor` e por meshes comuns fica preto. `T.InstancedMesh` foi estendido para clonar (em `QUIET`) qualquer material com `_sh`.
- Material criado depois do v30 não é "worldificado": não reutilize o objeto de material de uma mesh que o v30 modificou (por isso o `uq` na origem).

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

## Chunks do mundo estático (Passo 6, feito) — último bloco `gb` antes do script de boot

Meshes estáticas soltas na cena (`parent===sc`, `matrixAutoUpdate===false` = as que o bloco v12c congelou, Toon opaco, sem `userData.on`) são fundidas em **chunks de 64×64 m** (`CS`), com os contornos (`OLM`) filhos delas num mesh de contorno por chunk. Resultado: 1 draw call por chunk (+1 de contorno) em vez de 1 por caixa e 6 por prédio.

- **As meshes originais NÃO saem da cena.** Ficam escondidas com `m.layers.set(31)` (a câmera só vê a layer 0), então `m.visible` continua sendo o que o jogo quer. Todo código antigo (`b.ms`, `takeSnap/restoreWorld`, `removeB`, `sc.remove(m)`...) continua valendo. **Nunca use `layers` para outra coisa em meshes do mundo.**
- **Material único dos chunks** (`kmat`): `MeshToonMaterial{map:WT, vertexColors:true}`. Cor de cada face = cor do material (vira cor de vértice); repetição da textura de janela vai embutida nos UVs (`wallM` marca `q._wt=1` nas texturas de janela); faces sem textura apontam para um pixel branco da `WT` (uv .05,.05). Outras texturas (casas, placas) ganham 1 material por textura.
- **A prova de falha:** se um membro muda (`sigSet/sigEq`: posição, escala, rotação, cor; troca de material; `visible`; saiu da cena), ele é **liberado**: `layers`→0, `matrixAutoUpdate=true`, e o chunk é refeito sem ele (`rebuild`, na hora). Dano (`hitB`: `hp/k/fall`) é checado todo frame em `tick` (via `lod()` → `window.CKT`); o resto, 1/4 dos membros por frame. `sc.remove(m)` (wrapper) tira o membro do chunk. `restoreWorld` devolve o estado original → o membro é **reabsorvido** (checagem a cada 45 frames; trava anti vai-e-vem só se sair de novo em <120 frames, 3 vezes seguidas).
- Prédio que cai fica individual (como antes). Chunk refeito reaproveita as geometrias já "assadas" por membro (`r.pc`), então reconstruir custa ~1 ms. Geometria antiga é `dispose()`ada (testado: 7 ciclos de destruir/restaurar sem crescer).
- Contorno dos chunks: ligado quando a **caixa do chunk** está a < `LODC.wo` (40 m) do jogador — granularidade de chunk, não de prédio (diferença visual só em linhas finas).
- API de depuração: `CKX.off()` (tudo individual, para comparar), `CKX.on()`, `CKX.stats()`. `CS` fixo em 64 (testado 40/64/96: draw calls ≈ iguais; 64 é o equilíbrio).
- Armadilhas: no **r128 `Texture` não tem `userData`**; `Object3D.layers` oculta o objeto mas **não** seus filhos (por isso os contornos filhos também vão para a layer 31); `wolScan` ignora meshes `userData.ckm`; mesh nova do mundo criada *depois* do carregamento fica individual (não entra no chunk).
- O registro inicial roda uma vez ao fim do carregamento (~70 ms no PC).

Medido (Chromium headless PC, mesmas 8 posições do mapa, jogo rodando): **draw calls médios 757 → 313 (pico 1.031 → 509); CPU de `render()` 6,1 → 4,2 ms; triângulos ~100 mil (iguais)**. Comparação de pixels chunks ligados × desligados: corpo, janelas e cores idênticos (só diferem linhas de contorno); testado intacto, danificado, caindo, desabado, `restoreWorld` e `sc.remove` (diferença <0,01% da imagem).

Atribuição dos ~250 draw calls que sobram (vista inicial): instanced 61 · jogador 35 · mundo solto 44 (meshes enormes ≥100 m, `frustumCulled=false`, transparentes) · chunks 40 · veículos 27 · pedestres 16 · aninhados 18. **Pico de destruição ainda chega a ~1.000**: cada explosão cria dezenas de caixas de destroço individuais (`parts[]`) — isso é o Passo 5 (FX com pool/instancing).

## Efeitos transitórios em pool/instancing (Passo 5, feito)

Perfil de alocação em combate pesado (antes): ~2.800 meshes por explosões, ~1.600 por destroços de prédio, ~750 de sangue, mais rastros e foguetes — todas `box()` criadas e removidas por evento (cada uma viva = 1 draw call). **Não havia vazamento de GPU por evento** (geometria `BG` e materiais já eram compartilhados desde o Passo 2); o custo era draw calls e churn de `Mesh`/`sc.add`/`sc.remove`.

- **`dbr(w,h,d,cor,x,y,z)`** (logo depois de `box()`, 1º bloco) devolve um **proxy `Object3D`** reaproveitado de um pool (`DBF`), com o mesmo contrato de uma mesh (`position`, `scale`, `rotation`, `lookAt`). Todos os proxies vivos (`DBA`) são desenhados por **um único `InstancedMesh`** (`DBM`, 1.024 instâncias, cor por instância, `MeshToonMaterial`). `dbrFlush()` (chamado em `lod()`, 1×/frame) grava matrizes e cores. Se o pool encher, `dbr` devolve um proxy morto (efeito descartado, sem erro).
- Usam `dbr`: destroços de explosão (`boom`) e de prédio (`hitB`), respingos (`splash`, 2 definições), destroços de barreira, sangue (partículas e decalques `BL`), rastros de tiro (`tracer`, `tracer3`, `tr3`) e granadas/foguetes/tanque/helicóptero (`gren`). **Código novo que cria efeito temporário deve usar `dbr`, nunca `box()`.** `parts/trc/gren/BL` e seus laços de atualização não mudaram: eles chamam `sc.remove(proxy)`, e o wrapper de `sc.remove` devolve o slot ao pool.
- **Fumaça/fogo (`fx()`, bloco v11b):** as 130 meshes com 130 materiais transparentes viraram 1 `InstancedMesh` (`fxI`) com cor por instância e **opacidade por instância** (atributo `iOp` injetado via `onBeforeCompile`). Cada slot é um `Object3D` com `material.{color,opacity}` falso, então `fx()`/`fxTick0()` ficaram iguais (mesma sequência de `R()`); `fxTick` empacota os puffs ativos. A ordem de desenho é a do índice (antes: z), com diferença visual mínima na sobreposição da transparência.
- **Dispose:** `uq()` marca clones como `_own`; o wrapper de `sc.remove` (1º bloco, o mais interno da cadeia) percorre o objeto removido e chama `.dispose()` nos materiais `_own`. Geometrias/materiais compartilhados (`BG`, `mat()`, `OLM`...) **nunca** devem ser descartados. Os únicos recursos de geometria criados em tempo de jogo são as geometrias mescladas dos Passos 6 e 7, que já são descartadas.
- Depuração: `window.FXD={fxm,fxI,fxTick,fx,fxTick0}`; `DBA/DBF/DBN` ficam globais (`DBA.length` = efeitos vivos).

Medido (Chromium headless PC, cenário de combate: tiros, granadas, foguetes, ~130 explosões, mortes, carros destruídos, prédios caindo; 3 rodadas): **pico de draw calls 1.093/1.230/977 → 713/816/682** (o que sobra são pedestres/cops próximos e prédios danificados fora do chunk); meshes criadas por efeitos 5.000+ → 0 (o pool cresce uma vez e reaproveita); geometrias/texturas na GPU estáveis nas 3 rodadas; ao fim do combate o pool devolve tudo (sobram só os 22 decalques de sangue); CPU do `update()` inalterada (p50 ≈ 2,5 ms, p99 5–10 ms nas duas versões, dentro do ruído; o ganho do Passo 5 é em draw calls e criação de objetos, não em CPU de lógica). Fidelidade: 150 destroços pelo pool × meshes reais = **idêntico** (diferença máx. 1/255); fumaça/fogo ≈ igual (0,8% dos pixels, só sobreposição de transparência).

## Perseguição, morte e hospital — causas medidas e correções (Passo 5b)

Relato do celular: FPS 12 e ~940 draw calls ao acordar no hospital, ~2.640 materiais únicos, e centenas de draw calls em perseguição. Reproduzido no headless e medido:

1. **Hospital = `restoreWorld` × `v36` (o grande culpado, já existia no Remaster).** O `restoreWorld` (bloco v18) chamava `m.updateMatrix()` em **todos** os 198 prédios/telhados do snapshot; o guarda do `v36` (`guard()` sobrescreve `updateMatrix`/`material`/`geometry`/`visible`) trata isso como "objeto movido" e **desanexa todos do agrupamento para sempre** → +~220 draw calls permanentes (prédio solto = até 6 calls) a cada morte. Correção: (a) `restoreWorld` só chama `updateMatrix()` se `scale.y`/`position.y`/`matrixAutoUpdate` realmente mudaram; (b) `OPT36.reattach(m)` (fila `OPT36.rq`, **10 por quadro**, em `reTick()` dentro do update do v36) devolve ao setor os prédios restaurados, **só se `pristine(rec)`**: matriz local == a do agrupamento (`rec.m0`), cores == originais (`rec.c0`), visível, congelado, opaco, e o motivo do destacamento foi `dano|updateMatrix|material` (nunca `moveu`/`cor`). Resultado: desanexados depois do respawn 198 → 0; draw calls pós-hospital ~400 → ~155; 1ª renderização depois de acordar 14 → 8 ms.
   - **Regra:** nunca chame `updateMatrix()`, nem troque `material`/`geometry`/`visible`, numa mesh do mundo agrupada pelo v36 sem querer destacá-la. Se restaurar estado, chame `OPT36.reattach(m)` depois.
2. **`restoreWorld` poda `v.g.children` além do snapshot** — o meu LOD mesclado é um filho a mais e era arrancado sem `lmOff` (veículo com `_lm` obsoleto = invisível ao longe). Agora `LMX.lmOff(v)` roda antes da poda (reproduzido: 1 veículo obsoleto → 0).
3. **Materiais ~2.640 não vêm do spawn** (+15 em toda a perseguição): vinham do fix do v30 (modo realista), que dava uma cópia de material a **cada** mesh de topo. Agora `wsh(m)` dá **uma cópia worldificada por material de origem** (`WCL`, `_sh=1`, criada em `QUIET`), compartilhada entre as meshes de topo. O clone do dano (`uq`/`cq`) agora **preserva o shader** (`onBeforeCompile`, `customProgramCacheKey`, `userData`), senão prédio danificado perderia o shader de mundo. Materiais únicos: ~2.620 → ~1.120.
4. **Perseguição = multidão perto.** Cada policial completo custa ~27 draw calls e cada viatura ~34 (cabeça/tronco têm 6 texturas distintas; não dá para fundir sem atlas). **Orçamento de detalhe** em `lod()` (`lodBudget`): dentro de `pm`/`vm`, só os `LODC.bp`=6 pedestres e `LODC.bv`=3 carros/motos **mais próximos e à frente da câmera** mantêm o modelo completo; os demais usam o mesclado. `pmin`=9 m/`vmin`=12 m é o piso. Com poucas entidades perto nada muda. Multidão de 14 policiais + 8 viaturas: ~975 → ~635 draw calls.
5. **`anim`:** pedestre mesclado (`_lm`) ou escondido (`g.visible===false`: >95 m, no trem) não precisa animar membros. Wrapper mais externo da cadeia de 11 camadas, no último bloco (ragdoll e jogador sempre animam). `anim` 0,26 → <0,08 ms/frame; `update()` médio 2,0 → 1,65 ms.

**Decisões tomadas com dados (não repetir a discussão):**
- **Sem pooling de entidades.** Criar um pedestre/policial/carro custa **0,05–0,065 ms** (materiais já são cache). Pooling economizaria centésimos de ms e arriscaria quebrar ragdoll, gore, roupas/skins e estado de veículo. Os materiais já são reaproveitados.
- **IA e colisão já estavam otimizadas pelo Remaster** (`VPAIRS` por grade no v40, unidades distantes com menos frequência no v44; `trafAI` roda em ~16 de 89 veículos por frame; cada peça < 0,15 ms). Não mexa nelas sem medir.
- O custo do respawn é pequeno em CPU (`restoreWorld` ~3 ms, `respawn()` <1 ms); o que doía era o **estado permanente** (prédios soltos), não um engasgo de lógica. A fila de 10/quadro já espalha o resto.

## Medição sobre o Remaster (estado atual) — Chromium headless PC, 8 posições do mapa, jogo rodando

| | Remaster puro | Remaster + otimizações (esta `main`) |
|---|---|---|
| Draw calls médios / pico — **realista** (padrão), passeio | 561 / 876 | **298 / 430** |
| Draw calls médios / pico — **cartoon**, passeio | 576 / 891 | **297 / 398** |
| CPU de `render()` / `update()` (realista) | 6,1 / 1,9 ms | 3,6 / 1,4 ms |
| Multidão (14 policiais + 8 viaturas a 6–24 m, 3 estrelas) | ~975 DC | **~635 DC** |
| Depois de morrer e acordar no hospital (DC; prédios desanexados do v36) | ~400 DC; 198 desanexados (permanente) | **~155 DC; 0 desanexados** |
| Materiais únicos na cena (contador do HUD, realista) | ~4.000 (Remaster) / ~2.620 (antes do Passo 5b) | **~1.120** |
| `update()` médio com perseguição | 2,0 ms | 1,65 ms |
| Mapa, menu, música, configurações, gore | referência | **idênticos** (hash do mapa igual; 56/63 campos iguais, os 7 restantes são o contador de FPS e o pool de sangue) |
| Diferença de pixels vs. Remaster (LOD de entidades off) | — | 0,01–0,18% (realista), 0,05–0,78% (cartoon) |

Os ganhos sobre o Remaster vêm do **LOD mesclado de carros/pedestres (Passo 7)**, do **pool/instancing de efeitos (Passo 5)** e do **cache de materiais (Passo 2)**; o agrupamento do mundo já era do v36.

## Gargalos conhecidos (ordem de gravidade)

1. Draw calls ~250–330 em passeio normal (alvo no celular: 150–300); **picos em combate ~700–800** (era ~1.000–1.200), agora dominados por **pedestres/cops próximos (~20 meshes cada, ~400 calls com uma multidão a <24 m)** e por prédios danificados (saem do chunk). → mesclar o modelo *de perto* (Passos 7b/9).
2. ~~Contornos~~ e ~~mundo não mesclado~~ (resolvidos: Passos 7 e 6).
3. Modelos de carro/ped *de perto* ainda têm ~12–22 meshes; instanced (61 calls: postes/placas etc.); jogador 35 calls.
4. ~~Rastros/partículas/destroços por evento~~ (resolvido: Passo 5). Restam entidades que ainda são criadas/destruídas por spawn (pedestres/veículos; ~25 meshes cada) → Passo 9 (pool de entidades).
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
- [x] **5. Pool/instancing de efeitos** (`dbr`/`DBM`, `fxI`) + dispose de materiais próprios (ver seção acima; ainda dentro do `game.html`, sem módulo `FXSystem`).
- [x] **6a. Chunks mesclados do mundo estático** (ver seção acima; feito dentro do `game.html`).
- [ ] **6b. `SpatialGrid`** substituindo as varreduras lineares em `solids[]` (o `push()` já usa grade; faltam spawn/`los`/outros).
- [x] **7. LOD mesclado de carro/pedestre + contornos do mundo só perto** (feito como LOD por distância; modelo de perto continua com várias meshes por ter textura por face).
- [ ] **8. `PhysicsSystem`** — colisão via grade, timestep fixo.
- [ ] **9. IA** — Traffic/Ped/Police com LOD por distância e pool de entidades.
- [ ] **10. Player e veículos especiais** (avião, heli, tanque, barco, trem; modos `FZ.mode`).
- [ ] **11. Missões, loja, garagem, save.**

Regra de ouro: nunca refatorar e mudar visual/jogabilidade no mesmo passo. A cada passo, rodar o teste headless (zero `pageerror`) e comparar as métricas da tabela.

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

0. **Contador:** `UPD`/`RND`/`ESP`, resolução e `b<hash>` aparecem; num celular, confira que o `b<hash>` é o do último commit antes de medir qualquer coisa.
1. **Mapa idêntico:** hash de `solids` (x0,x1,z0,z1,h ×100, ordenado), posições de `peds` e `vehs` logo após carregar. Tem que bater com o Remaster **fora das mudanças pedidas pelo usuário** (parque no lugar da montanha com estrada, ilha dos animais, lagos recolocados e árvores/solids a elas ligados): compare excluindo `peds.an`, os solids a <135 m da ilha (560,-110), do parque (150,-294) e as árvores/piscinas plantadas no lugar dos lagos; o resto (`vehs`, `peds`, ~1.590 de 1.605 solids) tem que ser igual. (Ver "Mapa fixo" abaixo.)
2. **Zero `pageerror`** no carregamento e em ~900 frames de combate (tiros, granadas, foguetes, explosões, mortes, carros destruídos, prédios caindo, `V18.restoreWorld()`).
3. **Menu e configurações:** `CFGUI.open()` lista 10 linhas e 23 opções (Textura, Resolução, Renderização, **Sangue**, **Gore**, Densidade, **Estilo Gráfico Cartoon/Realista**, **Qualidade Visual**, **Contador de desempenho**, Cheats); clicar cada opção altera `CFG` e grava `maua_cfg`; `#mnew`/`#mlod` visíveis; `MUS.mode==='menu'` e contexto de áudio `running`.
4. **Gore e sangue:** matar pedestres com `hurt()` e com tiro de espingarda (`shoot(W.shot)`) com Gore desligado/ligado cria os objetos esperados (pool + cena).
5. **Sem contaminação de material:** nenhum material do cache (`MC`/`WMC`/`TMC`) com cor/opacidade/transparência/shader diferentes do original, e nenhum `InstancedMesh` com material do cache.
6. **Comparação de pixels com o Remaster** (mesmos pontos de vista, LOD de entidades desligado: `LODC.pm=LODC.vm=1e9`): < 1% dos pixels com diferença >24. **Com `Qualidade Visual` Alto (padrão) o realista passa de 1% de propósito** (luz/céu/sombras novos): para o teste rode com `maua_cfg='{"vq":0}'` (deve voltar a ~0,1%).
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

## Contador de desempenho no celular (UPD / RND / ESP / build) e o que foi medido sobre fogo, explosões e 3 estrelas (Passo 5c)

O pill no topo da tela agora tem 2 linhas (3 quando há alerta):
- Linha 1: `FPS · DC · mat · geo · tex` (draw calls, materiais únicos na cena, geometrias e texturas na GPU).
- Linha 2: `UPD a/m · RND a/m · ESP e · L×A · b<hash>`.
  - **UPD** = ms do `update()` (lógica, física, IA), média/pior da última meia segundo. **UPD alto = gargalo de CPU de lógica.**
  - **RND** = ms do `rd.render()` **no JS** (montagem e envio dos draw calls, matrizes). **RND alto = draw calls/objetos demais.** *Não inclui a GPU* (o WebGL é assíncrono).
  - **ESP** = ms do quadro que não foram nem UPD nem RND = a GPU desenhando / vsync. **ESP alto com UPD e RND baixos = gargalo é a GPU** (preenchimento de pixels / shaders do modo realista / resolução). É o número que separa "CPU" de "GPU" no celular.
  - `L×A` = resolução real do canvas; `b<hash>` = **hash do commit do APK** (o workflow troca o marcador `@@BUILD@@` por `${GITHUB_SHA::7}`; `bdev` = rodando o `game.html` direto).
- Linha 3 `⚠ +N mat ← Tipo<função×qtd`: quando os materiais únicos saltam ≥150 entre duas medições (a cada 3 s), mostra por 30 s quem criou (`T.Mesh*Material` e `Material.clone` são contados depois do carregamento, sem custo relevante). Se disser `(sem criação: já estavam na cena)` os materiais não foram criados: entraram na cena (ex.: veículos re-adicionados).
- Os construtores `T.Mesh{Lambert,Phong,Basic,Toon,Standard}Material` e `Material.prototype.clone` são **embrulhados no fim do carregamento** (bloco do contador); não compare `constructor` por identidade.

**Medido (Chromium headless; profiler de CPU do CDP, 420 frames de perseguição 3★ + RPG + carros em chamas + explosões):**
- **Não existe nenhuma `PointLight`/`SpotLight`/sombra** no jogo (só 3 luzes fixas: hemisférica, direcional, ambiente). Explosão/fogo **não criam luz**. Descartado.
- Tempo de JS por quadro em perseguição: ~2 ms de `update()` e ~3,5 ms de `render()`; nenhuma função do jogo passa de ~0,1 ms/frame; GC 0,16 ms/frame. Não há laço O(n²) relevante (colisão por grade `VPAIRS`).
- **Maior custo de JS = atualização de matrizes da cena da própria Three.js** (`updateMatrixWorld`+`compose`+`multiplyMatrices`+`updateMatrix` ≈ 1,2 ms/frame no PC, ~4.700 nós: cada pedestre/veículo tem 13–23 filhos, mesmo escondido ou mesclado). Candidato futuro (não feito): congelar `matrixAutoUpdate` das subárvores de entidades escondidas/mescladas.
- Fumaça/fogo: 130 puffs de 4 m na frente da câmera derrubam a vazão só ~10–15% no renderizador por software (2,6 → 2,2 fps); **não é o gargalo de preenchimento**. O modo realista (shader de mundo + céu procedural com ruído fbm por pixel + água) é pesado por pixel na GPU: no celular o `ESP` alto é o sinal.
- Um programa de shader novo foi compilado durante toda a sequência de combate (compilação de 1ª vez; custa 100–500 ms num celular e aparece como "5 FPS" naquela janela de 0,5 s). Não foi reproduzido de forma isolada.

**Salto de materiais "após o hospital" (1.179 → 2.637) — NÃO reproduzido:** na simulação (perseguição + RPG + carros em chamas + morte + hospital, e também com o tráfego original já substituído) os materiais ficaram em ~1.120–1.200 e **nada é criado no respawn** (instrumentado: 0 materiais criados na fase do hospital). O `2.637` é exatamente o patamar do build `ae69330` (2.618–2.637) e os dois APKs de um mesmo commit são apps diferentes (`.game` e `.remaster`, com `localStorage` separado). **O `app-build.gradle` não fixa assinatura**: cada build do Actions usa um keystore de debug novo, então o Android só atualiza por cima se o app antigo for desinstalado antes (e `apk.yml` mantém `versionCode 1`). Se o contador mostrar um `b<hash>` diferente do último commit, o celular está rodando um APK antigo. (Desinstalar apaga o save do WebView.)
- Único crescimento real ligado ao respawn: o `restoreWorld` re-adiciona **todos** os veículos do snapshot inicial que não estão mais em `vehs`; numa sessão longa o tráfego original já foi trocado, então a população passa de ~62 para ~151 veículos (+~230 materiais). É limitado (não cresce a cada morte) e **foi deixado como está**: limitar isso mudaria quais carros "voltam" depois de morrer (mecânica do Remaster). Se for preciso, a alternativa segura é despachar só tráfego comum (`v.tr`, sem `ai/own/mg/rc/ev`) a >80 m depois do restore.

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

## v46 — vida na cidade (último bloco `gb`, `window.LIFE`)

Pedido do usuário (jogabilidade, não otimização). Tudo no último bloco antes do boot; não altera o mapa (hash igual) nem o consumo de RNG semeado.

- **Táxi:** `taxiTick` foi redefinido. Passageiro e destino saem de `LIFE.pickSW()` = ponto de **calçada** (linha `l±7,5`, `±10,5` na avenida z=0) em frente a um prédio (`front(b)`: porta na fachada, nunca no meio da rua nem em trecho de cruzamento, nunca dentro de `solids`). Raio de embarque/entrega 9,5 m.
- **Motoristas veem você a pé:** o Remaster tinha "motorista distraído" (`_ds`, 40% de chance de ignorar o jogador a pé, bloco "ignora"/`DBG.dis`). Agora só existe por cheat (`DBG.dis`). O wrapper de `trafAI` no v46 freia, e se você não sair em ~2 s o carro **contorna** pelo lado (deslocamento lateral `_pb`, igual ao `_ov`; esconde `P` com `P.x=1e5` só durante a chamada interna). Folga lateral mínima ~2,8 m (menos que isso o carro "bate" no jogador e recebe impulso de `playerHit`).
- **Pedestres desviam de você:** wrapper de `pedWalk` projeta o NPC para fora de um raio de 1,3 m do jogador com um pequeno passo tangencial (contorna em vez de empurrar). Ignora NPCs em reação (`rx/fl/ar/arg/evw/ctl/sm/swm/mg`), policiais hostis e o jogador em veículo.
- **Evento de batida (EVC, bloco v21):** sem avisos na tela (os 3 `msg` foram removidos) e bem raro (primeiro 8–15 min; intervalos de 12–22 min).
- **Eventos raros novos (`LIFE.force('nome')` para testar):** `fight` (briga), `chat` (conversa), `house` (NPC entra/sai de casa que **não** está à venda: `XPROP.PR[].m` a <30 m = à venda), `park` (carro estaciona junto à loja, motorista entra, volta e vai embora), `chasefoot` (polícia persegue NPC a pé), `chasecar` (viatura persegue carro). Um por vez, intervalo 130–320 s entre eventos, só com 0 estrela, jogador a pé/carro no chão e fora de casa. NPCs de evento são peds comuns com `p.lf=ev` (o wrapper de `pedWalk` chama `ev.drive`), removidos no fim sem repor (`kill`); se alguém sofre crime/tiro (`rag`/`fl`/`hp<=0`) o evento se dissolve e os NPCs voltam ao comportamento normal. Carros de evento têm `ev=1` (o `trafAI` os ignora) e se movem por cinemática própria.
- **Câmera no parkour:** `fy` (altura de foco) só seguia o jogador acima de 2,4 m. Agora acompanha desde o início (`FZ.mode` `pk`/`climb`, ou em pé em altura >1,25 m), com suavização (9/s subindo, 3,5/s descendo). `FZ` não é global: use `window.TRAINDBG.FZ`.

- **Correções de jogabilidade (v46, 2ª rodada):**
  - **Teletransporte de NPC ao ser atingido** (todos, não só praia): o limitador anti-teletransporte do bloco "lastP" (~linha 2298) ignorava quem fugia (`fl>0`) e guardava a posição velha; ao fim da fuga o NPC voltava para lá. Agora `lastP.delete(p)` nos casos ignorados. NPC da praia atingido (`beachWalk`) foge pela areia (clampado em `BEACH`) em vez de virar NPC de rua e ser puxado para o asfalto.
  - **"Chão de grama" na praia:** o v47 cobria os lagos perto da praia com caixas `0x48773c` (e pintava o minimapa de verde) e os removia de `PONDS`. Agora a caixa é criada e removida (`sc.remove`, mantém o consumo de RNG) e os lagos continuam lagos (nadáveis, azuis no minimapa).
  - **Telhado das casas:** `roofAt` (bloco v42) devolvia só o topo da parede; casas `isH` têm telhado em pirâmide (`b.ms[1]`, cone de 4 lados). Agora o piso sobe pela inclinação (`base→ápice`), valendo também para helicóptero (`AIRFLOOR`).
  - **Braços para cima em telhado/morro:** o `anim` base levanta os braços se `o.y>1.2`; o wrapper do v46 desfaz quando o jogador está apoiado (`FZ.mode=='gnd'`, `|P.vy|<.6`).
  - **Bazuca:** em mira, o foguete herdava `tan(AP)` da câmera (que olha de cima) e mergulhava aos pés; agora sai quase reto (`AP>0` sobe; `AP<0` desce só 12%).

- **3ª rodada de ajustes (v46):**
  - **Contador de desempenho opcional:** nova linha em Configurações (`CFG.perf`, padrão **desligado**); `PERFHUD(0/1)` é aplicado ao carregar e ao clicar. Para medir no celular, ative a opção.
  - **Mira manual:** `pickLock()` só trava helicóptero (alvos de solo não são mais travados); no modo mira e no drive-by `window.__NOAS=1` faz o `shoot` base acertar só o que está na linha do tiro (distância lateral < raio do alvo). Drive-by atira para onde a câmera aponta (`camAng()`). A bazuca em mira sai quase reta (sobe com `AP>0`).
  - **Polícia:** helicóptero do mar nasce na delegacia (`-125,-67`) e voa até você; piloto tem vida (`h.ph`=170, `HELIAPPLY`); policial na água não atira (`copAI` wrapper e elite); a 3 estrelas as viaturas despachadas são pretas (`0x14161b`) ou o caminhão `swat` (que desce **4** policiais); entrar numa viatura sem motorista não faz sair outro policial (`takeover` ignora `nodrv/_out`); policiais e NPCs em fuga podem ir até a areia (limite de 320 → 460 no laço de peds).
  - **Granada:** NPCs e policiais num raio de 17 m de uma granada no ar fogem dela (`p._gf`).
  - **Aeronaves:** sem parede invisível (limites antigos ±365/±420 e teto 90/100 removidos). Fora de |x|,|z|>400 ou y>150 o motor falha (`v._fl`), a aeronave cai girando e explode no chão/água; aviso a 375 m / 130 m.
  - **Tubarão:** só ataca a >130 m da costa (antes 70); o jogador a nado pode ir até ±600 (antes ±450).
  - **Lagos da praia:** os lagos perto da areia (`PONDS` com `z>283`) saem de verdade (decalques do `XINST` zerados, minimapa repintado, física removida) e até 6 deles são recriados em outro canto do mapa (`PONDMOVE`, fora da cidade e longe de prédios/pista).
  - **Placas:** cada plano de texto em canvas com `DoubleSide` vira `FrontSide` + uma cópia virada para trás (não aparece mais espelhado).
  - **Áudio:** `scream`/`snd('scream')` agora são vozes com formantes, vibrato e respiração (grito e "ai"); sirene `wail2` suave (triângulo/senoide com curva de frequência e reverb); `blip` não usa mais onda quadrada; sirene da ambulância e `chime/fanfare` sem quadrada.

- **4ª rodada (v46):**
  - **Armas:** `AIM`/`AP` são locais do bloco v11d — de fora use `window.AIMST()` e `window.CAMPITCH()` (um `ReferenceError` ali quebrava `launch`: o RPG não recarregava). A animação de recarga (v48 §9) zerava a posição do RPG (que é filho do corpo): agora `cur=='rpg'` volta a `(.32,.66,.1)`.
  - **Drive-by:** a mira (`#ret`) aparece enquanto o botão 🔫 está pressionado e o tiro vai na direção real da câmera (`cam.getWorldDirection`).
  - **Tiros no alto:** `tracer` global agora usa a altura do atirador (`P.y+.4`) e do alvo (`GRH+1.3`); erro = horizontal.
  - **Natação:** `swimNoGun` força `cur='fist'` enquanto `FZ.mode=='swim'` e restaura a arma ao sair.
  - **Barco da polícia:** ao entrar numa lancha policial com policial (`v.pboat && v.npcd`) começa um QTE (4 botões, 1,9 s cada, `#q46`); acertar derruba o policial (SINK: arco, splash, afunda e some), errar leva 18 de dano e joga o jogador na água.
  - **Chão invisível no mar:** `window.ARN` (interiores dos imóveis a oeste, garagem, arenas de minigame) fazia `waterAt` virar "terra" em retângulos grandes do mar (ex.: x −460..−335, z −140..424). `ARN.some` agora só considera retângulos do mar quando `inZone()` (`MGACT`, `XPROP.IN.prop>=0` ou `V45.G6.inHall`); retângulos em terra e os da ilha (`a.isl`) valem sempre.
  - **Aeronaves caindo:** `AIRFLOOR` inclui o terreno (`GRH`); com o cheat `GOD` o `dmgV` bloqueava a morte do veículo do jogador e a aeronave atravessava o chão — agora `GOD` é suspenso só durante a queda (`v._fl`) e há morte forçada.
  - **Montanha com estrada:** `F.mts` com `road` ganham `H=0,crag=0,flat=1` (o RNG continua igual); no lugar fica um parque (praça, fonte, árvores com colisão) e 2 prédios `bld()`. Sobrou 1 montanha livre sem estrada quando existir.
  - **Ilha selvagem (`window.ISL`, x 560, z −110, r 58):** disco de areia/grama + 45 árvores + pedras; a física de terra firme vem de faixas em `ARN` (`isl=1`). Animais são peds (`p.an`: urso, onça, porco, veado) com modelo de caixas (`mkAnimal`) e IA própria (`anDrive`); urso/onça atacam a pé na ilha, porco/veado fogem; `crime()` é ignorado a <98 m da ilha; `civ()` (densidade) ignora `p.an/p.lf`; limite do laço de peds 720; o jogador a pé vai até ±720 perto da ilha; o tubarão não ataca a <128 m dela. Reposição de animais quando o jogador está a >148 m.
  - **Futebol:** cada tempo tem 1:50 (`FB.t=110`).

- **5ª rodada (v46):**
  - **Fuga de motoristas** (tiroteio): `vrxTick` limita `S[t].m` a 58% enquanto foge; `_vfl` usa 1,05×/0,72× em vez de 1,7×/1,2×.
  - **Lagos:** só 2 lagoas (parques em lotes `lagoon`, em (−125,27) e (175,−75)) sobraram; os outros `PONDS` perderam decalques (`XINST`), física e minimapa e viraram árvores com colisão; 8 casas (`isH`) ganharam piscina pequena (5,8×3,4, nadável). O recoloca-lagos da rodada anterior foi desligado (`PM=[]`).
  - **Ilha (r=125):** 4 áreas (`ZN`): ursos (caverna, lago, pinheiros), onças (selva, troncos, pedras), porcos (pasto, cercado, feno, poça), veados (campo e lago). Animais ficam na própria área ao vagar; sem parede invisível (limite só na borda real da ilha); ao perseguir têm coleira (`leash`: urso 50 m, onça 62 m da área, ou 14 s) e depois voltam e ignoram o jogador por 12 s. Ilha aparece no minimapa (`mini` wrapper). Animais usam `p.mg=1`, `_wm=1` e `CFG.gore` é zerado durante o `hurt` deles (sem membros arrancados). Sons próprios (`asnd`: urso, onça, porco, veado); `scream()` ignora animais.
  - **Aeronave que cai** mata o jogador (`hurtP(500)`, ejetado; com cheat `GOD` ele sobrevive de propósito).
  - Não foi reproduzido: aeronave atropelando NPCs em voo (o código base exclui `t=='plane'`).

- **6ª rodada (v46):** ilha também no mapa do menu de pausa (`drawMap` wrapper, sem tocar `bgc`; mar azul à direita de x=350) e seta do jogador redesenhada por cima da ilha no minimapa e no mapa. Piscinas só dentro da cidade (|x|,|z|<215), longe das linhas `L`, e só onde o `bgc` ao redor é gramado (`gOK`: ruas externas **não** estão no `bgc`, por isso nada fora da grade); ao lado do muro da casa, deslocadas do centro (porta). Trem agora nasce parado na 1ª estação (antes em x=-300); a lógica já ia só de Porto Moll (-280) a Vila Moll (125) e voltava (conferido por simulação de 33 min).

- **7ª rodada (v46, bloco "7ª rodada: sem rampas..."):** `XTERR.RAMPS` esvaziado e as malhas das rampas removidas; extensões das ruas ao sul (x=-150/-50, ponte, retorno com canteiro), o anel viário solto (`F.ring`) e a estrada/mirante da montanha foram removidos por varredura de `sc.children` (por cor e posição) e viram árvores (colisores antigos neutralizados com `h=-1`, nunca `splice`); o **parque da montanha deixou de ser construído** (só árvores). Muros de lote (decal `0x9a9a9a`, fino, ≥20 m) a <11 m da porta de um imóvel somem. Garagem dos apartamentos de luxo (`sideSpot`, bloco v45): a porta agora olha para a rua (`yaw+π`, posição `+fx*bk`) e a saída do carro sai para a rua. Rua que sobrou de propósito: acessos aos imóveis (`5c`), avenida costeira (x≈276) e ruas da grade.

- **8ª rodada (v46 + boot):** **ilha dos animais removida** (todo o bloco `ISL/ZN/AN`, minimapa e mapa de pausa; os `window.ISL&&` que sobraram nos laços de limite/tubarão são guardas inofensivas). Mapa de pausa: legenda em 2 colunas com rolagem, zoom-out até `msc=.22`. Aeronaves: motor falha só a >900 m (aviso 850 m) ou y>260. Polícia no mar/fuga: `window.CANVAN(o)` (bloco v48) — viaturas, lanchas e helicópteros só somem a >170 m ou a >95 m **fora da tela** (atrás da câmera); lancha da polícia que o jogador dirige nunca some; sem estrelas, as lanchas se afastam e o helicóptero volta à base (`rtb`). Loja de armas: `#amm` (tela cheia AMMU★NATION, vendedor do jogo renderizado por `rd` num `WebGLRenderTarget` de braços cruzados, lista de armas com `WIMG`, barras de estatística, Comprar/paraquedas/colete) envolve `openShop/closeShop/shopUI` sem mexer em `buy`/`SH`. Tela inicial: arte nova em `--mimg2` (o `--mimg` antigo continua no menu do jogo/slots), zonas clicáveis `bj`/`bcfg`/`bs`; **Configurações** inicia o carregamento e abre `CFGUI.open()` ao terminar. Loading: 4 artes em `LIM[]` (JPEG base64), troca aleatória a cada 2,8 s com dica (`TIPS`), barra e % em HTML por cima da faixa da arte.

- **Melhoria gráfica — Etapas 0 e 1 (v46):** `CFG.vq` (Qualidade Visual Baixo/Alto, padrão Alto) + `window.VQ` (`on`, `lv` 0–2, `tag()` aparece no contador como `Q2`). Governador: média móvel do tempo de quadro; >40 ms por 4 s desce um nível (nível 1 mantém tudo, nível 0 desliga bruma do céu e sombras de árvores), <27 ms por 12 s sobe. Alto: sol mais quente/forte (×1,2), hemisférica ×0,88, ambiente ×0,6 (só realista), uniform `uQ` no shader do céu (bruma no horizonte + brilho do sol) e **sombra de contato nas copas** (1 `InstancedMesh`, `userData.fxp=1`, ~1.060 instâncias a partir das cores de copa em `XINST`). **Medida no celular (usuário, tudo no máximo): CPU-bound** — calmo 46 FPS/453 DC/UPD 6,5/RND 14/ESP 1; carro 33 FPS/607 DC/RND 19; perseguição 19 FPS/800 DC/RND 31; explosão 14 FPS/ESP 22 (só aí a GPU pesa: fumaça/transparência). Regra: nada que some draw calls ou nós de cena; ganho de FPS vem de reduzir DC/RND.

- **Veículos vivos (v46, bloco "veículos vivos"):** ocupantes visíveis (`v._oc`: 1 malha com cor por vértice, até 8 por vez a <28 m, só `car/truck/junk`; o cabine vira vidro translúcido enquanto o ocupante aparece e volta ao opaco antes do LOD mesclado) — o antigo `v.drv` fica sempre oculto. Tiro: `shoot` embrulhado com `SHT`; `dmgV` com `SHT` mata o motorista (50%/tiro, garantido no 3º; não vale para `pol/disp`), `killDriver` (sangue, `crime(.5)`, `DRVD`: acelera 2,2–3,8 s e freia). Roubo animado (`EA`, wrapper mais externo de `act`): carro/caminhão/ônibus/supercarro = anda até a porta (contorna pela traseira se preciso), porta (`v._door`) abre, puxa o ocupante (o ped criado pelo `takeover` é "escondido" e arrastado), entra, porta fecha; moto/bike = monta com salto; barco = pula para dentro. Entrada **já aconteceu no jogo** (`P.veh` setado); a animação é só visual e trava o controle (`J/tb/tc`, `v.sp=0`). Desligado com Qualidade Visual Baixo (`lowQ()`). Corpo de motorista morto sai (ped morto) ao entrar. Ambulância-van: `window.mkAmbVan(v)` (substitui os filhos do `spawnV('car')`, `v.amb`, `kd='ambulancia'`; o evento `ambulance()` usa a van e 3 vans ficam estacionadas no hospital com `v.parked=1`).

- **Interiores, saída animada e trem (v46, mesmo bloco "veículos vivos"):** `intTick` (4×/s) liga `v._in` = 1 mesh de geometria mesclada (cor por vértice, 1 draw call) com volante/bancos/painel/retrovisor (carros, picapes, caminhões, supercarros), bancos e janelas (ônibus), cabine (aviões/helis) e console/bancos (barcos), só para ≤8 veículos a <~30 m e fora de Qualidade Visual Baixo; a cabine vira vidro translúcido enquanto o interior aparece. **Trem:** `trainTick` troca (a <48 m) carroceria/janelas por casca com aberturas + vidros + bancos/barras (`g._ti`), escondendo os filhos originais 0,4,5,6. **Sair do veículo:** `exitAct` (dentro do wrapper `act`): carro/caminhão/ônibus lento = `startXA` (abre porta, sai); com `sp>6` = ragdoll lançado do banco (herda velocidade, porta balança `flapDoor`); moto >2,5 = pulo (`HOP`), ragdoll/dano se >16; `seatedPlayer` mantém o jogador no banco. API: `window.VEHX`. **Aeronave × NPCs:** o laço `coast` (bloco v16) agora ignora `plane/boat` e quem está a y≥1,5 — antes atropelava NPCs do chão com o helicóptero no ar.

- **Interiores reformulados (v46, 2ª versão, substitui a cápsula translúcida):** nada de cabine virando vidro. Perto (<~30 m, ≤8 veículos, só fora de Qualidade Visual Baixo) `interiorOf/intOn` **escondem** a cabine original (`cab`, para-brisa de caminhão, cabines de barco/helicóptero, fuselagem de avião) e ligam **2 malhas**: `v._in` (opaca, cor por vértice: teto, colunas A/B/C na cor da carroceria, forro, bancos, painel, volante, console, retrovisores) e `v._ing` (vidros em quadros `Q`, `GLM` translúcido) — gerador `gh()` (cabine com inclinação de para-brisa/vidro traseiro, janelas entre colunas), `carInt` (sedan/esportivo/luxo/suv/pickup/caminhão/supercarro), `planeInt` (cockpit integrado à fuselagem: mono/biplano/jato), `heliInt`, `boatInt` (barco/lancha abertos com console+para-brisa; pesqueiro/iate com cabine de janelas), `motoInt` (assento, tanque, guidão, painel, retrovisores; sem esconder nada), ônibus com vidros. `bake()` aceita `{t:'q'}` (quadrilátero). `seatedPlayer` calcula escala/altura pelo teto da cabine (cabeça não atravessa). Chaves de cache em `IGEO` (incluem cor da carroceria).

- **HD v2: carro realista (v46, último bloco `gb` "HD v2", `window.HD`).** Os kinds **`esportivo`, `rua` e `luxo`** usam o mesmo modelo GLB (rua mantém o neon de chão) (Car Concept, CC-BY 4.0, `docs/CREDITOS.md`); o resto da frota segue com caixas até o usuário aprovar. Arquivos `gfx/GLTFLoader.js` + `gfx/models.js` (`GLBPACK` = `esportivo` 37,7k tri + `esportivo_lo` 9,6k tri, base64, **sem texturas**, cores por vértice) carregados no boot depois do `three.min.js` (ausentes → caixas). Pipeline: `gfx/tools/process_glb.mjs` (simplifica) → `build_car.mjs` (une por material: `st_p1` tinta tingível, `st_dark`, `st_glass`, `st_lights`; 4 rodas `wheel_*` com centro no pivô; nós `seat_driver`/`cabin_roof`); `LO=1` gera a versão distante. `scan` (0,25 s, ≤2/ciclo, <70 m) esconde o carro de caixas **por camada** (`layers.set(31)` em cada filho e descendentes; guarda `_l0`; **nunca por `visible`**: o LOD mesclado `lmOff` restaurava `visible=true` das caixas e elas reapareciam junto do HD — roda velha, asa e cabine de vidro duplicadas; `lmCollect` ignora meshes sem camada 0; `upgrade` chama `lmOff` antes) (não remove) e põe `v._hd`; corpo em pivô `v._hdB` (inclina com frenagem/curva), rodas giram por `v.sp` e as dianteiras esterçam pela guinada, escala **uniforme** `s` (=min(Lt*1.18/L, Wt*1.35/W); esterço = atan(2.8·guinada/velocidade com sinal), clamp ±0,35 e zona morta — a versão antiga usava atan2 e travava as rodas a 0,5 rad em marcha à ré), prévia da concessionária: `vehShop.spawnPrev` chama `HD.up(v)` direto (o `scan` não roda com o jogo pausado), `v._seat` recalculado (motorista no centro, x=0, como no modelo), `v._hw`. LOD: geometria `_lo` além de 16 m (histerese 13) e quando `_lm`; `lmBuild` agora respeita cor por vértice (`geometry.attributes.color`). Vidro translúcido sempre ligado (escondido quando `_lm`); interior é do próprio modelo (`HD.intOn` é no-op; `_intOn` só sinaliza para `seatedPlayer`). `restoreWorld` que arranca filhos: `scan` refaz. Cartoon (`GFX===0`) usa Lambert. Medido (6 esportivos a 13–21 m): draw calls 370 → 263, triângulos +111k (3 em detalhe). Limitações: porta animada é a caixa antiga (porta do modelo é estática), faróis não acendem à noite, sem deformação.

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

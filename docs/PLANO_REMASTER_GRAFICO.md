# Plano de reconstrução visual — Crazy Thief Dude

## 1. Diagnóstico (medido, não suposto)
- **Arquitetura:** `game.html` único (~2 MB, 56 blocos `gb` empilhados, ~40 camadas de `update`), Three.js r128, WebView Android. Sem bundler, sem GLTFLoader, sem PBR hoje (materiais Toon/Lambert; Phong em veículos/peds no modo realista).
- **Modelos:** 100% primitivos (`box()` + `BG` unitário). Carro = 2 caixas + 4 rodas; pedestre = ~22 caixas; prédio = caixas com textura de canvas procedural. Não existe pipeline de GLB.
- **Gargalo real no celular (medido pelo usuário, tudo no máximo):** CPU-bound — calmo 46 FPS / 453 DC / RND 14 ms; carro 33 FPS; perseguição 19 FPS / 800 DC; explosão 14 FPS (GPU só pesa com fumaça). Cada objeto novo = draw call + nós de matriz.
- **Consequência:** "mais polígonos e mais objetos" derruba o FPS. Qualidade só entra se for **malha única por entidade, material compartilhado, textura em atlas e LOD**.
- **Restrições:** mapa fixo por semente (blocos novos só no fim; `BURN/QUIET`), REGRA Nº 1 (nada removido), checklist de verificação a cada commit.
- **Recursos externos (testado agora no ambiente):** `raw.githubusercontent.com` e registro npm respondem; ambientCG, Polyhaven e jsDelivr estão **bloqueados**. Dá para buscar GLB/texturas **de repositórios públicos do GitHub** e o `GLTFLoader` r128 via `npm pack three@0.128.0`. Tudo teria de ser **embutido no APK** (sem download em jogo) e com **licença CC0/MIT conferida**. Não existe modelo "de GTA"; fazemos identidade própria.

## 2. Metas honestas
- 60 FPS no celular com GLB detalhado é **incompatível** com o que foi medido (19–46 FPS hoje). Meta realista: manter o nível atual de FPS no Alto/Médio e ganhar **30 FPS estáveis no Baixo**; qualidade extra só onde o orçamento permitir (veículo do jogador e arredores).
- Mundo todo "fotorrealista" não cabe num único `game.html`/WebView. A evolução é por camadas e por distância (detalhe só perto).

## 3. Etapas (cada uma: implementar → testar → medir → commit)
| # | Etapa | Conteúdo | Risco |
|---|---|---|---|
| 0 | **Base de medição** (feito) | contador UPD/RND/ESP, checklist | — |
| 1 | **Luz/céu/atmosfera** (feito 1ª parte: sol, bruma, sombra de copa) | ciclo dia/noite real, faróis/postes funcionais (emissivo + sprites, sem PointLight), tone mapping, neblina | baixo |
| 2 | **Pipeline de recursos** | `GLTFLoader` embutido, atlas de texturas 512–1024 com mipmaps, KTX2 só se o WebView suportar; cache e descarte | médio |
| 3 | **Veículos HD (prioridade 1)** | substituir o modelo de caixas por GLB low-poly (≤6–8 mil tri, 1 material PBR + atlas) por categoria: sedan, esportivo, SUV, picape, caminhão, ônibus, moto; rodas separadas girando; suspensão/inclinação reais; LOD → malha atual. Interiores já feitos entram como "LOD 0" | alto |
| 4 | **Física de veículos** | suspensão por mola, transferência de peso, aderência/derrapagem, freio progressivo (sobre `drive()` atual, sem trocar colisão) | alto (mexe em jogabilidade) |
| 5 | **Personagens** | corpo GLB com esqueleto + clips (andar/correr/dirigir/mirar/recarregar) via `AnimationMixer`; hoje animação é rotação de caixas | alto |
| 6 | **Cidade** | prédios com fachadas em atlas (portas/janelas/telhado), calçada/asfalto com textura e rejunte, árvores em impostor+GLB, props urbanos (instanced) | médio |
| 7 | **Água e clima** | onda por shader, espuma de proa, chuva (partículas instanciadas), poças, marcas de pneu (decalques instanciados) | médio |
| 8 | **Aeronaves e barcos** | física de voo (sustentação/arfagem), pouso/decolagem; flutuação e ondulação acopladas à água | alto |
| 9 | **Escalabilidade Baixo/Médio/Alto** | LOD por distância, orçamento de NPCs, resolução dinâmica (já há governador), descarregamento fora da área | médio |

## 4. Recomendação de ordem
2 → 3 (um carro de cada categoria, comparando FPS no seu celular) → 1 (noite/faróis) → 4 → 5 → 6 → 7 → 8 → 9. Parar e medir no celular depois da 3: se o custo for alto, ajusto orçamento antes de multiplicar o resto.

## 5. O que preciso de você
1. Autorizar começar pela **Etapa 2+3** (pipeline + primeiros veículos).
2. Fontes de arte: posso usar GLB/texturas **CC0/MIT de repositórios públicos do GitHub** (licença anotada em `docs/CREDITOS.md`); se você tiver pacotes comprados/próprios, mande os arquivos.
3. Confirmar que o APK pode crescer (~15–40 MB de assets).

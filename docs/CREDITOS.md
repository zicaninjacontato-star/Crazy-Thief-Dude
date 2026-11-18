# Créditos e licenças de recursos de terceiros

Cada recurso é verificado individualmente (licença original conferida). Aceitos: CC0, MIT e CC-BY 4.0 (uso comercial permitido, com crédito registrado aqui).

| Recurso | Arquivo | Autor | Licença | Origem |
|---|---|---|---|---|
| GLTFLoader.js (three.js r128) | `gfx/GLTFLoader.js` | autores do three.js | MIT | npm `three@0.128.0`; licença em `gfx/LICENSE-threejs-MIT.txt` |

## Histórico
- **Kenney Car Kit (CC0)** foi integrado e **removido** (estilo cartoon fora do padrão visual desejado). Nenhum modelo dele permanece no jogo.
- Nenhum modelo de veículo realista está integrado ainda; aguarda aprovação do primeiro sedã (ver plano em `docs/PLANO_REMASTER_GRAFICO.md`).

## Como registrar um modelo novo
Para cada GLB: nome, autor, URL da página, licença exata (CC0 / CC-BY 4.0), data da verificação, alterações feitas e arquivo de licença/captura em `gfx/`.

## Modelo integrado (kind `esportivo`)
| Recurso | Autor | Licença | Origem |
|---|---|---|---|
| **Car Concept** (`CarConcept.glb`) | Khronos Group / Eric Chadwick, a partir do modelo de domínio público "Free Concept Car 004" de Unity Fan (CC0) | **CC-BY 4.0** (licença exclui logotipos/marcas Khronos) | `github.com/KhronosGroup/glTF-Sample-Assets` → `Models/CarConcept` (LICENSE.md conferido) |

**Alterações feitas:** simplificação de malha (213 mil → 37,7 mil triângulos; versão distante 9,6 mil), remoção de **todas as texturas** (logotipos Khronos e placa saem junto; cores passam a vértice), união por material, 4 rodas separadas, espelhamento não necessário. Scripts: `gfx/tools/process_glb.mjs`, `gfx/tools/build_car.mjs`; saídas em `gfx/src/*.glb` (embutidas em `gfx/models.js`).

Crédito exigido (CC-BY 4.0): "Car Concept" © Khronos Group / Eric Chadwick, derivado de "Free Concept Car 004" (Unity Fan, CC0); licença CC BY 4.0; modificado (simplificado e sem texturas).

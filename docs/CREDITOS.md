# Créditos e licenças de recursos de terceiros

Cada recurso foi verificado individualmente (arquivo de licença original conferido). Só entram recursos CC0 ou MIT.

| Recurso | Arquivo no jogo | Autor | Licença | Origem / verificação |
|---|---|---|---|---|
| **Car Kit 3.1** — modelos de carros (sedan, sedan-sports, hatchback-sports, suv, suv-luxury, taxi, police, ambulance, firetruck, van, truck, delivery, delivery-flat, garbage-truck, truck-flat, race) e textura `colormap` | `gfx/models.js` (GLB em base64) | Kenney (www.kenney.nl) | **CC0 1.0** | Pacote oficial reempacotado em `github.com/Arslan12216775/kenney_car-kit`; o `License.txt` original do pacote ("Creative Commons Zero, CC0") está em `gfx/LICENSE-kenney-car-kit.txt`. Atribuição é opcional, feita aqui por cortesia. |
| **Motocicleta** (`vehicle-motorcycle.glb`) — ainda não usada no jogo | `gfx/models.js` | Kenney | **MIT** (repositório) / arte CC0 | `github.com/KenneyNL/Starter-Kit-Racing`, licença em `gfx/LICENSE-kenney-starter-kit-racing-MIT.txt`. |
| **GLTFLoader.js** (three.js r128, `examples/js/loaders`) | `gfx/GLTFLoader.js` | autores do three.js | **MIT** | Pacote npm `three@0.128.0`; licença em `gfx/LICENSE-threejs-MIT.txt`. |

## Modelos considerados e recusados
- `ferrari.glb` dos exemplos do three.js: licença CC-BY 4.0 (exige atribuição específica; fora da regra "CC0 ou MIT"). Não usado.
- ambientCG / Polyhaven (CC0): inacessíveis a partir do ambiente de desenvolvimento (rede bloqueada); podem entrar depois se a rede permitir.

## Tratamento aplicado
Os GLB não foram alterados. Em tempo de execução a textura `colormap` é reduzida a 128×128 e recolorida por veículo (célula de tinta), e as faces de vidro viram janelas recortadas + vidro translúcido (`game.html`, bloco "HD: modelos GLB").

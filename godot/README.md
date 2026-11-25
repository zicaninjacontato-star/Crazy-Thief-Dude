# Crazy Thief Dude Next — fatia de teste em Godot 4.3

Protótipo para avaliar o visual e o desempenho de uma versão do jogo em motor nativo. **O jogo web (`../game.html`) não depende disto.**

Conteúdo (lote 7): táxi e 3 missões, praia/mar/píer com barcos, aeroporto com avião e helicóptero, delegacia, polícia por estrelas (viaturas, SWAT, helicóptero), interiores das lojas, roleta de armas, mira manual, fuzil/sniper/bazuca/granada, soco em combo, explosões, dano e destruição de veículos, batida de moto, queda, entrar/sair animado em todos os veículos, tubarão.

Conteúdo (lote 6): motos (estacionadas, no trânsito e na concessionária) e ônibus com linha e pontos; noite mais clara e sem o travamento ao anoitecer.

Conteúdo (lote 5): loja de roupas (camiseta, calça, jaqueta, boné/touca, óculos, cabelo, com prova no personagem), ciclo de dia e noite (pôr do sol, lua, janelas acesas, postes e faróis com luz de verdade) e relógio no HUD.

Conteúdo (lote 4): menu inicial (continuar / novo jogo / configurações), pausa, configurações (sangue, gore, qualidade gráfica baixa/média/alta, volume, contador de FPS), loja de armas AMMU★NATION (armas, munição, colete), concessionária (5 modelos, 8 cores) e save automático.

Conteúdo (lote 3): armas (soco, pistola, submetralhadora, espingarda) com mira automática para o celular, botões ATIRAR e troca de arma, rastro e clarão de tiro; policiais descem da viatura, perseguem a pé e atiram; morte com ragdoll do jogador → WASTED → hospital (-$100); preso a pé → delegacia (-$100); pedestres mortos deixam dinheiro.

Conteúdo (lote 2): carros próprios gerados por código (sedã, hatch, SUV, picape, esportivo, viatura) com centro de massa baixo e anticapotamento; HUD com minimapa, vida, dinheiro e estrelas; sons sintetizados (motor, sirene, batida, grito, passos); ragdoll físico (corpos rígidos + juntas) com sangue e gore (membro arrancado em impacto forte); cidade fundida por material (menos draw calls) e resolução 3D a 75% no celular.

Conteúdo original: um bairro 5×5 quadras gerado por código (asfalto, calçadas com rejunte, prédios com fachadas PBR com janelas reflexivas, postes, árvores), céu, sol com sombras reais, tonemap ACES, bloom e neblina; personagem a pé (andar/correr/pular, provisório até haver modelo com esqueleto); carro com física do Godot (`VehicleBody3D`: suspensão, atrito, transferência de peso); pedestres; atropelamento → estrelas → viatura persegue → "preso".

Controles: joystick (esquerda), arrastar no meio/direita gira a câmera, botões CARRO / PULO / CORRER (a pé) e ACEL / FREIO (no carro). Teclado: WASD/setas, E entra/sai, Espaço pula/freio de mão, Shift corre, J/Ctrl atira, Q/Tab troca a arma.

Build: o workflow `.github/workflows/godot-apk.yml` exporta o APK (release `godot-slice`, pacote `com.crazythiefdude.next`, instala ao lado dos outros).

Teste local (captura): `godot --path godot --rendering-driver opengl3 --rendering-method gl_compatibility -- --shot=saida.png --view=street|car|drive|walk`.

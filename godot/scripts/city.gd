extends Node3D
## Gera o bairro de teste: quadras com calçadas, prédios com fachadas PBR, ruas com faixas,
## postes e árvores (MultiMesh), além de toda a colisão estática.

const M := preload("res://scripts/mats.gd")

const W2 := preload("res://scripts/world2.gd")
const N := 5            # quadras por lado
const CELL := 64.0      # distância entre centros de quadras
const ROADW := 14.0     # largura do asfalto entre quadras
const SIDE := 4.0       # largura da calçada
var BLOCK := CELL - ROADW   # lado da laje da quadra (calçada + lotes)

var body: StaticBody3D
var rng := RandomNumberGenerator.new()
var lanes: Array = []   # pontos de rota de carros (centro das faixas)
var walk_loops: Array = []  # percursos de pedestres (um por quadra)
var hospital_pos := Vector3.ZERO
var police_pos := Vector3.ZERO
var shops: Array = []   # {type, pos, name}
var lamp_mat: StandardMaterial3D
var bus_route: Array = []   # [{p: Vector3 (faixa), stop: bool}] em volta das quadras 1..3 x 1..3

func _ready() -> void:
	rng.seed = 2026
	body = StaticBody3D.new()
	body.name = "Colisao"
	add_child(body)
	_ground()
	for i in N:
		for j in N:
			_block(_center(i), _center(j))
	_markings()
	_props()
	_landmarks()
	_bus_line()
	_flush()
	for sc in _store_cars:
		var b: Dictionary = preload("res://scripts/carmodel.gd").build(sc[2], sc[3])
		var root: Node3D = b.root
		add_child(root)
		root.position = sc[0]
		root.rotation.y = sc[1]
		for wd in b.wheels:
			root.add_child(wd.node)
			wd.node.position = wd.pos

## linha de ônibus: retângulo em volta das quadras 1..3 x 1..3, com ponto no meio de cada lado
func _bus_line() -> void:
	var r := CELL * 0.5 + 2.6
	var x0 := _center(1) - r
	var x1 := _center(3) + r
	var z0 := _center(1) - r
	var z1 := _center(3) + r
	var xm := _center(2)
	var zm := _center(2)
	var pts := [[x0, z0, false], [x0, zm, true], [x0, z1, false], [xm, z1, true], [x1, z1, false], [x1, zm, true], [x1, z0, false], [xm, z0, true]]
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var pole := M.plain(Color(0.3, 0.32, 0.34), 0.4, 0.8)
	var roof := M.plain(Color(0.15, 0.4, 0.75), 0.4, 0.3)
	var glass := M.plain(Color(0.6, 0.7, 0.75), 0.1, 0.6)
	var bench := M.plain(Color(0.35, 0.22, 0.12), 0.7)
	for q in pts:
		var p := Vector3(q[0], 0.0, q[1])
		bus_route.append({"p": p, "stop": q[2]})
		if not q[2]:
			continue
		# abrigo na calçada, do lado de fora do retângulo
		var out := Vector3(signf(p.x - cx), 0, 0) if absf(p.x - cx) > absf(p.z - cz) else Vector3(0, 0, signf(p.z - cz))
		var c := p + out * 6.2 + Vector3(0, 0.15, 0)
		var side := Vector3(out.z, 0, out.x).abs()
		var lng := side * 3.2 + out.abs() * 0.12
		_box(Vector3(0.1, 2.6, 0.1), c + side * 1.5 + out * 0.5 + Vector3(0, 1.3, 0), pole, false)
		_box(Vector3(0.1, 2.6, 0.1), c - side * 1.5 + out * 0.5 + Vector3(0, 1.3, 0), pole, false)
		_box(side * 3.4 + out.abs() * 1.4 + Vector3(0, 0.08, 0), c + Vector3(0, 2.62, 0), roof, false)
		_box(lng + Vector3(0, 1.6, 0), c + out * 0.62 + Vector3(0, 1.2, 0), glass, true)
		_box(side * 2.4 + out.abs() * 0.4 + Vector3(0, 0.08, 0), c + out * 0.35 + Vector3(0, 0.48, 0), bench, false)
		_box(Vector3(0.08, 2.4, 0.08), c - out * 0.55 + side * 2.2 + Vector3(0, 1.2, 0), pole, true)
		_box(side * 0.5 + out.abs() * 0.06 + Vector3(0, 0.5, 0), c - out * 0.55 + side * 2.2 + Vector3(0, 2.6, 0), M.emissive(Color(0.15, 0.45, 0.95), 1.2), false)
		var lb := Label3D.new()
		lb.text = "ÔNIBUS"
		lb.font_size = 64
		lb.pixel_size = 0.004
		lb.outline_size = 8
		lb.shaded = false
		lb.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		lb.position = c - out * 0.55 + side * 2.2 + Vector3(0, 3.05, 0)
		add_child(lb)

func _flush() -> void:
	for mat in _batch:
		var mi := MeshInstance3D.new()
		mi.mesh = _batch[mat].commit()
		mi.material_override = mat
		add_child(mi)
	_batch.clear()

func _center(i: int) -> float:
	return (i - (N - 1) * 0.5) * CELL

func extent() -> float:
	return N * CELL * 0.5

## Caixas estáticas são acumuladas por material e fundidas numa malha só no fim (_flush):
## a cidade inteira vira ~15 draw calls em vez de centenas.
var _batch := {}

func _box(size: Vector3, pos: Vector3, mat: Material, collide := true, parent: Node = self) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	if parent == self:
		if not _batch.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_batch[mat] = st
		_batch[mat].append_from(bm, 0, Transform3D(Basis(), pos))
	else:
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = mat
		mi.position = pos
		parent.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.position = pos
		body.add_child(cs)

func _ground() -> void:
	var ext := extent() + ROADW * 0.5
	var asphalt := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(ext * 2.0, ext * 2.0)
	asphalt.mesh = pm
	asphalt.material_override = M.asphalt()
	add_child(asphalt)
	# terra só na ilha (cidade + praia) e na península do aeroporto: mar em volta
	for r in W2.land_rects():
		var grass := MeshInstance3D.new()
		var gm := PlaneMesh.new()
		gm.size = r.size
		grass.mesh = gm
		grass.position = Vector3(r.get_center().x, -0.03, r.get_center().y)
		grass.material_override = M.grass()
		add_child(grass)
		# chão firme só em terra (o leito do mar fica no world2, a −12 m)
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(r.size.x + 8.0, 20.0, r.size.y)
		cs.shape = bx
		cs.position = Vector3(r.get_center().x + (4.0 if r.end.x >= W2.SHORE_X else 0.0), -10.0, r.get_center().y)
		body.add_child(cs)

func _block(cx: float, cz: float) -> void:
	# laje da calçada (meio-fio de 15 cm)
	_box(Vector3(BLOCK, 0.15, BLOCK), Vector3(cx, 0.075, cz), M.sidewalk())
	# percurso de pedestres ao redor da quadra
	var r := BLOCK * 0.5 - 1.6
	walk_loops.append([Vector3(cx - r, 0.15, cz - r), Vector3(cx + r, 0.15, cz - r), Vector3(cx + r, 0.15, cz + r), Vector3(cx - r, 0.15, cz + r)])
	var inner := BLOCK - SIDE * 2.0
	var downtown: float = 1.0 - clamp(Vector2(cx, cz).length() / (extent() * 1.1), 0.0, 1.0)
	var plan := rng.randi_range(0, 9)
	# quadra com loja: prédios ao redor e a loja (com vitrine e interior visível) de frente para a rua sul
	var bi := roundi(cx / CELL + (N - 1) * 0.5)
	var bj := roundi(cz / CELL + (N - 1) * 0.5)
	if Vector2i(bi, bj) == POLICE_BLOCK:
		_police_station(cx, cz)
		return
	if Vector2i(bi, bj) == SAFE_BLOCK:
		_safehouse(cx, cz, inner, downtown)
		return
	var stype: String = STORE_BLOCKS.get(Vector2i(bi, bj), "")
	if stype != "":
		var hh := inner * 0.5
		_building(Rect2(cx - hh, cz - hh, hh - 9.0, inner), downtown * 0.6)
		_building(Rect2(cx + 9.0, cz - hh, hh - 9.0, inner), downtown * 0.6)
		_building(Rect2(cx - 9.0, cz - hh + 14.0, 18.0, inner - 14.0), downtown * 0.6)
		_store(Rect2(cx - 9.0, cz - hh, 18.0, 14.0), stype)
		return
	if plan == 0:
		_park(cx, cz, inner)
		return
	var lots: Array = []
	var h := inner * 0.5
	if plan < 3:
		lots.append(Rect2(cx - h, cz - h, inner, inner))
	elif plan < 6:
		lots.append(Rect2(cx - h, cz - h, inner * 0.5, inner))
		lots.append(Rect2(cx, cz - h, inner * 0.5, inner))
	else:
		for a in 2:
			for b in 2:
				lots.append(Rect2(cx - h + a * inner * 0.5, cz - h + b * inner * 0.5, inner * 0.5, inner * 0.5))
	for lot in lots:
		_building(lot, downtown)

func _building(lot: Rect2, downtown: float) -> void:
	var gap := 1.2
	var w := lot.size.x - gap * 2.0
	var d := lot.size.y - gap * 2.0
	var floors := int(round(lerp(2.0, 16.0, pow(downtown, 1.3)) * rng.randf_range(0.6, 1.25)))
	floors = clamp(floors, 2, 22)
	var style := rng.randi_range(0, 4)
	if floors > 11 and rng.randf() < 0.6:
		style = 2
	var hgt := floors * 3.4
	var c := lot.get_center()
	# térreo com vitrines (4 m) + corpo do prédio
	var ground_h := 4.0
	_box(Vector3(w, ground_h, d), Vector3(c.x, ground_h * 0.5 + 0.15, c.y), M.facade(4 if style != 4 else 0))
	_box(Vector3(w, hgt - ground_h, d), Vector3(c.x, ground_h + (hgt - ground_h) * 0.5 + 0.15, c.y), M.facade(style))
	# marquise sobre o térreo
	var awn := M.plain(Color.from_hsv(rng.randf(), 0.55, 0.55), 0.6)
	_box(Vector3(w + 1.6, 0.25, d + 1.6), Vector3(c.x, ground_h + 0.25, c.y), awn, false)
	# platibanda e laje de cobertura
	var top := hgt + 0.15
	var roof := M.concrete(Color(0.42, 0.41, 0.4))
	# platibanda e laje COM colisão (antes o jogador pisava 1 m abaixo e "afundava" no telhado)
	_box(Vector3(w + 0.5, 0.9, d + 0.5), Vector3(c.x, top + 0.45, c.y), roof, true)
	_box(Vector3(w - 0.3, 0.2, d - 0.3), Vector3(c.x, top + 0.95, c.y), M.concrete(Color(0.3, 0.3, 0.31)), true)
	# equipamentos no telhado
	for k in rng.randi_range(1, 4):
		var p := Vector3(c.x + rng.randf_range(-w * 0.3, w * 0.3), top + 1.6, c.y + rng.randf_range(-d * 0.3, d * 0.3))
		_box(Vector3(rng.randf_range(1.5, 3.0), 1.2, rng.randf_range(1.5, 2.5)), p, M.plain(Color(0.6, 0.62, 0.63), 0.4, 0.6), true)

const STORE_BLOCKS := {Vector2i(3, 3): "guns", Vector2i(1, 1): "cars", Vector2i(2, 3): "clothes", Vector2i(0, 2): "food", Vector2i(2, 1): "shop24", Vector2i(4, 3): "tuning"}
const POLICE_BLOCK := Vector2i(3, 1)
const SAFE_BLOCK := Vector2i(1, 2)
var station_cars: Array = []     # vagas da garagem da polícia [pos, yaw]
var station := {}                # pontos da delegacia: cela, saída da garagem, heliponto, porta
var safehouse := {}              # casa segura: spawn, cama, porta

## loja de um andar: paredes, vitrine de vidro na frente (sul) e um interior de verdade visto de fora
func _store(r: Rect2, type: String) -> void:
	var x0 := r.position.x + 0.6
	var x1 := r.end.x - 0.6
	var z0 := r.position.y + 0.6        # frente (rua)
	var z1 := r.end.y - 0.6
	var H := 5.2
	var cx := (x0 + x1) * 0.5
	var w := x1 - x0
	var d := z1 - z0
	var wall_c: Color = {"guns": Color(0.3, 0.28, 0.26), "clothes": Color(0.9, 0.87, 0.85), "cars": Color(0.88, 0.9, 0.93), "food": Color(0.95, 0.82, 0.55), "shop24": Color(0.9, 0.93, 0.9), "tuning": Color(0.35, 0.36, 0.4)}[type]
	var wall := M.plain(wall_c, 0.8)
	var ext := M.facade(4)
	# casca externa
	_box(Vector3(w, H, 0.3), Vector3(cx, H * 0.5 + 0.15, z1), ext)
	_box(Vector3(0.3, H, d), Vector3(x0, H * 0.5 + 0.15, (z0 + z1) * 0.5), ext)
	_box(Vector3(0.3, H, d), Vector3(x1, H * 0.5 + 0.15, (z0 + z1) * 0.5), ext)
	_box(Vector3(w + 0.6, 0.5, d + 0.6), Vector3(cx, H + 0.4, (z0 + z1) * 0.5), M.concrete(Color(0.4, 0.4, 0.42)))
	_box(Vector3(w + 1.2, 0.9, 0.4), Vector3(cx, H + 0.6, z0 - 0.1), M.plain(Color(0.08, 0.08, 0.09), 0.5))
	# paredes de dentro (cor da loja), piso e teto com luzes
	_box(Vector3(w - 0.4, H - 0.2, 0.05), Vector3(cx, H * 0.5 + 0.15, z1 - 0.18), wall, false)
	_box(Vector3(0.05, H - 0.2, d), Vector3(x0 + 0.18, H * 0.5 + 0.15, (z0 + z1) * 0.5), wall, false)
	_box(Vector3(0.05, H - 0.2, d), Vector3(x1 - 0.18, H * 0.5 + 0.15, (z0 + z1) * 0.5), wall, false)
	_box(Vector3(w - 0.3, 0.06, d - 0.3), Vector3(cx, 0.2, (z0 + z1) * 0.5), M.plain(Color(0.82, 0.8, 0.76) if type != "cars" else Color(0.9, 0.9, 0.92), 0.25, 0.1), false)
	_box(Vector3(w - 0.3, 0.1, d - 0.3), Vector3(cx, H + 0.1, (z0 + z1) * 0.5), M.plain(Color(0.95, 0.95, 0.95), 0.9), false)
	for k in 3:
		_box(Vector3(2.4, 0.06, 0.5), Vector3(cx - 5.0 + k * 5.0, H + 0.03, (z0 + z1) * 0.5), M.emissive(Color(1, 0.97, 0.9), 2.5), false)
	# vitrine: pilares, vidro (com colisão) e porta
	for xx in [x0, cx - 1.4, cx + 1.4, x1]:
		_box(Vector3(0.3, H, 0.3), Vector3(xx, H * 0.5 + 0.15, z0), M.plain(Color(0.1, 0.1, 0.11), 0.4, 0.6))
	var glass := M.plain(Color(0.55, 0.7, 0.78), 0.05, 0.3)
	var g2: StandardMaterial3D = glass.duplicate()
	g2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g2.albedo_color = Color(0.55, 0.72, 0.82, 0.22)
	_box(Vector3(cx - 1.4 - x0, H - 0.6, 0.06), Vector3((x0 + cx - 1.4) * 0.5, H * 0.5 - 0.1, z0), g2)
	_box(Vector3(x1 - cx - 1.4, H - 0.6, 0.06), Vector3((x1 + cx + 1.4) * 0.5, H * 0.5 - 0.1, z0), g2)
	_box(Vector3(2.6, 3.0, 0.06), Vector3(cx, 1.65, z0), g2)
	_box(Vector3(2.8, H - 3.2, 0.3), Vector3(cx, 3.2 + (H - 3.2) * 0.5, z0), M.plain(Color(0.1, 0.1, 0.11), 0.4, 0.6))
	# vitrine por dentro (o que se vê da rua)
	match type:
		"guns":
			for xx in [x0 + 0.5, x1 - 0.5]:
				for yy in [1.3, 2.2, 3.1]:
					_box(Vector3(0.35, 0.05, d - 2.0), Vector3(xx, yy, (z0 + z1) * 0.5), M.wood(), false)
					for zz in range(int(z0 + 2), int(z1 - 1), 2):
						_box(Vector3(0.1, 0.08, 0.9), Vector3(xx, yy + 0.1, zz), M.plain(Color(0.08, 0.08, 0.09), 0.4, 0.8), false)
			_box(Vector3(6.0, 1.05, 0.9), Vector3(cx, 0.65, z1 - 2.2), M.plain(Color(0.25, 0.18, 0.12), 0.5), false)
			_box(Vector3(6.0, 2.0, 0.08), Vector3(cx, 3.3, z1 - 0.25), M.plain(Color(0.6, 0.08, 0.05), 0.6), false)
		"clothes":
			for xx in [cx - 5.0, cx - 2.5, cx + 2.5, cx + 5.0]:
				_box(Vector3(0.05, 1.5, 0.05), Vector3(xx, 0.95, (z0 + z1) * 0.5), M.plain(Color(0.7, 0.7, 0.72), 0.3, 0.9), false)
				_box(Vector3(0.05, 0.05, 3.0), Vector3(xx, 1.7, (z0 + z1) * 0.5), M.plain(Color(0.7, 0.7, 0.72), 0.3, 0.9), false)
				for k in 6:
					_box(Vector3(0.55, 0.85, 0.08), Vector3(xx, 1.2, (z0 + z1) * 0.5 - 1.2 + k * 0.48), M.plain(Color.from_hsv(fmod(k * 0.17 + xx * 0.03 + 2.0, 1.0), 0.6, 0.8), 0.9), false)
			for xx in [x0 + 2.0, x1 - 2.0]:
				_box(Vector3(0.5, 1.75, 0.35), Vector3(xx, 1.05, z0 + 1.5), M.plain(Color(0.92, 0.85, 0.78), 0.6), false)   # manequins
				_box(Vector3(0.62, 0.7, 0.42), Vector3(xx, 1.5, z0 + 1.5), M.plain(Color(0.8, 0.2, 0.4), 0.8), false)
		"food":
			# lanchonete: balcão, chapa, mesas e banquetas
			_box(Vector3(w - 3.0, 1.05, 0.9), Vector3(cx, 0.65, z1 - 2.4), M.plain(Color(0.75, 0.15, 0.1), 0.5), false)
			_box(Vector3(4.0, 0.9, 0.7), Vector3(cx, 0.6, z1 - 0.9), M.plain(Color(0.6, 0.62, 0.64), 0.3, 0.8), false)
			_box(Vector3(w - 3.0, 0.9, 0.08), Vector3(cx, 4.0, z1 - 0.25), M.emissive(Color(1.0, 0.75, 0.2), 1.2), false)
			for k in 3:
				var tx := cx - 5.0 + k * 5.0
				_box(Vector3(1.4, 0.06, 1.4), Vector3(tx, 0.95, z0 + 3.0), M.plain(Color(0.9, 0.9, 0.88), 0.4), false)
				_box(Vector3(0.12, 0.8, 0.12), Vector3(tx, 0.55, z0 + 3.0), M.plain(Color(0.3, 0.3, 0.3), 0.4, 0.8), false)
		"shop24":
			# loja de conveniência: prateleiras, geladeiras iluminadas e caixa perto da porta
			for k in 3:
				_box(Vector3(0.6, 1.7, d - 5.0), Vector3(cx - 4.0 + k * 4.0, 1.0, (z0 + z1) * 0.5 + 1.0), M.plain(Color(0.85, 0.85, 0.82), 0.5), false)
				for yy in [0.6, 1.1, 1.6]:
					_box(Vector3(0.7, 0.25, d - 5.4), Vector3(cx - 4.0 + k * 4.0, yy + 0.15, (z0 + z1) * 0.5 + 1.0), M.plain(Color.from_hsv(fmod(k * 0.3 + yy, 1.0), 0.6, 0.85), 0.8), false)
			_box(Vector3(w - 1.0, 2.2, 0.6), Vector3(cx, 1.25, z1 - 0.6), M.emissive(Color(0.75, 0.9, 1.0), 0.8), false)
			_box(Vector3(2.4, 1.0, 0.8), Vector3(x1 - 2.5, 0.65, z0 + 2.0), M.plain(Color(0.2, 0.5, 0.25), 0.5), false)
		"tuning":
			# oficina: elevador, pneus, painel de ferramentas
			_box(Vector3(3.0, 0.2, 5.0), Vector3(cx, 0.3, (z0 + z1) * 0.5), M.plain(Color(0.85, 0.7, 0.1), 0.5, 0.4), false)
			for sx in [-1.6, 1.6]:
				_box(Vector3(0.3, 2.2, 0.3), Vector3(cx + sx, 1.2, (z0 + z1) * 0.5 + 2.6), M.plain(Color(0.85, 0.7, 0.1), 0.5, 0.4), false)
			for k in 4:
				_box(Vector3(0.7, 0.7, 0.3), Vector3(x0 + 1.0, 0.5 + k * 0.32, z1 - 2.0), M.plain(Color(0.06, 0.06, 0.06), 0.9), false)
			_box(Vector3(5.0, 2.0, 0.08), Vector3(cx, 2.6, z1 - 0.25), M.plain(Color(0.6, 0.12, 0.12), 0.6), false)
		"cars":
			_store_cars.append([Vector3(cx - 4.0, 0.25, (z0 + z1) * 0.5), 0.7, "sport", Color(0.85, 0.08, 0.05)])
			_store_cars.append([Vector3(cx + 4.0, 0.25, (z0 + z1) * 0.5), -0.7, "suv", Color(0.08, 0.2, 0.5)])
			_box(Vector3(w - 1.0, 0.05, d - 1.0), Vector3(cx, 0.24, (z0 + z1) * 0.5), M.plain(Color(0.95, 0.95, 0.97), 0.1, 0.1), false)
	# luz interna (só desta loja)
	var l := OmniLight3D.new()
	l.omni_range = 12.0
	l.light_energy = 1.6
	l.position = Vector3(cx, H - 0.6, (z0 + z1) * 0.5)
	add_child(l)

var _store_cars: Array = []

func _park(cx: float, cz: float, inner: float) -> void:
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(inner, inner)
	g.mesh = pm
	g.position = Vector3(cx, 0.16, cz)
	g.material_override = M.grass()
	add_child(g)
	_box(Vector3(6, 0.6, 6), Vector3(cx, 0.45, cz), M.concrete(Color(0.7, 0.7, 0.68)))
	_box(Vector3(5, 0.2, 5), Vector3(cx, 0.8, cz), M.plain(Color(0.15, 0.3, 0.38), 0.05, 0.3), false)

var _trees: Array = []
var _lamps: Array = []
var props: Array = []        # postes e árvores quebráveis
var _fallen: Array = []
var pmm := {}                # MultiMeshInstance3D: pole, head, trunk, crown
var _pgrid := {}

func _markings() -> void:
	# faixas tracejadas no centro de cada rua e faixas de pedestres nos cruzamentos
	var dash: Array = []
	var zebra: Array = []
	var ext := extent()
	for k in N + 1:
		var p := -ext + k * CELL - (0.0 if k < N + 1 else 0.0)
		var road := (k - N * 0.5) * CELL
		for s in range(int(-ext), int(ext), 6):
			var t := float(s) + 1.5
			var near_x := false
			for q in N + 1:
				if absf(t - ((q - N * 0.5) * CELL)) < ROADW * 0.6:
					near_x = true
			if near_x: continue
			dash.append(Transform3D(Basis(), Vector3(road, 0.012, t)))
			dash.append(Transform3D(Basis().rotated(Vector3.UP, PI * 0.5), Vector3(t, 0.012, road)))
		# rotas de carros (mão dupla, faixa a 2,6 m do centro)
		lanes.append([Vector3(road + 2.6, 0, -ext), Vector3(road + 2.6, 0, ext)])
		lanes.append([Vector3(road - 2.6, 0, ext), Vector3(road - 2.6, 0, -ext)])
		for q in N + 1:
			var cross := (q - N * 0.5) * CELL
			for side in [-1.0, 1.0]:
				for st in range(-5, 6):
					zebra.append(Transform3D(Basis(), Vector3(road + st * 1.2, 0.012, cross + side * (ROADW * 0.5 + 1.5))))
					zebra.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(cross + side * (ROADW * 0.5 + 1.5), 0.012, road + st * 1.2)))
	_multimesh(_mesh_box(Vector3(0.15, 0.02, 3.0)), M.plain(Color(0.85, 0.75, 0.2), 0.6), dash)
	_multimesh(_mesh_box(Vector3(0.6, 0.02, 2.6)), M.plain(Color(0.86, 0.86, 0.84), 0.6), zebra)

func _props() -> void:
	var lamps: Array = []
	var heads: Array = []
	var trunks: Array = []
	var crowns: Array = []
	for i in N:
		for j in N:
			var cx := _center(i)
			var cz := _center(j)
			var r := BLOCK * 0.5 - 0.7
			for s in range(-2, 3):
				var o := s * (BLOCK / 5.0)
				for p in [Vector3(cx + o, 0.15, cz - r), Vector3(cx + o, 0.15, cz + r), Vector3(cx - r, 0.15, cz + o), Vector3(cx + r, 0.15, cz + o)]:
					if s % 2 == 0:
						props.append({"type": "lamp", "pos": p, "idx": lamps.size(), "shape": _prop_shape(p, 0.15, 7.0), "alive": true})
						lamps.append(Transform3D(Basis(), p + Vector3(0, 3.5, 0)))
						heads.append(Transform3D(Basis(), p + Vector3(0, 7.0, 0)))
						_lamps.append(p)
					else:
						trunks.append(Transform3D(Basis(), p + Vector3(0, 1.5, 0)))
						var sc := rng.randf_range(0.85, 1.25)
						crowns.append(Transform3D(Basis().scaled(Vector3(sc, sc * 0.9, sc)), p + Vector3(0, 4.2, 0)))
						_trees.append(p)
						props.append({"type": "tree", "pos": p, "idx": trunks.size() - 1, "shape": _prop_shape(p, 0.25, 3.0), "alive": true, "sc": sc})
	var pole := CylinderMesh.new()
	pole.top_radius = 0.07
	pole.bottom_radius = 0.11
	pole.height = 7.0
	pole.radial_segments = 8
	pole.rings = 1
	pmm["pole"] = _multimesh(pole, M.plain(Color(0.18, 0.19, 0.2), 0.4, 0.8), lamps)
	lamp_mat = M.emissive(Color(1.0, 0.86, 0.62), 1.5).duplicate()
	pmm["head"] = _multimesh(_mesh_box(Vector3(0.5, 0.18, 0.9)), lamp_mat, heads)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.14
	trunk.bottom_radius = 0.22
	trunk.height = 3.0
	trunk.radial_segments = 8
	trunk.rings = 1
	pmm["trunk"] = _multimesh(trunk, M.bark(), trunks)
	var crown := SphereMesh.new()
	crown.radius = 2.2
	crown.height = 3.6
	crown.radial_segments = 12
	crown.rings = 7
	pmm["crown"] = _multimesh(crown, M.leaves(), crowns)
	for i in props.size():
		var k := _pcell(props[i].pos)
		if not _pgrid.has(k):
			_pgrid[k] = []
		_pgrid[k].append(i)

func _mesh_box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

func _prop_shape(p: Vector3, r: float, h: float) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = r
	cy.height = h
	cs.shape = cy
	cs.position = p + Vector3(0, h * 0.5, 0)
	body.add_child(cs)
	return cs

func _pcell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / 10.0), floori(p.z / 10.0))

## postes e árvores perto de 'p' (índices em props)
func props_near(p: Vector3) -> Array:
	var c := _pcell(p)
	var out := []
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var k := c + Vector2i(dx, dz)
			if _pgrid.has(k):
				for i in _pgrid[k]:
					if props[i].alive:
						out.append(i)
	return out

## derruba um poste/árvore: some da MultiMesh e vira corpo rígido empurrado pela batida
func break_prop(i: int, vel: Vector3) -> void:
	var pr: Dictionary = props[i]
	if not pr.alive:
		return
	pr.alive = false
	pr.shape.queue_free()
	if not pr.has("xf0"):
		var a: MultiMesh = (pmm.pole if pr.type == "lamp" else pmm.trunk).multimesh
		var b2: MultiMesh = (pmm.head if pr.type == "lamp" else pmm.crown).multimesh
		pr.xf0 = [a.get_instance_transform(pr.idx), b2.get_instance_transform(pr.idx)]
	var zero := Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), Vector3(0, -50, 0))
	var rb := RigidBody3D.new()
	rb.collision_layer = 4
	rb.collision_mask = 1
	var p: Vector3 = pr.pos
	if pr.type == "lamp":
		pmm.pole.multimesh.set_instance_transform(pr.idx, zero)
		pmm.head.multimesh.set_instance_transform(pr.idx, zero)
		_lamps.erase(p)
		rb.mass = 90.0
		_rb_part(rb, pmm.pole.multimesh.mesh, pmm.pole.material_override, Vector3(0, 3.5, 0), Basis())
		_rb_part(rb, pmm.head.multimesh.mesh, pmm.head.material_override, Vector3(0, 7.0, 0), Basis())
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(0.25, 7.0, 0.25)
		cs.shape = bx
		cs.position = Vector3(0, 3.5, 0)
		rb.add_child(cs)
	else:
		pmm.trunk.multimesh.set_instance_transform(pr.idx, zero)
		pmm.crown.multimesh.set_instance_transform(pr.idx, zero)
		_trees.erase(p)
		rb.mass = 350.0
		var sc: float = pr.sc
		_rb_part(rb, pmm.trunk.multimesh.mesh, pmm.trunk.material_override, Vector3(0, 1.5, 0), Basis())
		_rb_part(rb, pmm.crown.multimesh.mesh, pmm.crown.material_override, Vector3(0, 4.2, 0), Basis().scaled(Vector3(sc, sc * 0.9, sc)))
		var cs2 := CollisionShape3D.new()
		var bx2 := BoxShape3D.new()
		bx2.size = Vector3(0.45, 3.0, 0.45)
		cs2.shape = bx2
		cs2.position = Vector3(0, 1.5, 0)
		rb.add_child(cs2)
		var cs3 := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = 1.6
		cs3.shape = sp
		cs3.position = Vector3(0, 4.2, 0)
		rb.add_child(cs3)
	rb.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	rb.center_of_mass = Vector3(0, 2.0, 0)
	get_parent().add_child(rb)
	rb.add_to_group("tmp")
	# no máximo 14 postes/árvores caídos com física ao mesmo tempo (o mais antigo some)
	_fallen.append(rb)
	while _fallen.size() > 14:
		var old = _fallen.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	rb.global_position = p + Vector3(0, 0.02, 0)
	var dir := Vector3(vel.x, 0, vel.z)
	rb.apply_impulse(dir * rb.mass * 0.45, Vector3(0, 2.5, 0))
	rb.get_tree().create_timer(60.0).timeout.connect(rb.queue_free)

## reinício do mundo: postes e árvores derrubados voltam ao lugar
func restore_props() -> void:
	for pr in props:
		if pr.alive:
			continue
		pr.alive = true
		var p: Vector3 = pr.pos
		if pr.type == "lamp":
			pmm.pole.multimesh.set_instance_transform(pr.idx, pr.xf0[0])
			pmm.head.multimesh.set_instance_transform(pr.idx, pr.xf0[1])
			_lamps.append(p)
			pr.shape = _prop_shape(p, 0.15, 7.0)
		else:
			pmm.trunk.multimesh.set_instance_transform(pr.idx, pr.xf0[0])
			pmm.crown.multimesh.set_instance_transform(pr.idx, pr.xf0[1])
			_trees.append(p)
			pr.shape = _prop_shape(p, 0.25, 3.0)

func _rb_part(rb: RigidBody3D, mesh: Mesh, mat: Material, pos: Vector3, b: Basis) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(b, pos)
	rb.add_child(mi)

func _multimesh(mesh: Mesh, mat: Material, xf: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for k in xf.size():
		mm.set_instance_transform(k, xf[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
	return mmi

## hospital e delegacia: placas grandes na calçada e pontos de reaparecimento
func _landmarks() -> void:
	hospital_pos = Vector3(_center(1), 0.3, _center(3) - BLOCK * 0.5 + 1.6)
	police_pos = Vector3(_center(3), 0.3, _center(1) - BLOCK * 0.5 + 1.6)
	var white := M.emissive(Color(0.95, 0.95, 0.95), 0.6)
	var red := M.emissive(Color(0.9, 0.08, 0.08), 1.4)
	var blue := M.emissive(Color(0.12, 0.3, 0.9), 1.4)
	var pole := M.plain(Color(0.25, 0.25, 0.27), 0.4, 0.7)
	# lojas: AMMU★NATION e concessionária (porta na calçada, placa luminosa com texto)
	var gs := Vector3(_center(3), 0.3, _center(3) - BLOCK * 0.5 + 1.6)
	var cs := Vector3(_center(1), 0.3, _center(1) - BLOCK * 0.5 + 1.6)
	var rs := Vector3(_center(2), 0.3, _center(3) - BLOCK * 0.5 + 1.6)
	shops = [{"type": "guns", "pos": gs, "name": "AMMU★NATION", "col": Color(0.95, 0.15, 0.1)}, {"type": "cars", "pos": cs, "name": "CONCESSIONÁRIA", "col": Color(0.2, 0.75, 1.0)}, {"type": "clothes", "pos": rs, "name": "ROUPAS", "col": Color(0.95, 0.45, 0.85)},
		{"type": "food", "pos": Vector3(_center(0), 0.3, _center(2) - BLOCK * 0.5 + 1.6), "name": "LANCHONETE", "col": Color(1.0, 0.7, 0.15)},
		{"type": "shop24", "pos": Vector3(_center(2), 0.3, _center(1) - BLOCK * 0.5 + 1.6), "name": "LOJA 24H", "col": Color(0.3, 0.9, 0.4)},
		{"type": "tuning", "pos": Vector3(_center(4), 0.3, _center(3) - BLOCK * 0.5 + 1.6), "name": "OFICINA TUNING", "col": Color(1.0, 0.55, 0.1)}]
	for sh in shops:
		var sp: Vector3 = sh.pos
		var em := M.emissive(sh.col, 1.6)
		_box(Vector3(5.2, 0.12, 2.6), sp + Vector3(0, 0.0, 0.2), M.plain(Color(0.12, 0.12, 0.13), 0.5, 0.2), false)
		_box(Vector3(0.12, 3.2, 0.12), sp + Vector3(-2.4, 1.6, -0.6), pole, true)
		_box(Vector3(0.12, 3.2, 0.12), sp + Vector3(2.4, 1.6, -0.6), pole, true)
		_box(Vector3(5.0, 1.0, 0.25), sp + Vector3(0, 3.6, -0.6), M.plain(Color(0.05, 0.05, 0.06), 0.4, 0.2), false)
		_box(Vector3(5.0, 0.08, 0.3), sp + Vector3(0, 3.06, -0.6), em, false)
		var lb := Label3D.new()
		lb.text = sh.name
		lb.font_size = 96
		lb.pixel_size = 0.0075
		lb.modulate = sh.col.lightened(0.3)
		lb.outline_size = 10
		lb.position = sp + Vector3(0, 3.6, -0.76)
		lb.rotation.y = PI
		lb.shaded = false
		add_child(lb)
	for spec in [[hospital_pos, red, "H"], [police_pos, blue, "P"]]:
		var p: Vector3 = spec[0] + Vector3(2.5, 0, 0)
		_box(Vector3(0.15, 4.0, 0.15), p + Vector3(0, 2.0, 0), pole, true)
		_box(Vector3(2.2, 2.2, 0.2), p + Vector3(0, 5.0, 0), white, false)
		if spec[2] == "H":
			_box(Vector3(1.6, 0.45, 0.25), p + Vector3(0, 5.0, 0), red, false)
			_box(Vector3(0.45, 1.6, 0.25), p + Vector3(0, 5.0, 0), red, false)
		else:
			_box(Vector3(1.7, 1.7, 0.25), p + Vector3(0, 5.0, 0), blue, false)
			_box(Vector3(0.9, 0.9, 0.3), p + Vector3(0, 5.0, 0), white, false)

# ---------------------------------------------------------------- delegacia completa
## Quarteirão inteiro: prédio de 2 andares na frente (sul) com recepção, sala dos policiais, sala de
## armas, corredor, 3 celas com grades, sala de interrogatório e vestiário; heliponto no telhado;
## garagem da polícia atrás (norte, aberta para a rua) com as viaturas; pátio entre os dois.
func _police_station(cx: float, cz: float) -> void:
	var h := (BLOCK - SIDE * 2.0) * 0.5            # 21 m
	var wallm := M.concrete(Color(0.82, 0.83, 0.85))
	var inner_w := M.plain(Color(0.78, 0.8, 0.84), 0.8)
	var floor_m := M.plain(Color(0.55, 0.56, 0.6), 0.4, 0.1)
	var blue := M.plain(Color(0.1, 0.22, 0.55), 0.5)
	var dark := M.plain(Color(0.12, 0.12, 0.14), 0.4, 0.6)
	var bars := M.plain(Color(0.25, 0.26, 0.28), 0.3, 0.9)
	var glass := M.plain(Color(0.15, 0.22, 0.3), 0.05, 0.6)
	var fz := cz - h            # frente (rua sul)
	var bz := cz - 3.0          # fundo do prédio
	var H := 4.2                # pé-direito do térreo
	var x0 := cx - h
	var x1 := cx + h
	# piso interno, laje entre andares (= teto do térreo), 2º andar (casca) e telhado
	_box(Vector3(2.0 * h, 0.06, bz - fz), Vector3(cx, 0.18, (fz + bz) * 0.5), floor_m, false)
	_box(Vector3(2.0 * h, 0.3, bz - fz), Vector3(cx, H + 0.3, (fz + bz) * 0.5), wallm, true)
	_box(Vector3(2.0 * h, H, 0.3), Vector3(cx, H * 1.5 + 0.45, fz), M.facade(1), true)
	_box(Vector3(2.0 * h, H, 0.3), Vector3(cx, H * 1.5 + 0.45, bz), M.facade(1), true)
	_box(Vector3(0.3, H, bz - fz), Vector3(x0, H * 1.5 + 0.45, (fz + bz) * 0.5), M.facade(1), true)
	_box(Vector3(0.3, H, bz - fz), Vector3(x1, H * 1.5 + 0.45, (fz + bz) * 0.5), M.facade(1), true)
	var roof_y := 2.0 * H + 0.6
	_box(Vector3(2.0 * h + 0.6, 0.4, bz - fz + 0.6), Vector3(cx, roof_y, (fz + bz) * 0.5), M.concrete(Color(0.4, 0.41, 0.42)), true)
	_box(Vector3(2.0 * h + 0.8, 0.9, 0.3), Vector3(cx, roof_y + 0.6, fz - 0.2), blue, false)
	# heliponto no telhado
	var hp := Vector3(cx + 8.0, roof_y + 0.25, (fz + bz) * 0.5)
	_box(Vector3(13.0, 0.06, 13.0), hp, M.concrete(Color(0.25, 0.26, 0.28)), false)
	_box(Vector3(1.0, 0.03, 6.0), hp + Vector3(-2.0, 0.04, 0), M.plain(Color(0.95, 0.85, 0.1), 0.6), false)
	_box(Vector3(1.0, 0.03, 6.0), hp + Vector3(2.0, 0.04, 0), M.plain(Color(0.95, 0.85, 0.1), 0.6), false)
	_box(Vector3(3.0, 0.03, 1.0), hp + Vector3(0, 0.04, 0), M.plain(Color(0.95, 0.85, 0.1), 0.6), false)
	# paredes externas do térreo: frente com porta (x −1,6..1,6) e janelas, fundo com porta para o pátio
	for seg in [[x0, cx - 1.6], [cx + 1.6, x1]]:
		var w: float = seg[1] - seg[0]
		_box(Vector3(w, H, 0.3), Vector3((seg[0] + seg[1]) * 0.5, H * 0.5 + 0.15, fz), wallm, true)
		_box(Vector3(w - 2.0, 1.4, 0.06), Vector3((seg[0] + seg[1]) * 0.5, 2.3, fz - 0.17), glass, false)
		_box(Vector3(w, H, 0.3), Vector3((seg[0] + seg[1]) * 0.5, H * 0.5 + 0.15, bz), wallm, true)
	_box(Vector3(3.2, H - 3.0, 0.3), Vector3(cx, H - 0.45, fz), wallm, true)
	_box(Vector3(3.2, H - 3.0, 0.3), Vector3(cx, H - 0.45, bz), wallm, true)
	_box(Vector3(0.3, H, bz - fz), Vector3(x0, H * 0.5 + 0.15, (fz + bz) * 0.5), wallm, true)
	_box(Vector3(0.3, H, bz - fz), Vector3(x1, H * 0.5 + 0.15, (fz + bz) * 0.5), wallm, true)
	# marquise, escada e placa
	_box(Vector3(14.0, 0.35, 3.0), Vector3(cx, H + 0.1, fz - 1.6), blue, false)
	_box(Vector3(6.0, 0.15, 1.6), Vector3(cx, 0.22, fz - 1.0), M.concrete(Color(0.85, 0.85, 0.86)), false)
	var lb := Label3D.new()
	lb.text = "DELEGACIA DE POLÍCIA"
	lb.font_size = 120
	lb.pixel_size = 0.01
	lb.modulate = Color(0.85, 0.92, 1.0)
	lb.outline_size = 12
	lb.shaded = false
	lb.rotation.y = PI
	lb.position = Vector3(cx, roof_y + 0.6, fz - 0.4)
	add_child(lb)
	for s in [-1.0, 1.0]:
		_box(Vector3(0.4, 0.4, 0.4), Vector3(cx + 6.0 * s, H + 0.45, fz - 2.9), M.emissive(Color(0.15, 0.35, 1.0), 3.0), false)
	# divisões internas: fileira da frente (z fz..fz+8,5), corredor (2 m), fileira do fundo (até bz)
	var c0 := fz + 8.5
	var c1 := c0 + 2.2
	for seg in [[x0, cx - 7.0 - 0.8], [cx - 7.0 + 0.8, cx - 0.9], [cx + 0.9, cx + 7.0 - 0.8], [cx + 7.0 + 0.8, x1]]:
		_box(Vector3(seg[1] - seg[0], H, 0.2), Vector3((seg[0] + seg[1]) * 0.5, H * 0.5 + 0.15, c0), inner_w, true)
	for xx in [cx - 7.0, cx + 7.0]:
		_box(Vector3(0.2, H, c0 - fz), Vector3(xx, H * 0.5 + 0.15, (fz + c0) * 0.5), inner_w, true)
	# recepção (centro, frente): balcão
	_box(Vector3(6.0, 1.1, 0.8), Vector3(cx, 0.7, fz + 5.0), M.wood(), true)
	_box(Vector3(6.0, 0.1, 1.0), Vector3(cx, 1.3, fz + 5.0), M.plain(Color(0.2, 0.2, 0.22), 0.4), false)
	# sala dos policiais (oeste, frente): mesas com computadores
	for k in 3:
		var dx := x0 + 3.0 + k * 4.2
		_box(Vector3(2.4, 0.08, 1.2), Vector3(dx, 0.95, fz + 4.0), M.wood(), true)
		_box(Vector3(0.7, 0.45, 0.06), Vector3(dx, 1.25, fz + 4.3), M.emissive(Color(0.4, 0.7, 1.0), 0.8), false)
		_box(Vector3(0.5, 0.9, 0.5), Vector3(dx, 0.6, fz + 5.2), dark, false)
	# sala de armas (leste, frente): estantes com fuzis, coletes e grade na porta
	for k in 3:
		var ax := x1 - 1.0
		_box(Vector3(0.6, 2.2, 2.0), Vector3(ax, 1.25, fz + 1.8 + k * 2.4), M.plain(Color(0.25, 0.27, 0.3), 0.4, 0.7), true)
		for g in 4:
			_box(Vector3(0.08, 1.0, 0.12), Vector3(ax - 0.35, 1.4, fz + 1.2 + k * 2.4 + g * 0.4), M.plain(Color(0.06, 0.06, 0.07), 0.4, 0.8), false)
	_box(Vector3(2.0, 1.0, 0.9), Vector3(cx + 10.0, 0.65, fz + 4.0), M.plain(Color(0.2, 0.22, 0.18), 0.6), true)
	for k in 3:
		_box(Vector3(0.5, 0.65, 0.25), Vector3(cx + 9.4 + k * 0.6, 1.5, fz + 4.0), M.plain(Color(0.1, 0.12, 0.15), 0.7), false)
	var lb2 := Label3D.new()
	lb2.text = "SALA DE ARMAS"
	lb2.font_size = 48
	lb2.pixel_size = 0.006
	lb2.shaded = false
	lb2.position = Vector3(cx + 10.5, 3.2, c0 - 0.15)
	lb2.rotation.y = PI
	add_child(lb2)
	# celas (oeste, fundo): 3 celas com grades viradas para o corredor e porta de grade aberta
	var cw := (cx - 2.0 - x0) / 3.0
	for k in 3:
		var ex := x0 + k * cw
		if k > 0:
			_box(Vector3(0.25, H, bz - c1), Vector3(ex, H * 0.5 + 0.15, (c1 + bz) * 0.5), inner_w, true)
		for b in int(cw / 0.25):
			var bx := ex + 0.2 + b * 0.25
			if bx > ex + cw * 0.5 - 0.6 and bx < ex + cw * 0.5 + 0.6:
				continue        # porta da cela (aberta)
			_box(Vector3(0.05, H - 0.2, 0.05), Vector3(bx, H * 0.5 + 0.15, c1), bars, true)
		_box(Vector3(cw, 0.12, 0.12), Vector3(ex + cw * 0.5, H - 0.1, c1), bars, false)
		_box(Vector3(cw - 1.0, 0.45, 0.9), Vector3(ex + cw * 0.5, 0.4, bz - 0.7), M.plain(Color(0.4, 0.42, 0.45), 0.6), true)
		_box(Vector3(0.6, 0.45, 0.6), Vector3(ex + cw - 0.6, 0.4, c1 + 1.0), M.plain(Color(0.92, 0.92, 0.94), 0.2), false)
	_box(Vector3(0.25, H, bz - c1), Vector3(cx - 2.0, H * 0.5 + 0.15, (c1 + bz) * 0.5), inner_w, true)
	var lb3 := Label3D.new()
	lb3.text = "CARCERAGEM"
	lb3.font_size = 48
	lb3.pixel_size = 0.006
	lb3.shaded = false
	lb3.position = Vector3(x0 + 4.0, 3.5, c1 - 0.1)
	lb3.rotation.y = PI
	add_child(lb3)
	# sala de interrogatório (centro, fundo): mesa, 2 cadeiras, luz pendente e espelho falso
	_box(Vector3(0.2, H, bz - c1), Vector3(cx + 7.0, H * 0.5 + 0.15, (c1 + bz) * 0.5), inner_w, true)
	for seg in [[cx - 2.0, cx + 1.6], [cx + 3.4, cx + 7.0]]:
		_box(Vector3(seg[1] - seg[0], H, 0.2), Vector3((seg[0] + seg[1]) * 0.5, H * 0.5 + 0.15, c1), inner_w, true)
	_box(Vector3(2.0, 0.08, 1.0), Vector3(cx + 2.5, 0.95, (c1 + bz) * 0.5), M.plain(Color(0.6, 0.6, 0.62), 0.3, 0.8), true)
	for sz in [-0.9, 0.9]:
		_box(Vector3(0.5, 0.9, 0.5), Vector3(cx + 2.5, 0.6, (c1 + bz) * 0.5 + sz), dark, false)
	_box(Vector3(0.6, 0.08, 0.6), Vector3(cx + 2.5, H - 0.6, (c1 + bz) * 0.5), M.emissive(Color(1, 0.95, 0.8), 3.0), false)
	_box(Vector3(3.0, 1.4, 0.05), Vector3(cx + 2.5, 2.2, c1 + 0.12), M.plain(Color(0.12, 0.13, 0.15), 0.02, 1.0), false)
	var lb4 := Label3D.new()
	lb4.text = "INTERROGATÓRIO"
	lb4.font_size = 48
	lb4.pixel_size = 0.006
	lb4.shaded = false
	lb4.position = Vector3(cx + 2.5, 3.5, c1 - 0.15)
	lb4.rotation.y = PI
	add_child(lb4)
	# vestiário (leste, fundo): armários
	_box(Vector3(cx + 8.6 - (cx + 7.0), H, 0.2), Vector3(cx + 7.8, H * 0.5 + 0.15, c1), inner_w, true)
	_box(Vector3(x1 - (cx + 10.4), H, 0.2), Vector3((cx + 10.4 + x1) * 0.5, H * 0.5 + 0.15, c1), inner_w, true)
	for k in 6:
		_box(Vector3(0.9, 2.0, 0.6), Vector3(cx + 9.0 + k * 1.0, 1.15, bz - 0.5), M.plain(Color(0.3, 0.4, 0.55), 0.4, 0.6), true)
	# luzes de teto (painéis)
	for xx in [cx - 14.0, cx - 7.0, cx, cx + 7.0, cx + 14.0]:
		for zz in [fz + 4.0, (c0 + c1) * 0.5, (c1 + bz) * 0.5]:
			_box(Vector3(1.4, 0.05, 0.5), Vector3(xx, H + 0.13, zz), M.emissive(Color(1, 0.98, 0.92), 2.0), false)
	var li := OmniLight3D.new()
	li.omni_range = 16.0
	li.light_energy = 1.2
	li.position = Vector3(cx, H - 0.5, (fz + bz) * 0.5)
	add_child(li)
	# pátio (asfalto) entre o prédio e a garagem
	_box(Vector3(2.0 * h, 0.05, 5.0), Vector3(cx, 0.18, cz), M.asphalt(), false)
	# garagem da polícia (norte): 4 vagas cobertas, aberta para a rua norte
	var gz0 := cz + 2.5
	var gz1 := cz + h
	_box(Vector3(2.0 * h, 0.05, gz1 - gz0), Vector3(cx, 0.18, (gz0 + gz1) * 0.5), M.concrete(Color(0.45, 0.45, 0.47)), false)
	_box(Vector3(2.0 * h, 5.0, 0.3), Vector3(cx, 2.65, gz0), wallm, true)
	_box(Vector3(0.3, 5.0, gz1 - gz0), Vector3(x0, 2.65, (gz0 + gz1) * 0.5), wallm, true)
	_box(Vector3(0.3, 5.0, gz1 - gz0), Vector3(x1, 2.65, (gz0 + gz1) * 0.5), wallm, true)
	_box(Vector3(2.0 * h + 0.6, 0.4, gz1 - gz0 + 0.6), Vector3(cx, 5.3, (gz0 + gz1) * 0.5), M.concrete(Color(0.4, 0.41, 0.42)), true)
	_box(Vector3(2.0 * h, 0.8, 0.3), Vector3(cx, 4.7, gz1), blue, false)
	for k in 5:
		_box(Vector3(0.15, 0.02, gz1 - gz0 - 4.0), Vector3(x0 + 4.0 + k * 8.5, 0.22, (gz0 + gz1) * 0.5 + 1.0), M.plain(Color(0.95, 0.95, 0.9), 0.6), false)
	var lb5 := Label3D.new()
	lb5.text = "GARAGEM · POLÍCIA"
	lb5.font_size = 80
	lb5.pixel_size = 0.008
	lb5.shaded = false
	lb5.position = Vector3(cx, 4.7, gz1 + 0.2)
	add_child(lb5)
	station_cars = []
	for k in 4:
		station_cars.append([Vector3(x0 + 8.25 + k * 8.5, 0.7, (gz0 + gz1) * 0.5), 0.0])
	station = {"cell": Vector3(x0 + cw * 0.5, 0.3, (c1 + bz) * 0.5 + 0.6), "door": Vector3(cx, 0.3, fz - 2.5),
		"garage_out": Vector3(cx, 0.7, gz1 + 6.0), "heli": hp + Vector3(0, 0.3, 0), "front": Vector3(cx, 0.3, fz)}

# ---------------------------------------------------------------- casa segura
## Sobrado com quintal: sala, quarto com cama (dormir = salvar e passar o tempo), garagem lateral.
func _safehouse(cx: float, cz: float, inner: float, downtown: float) -> void:
	var hh := inner * 0.5
	# prédios no fundo da quadra
	_building(Rect2(cx - hh, cz + 2.0, inner, hh - 2.0), downtown * 0.5)
	var fz := cz - hh + 3.0
	var x0 := cx - 9.0
	var x1 := cx + 5.0
	var bz := fz + 10.0
	var H := 3.4
	var wallm := M.plain(Color(0.86, 0.78, 0.62), 0.8)
	var trim := M.plain(Color(0.55, 0.3, 0.2), 0.7)
	# gramado e calçadinha
	_box(Vector3(inner, 0.05, hh - 2.0), Vector3(cx, 0.17, cz - hh * 0.5 - 0.5), M.grass(), false)
	_box(Vector3(1.6, 0.06, 3.0), Vector3(cx - 2.0, 0.2, fz - 1.5), M.concrete(Color(0.7, 0.7, 0.68)), false)
	_box(Vector3(x1 - x0, 0.06, bz - fz), Vector3((x0 + x1) * 0.5, 0.2, (fz + bz) * 0.5), M.wood(), false)
	# paredes (porta na frente em x −2,8..−1,2)
	_box(Vector3(-2.8 - (x0 - cx), H, 0.25), Vector3((x0 + cx - 2.8) * 0.5, H * 0.5 + 0.15, fz), wallm, true)
	_box(Vector3(x1 - (cx - 1.2), H, 0.25), Vector3((cx - 1.2 + x1) * 0.5, H * 0.5 + 0.15, fz), wallm, true)
	_box(Vector3(1.6, H - 2.4, 0.25), Vector3(cx - 2.0, H - 0.35, fz), wallm, true)
	_box(Vector3(x1 - x0, H, 0.25), Vector3((x0 + x1) * 0.5, H * 0.5 + 0.15, bz), wallm, true)
	_box(Vector3(0.25, H, bz - fz), Vector3(x0, H * 0.5 + 0.15, (fz + bz) * 0.5), wallm, true)
	_box(Vector3(0.25, H, bz - fz), Vector3(x1, H * 0.5 + 0.15, (fz + bz) * 0.5), wallm, true)
	# parede do quarto (porta em z fz+5..fz+6,4)
	_box(Vector3(0.15, H, 5.0), Vector3(cx + 0.5, H * 0.5 + 0.15, fz + 2.5), wallm, false)
	_box(Vector3(0.15, H, bz - fz - 6.4), Vector3(cx + 0.5, H * 0.5 + 0.15, (fz + 6.4 + bz) * 0.5), wallm, false)
	# telhado de duas águas (caixas inclinadas viram degraus; usamos laje + beiral)
	_box(Vector3(x1 - x0 + 1.0, 0.3, bz - fz + 1.0), Vector3((x0 + x1) * 0.5, H + 0.3, (fz + bz) * 0.5), trim, true)
	_box(Vector3(x1 - x0 - 1.0, 1.0, bz - fz - 3.0), Vector3((x0 + x1) * 0.5, H + 0.95, (fz + bz) * 0.5), trim, false)
	# janelas
	for xx in [x0 + 2.0, x1 - 2.5]:
		_box(Vector3(1.6, 1.1, 0.06), Vector3(xx, 1.8, fz - 0.14), M.plain(Color(0.2, 0.3, 0.38), 0.05, 0.6), false)
	# sala: sofá, TV e mesa
	_box(Vector3(2.6, 0.8, 0.9), Vector3(x0 + 2.0, 0.55, bz - 1.0), M.plain(Color(0.25, 0.3, 0.5), 0.9), true)
	_box(Vector3(1.6, 0.9, 0.08), Vector3(x0 + 2.0, 1.5, fz + 0.3), M.plain(Color(0.03, 0.03, 0.04), 0.2, 0.5), false)
	_box(Vector3(1.0, 0.05, 0.6), Vector3(x0 + 2.0, 0.62, (fz + bz) * 0.5), M.wood(), false)
	# quarto: cama de casal, criado-mudo, abajur
	var bed := Vector3(x1 - 2.2, 0.2, bz - 2.0)
	_box(Vector3(2.0, 0.45, 2.4), bed + Vector3(0, 0.28, 0), M.wood(), true)
	_box(Vector3(1.9, 0.2, 2.3), bed + Vector3(0, 0.6, 0), M.plain(Color(0.92, 0.92, 0.95), 0.9), false)
	_box(Vector3(1.9, 0.12, 0.5), bed + Vector3(0, 0.75, 0.9), M.plain(Color(0.95, 0.95, 0.97), 0.9), false)
	_box(Vector3(1.9, 0.22, 1.3), bed + Vector3(0, 0.68, -0.4), M.plain(Color(0.6, 0.15, 0.2), 0.9), false)
	_box(Vector3(2.1, 0.9, 0.12), bed + Vector3(0, 0.9, 1.2), M.wood(), false)
	_box(Vector3(0.5, 0.5, 0.5), bed + Vector3(-1.5, 0.45, 0.9), M.wood(), false)
	_box(Vector3(0.25, 0.3, 0.25), bed + Vector3(-1.5, 0.9, 0.9), M.emissive(Color(1.0, 0.85, 0.5), 1.5), false)
	# garagem ao lado (portão aberto para a rua)
	_box(Vector3(0.25, 3.0, 9.0), Vector3(x1 + 6.0, 1.65, fz + 4.5), wallm, true)
	_box(Vector3(6.0, 3.0, 0.25), Vector3(x1 + 3.0, 1.65, fz + 9.0), wallm, true)
	_box(Vector3(6.5, 0.3, 9.5), Vector3(x1 + 3.0, 3.2, fz + 4.5), trim, true)
	_box(Vector3(6.0, 0.05, 9.0), Vector3(x1 + 3.0, 0.2, fz + 4.5), M.concrete(Color(0.5, 0.5, 0.5)), false)
	var lb := Label3D.new()
	lb.text = "CASA SEGURA"
	lb.font_size = 64
	lb.pixel_size = 0.006
	lb.modulate = Color(0.6, 1.0, 0.6)
	lb.outline_size = 8
	lb.shaded = false
	lb.rotation.y = PI
	lb.position = Vector3(cx - 2.0, H + 0.5, fz - 0.3)
	add_child(lb)
	var li := OmniLight3D.new()
	li.omni_range = 9.0
	li.light_energy = 0.9
	li.position = Vector3((x0 + x1) * 0.5, H - 0.4, (fz + bz) * 0.5)
	add_child(li)
	safehouse = {"spawn": Vector3(cx - 2.0, 0.3, fz + 2.0), "bed": bed + Vector3(-1.4, 0.1, -0.6), "door": Vector3(cx - 2.0, 0.3, fz - 1.5), "garage": [Vector3(x1 + 3.0, 0.7, fz + 4.5), PI]}

extends Node3D
## Gera o bairro de teste: quadras com calçadas, prédios com fachadas PBR, ruas com faixas,
## postes e árvores (MultiMesh), além de toda a colisão estática.

const M := preload("res://scripts/mats.gd")

const N := 5            # quadras por lado
const CELL := 64.0      # distância entre centros de quadras
const ROADW := 14.0     # largura do asfalto entre quadras
const SIDE := 4.0       # largura da calçada
var BLOCK := CELL - ROADW   # lado da laje da quadra (calçada + lotes)

var body: StaticBody3D
var rng := RandomNumberGenerator.new()
var lanes: Array = []   # pontos de rota de carros (centro das faixas)
var walk_loops: Array = []  # percursos de pedestres (um por quadra)

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
	_flush()

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
	var grass := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(900, 900)
	grass.mesh = gm
	grass.position.y = -0.03
	grass.material_override = M.grass()
	add_child(grass)
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
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
	_box(Vector3(w + 0.5, 0.9, d + 0.5), Vector3(c.x, top + 0.45, c.y), roof, false)
	_box(Vector3(w - 0.3, 0.2, d - 0.3), Vector3(c.x, top + 0.95, c.y), M.concrete(Color(0.3, 0.3, 0.31)), false)
	# equipamentos no telhado
	for k in rng.randi_range(1, 4):
		var p := Vector3(c.x + rng.randf_range(-w * 0.3, w * 0.3), top + 1.6, c.y + rng.randf_range(-d * 0.3, d * 0.3))
		_box(Vector3(rng.randf_range(1.5, 3.0), 1.2, rng.randf_range(1.5, 2.5)), p, M.plain(Color(0.6, 0.62, 0.63), 0.4, 0.6), false)

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
						lamps.append(Transform3D(Basis(), p + Vector3(0, 3.5, 0)))
						heads.append(Transform3D(Basis(), p + Vector3(0, 7.0, 0)))
						_lamps.append(p)
					else:
						trunks.append(Transform3D(Basis(), p + Vector3(0, 1.5, 0)))
						var sc := rng.randf_range(0.85, 1.25)
						crowns.append(Transform3D(Basis().scaled(Vector3(sc, sc * 0.9, sc)), p + Vector3(0, 4.2, 0)))
						_trees.append(p)
						var cs := CollisionShape3D.new()
						var cy := CylinderShape3D.new()
						cy.radius = 0.25
						cy.height = 3.0
						cs.shape = cy
						cs.position = p + Vector3(0, 1.5, 0)
						body.add_child(cs)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.07
	pole.bottom_radius = 0.11
	pole.height = 7.0
	pole.radial_segments = 8
	pole.rings = 1
	_multimesh(pole, M.plain(Color(0.18, 0.19, 0.2), 0.4, 0.8), lamps)
	_multimesh(_mesh_box(Vector3(0.5, 0.18, 0.9)), M.emissive(Color(1.0, 0.93, 0.78), 1.5), heads)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.14
	trunk.bottom_radius = 0.22
	trunk.height = 3.0
	trunk.radial_segments = 8
	trunk.rings = 1
	_multimesh(trunk, M.bark(), trunks)
	var crown := SphereMesh.new()
	crown.radius = 2.2
	crown.height = 3.6
	crown.radial_segments = 12
	crown.rings = 7
	_multimesh(crown, M.leaves(), crowns)

func _mesh_box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

func _multimesh(mesh: Mesh, mat: Material, xf: Array) -> void:
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

extends Node3D
## Áreas fora da grade da cidade: praia + mar + píer (leste), aeroporto com heliponto (oeste),
## delegacia, interiores das lojas (salas afastadas do mapa, entradas por teleporte) e marcadores.

const M := preload("res://scripts/mats.gd")
const CM := preload("res://scripts/carmodel.gd")
const Humanoid := preload("res://scripts/humanoid.gd")

const SHORE_X := 236.0        # a partir daqui é mar
const WATER_Y := 0.9
const SEA_FLOOR := -12.0      # mar fundo (dá para mergulhar)
const BEACH_X0 := 172.0
const AIR_X := -330.0         # centro da pista

var main: Node3D
var body: StaticBody3D
var _batch := {}              # zona -> {material -> SurfaceTool}
var water: MeshInstance3D
var boat_spots: Array = []    # [Vector3, yaw]
var plane_spots: Array = []
var heli_spots: Array = []
var interiors := {}           # tipo -> {origin, exit, counter, door_out}
var beach_loop: Array = []
var tank_spots: Array = []    # base do exército: [pos, yaw]
var jet_spots: Array = []
var base_gate := Vector3.ZERO
var _wt := 0.0

func build(m: Node3D) -> void:
	main = m
	body = StaticBody3D.new()
	body.name = "ColisaoExtra"
	add_child(body)
	_beach()
	_airfield()
	_army_base()
	var types := ["guns", "clothes", "cars"]
	for i in types.size():
		_interior(types[i], Vector3(4000 + i * 80, 0, 0))
	for z in _batch:
		_flush(z)

func _process(dt: float) -> void:
	_wt += dt
	if water:
		var wm: StandardMaterial3D = water.material_override
		wm.uv1_offset = Vector3(_wt * 0.004, _wt * 0.0025, 0)

const ISL_X0 := -180.0       # ilha: cidade + praia (x de ISL_X0 até SHORE_X, z de ISL_Z0 até ISL_Z1)
const ISL_Z0 := -200.0
const ISL_Z1 := 200.0
const PEN_X0 := -520.0       # península estreita a oeste só com o aeroporto (z de −PEN_Z a PEN_Z)
const PEN_Z := 50.0
var fish_spots: Array = []   # [pos do pescador, yaw]

const BASE := Rect2(-520.0, 50.0, 150.0, 110.0)   # base do exército: canto isolado ao norte da ponta da península

## retângulos de terra (o resto é mar)
static func land_rects() -> Array:
	return [Rect2(ISL_X0, ISL_Z0, SHORE_X - ISL_X0, ISL_Z1 - ISL_Z0), Rect2(PEN_X0, -PEN_Z, ISL_X0 - PEN_X0 + 2.0, PEN_Z * 2.0), BASE]

static func _on_land(p: Vector2) -> bool:
	for r in land_rects():
		if r.has_point(p):
			return true
	return false

## bordas de costão calculadas a partir dos retângulos de terra (trechos de borda que dão para o mar):
## [início, fim, normal para o mar, estende no início, estende no fim] — a praia (leste) fica de fora
static func rim_edges() -> Array:
	var out := []
	for r in land_rects():
		var x0: float = r.position.x
		var z0: float = r.position.y
		var x1: float = r.end.x
		var z1: float = r.end.y
		var sides := [[Vector2(x0, z1), Vector2(x1, z1), Vector2(0, 1)], [Vector2(x0, z0), Vector2(x1, z0), Vector2(0, -1)], [Vector2(x0, z0), Vector2(x0, z1), Vector2(-1, 0)]]
		if x1 < SHORE_X - 1.0:
			sides.append([Vector2(x1, z0), Vector2(x1, z1), Vector2(1, 0)])
		for sd in sides:
			var a: Vector2 = sd[0]
			var b: Vector2 = sd[1]
			var n: Vector2 = sd[2]
			if n.y != 0.0 and b.x > SHORE_X - 6.0:
				b.x = SHORE_X - 6.0
			var L := a.distance_to(b)
			var t := (b - a).normalized()
			var seg_s := -1.0
			var s := 0.0
			while s <= L + 0.01:
				var coast := not _on_land(a + t * s + n * 1.0)
				if coast and seg_s < 0.0:
					seg_s = s
				if (not coast or s + 2.0 > L + 0.01) and seg_s >= 0.0:
					var e := s if coast else s - 2.0
					if e - seg_s > 3.0:
						var pa := a + t * seg_s
						var pb := a + t * e
						# extremidade convexa (depois dela é mar): a rampa se estende para fechar o canto
						var xa := not _on_land(pa - t * 1.5 - n * 1.0)
						var xb := not _on_land(pb + t * 1.5 - n * 1.0)
						out.append([Vector3(pa.x, 0, pa.y), Vector3(pb.x, 0, pb.y), Vector3(n.x, 0, n.y), xa, xb])
					seg_s = -1.0
				s += 2.0
	return out

## distância (m) da água até a ilha (0 = na beira); negativo = em terra
func sea_dist(x: float, z: float) -> float:
	# leste: a água começa na linha da praia; nos outros lados, 24 m depois da borda (costão)
	var best := 1e9
	for r in land_rects():
		var x1: float = SHORE_X if r.end.x >= SHORE_X else r.end.x + 24.0
		var dx := maxf(x - x1, r.position.x - 24.0 - x)
		var dz := maxf(z - (r.end.y + 24.0), (r.position.y - 24.0) - z)
		var d := Vector2(dx, dz).length() if dx > 0.0 and dz > 0.0 else maxf(dx, dz)
		best = minf(best, d)
	return best

func is_water(x: float, z: float) -> bool:
	if absf(x) > 2950.0 or absf(z) > 3450.0:
		return false               # fora do mundo / salas das lojas (x ~4000)
	return sea_dist(x, z) > 0.0

func is_swim(x: float, z := 0.0) -> bool:
	return is_water(x, z) and sea_dist(x, z) > 4.0

## altura do fundo (rampa da praia e leito)
func floor_y(x: float) -> float:
	if x < SHORE_X - 6.0:
		return 1.1
	if x < SHORE_X + 8.0:
		return lerpf(1.1, 0.0, (x - SHORE_X + 6.0) / 14.0)
	if x < SHORE_X + 70.0:
		return lerpf(0.0, SEA_FLOOR, (x - SHORE_X - 8.0) / 62.0)
	return SEA_FLOOR

# ---------------------------------------------------------------- utilidades (fundem caixas por zona/material)
func _box(zone: String, size: Vector3, pos: Vector3, mat: Material, collide := true, rot_y := 0.0) -> void:
	if not _batch.has(zone):
		_batch[zone] = {}
	var zb: Dictionary = _batch[zone]
	if not zb.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		zb[mat] = st
	var bm := BoxMesh.new()
	bm.size = size
	var xf := Transform3D(Basis(Vector3.UP, rot_y), pos)
	var arr: Array = bm.get_mesh_arrays()
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var st: SurfaceTool = zb[mat]
	for i in ix:
		st.set_normal(xf.basis * ns[i])
		st.set_uv(uv[i])
		st.add_vertex(xf * vs[i])
	if collide:
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = size
		cs.shape = bx
		cs.transform = xf
		body.add_child(cs)

func _flush(zone: String) -> void:
	for mat in _batch[zone]:
		var mi := MeshInstance3D.new()
		mi.mesh = _batch[zone][mat].commit()
		mi.material_override = mat
		add_child(mi)
	_batch[zone] = {}

func _label(text: String, pos: Vector3, size := 96, col := Color.WHITE, rot_y := 0.0, px := 0.01) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = col
	l.outline_size = 12
	l.shaded = false
	l.position = pos
	l.rotation.y = rot_y
	add_child(l)
	return l

## marcador de missão / entrada (cilindro luminoso translúcido)
static func marker(parent: Node, pos: Vector3, col: Color, r := 1.2) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 1.6
	cm.radial_segments = 20
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, 0.35)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 1.5
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.8, 0)
	return mi

# ---------------------------------------------------------------- praia, mar e píer
func _beach() -> void:
	# ilha: praia larga a leste e faixas de areia com rampa até o leito nos outros 3 lados
	var east := [[BEACH_X0, 0.0], [BEACH_X0 + 22.0, 1.1], [SHORE_X - 6.0, 1.1], [SHORE_X + 8.0, 0.0], [SHORE_X + 70.0, SEA_FLOOR], [SHORE_X + 110.0, SEA_FLOOR]]
	# costão de pedra nos outros 3 lados (sem praia): rampa de rocha que cai para o fundo
	var rim := [[0.0, 0.0], [8.0, 0.5], [16.0, 0.9], [22.0, 0.6], [25.0, -0.8], [60.0, SEA_FLOOR], [120.0, SEA_FLOOR]]
	_strip("x", 1.0, 0.0, east, ISL_Z0 - 120.0, ISL_Z1 + 120.0)
	for re in rim_edges():
		var pa: Vector3 = re[0]
		var pb: Vector3 = re[1]
		var n: Vector3 = re[2]
		var rk := M.rock(Color(0.32, 0.3, 0.27))
		if n.x != 0.0:
			_strip("x", n.x, pa.x, rim, minf(pa.z, pb.z) - (120.0 if re[3] else 0.0), maxf(pa.z, pb.z) + (120.0 if re[4] else 0.0), rk)
		else:
			_strip("z", n.z, pa.z, rim, minf(pa.x, pb.x) - (120.0 if re[3] else 0.0), maxf(pa.x, pb.x) + (120.0 if re[4] else 0.0), rk)
	_rocks()
	# leito do mar em volta de tudo (−12 m) e chão das salas das lojas
	var fl := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(6000.0, 4.0, 7000.0)
	fl.shape = fb
	fl.position = Vector3(0, SEA_FLOOR - 2.0, 0)
	body.add_child(fl)
	var fl2 := CollisionShape3D.new()
	var fb2 := BoxShape3D.new()
	fb2.size = Vector3(600.0, 20.0, 600.0)
	fl2.shape = fb2
	fl2.position = Vector3(4100.0, -10.0, 0)
	body.add_child(fl2)
	var bed := MeshInstance3D.new()
	var bpm := PlaneMesh.new()
	bpm.size = Vector2(6000.0, 7000.0)
	bed.mesh = bpm
	bed.material_override = M.sand()
	bed.position = Vector3(0, SEA_FLOOR, 0)
	add_child(bed)
	# mar em volta (planos que não cobrem a terra: faixas acima/abaixo e dos lados da península)
	var wm := M.water()
	var o := 25.0
	var rs := [
		Rect2(SHORE_X - 4.0, -3500.0, 3000.0 - SHORE_X + 4.0, 7000.0),                       # leste
		Rect2(-3000.0, -3500.0, 3000.0 + SHORE_X - 4.0, 3500.0 + ISL_Z0 - o),                 # sul
		Rect2(-3000.0, ISL_Z1 + o, 3000.0 + SHORE_X - 4.0, 3500.0 - ISL_Z1 - o),              # norte
		Rect2(-3000.0, ISL_Z0 - o, 3000.0 + PEN_X0 - o, ISL_Z1 - ISL_Z0 + 2.0 * o),           # oeste da península
		Rect2(BASE.end.x + o, PEN_Z + o, ISL_X0 - BASE.end.x - 2.0 * o, ISL_Z1 - PEN_Z),       # ao norte da península (entre a base e a ilha)
		Rect2(PEN_X0 - o, BASE.end.y + o, BASE.end.x - PEN_X0 + 2.0 * o, ISL_Z1 - BASE.end.y),  # ao norte da base
		Rect2(PEN_X0 - o, ISL_Z0 - o, ISL_X0 - PEN_X0, ISL_Z1 - PEN_Z)]                       # ao sul da península
	for r in rs:
		var wmi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = r.size
		wmi.mesh = pm
		wmi.material_override = wm
		wmi.position = Vector3(r.get_center().x, WATER_Y, r.get_center().y)
		wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(wmi)
		if water == null:
			water = wmi
	# guarda-sóis, toalhas, posto de salva-vidas, coqueiros
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var cols := [Color(0.9, 0.2, 0.15), Color(0.15, 0.45, 0.85), Color(0.95, 0.8, 0.1), Color(0.2, 0.7, 0.4)]
	for k in 22:
		var x := rng.randf_range(BEACH_X0 + 26.0, SHORE_X - 9.0)
		var z := rng.randf_range(-170.0, 170.0)
		var c: Color = cols[k % cols.size()]
		_box("beach", Vector3(0.06, 2.4, 0.06), Vector3(x, 2.3, z), M.plain(Color(0.9, 0.9, 0.9), 0.5), false)
		_box("beach", Vector3(2.6, 0.12, 2.6), Vector3(x, 3.45, z), M.plain(c, 0.6), false, rng.randf() * PI)
		_box("beach", Vector3(1.8, 0.03, 0.9), Vector3(x + 1.2, 1.13, z + 0.6), M.plain(cols[(k + 1) % cols.size()], 0.8), false, rng.randf() * PI)
	for k in 30:
		var x := rng.randf_range(BEACH_X0 + 6.0, BEACH_X0 + 24.0)
		var z := rng.randf_range(-185.0, 185.0)
		var y := clampf((x - BEACH_X0) / 22.0, 0.0, 1.0) * 1.1
		var h := rng.randf_range(6.0, 8.5)
		for q in 6:
			_box("beach", Vector3(0.32 - q * 0.02, h / 6.0, 0.32 - q * 0.02), Vector3(x + q * 0.12, y + h / 6.0 * (q + 0.5), z), M.bark(), q == 0)
		for a in 6:
			_box("beach", Vector3(3.6, 0.08, 0.7), Vector3(x + 0.7 + cos(a * 1.05) * 1.6, y + h + 0.1, z + sin(a * 1.05) * 1.6), M.leaves(), false, -a * 1.05)
	for z in [-150.0, 60.0, 260.0]:
		var x := SHORE_X - 14.0
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_box("beach", Vector3(0.15, 2.6, 0.15), Vector3(x + sx, 2.4, z + sz), M.wood(), true)
		_box("beach", Vector3(2.6, 0.15, 2.6), Vector3(x, 3.7, z), M.wood(), true)
		_box("beach", Vector3(2.2, 1.4, 2.2), Vector3(x, 4.5, z), M.plain(Color(0.9, 0.2, 0.15), 0.6), true)
		_box("beach", Vector3(2.8, 0.12, 2.8), Vector3(x, 5.25, z), M.plain(Color(0.95, 0.95, 0.95), 0.6), false)
	# píer de madeira com barcos
	var pz := 40.0
	_box("beach", Vector3(70.0, 0.25, 4.0), Vector3(SHORE_X + 28.0, 1.6, pz), M.wood(), true)
	for x in range(int(SHORE_X - 4), int(SHORE_X + 63), 6):
		for s in [-1.0, 1.0]:
			_box("beach", Vector3(0.3, 3.0, 0.3), Vector3(x, 0.3, pz + 1.8 * s), M.wood(), false)
	_box("beach", Vector3(4.0, 0.25, 16.0), Vector3(SHORE_X + 61.0, 1.6, pz + 8.0), M.wood(), true)
	boat_spots = [[Vector3(SHORE_X + 52.0, 0.4, pz + 6.5), PI * 0.5], [Vector3(SHORE_X + 52.0, 0.4, pz - 5.0), PI * 0.5], [Vector3(SHORE_X + 70.0, 0.4, pz + 12.0), 0.0]]
	beach_loop = [Vector3(BEACH_X0 + 30.0, 1.1, -170.0), Vector3(SHORE_X - 8.0, 1.1, -170.0), Vector3(SHORE_X - 8.0, 1.1, 170.0), Vector3(BEACH_X0 + 30.0, 1.1, 170.0)]

# ---------------------------------------------------------------- aeroporto
func _airfield() -> void:
	var asph := M.asphalt()
	_box("air", Vector3(340.0, 0.06, 24.0), Vector3(AIR_X, 0.03, 0), asph, false)
	for k in 24:
		_box("air", Vector3(6.0, 0.02, 0.5), Vector3(AIR_X - 160.0 + k * 14.0, 0.07, 0), M.plain(Color(0.92, 0.92, 0.9), 0.6), false)
	for s in [-1.0, 1.0]:
		_box("air", Vector3(340.0, 0.02, 0.35), Vector3(AIR_X, 0.07, 11.0 * s), M.plain(Color(0.92, 0.92, 0.9), 0.6), false)
	# pátio de concreto entre a pista e o hangar
	_box("air", Vector3(60.0, 0.05, 20.0), Vector3(-300.0, 0.025, -22.0), M.concrete(Color(0.5, 0.5, 0.5)), false)
	# hangar (ao sul da pista, porta virada para ela)
	var hx := -300.0
	var hz := -30.0
	_box("air", Vector3(40.0, 12.0, 0.6), Vector3(hx, 6.0, hz - 14.0), M.concrete(Color(0.55, 0.57, 0.6)), true)
	for s in [-1.0, 1.0]:
		_box("air", Vector3(0.6, 12.0, 28.0), Vector3(hx + 20.0 * s, 6.0, hz), M.concrete(Color(0.55, 0.57, 0.6)), true)
	_box("air", Vector3(41.0, 0.8, 29.0), Vector3(hx, 12.3, hz), M.plain(Color(0.35, 0.38, 0.42), 0.4, 0.6), true)
	_box("air", Vector3(40.0, 0.06, 28.0), Vector3(hx, 0.03, hz), M.concrete(Color(0.5, 0.5, 0.5)), false)
	_label("HANGAR", Vector3(hx, 10.5, hz + 14.4), 160, Color(1, 0.85, 0.2), 0.0)
	# torre de controle
	var tx := -215.0
	var tz := 32.0
	_box("air", Vector3(5.0, 18.0, 5.0), Vector3(tx, 9.0, tz), M.concrete(Color(0.82, 0.82, 0.8)), true)
	_box("air", Vector3(8.0, 3.5, 8.0), Vector3(tx, 19.8, tz), M.plain(Color(0.15, 0.25, 0.3), 0.05, 0.8), true)
	_box("air", Vector3(8.6, 0.5, 8.6), Vector3(tx, 21.8, tz), M.concrete(Color(0.82, 0.82, 0.8)), false)
	# heliponto
	var px := -420.0
	var pz := 2.0
	_box("air", Vector3(18.0, 0.12, 18.0), Vector3(px, 0.06, pz + 30.0), M.concrete(Color(0.35, 0.36, 0.38)), false)
	_box("air", Vector3(1.2, 0.03, 8.0), Vector3(px - 2.5, 0.13, pz + 30.0), M.plain(Color(0.95, 0.85, 0.1), 0.6), false)
	_box("air", Vector3(1.2, 0.03, 8.0), Vector3(px + 2.5, 0.13, pz + 30.0), M.plain(Color(0.95, 0.85, 0.1), 0.6), false)
	_box("air", Vector3(4.0, 0.03, 1.2), Vector3(px, 0.13, pz + 30.0), M.plain(Color(0.95, 0.85, 0.1), 0.6), false)
	plane_spots = [[Vector3(-195.0, 0.0, 0.0), -PI * 0.5], [Vector3(hx, 0.0, hz), 0.0]]
	heli_spots = [[Vector3(px, 0.15, pz + 30.0), -PI * 0.5]]
	_label("AEROPORTO", Vector3(-185.0, 6.0, 20.0), 200, Color(0.9, 0.95, 1.0), PI * 0.5, 0.012)

# ---------------------------------------------------------------- interiores das lojas
func _interior(type: String, o: Vector3) -> void:
	var zone := "int_" + type
	var W := 20.0
	var D := 16.0
	var H := 5.0
	var floor_m := M.concrete(Color(0.78, 0.76, 0.72)) if type != "cars" else M.plain(Color(0.85, 0.86, 0.88), 0.15, 0.2)
	var wall_c: Color = {"guns": Color(0.32, 0.3, 0.28), "clothes": Color(0.92, 0.88, 0.86), "cars": Color(0.9, 0.92, 0.95)}[type]
	var wall := M.plain(wall_c, 0.8)
	_box(zone, Vector3(W, 0.2, D), o + Vector3(0, 0.1, 0), floor_m, true)
	_box(zone, Vector3(W, 0.2, D), o + Vector3(0, H, 0), M.plain(Color(0.95, 0.95, 0.95), 0.9), true)
	_box(zone, Vector3(W, H, 0.3), o + Vector3(0, H * 0.5, D * 0.5), wall, true)
	_box(zone, Vector3(0.3, H, D), o + Vector3(W * 0.5, H * 0.5, 0), wall, true)
	_box(zone, Vector3(0.3, H, D), o + Vector3(-W * 0.5, H * 0.5, 0), wall, true)
	_box(zone, Vector3(W * 0.5 - 1.5, H, 0.3), o + Vector3(-W * 0.25 - 0.75, H * 0.5, -D * 0.5), wall, true)
	_box(zone, Vector3(W * 0.5 - 1.5, H, 0.3), o + Vector3(W * 0.25 + 0.75, H * 0.5, -D * 0.5), wall, true)
	_box(zone, Vector3(3.0, 1.6, 0.3), o + Vector3(0, H - 0.8, -D * 0.5), wall, true)
	_box(zone, Vector3(2.9, 3.3, 0.1), o + Vector3(0, 1.75, -D * 0.5 - 0.1), M.plain(Color(0.25, 0.35, 0.4), 0.05, 0.7), true)
	for x in [-6.0, 0.0, 6.0]:
		for z in [-4.0, 3.0]:
			_box(zone, Vector3(3.0, 0.08, 0.6), o + Vector3(x, H - 0.12, z), M.emissive(Color(1, 0.97, 0.9), 2.5), false)
	var light := OmniLight3D.new()
	light.omni_range = 22.0
	light.light_energy = 2.2
	light.light_color = Color(1.0, 0.96, 0.9)
	light.position = o + Vector3(0, H - 0.6, 0)
	add_child(light)
	# balcão + atendente
	var counter := o + Vector3(0, 0, D * 0.5 - 3.2)
	_box(zone, Vector3(6.0, 1.05, 0.9), counter + Vector3(0, 0.62, 0.8), M.plain(Color(0.25, 0.18, 0.12), 0.5), true)
	_box(zone, Vector3(6.2, 0.08, 1.1), counter + Vector3(0, 1.17, 0.8), M.plain(Color(0.1, 0.1, 0.1), 0.2, 0.3), false)
	var clerk := Humanoid.new()
	var shirt: Color = {"guns": Color(0.2, 0.25, 0.15), "clothes": Color(0.85, 0.3, 0.6), "cars": Color(0.12, 0.14, 0.2)}[type]
	clerk.build(shirt, Color(0.1, 0.1, 0.12), Color(0.78, 0.56, 0.38), Color(0.1, 0.07, 0.05))
	add_child(clerk)
	clerk.position = counter + Vector3(0, 0.15, 1.8)
	clerk.rotation.y = PI
	clerk.animate(0, 0)
	match type:
		"guns":
			for x in [-8.0, 8.0]:
				for y in [1.4, 2.4, 3.4]:
					_box(zone, Vector3(0.4, 0.06, 10.0), o + Vector3(x, y, 0), M.wood(), false)
					for z in range(-4, 5, 2):
						_box(zone, Vector3(0.12, 0.08, 0.9), o + Vector3(x - 0.05 * signf(x), y + 0.12, z), M.plain(Color(0.08, 0.08, 0.09), 0.4, 0.8), false, PI * 0.5)
			_box(zone, Vector3(8.0, 2.2, 0.15), o + Vector3(0, 3.2, D * 0.5 - 0.2), M.plain(Color(0.6, 0.08, 0.05), 0.6), false)
			_label("AMMU★NATION", o + Vector3(0, 3.2, D * 0.5 - 0.35), 120, Color(1, 0.9, 0.85), PI)
		"clothes":
			for x in [-7.0, -3.5, 3.5, 7.0]:
				_box(zone, Vector3(0.06, 1.6, 0.06), o + Vector3(x, 0.9, -2.0), M.plain(Color(0.7, 0.7, 0.72), 0.3, 0.9), false)
				_box(zone, Vector3(0.06, 0.06, 3.0), o + Vector3(x, 1.7, -0.5), M.plain(Color(0.7, 0.7, 0.72), 0.3, 0.9), false)
				for k in 7:
					var cc := Color.from_hsv(fmod(k * 0.13 + x * 0.05 + 1.0, 1.0), 0.6, 0.8)
					_box(zone, Vector3(0.6, 0.9, 0.08), o + Vector3(x, 1.2, -1.8 + k * 0.42), M.plain(cc, 0.9), false, PI * 0.5)
			_box(zone, Vector3(0.1, 2.4, 1.4), o + Vector3(-W * 0.5 + 0.2, 1.4, 3.0), M.plain(Color(0.7, 0.8, 0.85), 0.02, 1.0), false)
			_label("ROUPAS", o + Vector3(0, 3.6, D * 0.5 - 0.2), 140, Color(0.95, 0.45, 0.85), PI)
		"cars":
			var kinds := ["hatch", "sedan", "pickup", "suv", "moto", "sport"]
			var colors := [Color(0.6, 0.04, 0.04), Color(0.92, 0.92, 0.93), Color(0.06, 0.2, 0.55), Color(0.45, 0.47, 0.5), Color(0.05, 0.05, 0.06), Color(0.85, 0.55, 0.05)]
			var spots := [Vector3(-7.5, 0, -3.2), Vector3(7.5, 0, -3.2), Vector3(-7.5, 0, 1.8), Vector3(7.5, 0, 1.8), Vector3(-3.2, 0, 1.6), Vector3(3.2, 0, 1.6)]
			for k in kinds.size():
				var b: Dictionary = (load("res://scripts/vehmodel.gd").build("moto", colors[k]) if kinds[k] == "moto" else CM.build(kinds[k], colors[k]))
				var root: Node3D = b.root
				add_child(root)
				root.position = o + spots[k] + Vector3(0, 0.2, 0)
				root.rotation.y = 0.6 if spots[k].x < 0 else -0.6
				if k >= 4:
					root.rotation.y = PI * 0.5
				for wd in b.wheels:
					var n: Node3D = wd.node
					root.add_child(n)
					n.position = wd.pos
			_label("CONCESSIONÁRIA", o + Vector3(0, 3.8, D * 0.5 - 0.2), 120, Color(0.3, 0.8, 1.0), PI)
	interiors[type] = {"origin": o, "spawn": o + Vector3(0, 0.3, -D * 0.5 + 3.6), "exit": o + Vector3(0, 0.2, -D * 0.5 + 0.8), "counter": counter + Vector3(0, 0.2, -0.3)}


## faixa de areia com rampa: eixo "x" (perfil em x, extensão em z) ou "z"; sign = para fora da ilha
func _strip(axis: String, sgn: float, edge: float, prof: Array, a0: float, a1: float, mat: Material = null) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in prof.size() - 1:
		var pa: Array = prof[i]
		var pb: Array = prof[i + 1]
		var d0: float = pa[0] if axis == "x" and sgn > 0 and prof[0][0] > 100.0 else edge + sgn * pa[0]
		var d1: float = pb[0] if axis == "x" and sgn > 0 and prof[0][0] > 100.0 else edge + sgn * pb[0]
		var q := []
		if axis == "x":
			q = [Vector3(d0, pa[1], a0), Vector3(d1, pb[1], a0), Vector3(d1, pb[1], a1), Vector3(d0, pa[1], a1)]
		else:
			q = [Vector3(a0, pa[1], d0), Vector3(a0, pb[1], d1), Vector3(a1, pb[1], d1), Vector3(a1, pa[1], d0)]
		var tri := [q[0], q[1], q[2], q[0], q[2], q[3]]
		var flip := (sgn < 0) == (axis == "x")
		if flip:
			tri = [q[0], q[2], q[1], q[0], q[3], q[2]]
		for v in tri:
			st.set_uv(Vector2(v.x, v.z) * 0.2)
			st.add_vertex(v)
	st.generate_normals()
	var sm := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = mat if mat else M.sand()
	add_child(mi)
	var cs := CollisionShape3D.new()
	var shp := sm.create_trimesh_shape()
	shp.backface_collision = true
	cs.shape = shp
	body.add_child(cs)

# ---------------------------------------------------------------- costão: pedras, pontos de pesca e farol
func _rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 515
	var rk := M.rock(Color(0.5, 0.48, 0.44))
	var rk2 := M.rock(Color(0.42, 0.38, 0.33))
	# pedras ao longo das bordas de costão
	var edges := []
	for re in rim_edges():
		var a0: Vector3 = re[0]
		var a1: Vector3 = re[1]
		var L := a0.distance_to(a1)
		var t := 0.0
		while t < L:
			edges.append([a0.lerp(a1, t / L), re[2]])
			t += rng.randf_range(5.0, 9.0)
	for e in edges:
		var out: Vector3 = e[1]
		var k := rng.randi_range(1, 3)
		for q in k:
			var d := rng.randf_range(6.0, 26.0)
			var sz := Vector3(rng.randf_range(1.5, 4.5), rng.randf_range(1.0, 3.2), rng.randf_range(1.5, 4.5)) * (1.0 + d / 40.0)
			var side := Vector3(out.z, 0, -out.x) * rng.randf_range(-3.0, 3.0)
			var pos: Vector3 = e[0] + out * d + side
			var gy := 0.6 if d < 22.0 else -1.0
			pos.y = gy + sz.y * 0.3
			_box("rocks", sz, pos, rk if rng.randf() < 0.6 else rk2, d < 20.0 and sz.y > 1.6, rng.randf() * PI)
	# pontos de pesca: deque de madeira saindo do costão, banco, balde e pescador com vara
	var spots := [[Vector3(-90.0, 0, ISL_Z1), Vector3(0, 0, 1)], [Vector3(70.0, 0, ISL_Z1), Vector3(0, 0, 1)],
			[Vector3(-60.0, 0, ISL_Z0), Vector3(0, 0, -1)], [Vector3(110.0, 0, ISL_Z0), Vector3(0, 0, -1)], [Vector3(ISL_X0, 0, 130.0), Vector3(-1, 0, 0)],
			[Vector3(-300.0, 0, PEN_Z), Vector3(0, 0, 1)], [Vector3(-260.0, 0, -PEN_Z), Vector3(0, 0, -1)]]
	for sp in spots:
		var o: Vector3 = sp[0]
		var out: Vector3 = sp[1]
		var yaw := atan2(out.x, out.z)
		var len_ := 30.0
		var mid := o + out * (len_ * 0.5 + 6.0)
		var dims := Vector3(3.0, 0.25, len_) if absf(out.z) > 0.5 else Vector3(len_, 0.25, 3.0)
		_box("rocks", dims, mid + Vector3(0, 1.6, 0), M.wood(), true)
		var tip := o + out * (len_ + 5.0)
		for t in range(0, int(len_), 5):
			for s2 in [-1.0, 1.0]:
				var side: Vector3 = Vector3(out.z, 0, -out.x) * 1.4 * s2
				_box("rocks", Vector3(0.25, 3.4, 0.25), o + out * (8.0 + t) + side + Vector3(0, 0.0, 0), M.wood(), false)
		_box("rocks", Vector3(1.6, 0.5, 0.5), tip - out * 1.5 + Vector3(0, 2.0, 0), M.wood(), false, yaw + PI * 0.5)
		_box("rocks", Vector3(0.4, 0.45, 0.4), tip - out * 1.0 + Vector3(0.9, 1.95, 0), M.plain(Color(0.2, 0.45, 0.8), 0.5), false)
		fish_spots.append([tip - out * 1.2 + Vector3(0, 1.75, 0), yaw])
	# farol no canto noroeste
	var lh := Vector3(PEN_X0 + 6.0, 0.0, -PEN_Z + 8.0)
	for i in 6:
		var w := 4.2 - i * 0.35
		_box("rocks", Vector3(w, 3.0, w), lh + Vector3(0, 1.5 + i * 3.0, 0), M.plain(Color(0.92, 0.92, 0.9) if i % 2 == 0 else Color(0.8, 0.12, 0.1), 0.6), true)
	_box("rocks", Vector3(2.4, 2.0, 2.4), lh + Vector3(0, 19.0, 0), M.emissive(Color(1.0, 0.9, 0.5), 2.5), false)
	_box("rocks", Vector3(3.0, 0.4, 3.0), lh + Vector3(0, 20.2, 0), M.plain(Color(0.15, 0.15, 0.15), 0.5), false)

# ---------------------------------------------------------------- base do exército (canto isolado)
## muro com portão, quartéis, hangar dos caças com pista curta, garagem dos tanques, torres de vigia,
## heliponto e mastro. É de lá que saem os tanques e os caças a 5 estrelas.
func _army_base() -> void:
	var r := BASE
	var x0: float = r.position.x + 4.0
	var x1: float = r.end.x - 4.0
	var z0: float = r.position.y + 4.0
	var z1: float = r.end.y - 4.0
	var cx := (x0 + x1) * 0.5
	var olive := M.concrete(Color(0.36, 0.38, 0.28))
	var sand_c := M.concrete(Color(0.58, 0.54, 0.44))
	var dark := M.plain(Color(0.16, 0.17, 0.14), 0.6)
	var asph := M.asphalt()
	# pátio de asfalto
	_box("base", Vector3(x1 - x0, 0.06, z1 - z0), Vector3(cx, 0.03, (z0 + z1) * 0.5), asph, false)
	# muro (portão ao sul, voltado para a pista do aeroporto)
	var gate_x := x1 - 18.0
	_box("base", Vector3(x1 - x0, 2.8, 0.5), Vector3(cx, 1.4, z1), sand_c, true)
	_box("base", Vector3(0.5, 2.8, z1 - z0), Vector3(x0, 1.4, (z0 + z1) * 0.5), sand_c, true)
	_box("base", Vector3(0.5, 2.8, z1 - z0), Vector3(x1, 1.4, (z0 + z1) * 0.5), sand_c, true)
	_box("base", Vector3(gate_x - 6.0 - x0, 2.8, 0.5), Vector3((x0 + gate_x - 6.0) * 0.5, 1.4, z0), sand_c, true)
	_box("base", Vector3(x1 - gate_x - 6.0, 2.8, 0.5), Vector3((gate_x + 6.0 + x1) * 0.5, 1.4, z0), sand_c, true)
	for sx in [-6.0, 6.0]:
		_box("base", Vector3(0.8, 3.6, 0.8), Vector3(gate_x + sx, 1.8, z0), dark, true)
	_box("base", Vector3(12.0, 0.25, 0.25), Vector3(gate_x, 1.1, z0 - 0.6), M.plain(Color(0.9, 0.15, 0.1), 0.6), false)
	base_gate = Vector3(gate_x, 0.3, z0 - 3.0)
	# quartéis (2 prédios baixos com janelas)
	for k in 2:
		var bz := z1 - 12.0 - k * 22.0
		_box("base", Vector3(30.0, 5.0, 12.0), Vector3(x0 + 20.0, 2.5, bz), olive, true)
		_box("base", Vector3(31.0, 0.4, 13.0), Vector3(x0 + 20.0, 5.2, bz), dark, false)
		for w in 6:
			_box("base", Vector3(2.0, 1.2, 0.1), Vector3(x0 + 8.0 + w * 4.8, 3.0, bz - 6.05), M.plain(Color(0.15, 0.22, 0.28), 0.1, 0.6), false)
		_label("QUARTEL %d" % (k + 1), Vector3(x0 + 20.0, 4.3, bz - 6.2), 120, Color(0.95, 0.9, 0.7), PI, 0.01)
	# hangar dos caças (aberto para o leste) + pista curta
	var hx := x1 - 26.0
	var hz := z1 - 16.0
	_box("base", Vector3(36.0, 11.0, 0.6), Vector3(hx, 5.5, hz + 12.0), olive, true)
	_box("base", Vector3(0.6, 11.0, 24.0), Vector3(hx - 18.0, 5.5, hz), olive, true)
	_box("base", Vector3(37.0, 0.8, 25.0), Vector3(hx, 11.4, hz), dark, true)
	_label("HANGAR MILITAR", Vector3(hx, 9.5, hz - 12.2), 140, Color(1, 0.85, 0.3), PI, 0.012)
	jet_spots = [[Vector3(hx - 6.0, 2.0, hz), PI * 0.5], [Vector3(hx + 8.0, 2.0, hz), PI * 0.5]]
	# garagem dos tanques (aberta para o sul)
	var gx := cx + 10.0
	var gz := z0 + 22.0
	_box("base", Vector3(26.0, 6.0, 0.5), Vector3(gx, 3.0, gz + 7.0), olive, true)
	for sx in [-13.0, 13.0]:
		_box("base", Vector3(0.5, 6.0, 14.0), Vector3(gx + sx, 3.0, gz), olive, true)
	_box("base", Vector3(27.0, 0.6, 15.0), Vector3(gx, 6.2, gz), dark, true)
	tank_spots = [[Vector3(gx - 6.0, 0.6, gz), PI], [Vector3(gx + 6.0, 0.6, gz), PI]]
	# torres de vigia nos cantos
	for c in [Vector3(x0 + 2.0, 0, z0 + 2.0), Vector3(x1 - 2.0, 0, z0 + 2.0), Vector3(x0 + 2.0, 0, z1 - 2.0), Vector3(x1 - 2.0, 0, z1 - 2.0)]:
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_box("base", Vector3(0.3, 7.0, 0.3), c + Vector3(sx * 1.4, 3.5, sz * 1.4), dark, true)
		_box("base", Vector3(3.6, 0.3, 3.6), c + Vector3(0, 7.0, 0), dark, true)
		_box("base", Vector3(3.6, 1.0, 0.1), c + Vector3(0, 7.6, 1.75), olive, false)
		_box("base", Vector3(3.6, 0.2, 3.6), c + Vector3(0, 9.3, 0), olive, false)
	# heliponto e mastro
	var hp := Vector3(x0 + 18.0, 0.07, z0 + 16.0)
	_box("base", Vector3(16.0, 0.08, 16.0), hp, M.concrete(Color(0.3, 0.31, 0.3)), false)
	_box("base", Vector3(1.2, 0.03, 7.0), hp + Vector3(-2.3, 0.06, 0), M.plain(Color(0.95, 0.95, 0.9), 0.6), false)
	_box("base", Vector3(1.2, 0.03, 7.0), hp + Vector3(2.3, 0.06, 0), M.plain(Color(0.95, 0.95, 0.9), 0.6), false)
	_box("base", Vector3(3.4, 0.03, 1.2), hp + Vector3(0, 0.06, 0), M.plain(Color(0.95, 0.95, 0.9), 0.6), false)
	_box("base", Vector3(0.15, 12.0, 0.15), Vector3(cx - 10.0, 6.0, z0 + 6.0), M.plain(Color(0.8, 0.8, 0.82), 0.3, 0.8), true)
	_box("base", Vector3(0.05, 1.6, 2.6), Vector3(cx - 10.0, 11.0, z0 + 7.4), M.plain(Color(0.1, 0.45, 0.2), 0.8), false)
	# caixas de munição e sacos de areia
	for k in 8:
		_box("base", Vector3(1.4, 1.0, 1.0), Vector3(cx - 30.0 + (k % 4) * 1.6, 0.5 + float(k / 4) * 1.0, z0 + 30.0), M.plain(Color(0.3, 0.33, 0.2), 0.8), true)
	for k in 6:
		_box("base", Vector3(2.0, 0.9, 1.0), Vector3(x0 + 6.0 + k * 2.2, 0.45, z0 + 4.0), M.plain(Color(0.6, 0.55, 0.4), 0.9), true)
	_label("BASE MILITAR · ACESSO RESTRITO", Vector3(gate_x, 4.4, z0 - 0.4), 140, Color(1.0, 0.3, 0.2), PI, 0.012)

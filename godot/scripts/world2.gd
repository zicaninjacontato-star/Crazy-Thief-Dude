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
var station_cars: Array = []  # vagas da delegacia [pos, yaw]
var beach_loop: Array = []
var _wt := 0.0

func build(m: Node3D) -> void:
	main = m
	body = StaticBody3D.new()
	body.name = "ColisaoExtra"
	add_child(body)
	_beach()
	_airfield()
	_station()
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

const ISL_X0 := -600.0       # ilha: x de ISL_X0 até SHORE_X, z de ISL_Z0 até ISL_Z1
const ISL_Z0 := -600.0
const ISL_Z1 := 600.0

## distância (m) da água até a ilha (0 = na beira); negativo = em terra
func sea_dist(x: float, z: float) -> float:
	var dx := maxf(x - SHORE_X, ISL_X0 - 24.0 - x)
	var dz := maxf(z - (ISL_Z1 + 24.0), (ISL_Z0 - 24.0) - z)
	if dx > 0.0 and dz > 0.0:
		return Vector2(dx, dz).length()
	return maxf(dx, dz)

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
	var rim := [[0.0, 0.0], [10.0, 1.1], [20.0, 1.1], [30.0, 0.0], [90.0, SEA_FLOOR], [120.0, SEA_FLOOR]]
	_strip("x", 1.0, 0.0, east, ISL_Z0 - 120.0, ISL_Z1 + 120.0)
	_strip("x", -1.0, ISL_X0, rim, ISL_Z0 - 120.0, ISL_Z1 + 120.0)
	_strip("z", 1.0, ISL_Z1, rim, ISL_X0 - 120.0, SHORE_X + 10.0)
	_strip("z", -1.0, ISL_Z0, rim, ISL_X0 - 120.0, SHORE_X + 10.0)
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
	# mar nos 4 lados (sem cobrir a ilha)
	var wm := M.water()
	for r in [Rect2(SHORE_X - 4.0, -3500.0, 3000.0 - SHORE_X + 4.0, 7000.0), Rect2(-3000.0, -3500.0, 3000.0 + ISL_X0 - 25.0, 7000.0),
			Rect2(ISL_X0 - 25.0, ISL_Z1 + 25.0, SHORE_X - 4.0 - ISL_X0 + 25.0, 3500.0 - ISL_Z1 - 25.0), Rect2(ISL_X0 - 25.0, -3500.0, SHORE_X - 4.0 - ISL_X0 + 25.0, 3500.0 + ISL_Z0 - 25.0)]:
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
		var z := rng.randf_range(-300.0, 300.0)
		var c: Color = cols[k % cols.size()]
		_box("beach", Vector3(0.06, 2.4, 0.06), Vector3(x, 2.3, z), M.plain(Color(0.9, 0.9, 0.9), 0.5), false)
		_box("beach", Vector3(2.6, 0.12, 2.6), Vector3(x, 3.45, z), M.plain(c, 0.6), false, rng.randf() * PI)
		_box("beach", Vector3(1.8, 0.03, 0.9), Vector3(x + 1.2, 1.13, z + 0.6), M.plain(cols[(k + 1) % cols.size()], 0.8), false, rng.randf() * PI)
	for k in 30:
		var x := rng.randf_range(BEACH_X0 + 6.0, BEACH_X0 + 24.0)
		var z := rng.randf_range(-400.0, 400.0)
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
	beach_loop = [Vector3(BEACH_X0 + 30.0, 1.1, -200.0), Vector3(SHORE_X - 8.0, 1.1, -200.0), Vector3(SHORE_X - 8.0, 1.1, 200.0), Vector3(BEACH_X0 + 30.0, 1.1, 200.0)]

# ---------------------------------------------------------------- aeroporto
func _airfield() -> void:
	var asph := M.asphalt()
	_box("air", Vector3(340.0, 0.06, 24.0), Vector3(AIR_X, 0.03, 0), asph, false)
	for k in 24:
		_box("air", Vector3(6.0, 0.02, 0.5), Vector3(AIR_X - 160.0 + k * 14.0, 0.07, 0), M.plain(Color(0.92, 0.92, 0.9), 0.6), false)
	for s in [-1.0, 1.0]:
		_box("air", Vector3(340.0, 0.02, 0.35), Vector3(AIR_X, 0.07, 11.0 * s), M.plain(Color(0.92, 0.92, 0.9), 0.6), false)
	# pista de táxi até a cidade
	_box("air", Vector3(150.0, 0.06, 14.0), Vector3(-240.0, 0.03, 40.0), asph, false)
	# hangar
	var hx := -250.0
	var hz := 75.0
	_box("air", Vector3(40.0, 12.0, 0.6), Vector3(hx, 6.0, hz + 14.0), M.concrete(Color(0.55, 0.57, 0.6)), true)
	for s in [-1.0, 1.0]:
		_box("air", Vector3(0.6, 12.0, 28.0), Vector3(hx + 20.0 * s, 6.0, hz), M.concrete(Color(0.55, 0.57, 0.6)), true)
	_box("air", Vector3(41.0, 0.8, 29.0), Vector3(hx, 12.3, hz), M.plain(Color(0.35, 0.38, 0.42), 0.4, 0.6), true)
	_box("air", Vector3(40.0, 0.06, 28.0), Vector3(hx, 0.03, hz), M.concrete(Color(0.5, 0.5, 0.5)), false)
	_label("HANGAR", Vector3(hx, 10.5, hz - 14.4), 160, Color(1, 0.85, 0.2), PI)
	# torre de controle
	var tx := -215.0
	var tz := -45.0
	_box("air", Vector3(5.0, 18.0, 5.0), Vector3(tx, 9.0, tz), M.concrete(Color(0.82, 0.82, 0.8)), true)
	_box("air", Vector3(8.0, 3.5, 8.0), Vector3(tx, 19.8, tz), M.plain(Color(0.15, 0.25, 0.3), 0.05, 0.8), true)
	_box("air", Vector3(8.6, 0.5, 8.6), Vector3(tx, 21.8, tz), M.concrete(Color(0.82, 0.82, 0.8)), false)
	# heliponto
	var px := -205.0
	var pz := 40.0
	_box("air", Vector3(18.0, 0.12, 18.0), Vector3(px, 0.06, pz + 30.0), M.concrete(Color(0.35, 0.36, 0.38)), false)
	_box("air", Vector3(1.2, 0.03, 8.0), Vector3(px - 2.5, 0.13, pz + 30.0), M.plain(Color(0.95, 0.85, 0.1), 0.6), false)
	_box("air", Vector3(1.2, 0.03, 8.0), Vector3(px + 2.5, 0.13, pz + 30.0), M.plain(Color(0.95, 0.85, 0.1), 0.6), false)
	_box("air", Vector3(4.0, 0.03, 1.2), Vector3(px, 0.13, pz + 30.0), M.plain(Color(0.95, 0.85, 0.1), 0.6), false)
	plane_spots = [[Vector3(-195.0, 0.0, 0.0), -PI * 0.5], [Vector3(hx, 0.0, hz), PI]]
	heli_spots = [[Vector3(px, 0.15, pz + 30.0), -PI * 0.5]]
	_label("AEROPORTO", Vector3(-185.0, 6.0, 20.0), 200, Color(0.9, 0.95, 1.0), PI * 0.5, 0.012)

# ---------------------------------------------------------------- delegacia
func _station() -> void:
	var c: Vector3 = main.city.police_pos
	var blue := M.plain(Color(0.1, 0.22, 0.55), 0.5)
	var white := M.concrete(Color(0.86, 0.87, 0.88))
	# fachada com marquise azul, colunas e escada
	_box("st", Vector3(22.0, 0.5, 4.0), c + Vector3(0, 4.2, 1.0), blue, false)
	for s in [-1.0, -0.33, 0.33, 1.0]:
		_box("st", Vector3(0.5, 4.0, 0.5), c + Vector3(10.0 * s, 2.0, -0.6), white, true)
	_box("st", Vector3(12.0, 0.3, 2.0), c + Vector3(0, 0.15, 1.6), white, false)
	_label("DELEGACIA", c + Vector3(0, 5.3, 2.25), 180, Color(0.85, 0.92, 1.0), PI, 0.012)
	for s in [-1.0, 1.0]:
		_box("st", Vector3(0.4, 0.4, 0.4), c + Vector3(7.5 * s, 4.75, 2.2), M.emissive(Color(0.15, 0.35, 1.0), 3.0), false)
	var road_z: float = c.z - 2.7     # junto ao meio-fio (fora da faixa de rolamento)
	for k in 3:
		station_cars.append([Vector3(c.x - 10.0 + k * 7.0, 0.7, road_z), PI * 0.5])

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
func _strip(axis: String, sgn: float, edge: float, prof: Array, a0: float, a1: float) -> void:
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
	mi.material_override = M.sand()
	add_child(mi)
	var cs := CollisionShape3D.new()
	var shp := sm.create_trimesh_shape()
	shp.backface_collision = true
	cs.shape = shp
	body.add_child(cs)

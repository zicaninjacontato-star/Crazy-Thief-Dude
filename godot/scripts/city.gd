extends Node3D
## Gera o bairro de teste: quadras com calçadas, prédios com fachadas PBR, ruas com faixas,
## postes e árvores (MultiMesh), além de toda a colisão estática.

const M := preload("res://scripts/mats.gd")

const W2 := preload("res://scripts/world2.gd")
const N := 7            # quadras por lado
const CELL := 64.0      # distância entre centros de quadras
const ROADW := 14.0     # largura do asfalto entre quadras
const SIDE := 4.0       # largura da calçada
var BLOCK := CELL - ROADW   # lado da laje da quadra (calçada + lotes)

var body: StaticBody3D
var rng := RandomNumberGenerator.new()
var lanes: Array = []   # pontos de rota de carros (centro das faixas)
var house_loops: Array = []   # índices em walk_loops das ruas de casas (norte/sul)
var walk_loops: Array = []  # percursos de pedestres (um por quadra)
var hospital_pos := Vector3.ZERO
var police_pos := Vector3.ZERO
var shops: Array = []   # {type, pos, name}
var lamp_mat: StandardMaterial3D
var bus_route: Array = []   # [{p: Vector3 (faixa), stop: bool}] em volta das quadras 1..3 x 1..3

## manual = true: o main chama build() aos poucos (tela de título com barra de progresso)
var manual := false
func _ready() -> void:
	if not manual:
		build()

func build(step: Callable = Callable()) -> void:
	_party_rng.seed = 99
	rng.seed = 2026
	body = StaticBody3D.new()
	body.name = "Colisao"
	add_child(body)
	_ground()
	for i in N:
		for j in N:
			_block(_center(i), _center(j))
		if step.is_valid():
			await step.call(0.05 + 0.45 * float(i + 1) / N, "Construindo a cidade")
	_markings()
	_props()
	_landmarks()
	_bus_line()
	_race_lot()
	if step.is_valid():
		await step.call(0.55, "Bairros, morros e ponte")
	_districts()
	if step.is_valid():
		await step.call(0.62, "Juntando a cidade")
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
	if OS.get_cmdline_user_args().has("--view=matstat"):
		var st := {}
		for mat in _batch:
			var m: StandardMaterial3D = mat
			var k := "tex" if m.albedo_texture else "notex"
			k += "_emi" if m.emission_enabled else ""
			k += "_tri" if m.uv1_triplanar else ""
			k += "_alpha" if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED else ""
			k += "_nrm" if m.normal_enabled else ""
			k += "_vc" if m.vertex_color_use_as_albedo else ""
			st[k] = st.get(k, 0) + 1
		print("MATSTAT ", st, " total=", _batch.size())
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

## material liso (só cor, sem textura/emissão/transparência): vai para um lote único com cor por
## vértice, separado só por rugosidade/metal. Antes eram ~580 materiais = ~580 malhas/draw calls.
var _vc_mats := {}
func _vc_key(mat: Material):
	if not (mat is StandardMaterial3D):
		return null
	var m: StandardMaterial3D = mat
	# letreiros/luzes de uma cor só (emissão sem textura): um material sem sombreamento com cor por vértice
	if m.emission_enabled and m.emission_texture == null and m.albedo_texture == null and m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
		if not _vc_mats.has("emi"):
			var em := StandardMaterial3D.new()
			em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			em.vertex_color_use_as_albedo = true
			_vc_mats["emi"] = em
		return "emi"
	if m.emission_enabled or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or m.vertex_color_use_as_albedo or m.albedo_color.a < 0.99:
		return null
	# mesmo "acabamento" (texturas, rugosidade, metal, escala/triplanar) = mesmo material; a cor vai no vértice
	var key := "vc|%s|%s|%s|%.1f|%.1f|%s|%s" % [m.albedo_texture, m.normal_texture if m.normal_enabled else null, m.roughness_texture, snappedf(m.roughness, 0.1), snappedf(m.metallic, 0.1), m.uv1_scale, m.uv1_triplanar]
	if not _vc_mats.has(key):
		var vm: StandardMaterial3D = m.duplicate()
		vm.vertex_color_use_as_albedo = true
		vm.albedo_color = Color.WHITE
		vm.roughness = snappedf(m.roughness, 0.1)
		vm.metallic = snappedf(m.metallic, 0.1)
		_vc_mats[key] = vm
	return key

func _batch_add(mesh: Mesh, xf: Transform3D, mat: Material) -> void:
	var key = _vc_key(mat)
	if key == null:
		if not _batch.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_batch[mat] = st
		_batch[mat].append_from(mesh, 0, xf)
		return
	var vm: StandardMaterial3D = _vc_mats[key]
	if not _batch.has(vm):
		var st2 := SurfaceTool.new()
		st2.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batch[vm] = st2
	var col: Color = (mat as StandardMaterial3D).albedo_color
	if key == "emi":
		var sm: StandardMaterial3D = mat
		col = sm.emission.lightened(clampf((sm.emission_energy_multiplier - 1.0) * 0.15, 0.0, 0.35))
	var arr: Array = mesh.get_mesh_arrays()
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var tg = arr[Mesh.ARRAY_TANGENT]
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var stv: SurfaceTool = _batch[vm]
	var has_tg: bool = tg != null and tg.size() >= vs.size() * 4
	for i in ix:
		stv.set_color(col)
		stv.set_normal((xf.basis * ns[i]).normalized())
		stv.set_uv(uvs[i])
		if has_tg:
			var t3 := (xf.basis * Vector3(tg[i * 4], tg[i * 4 + 1], tg[i * 4 + 2])).normalized()
			stv.set_tangent(Plane(t3, tg[i * 4 + 3]))
		stv.add_vertex(xf * vs[i])

func _box(size: Vector3, pos: Vector3, mat: Material, collide := true, parent: Node = self) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	if parent == self:
		_batch_add(bm, Transform3D(Basis(), pos), mat)
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
	if Vector2i(bi, bj) == HOSPITAL_BLOCK:
		_hospital(cx, cz)
		return
	if Vector2i(bi, bj) == GANG_BLOCK:
		_gang_hq(cx, cz, inner, "p", PI)
		return
	# fileira norte: rua só de casas · fileira sul: galpões e obras
	if bj == N - 1 and STORE_BLOCKS.get(Vector2i(bi, bj), "") == "":
		_houses_block(cx, cz, inner)
		return
	if bj == 0 and STORE_BLOCKS.get(Vector2i(bi, bj), "") == "":
		if bi == 1 or bi == 5:
			_construction(cx, cz, inner)
		else:
			_warehouses(cx, cz, inner)
		return
	_avenue = bj == 3 or bj == 4      # avenida central: térreo cheio de lojas
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

var _avenue := false
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
	if _avenue:
		# avenida: letreiros luminosos coloridos das lojas do térreo nos 4 lados
		for sd in 4:
			for k in 2:
				var col := Color.from_hsv(rng.randf(), 0.75, 1.0)
				var off := (k - 0.5) * 0.45
				var pos := Vector3(c.x, ground_h - 0.5, c.y)
				var sz := Vector3(w * 0.35, 0.6, 0.12)
				match sd:
					0: pos += Vector3(off * w, 0, -d * 0.5 - 0.1)
					1: pos += Vector3(off * w, 0, d * 0.5 + 0.1)
					2:
						pos += Vector3(-w * 0.5 - 0.1, 0, off * d)
						sz = Vector3(0.12, 0.6, d * 0.35)
					3:
						pos += Vector3(w * 0.5 + 0.1, 0, off * d)
						sz = Vector3(0.12, 0.6, d * 0.35)
				_box(sz, pos, M.emissive(col, 1.4), false)
	# platibanda e laje de cobertura
	var top := hgt + 0.15
	var roof := M.concrete(Color(0.42, 0.41, 0.4))
	# platibanda e laje COM colisão (antes o jogador pisava 1 m abaixo e "afundava" no telhado)
	_box(Vector3(w + 0.5, 0.9, d + 0.5), Vector3(c.x, top + 0.45, c.y), roof, true)
	_box(Vector3(w - 0.3, 0.2, d - 0.3), Vector3(c.x, top + 0.95, c.y), M.concrete(Color(0.3, 0.3, 0.31)), true)
	# alguns prédios médios têm festa no terraço (piscina, churrasco, gente conversando)
	var party: bool = rooftops.size() < 4 and w >= 15.0 and d >= 15.0 and floors >= 4 and floors <= 14 and _party_rng.randf() < 0.3
	# equipamentos no telhado (o sorteio acontece sempre, para não mudar o resto do mapa)
	for k in rng.randi_range(1, 4):
		var p := Vector3(c.x + rng.randf_range(-w * 0.3, w * 0.3), top + 1.6, c.y + rng.randf_range(-d * 0.3, d * 0.3))
		var esz := Vector3(rng.randf_range(1.5, 3.0), 1.2, rng.randf_range(1.5, 2.5))
		if not party:
			_box(esz, p, M.plain(Color(0.6, 0.62, 0.63), 0.4, 0.6), true)
	if party:
		_roof_party(c, w, d, top + 1.05)

var rooftops: Array = []     # festas nos terraços: {top, entry, exit, people, pool, grill}
var _party_rng := RandomNumberGenerator.new()
func _roof_party(c: Vector2, w: float, d: float, fy: float) -> void:
	# lado da entrada: o que dá para a rua (longe do centro da quadra)
	var bi := roundi(c.x / CELL + (N - 1) * 0.5)
	var bj := roundi(c.y / CELL + (N - 1) * 0.5)
	var rel := c - Vector2(_center(bi), _center(bj))
	var sd := Vector2(0, 1)
	if absf(rel.x) > absf(rel.y) + 1.0:
		sd = Vector2(signf(rel.x), 0)
	elif absf(rel.y) > 1.0:
		sd = Vector2(0, signf(rel.y))
	var half := Vector2(w, d) * 0.5
	var edge := Vector2(c.x + sd.x * (half.x + 0.9), c.y + sd.y * (half.y + 0.9))
	var entry := Vector3(edge.x, 0.3, edge.y)
	# portaria no térreo
	var col := Color(0.2, 0.85, 1.0)
	_box(Vector3(2.4 if sd.y != 0 else 0.15, 2.6, 0.15 if sd.y != 0 else 2.4), Vector3(c.x + sd.x * (half.x + 0.08), 1.45, c.y + sd.y * (half.y + 0.08)), M.plain(Color(0.08, 0.08, 0.1), 0.3), false)
	var lb := Label3D.new()
	lb.text = "TERRAÇO · POOL PARTY"
	lb.font_size = 64
	lb.pixel_size = 0.01
	lb.modulate = col
	lb.outline_size = 10
	lb.shaded = false
	lb.position = Vector3(edge.x, 3.4, edge.y)
	lb.rotation.y = atan2(sd.x, sd.y)
	add_child(lb)
	# deque de madeira e piscina (borda + água)
	var deck := M.wood()
	_box(Vector3(w - 1.2, 0.08, d - 1.2), Vector3(c.x, fy + 0.04, c.y), deck, false)
	var pw := w * 0.5
	var pd := d * 0.34
	var pc := Vector3(c.x - sd.x * w * 0.12, fy, c.y - sd.y * d * 0.12)
	var rim := M.concrete(Color(0.92, 0.92, 0.9))
	for k in 4:
		var horiz := k < 2
		var sz := Vector3(pw + 0.6, 0.55, 0.3) if horiz else Vector3(0.3, 0.55, pd)
		var off := Vector3(0, 0.27, (pd * 0.5 + 0.15) * (1 if k == 0 else -1)) if horiz else Vector3((pw * 0.5 + 0.15) * (1 if k == 2 else -1), 0.27, 0)
		_box(sz, pc + off, rim, true)
	_box(Vector3(pw, 0.4, pd), pc + Vector3(0, 0.2, 0), M.plain(Color(0.25, 0.6, 0.85), 0.3), false)
	var wt := MeshInstance3D.new()
	var wm := PlaneMesh.new()
	wm.size = Vector2(pw, pd)
	wt.mesh = wm
	wt.material_override = M.water()
	wt.position = pc + Vector3(0, 0.46, 0)
	add_child(wt)
	# espreguiçadeiras, guarda-sóis, churrasqueira, mesa, caixas de som e luzes
	var ppl: Array = []
	var side := Vector3(sd.y, 0, -sd.x) if sd.y != 0 else Vector3(0, 0, 1)
	for k in 4:
		var lp := pc + side * ((k - 1.5) * 2.4) + Vector3(sd.x, 0, sd.y) * (pd * 0.5 + 1.8 if sd.y != 0 else pw * 0.5 + 1.8)
		_box(Vector3(0.7, 0.3, 1.8), lp + Vector3(0, 0.25, 0), M.plain([Color(0.95, 0.95, 0.95), Color(0.95, 0.5, 0.1)][k % 2], 0.6), false)
	for k in 2:
		var up := pc + side * (k * 2.0 - 1.0) * (pw * 0.5 + 1.6) + Vector3(0, 0, 0)
		_box(Vector3(0.08, 2.3, 0.08), up + Vector3(0, 1.15, 0), M.plain(Color(0.8, 0.8, 0.8), 0.4), false)
		_box(Vector3(2.4, 0.12, 2.4), up + Vector3(0, 2.3, 0), M.plain([Color(0.95, 0.2, 0.3), Color(0.2, 0.7, 0.9)][k], 0.7), false)
	var gp := Vector3(c.x + sd.x * (half.x - 2.5) + side.x * (w * 0.3), fy, c.y + sd.y * (half.y - 2.5) + side.z * (d * 0.3))
	if sd.y == 0:
		gp = Vector3(c.x + sd.x * (half.x - 2.5), fy, c.y + d * 0.3)
	_box(Vector3(1.6, 0.9, 0.7), gp + Vector3(0, 0.45, 0), M.plain(Color(0.12, 0.12, 0.13), 0.4, 0.5), true)
	_box(Vector3(1.5, 0.05, 0.6), gp + Vector3(0, 0.93, 0), M.emissive(Color(1.0, 0.35, 0.05), 1.6), false)
	var mesa := gp + Vector3(-sd.x * 3.0, 0, -sd.y * 3.0) + side * 2.0
	_box(Vector3(1.8, 0.08, 0.9), mesa + Vector3(0, 0.75, 0), deck, false)
	_box(Vector3(0.12, 0.72, 0.12), mesa + Vector3(0, 0.37, 0), deck, false)
	for k in 2:
		_box(Vector3(0.6, 1.1, 0.6), Vector3(c.x, fy, c.y) + side * (k * 2.0 - 1.0) * (minf(w, d) * 0.5 - 1.2) + Vector3(0, 0.55, 0), M.plain(Color(0.05, 0.05, 0.06), 0.4), false)
	for k in 10:
		var t := float(k) / 9.0
		var lp2 := Vector3(c.x, fy + 2.6, c.y) + side * lerpf(-0.45, 0.45, t) * maxf(w, d) + Vector3(sd.x, 0, sd.y) * 0.3 * minf(w, d)
		_box(Vector3(0.18, 0.18, 0.18), lp2, M.emissive(Color.from_hsv(t, 0.7, 1.0), 1.8), false)
	var li := OmniLight3D.new()
	li.omni_range = 16.0
	li.light_energy = 0.8
	li.light_color = Color(1.0, 0.8, 0.6)
	li.position = Vector3(c.x, fy + 3.5, c.y)
	add_child(li)
	# gente: rodinhas de conversa no deque, churrasqueiro, gente na beira da piscina
	var grill_man := gp + Vector3(-sd.x * 1.0, 0, -sd.y * 1.0)
	for k in 7:
		var ang := float(k) / 7.0 * TAU
		var r := minf(w, d) * 0.5 - 2.2
		var pp2 := Vector3(c.x + cos(ang) * r * 0.9, fy, c.y + sin(ang) * r * 0.9)
		if pp2.distance_to(pc) < maxf(pw, pd) * 0.5 + 0.8:
			pp2 = pp2 + (pp2 - pc).normalized() * 2.0
		ppl.append([pp2, atan2(c.x - pp2.x, c.y - pp2.z)])
	ppl.append([grill_man, atan2(gp.x - grill_man.x, gp.z - grill_man.z)])
	# saída: porta da escada no terraço
	var ex := Vector3(edge.x - sd.x * 2.6, fy, edge.y - sd.y * 2.6) + side * (maxf(w, d) * 0.3)
	_box(Vector3(1.6, 2.4, 1.6), ex + Vector3(0, 1.2, 0) - Vector3(sd.x, 0, sd.y) * 1.2, M.concrete(Color(0.5, 0.5, 0.52)), true)
	rooftops.append({"top": Vector3(c.x, fy, c.y), "entry": entry, "exit": ex, "people": ppl, "pool": pc + Vector3(0, 0.46, 0), "fee": 50})

const STORE_BLOCKS := {Vector2i(4, 4): "guns", Vector2i(2, 2): "cars", Vector2i(3, 4): "clothes", Vector2i(1, 3): "food", Vector2i(3, 2): "shop24", Vector2i(5, 4): "tuning", Vector2i(5, 2): "shop24b"}
const STORE_NAMES := {"guns": "AMMU★NATION", "cars": "CONCESSIONÁRIA", "clothes": "ROUPAS", "food": "LANCHONETE", "shop24": "LOJA 24H", "shop24b": "LOJA 24H", "tuning": "OFICINA TUNING"}
const STORE_COLS := {"guns": Color(0.95, 0.15, 0.1), "cars": Color(0.2, 0.75, 1.0), "clothes": Color(0.95, 0.45, 0.85), "food": Color(1.0, 0.7, 0.15), "shop24": Color(0.3, 0.9, 0.4), "shop24b": Color(0.3, 0.9, 0.4), "tuning": Color(1.0, 0.55, 0.1)}
const POLICE_BLOCK := Vector2i(4, 2)
const SAFE_BLOCK := Vector2i(2, 3)
const HOSPITAL_BLOCK := Vector2i(1, 4)     # hospital de 3 andares com heliponto
const GANG_BLOCK := Vector2i(5, 6)       # esconderijo da Gangue Rosa (o da Verde fica ao sul, x −90)
var _store_info := {}        # tipo -> {door, counter, clerk, center, x0, x1, z0, z1}
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
	var wall_c: Color = {"guns": Color(0.3, 0.28, 0.26), "clothes": Color(0.9, 0.87, 0.85), "cars": Color(0.88, 0.9, 0.93), "food": Color(0.95, 0.82, 0.55), "shop24": Color(0.9, 0.93, 0.9), "shop24b": Color(0.9, 0.93, 0.9), "tuning": Color(0.35, 0.36, 0.4)}[type]
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
	if type != "tuning":
		_box(Vector3(cx - 1.4 - x0, H - 0.6, 0.06), Vector3((x0 + cx - 1.4) * 0.5, H * 0.5 - 0.1, z0), g2)
		_box(Vector3(x1 - cx - 1.4, H - 0.6, 0.06), Vector3((x1 + cx + 1.4) * 0.5, H * 0.5 - 0.1, z0), g2)
		# porta aberta (vão de 2,8 m): dá para entrar andando, sem tela de carregamento
		_box(Vector3(2.8, H - 3.2, 0.3), Vector3(cx, 3.2 + (H - 3.2) * 0.5, z0), M.plain(Color(0.1, 0.1, 0.11), 0.4, 0.6))
	else:
		_box(Vector3(w, 0.8, 0.3), Vector3(cx, H - 0.25, z0), M.plain(Color(0.1, 0.1, 0.11), 0.4, 0.6))
	var nm := Label3D.new()
	nm.text = STORE_NAMES.get(type, "")
	nm.font_size = 96
	nm.pixel_size = 0.0075
	nm.modulate = STORE_COLS.get(type, Color.WHITE).lightened(0.3)
	nm.outline_size = 10
	nm.shaded = false
	nm.rotation.y = PI
	nm.position = Vector3(cx, H + 0.6, z0 - 0.35)
	add_child(nm)
	var cnt := Vector3(cx, 0.3, z1 - 2.2)
	var clerk := Vector3(cx, 0.3, z1 - 1.2)
	match type:
		"clothes":
			_box(Vector3(3.0, 1.05, 0.8), Vector3(cx + 5.0, 0.65, z1 - 2.2), M.wood(), true)
			cnt = Vector3(cx + 5.0, 0.3, z1 - 2.2)
			clerk = Vector3(cx + 5.0, 0.3, z1 - 1.2)
		"cars":
			_box(Vector3(3.0, 1.0, 1.0), Vector3(cx, 0.6, z1 - 2.0), M.plain(Color(0.2, 0.22, 0.25), 0.4, 0.4), true)
			cnt = Vector3(cx, 0.3, z1 - 2.0)
			clerk = Vector3(cx, 0.3, z1 - 1.0)
		"shop24", "shop24b":
			cnt = Vector3(x1 - 2.5, 0.3, z0 + 2.0)
			clerk = Vector3(x1 - 2.5, 0.3, z0 + 3.0)
		"tuning":
			cnt = Vector3(cx, 0.3, (z0 + z1) * 0.5)
			clerk = Vector3(x0 + 2.0, 0.3, z1 - 2.0)
	_store_info[type] = {"door": Vector3(cx, 0.3, z0 - 1.2), "counter": cnt, "clerk": clerk, "center": Vector3(cx, 0.3, (z0 + z1) * 0.5), "x0": x0, "x1": x1, "z0": z0, "z1": z1}
	# vitrine por dentro (o que se vê da rua)
	match type:
		"guns":
			for xx in [x0 + 0.5, x1 - 0.5]:
				for yy in [1.3, 2.2, 3.1]:
					_box(Vector3(0.35, 0.05, d - 2.0), Vector3(xx, yy, (z0 + z1) * 0.5), M.wood(), false)
					for zz in range(int(z0 + 2), int(z1 - 1), 2):
						_box(Vector3(0.1, 0.08, 0.9), Vector3(xx, yy + 0.1, zz), M.plain(Color(0.08, 0.08, 0.09), 0.4, 0.8), false)
			_box(Vector3(6.0, 1.05, 0.9), Vector3(cx, 0.65, z1 - 2.2), M.plain(Color(0.25, 0.18, 0.12), 0.5), true)
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
			_box(Vector3(w - 3.0, 1.05, 0.9), Vector3(cx, 0.65, z1 - 2.4), M.plain(Color(0.75, 0.15, 0.1), 0.5), true)
			_box(Vector3(4.0, 0.9, 0.7), Vector3(cx, 0.6, z1 - 0.9), M.plain(Color(0.6, 0.62, 0.64), 0.3, 0.8), false)
			_box(Vector3(w - 3.0, 0.9, 0.08), Vector3(cx, 4.0, z1 - 0.25), M.emissive(Color(1.0, 0.75, 0.2), 1.2), false)
			for k in 3:
				var tx := cx - 5.0 + k * 5.0
				_box(Vector3(1.4, 0.06, 1.4), Vector3(tx, 0.95, z0 + 3.0), M.plain(Color(0.9, 0.9, 0.88), 0.4), false)
				_box(Vector3(0.12, 0.8, 0.12), Vector3(tx, 0.55, z0 + 3.0), M.plain(Color(0.3, 0.3, 0.3), 0.4, 0.8), false)
		"shop24", "shop24b":
			# loja de conveniência: prateleiras, geladeiras iluminadas e caixa perto da porta
			for k in 3:
				_box(Vector3(0.6, 1.7, d - 5.0), Vector3(cx - 4.0 + k * 4.0, 1.0, (z0 + z1) * 0.5 + 1.0), M.plain(Color(0.85, 0.85, 0.82), 0.5), false)
				for yy in [0.6, 1.1, 1.6]:
					_box(Vector3(0.7, 0.25, d - 5.4), Vector3(cx - 4.0 + k * 4.0, yy + 0.15, (z0 + z1) * 0.5 + 1.0), M.plain(Color.from_hsv(fmod(k * 0.3 + yy, 1.0), 0.6, 0.85), 0.8), false)
			_box(Vector3(w - 1.0, 2.2, 0.6), Vector3(cx, 1.25, z1 - 0.6), M.emissive(Color(0.75, 0.9, 1.0), 0.8), false)
			_box(Vector3(2.4, 1.0, 0.8), Vector3(x1 - 2.5, 0.65, z0 + 2.0), M.plain(Color(0.2, 0.5, 0.25), 0.5), true)
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
var map_houses: Array = []   # plantas das casas fora da grade (minimapa/mapa)
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
	# faixas pintadas: plano de 2 triângulos (antes caixa de 12)
	_multimesh(_mesh_plane(Vector2(0.15, 3.0)), M.plain(Color(0.85, 0.75, 0.2), 0.6), dash).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_multimesh(_mesh_plane(Vector2(0.6, 2.6)), M.plain(Color(0.86, 0.86, 0.84), 0.6), zebra).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

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
				var side_i := -1
				for p in [Vector3(cx + o, 0.15, cz - r), Vector3(cx + o, 0.15, cz + r), Vector3(cx - r, 0.15, cz + o), Vector3(cx + r, 0.15, cz + o)]:
					side_i += 1
					# nada na frente do portão do esconderijo das gangues
					var gate_blocked := false
					for gq in gang_hq.values():
						if Vector2(p.x - gq.gate_out.x, p.z - gq.gate_out.z).length() < 11.0:
							gate_blocked = true
					if gate_blocked:
						continue
					# otimização: 1 poste por lado (no meio) e 1 árvore a cada 2 lados (antes 3 postes + 2 árvores)
					if s == 0:
						props.append({"type": "lamp", "pos": p, "idx": lamps.size(), "shape": _prop_shape(p, 0.15, 7.0), "alive": true})
						lamps.append(Transform3D(Basis(), p + Vector3(0, 3.5, 0)))
						heads.append(Transform3D(Basis(), p + Vector3(0, 7.0, 0)))
						_lamps.append(p)
					elif s == (1 if (i + j + side_i) % 2 == 0 else -1) and (side_i + i) % 2 == 0:
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
	pmm["head"].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	crown.radial_segments = 8
	crown.rings = 5
	pmm["crown"] = _multimesh(crown, M.leaves(), crowns)
	for i in props.size():
		var k := _pcell(props[i].pos)
		if not _pgrid.has(k):
			_pgrid[k] = []
		_pgrid[k].append(i)

func _mesh_plane(size: Vector2) -> PlaneMesh:
	var p := PlaneMesh.new()
	p.size = size
	p.center_offset = Vector3(0, 0.012, 0)
	return p

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
	if hospital_pos == Vector3.ZERO:
		hospital_pos = Vector3(_center(1), 0.3, _center(4) - BLOCK * 0.5 + 1.6)
	police_pos = Vector3(_center(POLICE_BLOCK.x), 0.3, _center(POLICE_BLOCK.y) - BLOCK * 0.5 + 1.6)
	var white := M.emissive(Color(0.95, 0.95, 0.95), 0.6)
	var red := M.emissive(Color(0.9, 0.08, 0.08), 1.4)
	var blue := M.emissive(Color(0.12, 0.3, 0.9), 1.4)
	var pole := M.plain(Color(0.25, 0.25, 0.27), 0.4, 0.7)
	# lojas: a entrada é a própria loja (sem placa/fachada na calçada e sem tela de carregamento)
	shops = []
	for t in _store_info:
		var si: Dictionary = _store_info[t]
		shops.append({"type": t, "pos": si.door, "counter": si.counter, "clerk": si.clerk, "center": si.center, "name": STORE_NAMES[t], "col": STORE_COLS[t], "box": Rect2(si.x0, si.z0, si.x1 - si.x0, si.z1 - si.z0)})
	for spec in [[police_pos, blue, "P"]]:
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

# ---------------------------------------------------------------- hospital
## Prédio de 3 andares (pé-direito 4 m) ocupando a frente do quarteirão, entrada ao sul:
## térreo = recepção, sala de espera, 2 consultórios; 1º andar = enfermaria com macas e pacientes;
## 2º andar = centro cirúrgico e quartos; telhado = heliponto. Rampas em zigue-zague no lado leste
## ligam os andares (vão nas lajes com guarda-corpo). hospital_pos = recepção (onde você acorda).
var hospital := {}
func _hospital(cx: float, cz: float) -> void:
	var h := (BLOCK - SIDE * 2.0) * 0.5
	var wallm := M.concrete(Color(0.93, 0.94, 0.95))
	var inner_w := M.plain(Color(0.86, 0.9, 0.92), 0.8)
	var floor_m := M.plain(Color(0.78, 0.8, 0.82), 0.35, 0.05)
	var green := M.plain(Color(0.25, 0.6, 0.5), 0.6)
	var red := M.emissive(Color(0.9, 0.08, 0.08), 1.4)
	var glass := M.plain(Color(0.2, 0.3, 0.38), 0.05, 0.6)
	var bedm := M.plain(Color(0.92, 0.94, 0.96), 0.5)
	var metal := M.plain(Color(0.6, 0.62, 0.65), 0.3, 0.8)
	var fz := cz - h
	var bz := cz + h - 6.0
	var x0 := cx - h
	var x1 := cx + h
	var H := 4.0
	var T := 0.3
	# poço das rampas (leste): x de sx0 a x1, z de sa a sa+10
	var sx0 := x1 - 7.2
	var smid := x1 - 3.75
	var sa := fz + 8.0
	var sb := sa + 10.0
	# lajes (piso do 1º, 2º andar e telhado) com vão no poço das rampas
	for f in 4:
		var y := f * H + (0.2 if f == 0 else 0.0)
		if f == 0:
			_box(Vector3(2.0 * h, 0.06, bz - fz), Vector3(cx, 0.18, (fz + bz) * 0.5), floor_m, false)
			continue
		_box(Vector3(sx0 - x0, T, bz - fz), Vector3((x0 + sx0) * 0.5, y, (fz + bz) * 0.5), floor_m if f < 3 else M.concrete(Color(0.5, 0.51, 0.52)), true)
		_box(Vector3(x1 - sx0, T, sa - fz), Vector3((sx0 + x1) * 0.5, y, (fz + sa) * 0.5), floor_m, true)
		_box(Vector3(x1 - sx0, T, bz - sb), Vector3((sx0 + x1) * 0.5, y, (sb + bz) * 0.5), floor_m, true)
		# guarda-corpo em volta do vão (sobra a entrada/saída das rampas)
		_box(Vector3(0.12, 1.0, sb - sa), Vector3(sx0, y + 0.65, (sa + sb) * 0.5), metal, true)
		_box(Vector3(0.12, 1.0 if f < 3 else 1.0, sb - sa - 3.0), Vector3(smid, y + 0.65, (sa + sb) * 0.5 + (1.5 if f % 2 == 1 else -1.5)), metal, true)
	# rampas: térreo→1º (faixa leste, sobe para o norte), 1º→2º (faixa oeste, sobe para o sul),
	# 2º→telhado (faixa leste, sobe para o norte)
	var lane_e := (smid + x1) * 0.5
	var lane_w := (sx0 + smid) * 0.5
	for r in [[lane_e, 0.2, H, true], [lane_w, H, 2.0 * H, false], [lane_e, 2.0 * H, 3.0 * H, true]]:
		var rise: float = r[2] - r[1]
		var ang := atan2(rise, sb - sa)
		var ln := sqrt(rise * rise + (sb - sa) * (sb - sa))
		var up: bool = r[3]
		var b := Basis(Vector3.RIGHT, -ang if up else ang)
		_boxr(Vector3(3.2, 0.25, ln), Transform3D(b, Vector3(r[0], (r[1] + r[2]) * 0.5, (sa + sb) * 0.5)), M.concrete(Color(0.7, 0.71, 0.72)), true)
	# paredes externas por andar (frente com janelas; porta de 3,2 m no térreo)
	for f in 3:
		var y0 := f * H
		var yc := y0 + H * 0.5 + 0.15
		if f == 0:
			for seg in [[x0, cx - 1.6], [cx + 1.6, x1]]:
				var w: float = seg[1] - seg[0]
				_box(Vector3(w, H, T), Vector3((seg[0] + seg[1]) * 0.5, yc, fz), wallm, true)
				_box(Vector3(w - 2.0, 1.6, 0.06), Vector3((seg[0] + seg[1]) * 0.5, y0 + 2.2, fz - 0.17), glass, false)
			_box(Vector3(3.2, H - 3.0, T), Vector3(cx, y0 + H - 0.35, fz), wallm, true)
		else:
			_box(Vector3(2.0 * h, H, T), Vector3(cx, yc, fz), wallm, true)
			for k in 6:
				_box(Vector3(4.0, 1.6, 0.06), Vector3(x0 + 4.0 + k * 7.0, y0 + 2.3, fz - 0.17), glass, false)
		_box(Vector3(2.0 * h, H, T), Vector3(cx, yc, bz), wallm, true)
		_box(Vector3(T, H, bz - fz), Vector3(x0, yc, (fz + bz) * 0.5), wallm, true)
		_box(Vector3(T, H, bz - fz), Vector3(x1, yc, (fz + bz) * 0.5), wallm, true)
		_box(Vector3(2.0 * h + 0.2, 0.35, 0.35), Vector3(cx, y0 + H, fz - 0.05), green, false)
		# luzes de teto
		for xx in [cx - 14.0, cx - 5.0, cx + 5.0]:
			for zz in [fz + 5.0, fz + 15.0, fz + 25.0]:
				_box(Vector3(1.4, 0.05, 0.5), Vector3(xx, y0 + H - 0.05, zz), M.emissive(Color(1, 0.98, 0.95), 2.0), false)
	var roof_y := 3.0 * H
	# platibanda, letreiro, cruz vermelha e heliponto
	for seg in [[Vector3(2.0 * h, 1.0, 0.3), Vector3(cx, roof_y + 0.65, fz)], [Vector3(2.0 * h, 1.0, 0.3), Vector3(cx, roof_y + 0.65, bz)],
			[Vector3(0.3, 1.0, bz - fz), Vector3(x0, roof_y + 0.65, (fz + bz) * 0.5)], [Vector3(0.3, 1.0, bz - fz), Vector3(x1, roof_y + 0.65, (fz + bz) * 0.5)]]:
		_box(seg[0], seg[1], wallm, true)
	var hp := Vector3(cx - 6.0, roof_y + 0.2, (fz + bz) * 0.5 + 2.0)
	_box(Vector3(14.0, 0.06, 14.0), hp, M.concrete(Color(0.2, 0.42, 0.3)), false)
	for q in [[Vector3(1.0, 0.03, 6.0), Vector3(-2.0, 0.04, 0)], [Vector3(1.0, 0.03, 6.0), Vector3(2.0, 0.04, 0)], [Vector3(3.0, 0.03, 1.0), Vector3(0, 0.04, 0)]]:
		_box(q[0], hp + q[1], M.plain(Color(0.96, 0.96, 0.96), 0.6), false)
	_box(Vector3(5.0, 1.4, 0.3), Vector3(cx + 4.0, roof_y + 2.1, fz - 0.2), red, false)
	_box(Vector3(1.4, 5.0, 0.3), Vector3(cx + 4.0, roof_y + 2.1, fz - 0.2), red, false)
	var lb := Label3D.new()
	lb.text = "HOSPITAL"
	lb.font_size = 150
	lb.pixel_size = 0.01
	lb.modulate = Color(0.95, 0.15, 0.15)
	lb.outline_size = 14
	lb.shaded = false
	lb.rotation.y = PI
	lb.position = Vector3(cx - 9.0, roof_y + 1.6, fz - 0.4)
	add_child(lb)
	# marquise e rampa de ambulância na frente
	_box(Vector3(12.0, 0.3, 4.0), Vector3(cx, H - 0.6, fz - 2.0), green, false)
	_box(Vector3(6.0, 0.15, 2.0), Vector3(cx, 0.22, fz - 1.0), M.concrete(Color(0.88, 0.88, 0.88)), false)
	# ---- térreo: recepção, espera, consultórios (oeste)
	_box(Vector3(5.0, 1.1, 0.8), Vector3(cx + 2.0, 0.7, fz + 6.0), M.plain(Color(0.9, 0.9, 0.92), 0.4), true)
	_box(Vector3(5.0, 0.1, 1.0), Vector3(cx + 2.0, 1.3, fz + 6.0), green, false)
	for k in 4:
		_box(Vector3(2.6, 0.45, 0.6), Vector3(cx - 3.0 + (k % 2) * 3.2, 0.42, fz + 2.5 + float(k / 2) * 1.6), M.plain(Color(0.2, 0.45, 0.6), 0.7), true)
	var cons := x0 + 12.0
	_box(Vector3(0.2, H, bz - fz - 6.0), Vector3(cons, H * 0.5 + 0.15, fz + 6.0 + (bz - fz - 6.0) * 0.5), inner_w, true)
	for zz in [fz + 6.0, fz + 16.0]:
		_box(Vector3(cons - x0 - 2.0, H, 0.2), Vector3((x0 + cons) * 0.5 - 1.0, H * 0.5 + 0.15, zz), inner_w, true)
	for k in 2:
		var rz: float = fz + 11.0 + k * 10.0
		_box(Vector3(2.0, 0.6, 0.9), Vector3(x0 + 3.0, 0.5, rz), bedm, true)          # maca de exame
		_box(Vector3(1.6, 0.08, 0.8), Vector3(x0 + 8.0, 0.95, rz), M.wood(), true)     # mesa do médico
		_box(Vector3(0.6, 0.45, 0.05), Vector3(x0 + 8.0, 1.25, rz + 0.25), M.emissive(Color(0.5, 0.8, 1.0), 0.8), false)
		var lc := Label3D.new()
		lc.text = "CONSULTÓRIO %d" % (k + 1)
		lc.font_size = 40
		lc.pixel_size = 0.006
		lc.shaded = false
		lc.position = Vector3(cons + 0.15, 3.0, rz)
		lc.rotation.y = PI * 0.5
		add_child(lc)
	# ---- 1º andar: enfermaria (macas em fileira) e 2º andar: centro cirúrgico + quartos
	var beds: Array = []
	for k in 6:
		var bx := x0 + 4.0 + k * 4.4
		for row in [fz + 4.0, fz + 14.0]:
			_box(Vector3(1.0, 0.5, 2.1), Vector3(bx, H + 0.7, row), bedm, true)
			_box(Vector3(1.0, 0.15, 0.4), Vector3(bx, H + 0.98, row - 0.85), M.plain(Color(0.95, 0.95, 0.95), 0.9), false)
			_box(Vector3(0.05, 1.6, 0.05), Vector3(bx + 0.6, H + 1.1, row - 1.0), metal, false)    # suporte de soro
			_box(Vector3(0.2, 0.3, 0.08), Vector3(bx + 0.6, H + 1.85, row - 1.0), M.plain(Color(0.8, 0.9, 1.0), 0.2), false)
			beds.append(Vector3(bx, H + 0.95, row))
		_box(Vector3(0.1, 2.0, 3.2), Vector3(bx + 2.2, H + 1.15, fz + 4.0), M.plain(Color(0.5, 0.75, 0.8), 0.8), false)   # cortinas
	var y2 := 2.0 * H
	_box(Vector3(0.2, H, 16.0), Vector3(cx - 4.0, y2 + H * 0.5 + 0.15, fz + 8.0), inner_w, true)
	_box(Vector3(1.0, 0.9, 2.2), Vector3(x0 + 8.0, y2 + 0.6, fz + 8.0), metal, true)         # mesa de cirurgia
	_box(Vector3(1.2, 0.1, 1.2), Vector3(x0 + 8.0, y2 + H - 0.6, fz + 8.0), M.emissive(Color(1, 1, 0.95), 4.0), false)
	_box(Vector3(0.6, 1.4, 0.6), Vector3(x0 + 10.0, y2 + 0.85, fz + 6.0), M.plain(Color(0.3, 0.35, 0.4), 0.4, 0.6), true)
	var lcc := Label3D.new()
	lcc.text = "CENTRO CIRÚRGICO"
	lcc.font_size = 48
	lcc.pixel_size = 0.006
	lcc.shaded = false
	lcc.position = Vector3(cx - 4.15, y2 + 3.0, fz + 12.0)
	lcc.rotation.y = -PI * 0.5
	add_child(lcc)
	for k in 3:
		var rx := cx + 1.0 + k * 4.0
		_box(Vector3(1.0, 0.5, 2.1), Vector3(rx, y2 + 0.7, fz + 24.0), bedm, true)
		beds.append(Vector3(rx, y2 + 0.95, fz + 24.0))
	# sinal de andar perto das rampas
	for f in 3:
		var lf := Label3D.new()
		lf.text = ["TÉRREO", "1º ANDAR · ENFERMARIA", "2º ANDAR · CIRURGIA"][f]
		lf.font_size = 40
		lf.pixel_size = 0.006
		lf.shaded = false
		lf.position = Vector3(sx0 - 0.1, f * H + 3.0, sa - 1.0)
		lf.rotation.y = PI * 0.5
		add_child(lf)
	var li := OmniLight3D.new()
	li.omni_range = 18.0
	li.light_energy = 1.0
	li.position = Vector3(cx, H - 0.6, fz + 10.0)
	add_child(li)
	# área de ambulâncias (atrás)
	_box(Vector3(2.0 * h, 0.05, cz + h - bz), Vector3(cx, 0.18, (bz + cz + h) * 0.5), M.asphalt(), false)
	hospital_pos = Vector3(cx + 2.0, 0.3, fz + 3.5)
	hospital = {"beds": beds, "reception": Vector3(cx + 2.0, 0.2, fz + 7.2), "heli": hp + Vector3(0, 0.3, 0),
		"staff": [Vector3(x0 + 7.0, 0.2, fz + 12.0), Vector3(x0 + 7.0, 0.2, fz + 22.0), Vector3(x0 + 10.0, H + 0.2, fz + 9.0), Vector3(cx + 6.0, H + 0.2, fz + 9.0), Vector3(x0 + 9.0, y2 + 0.2, fz + 9.6)],
		"ambulances": [[Vector3(cx - 10.0, 0.7, bz + 3.0), PI * 0.5], [Vector3(cx + 10.0, 0.7, bz + 3.0), PI * 0.5]]}

# ---------------------------------------------------------------- ponto de encontro da corrida
## Estacionamento ao norte (longe do hospital), com carros tunados e gente conversando
var race_lot := {}
func _race_lot() -> void:
	var c := Vector3(-160.0, 0.0, 262.0)
	_box(Vector3(60.0, 0.08, 40.0), c + Vector3(0, 0.04, 0), M.asphalt(), true)
	for k in 9:
		_box(Vector3(0.15, 0.02, 5.0), c + Vector3(-24.0 + k * 6.0, 0.1, -14.0), M.plain(Color(0.95, 0.95, 0.9), 0.6), false)
		_box(Vector3(0.15, 0.02, 5.0), c + Vector3(-24.0 + k * 6.0, 0.1, 14.0), M.plain(Color(0.95, 0.95, 0.9), 0.6), false)
	for k in 2:
		var tp := c + Vector3(-28.0 + k * 56.0, 0, 0)
		_box(Vector3(0.3, 8.0, 0.3), tp + Vector3(0, 4.0, 0), M.plain(Color(0.2, 0.2, 0.22), 0.4, 0.7), true)
		_box(Vector3(2.4, 0.4, 0.8), tp + Vector3(0, 8.0, 0), M.emissive(Color(1, 0.95, 0.8), 3.0), false)
	# faixa de largada pintada e bandeira xadrez
	for k in 12:
		_box(Vector3(1.0, 0.02, 1.0), c + Vector3(-5.5 + k, 0.1, 0), M.plain(Color(0.05, 0.05, 0.05) if k % 2 == 0 else Color(0.95, 0.95, 0.95), 0.6), false)
	_box(Vector3(0.15, 5.0, 0.15), c + Vector3(-7.0, 2.5, 0), M.plain(Color(0.3, 0.3, 0.32), 0.4), true)
	var lb := Label3D.new()
	lb.text = "RACHA · PONTO DE ENCONTRO"
	lb.font_size = 90
	lb.pixel_size = 0.01
	lb.modulate = Color(1, 0.75, 0.1)
	lb.outline_size = 12
	lb.shaded = false
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.position = c + Vector3(0, 6.0, -19.0)
	add_child(lb)
	race_lot = {"giver": c + Vector3(0, 0.15, -10.0), "cars": [[c + Vector3(-18, 0.8, 14), PI], [c + Vector3(-12, 0.8, 14), PI], [c + Vector3(12, 0.8, 14), PI], [c + Vector3(18, 0.8, 14), PI], [c + Vector3(-18, 0.8, -14), 0.0]],
		"people": [[c + Vector3(-15, 0.1, 9), 0.6], [c + Vector3(-14, 0.1, 10.2), PI + 0.6], [c + Vector3(6, 0.1, 9), -0.4], [c + Vector3(7.2, 0.1, 9.8), PI - 0.4], [c + Vector3(16, 0.1, 9), 0.2], [c + Vector3(-8, 0.1, -9), 1.4], [c + Vector3(-6.8, 0.1, -8.6), -1.7]],
		"rent": c + Vector3(3.0, 0.8, -4.0)}

# ---------------------------------------------------------------- utilidades com rotação
func _boxr(size: Vector3, xf: Transform3D, mat: Material, collide := true) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	_batch_add(bm, xf, mat)
	if collide:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.transform = xf
		body.add_child(cs)

## caixa em coordenadas locais de uma "base" (origem + giro em y)
func _lb(base: Transform3D, size: Vector3, lp: Vector3, mat: Material, collide := true) -> void:
	_boxr(size, base * Transform3D(Basis(), lp), mat, collide)

## telhado de duas águas (duas placas inclinadas) em coordenadas locais
func _roof(base: Transform3D, w: float, d: float, y: float, mat: Material, pitch := 0.5) -> void:
	var half := d * 0.5 / cos(pitch) + 0.4
	for sg in [-1.0, 1.0]:
		var b := Basis(Vector3.RIGHT, sg * pitch)
		var lp := Vector3(0, y + sin(pitch) * d * 0.25, sg * d * 0.25)
		_boxr(Vector3(w + 0.8, 0.18, half), base * Transform3D(b, lp), mat, true)
	# oitões (triângulos aproximados por 3 degraus)
	for sx in [-1.0, 1.0]:
		for k in 3:
			var hh := sin(pitch) * d * 0.5 * (1.0 - k / 3.0)
			_lb(base, Vector3(0.2, hh / 3.0 + 0.05, d * (1.0 - k / 3.0)), Vector3(sx * w * 0.5, y + hh / 3.0 * (k + 0.5) - 0.02, 0), mat, false)

# ---------------------------------------------------------------- casas (rua só de casas)
const HOUSE_COLS := [Color(0.92, 0.86, 0.72), Color(0.75, 0.82, 0.88), Color(0.9, 0.75, 0.7), Color(0.8, 0.88, 0.75), Color(0.95, 0.93, 0.88), Color(0.85, 0.7, 0.5)]
func _houses_block(cx: float, cz: float, inner: float) -> void:
	var h := inner * 0.5
	_box(Vector3(inner, 0.05, inner), Vector3(cx, 0.17, cz), M.grass(), false)
	for a in 2:
		for b in 2:
			var lc := Vector3(cx + (a - 0.5) * h, 0.15, cz + (b - 0.5) * h)
			var yaw := 0.0 if b == 1 else PI          # frente para a rua mais próxima (norte/sul)
			_house(Transform3D(Basis(Vector3.UP, yaw), lc), h, rng.randf() < 0.3)

## casa decorativa num lote quadrado de lado 'L' (frente = +z local)
func _house(base: Transform3D, L: float, pool: bool) -> void:
	var wallm := M.plain(HOUSE_COLS[rng.randi() % HOUSE_COLS.size()], 0.85)
	var roofm := M.plain([Color(0.55, 0.22, 0.15), Color(0.3, 0.3, 0.33), Color(0.45, 0.3, 0.2)][rng.randi() % 3], 0.7)
	var w := rng.randf_range(8.0, 11.0)
	var d := rng.randf_range(7.0, 8.5)
	var H := 3.0
	var hz := -1.5
	_lb(base, Vector3(w, H, d), Vector3(0, H * 0.5 + 0.02, hz), wallm, true)
	_roof(base, w, d, H + 0.05, roofm)
	# planta da casa para o minimapa/mapa (4 cantos no mundo)
	var corners := PackedVector2Array()
	for cc in [Vector3(-w * 0.5, 0, hz - d * 0.5), Vector3(w * 0.5, 0, hz - d * 0.5), Vector3(w * 0.5, 0, hz + d * 0.5), Vector3(-w * 0.5, 0, hz + d * 0.5)]:
		var wp: Vector3 = base * cc
		corners.append(Vector2(wp.x, wp.z))
	map_houses.append(corners)
	# porta, janelas, degrau e chaminé
	_lb(base, Vector3(1.1, 2.1, 0.08), Vector3(-w * 0.2, 1.07, hz + d * 0.5 + 0.03), M.wood(), false)
	for x in [w * 0.15, w * 0.35, -w * 0.4]:
		_lb(base, Vector3(1.2, 1.0, 0.07), Vector3(x, 1.6, hz + d * 0.5 + 0.03), M.plain(Color(0.2, 0.3, 0.38), 0.05, 0.6), false)
		_lb(base, Vector3(1.4, 0.12, 0.15), Vector3(x, 1.03, hz + d * 0.5 + 0.07), M.plain(Color(0.95, 0.95, 0.95), 0.6), false)
	_lb(base, Vector3(1.6, 0.18, 1.0), Vector3(-w * 0.2, 0.09, hz + d * 0.5 + 0.5), M.concrete(Color(0.7, 0.7, 0.7)), false)
	_lb(base, Vector3(0.7, 1.6, 0.7), Vector3(w * 0.3, H + 1.9, hz - d * 0.15), M.plain(Color(0.45, 0.25, 0.18), 0.8), false)
	# cerca baixa com portão na frente
	var half := L * 0.5 - 0.6
	var fence := M.plain(Color(0.95, 0.95, 0.95), 0.6)
	_lb(base, Vector3(0.12, 0.9, 2.0 * half), Vector3(-half, 0.45, 0), fence, true)
	_lb(base, Vector3(0.12, 0.9, 2.0 * half), Vector3(half, 0.45, 0), fence, true)
	_lb(base, Vector3(2.0 * half, 0.9, 0.12), Vector3(0, 0.45, -half), fence, true)
	_lb(base, Vector3(half - 2.0, 0.9, 0.12), Vector3(-(half + 2.0) * 0.5 - 0.0, 0.45, half), fence, true)
	_lb(base, Vector3(half - 2.0, 0.9, 0.12), Vector3((half + 2.0) * 0.5, 0.45, half), fence, true)
	_lb(base, Vector3(2.4, 0.04, half - hz - d * 0.5), Vector3(-w * 0.2, 0.06, (half + hz + d * 0.5) * 0.5), M.concrete(Color(0.65, 0.63, 0.6)), false)
	if pool:
		_lb(base, Vector3(4.0, 0.08, 2.4), Vector3(w * 0.25, 0.08, -half + 2.0), M.plain(Color(0.2, 0.6, 0.85), 0.05, 0.2), false)
		_lb(base, Vector3(4.6, 0.12, 3.0), Vector3(w * 0.25, 0.04, -half + 2.0), M.concrete(Color(0.85, 0.85, 0.82)), false)
	# carro na garagem aberta ao lado (vaga)
	_house_spots.append(base * Vector3(w * 0.5 + 2.2, 0.6, hz + 1.0))

var _house_spots: Array = []      # vagas ao lado das casas (o main estaciona carros/bikes ali)

# ---------------------------------------------------------------- obras
func _construction(cx: float, cz: float, inner: float) -> void:
	var h := inner * 0.5
	var dirt := M.plain(Color(0.45, 0.36, 0.26), 0.95)
	var conc := M.concrete(Color(0.68, 0.68, 0.66))
	var steel := M.plain(Color(0.85, 0.6, 0.1), 0.5, 0.6)
	var fence := M.plain(Color(0.9, 0.85, 0.2), 0.7)
	_box(Vector3(inner, 0.06, inner), Vector3(cx, 0.18, cz), dirt, false)
	# tapume com portão (sul)
	_box(Vector3(inner, 2.2, 0.15), Vector3(cx, 1.25, cz + h), fence, true)
	_box(Vector3(0.15, 2.2, inner), Vector3(cx - h, 1.25, cz), fence, true)
	_box(Vector3(0.15, 2.2, inner), Vector3(cx + h, 1.25, cz), fence, true)
	_box(Vector3(h - 4.0, 2.2, 0.15), Vector3(cx - h * 0.5 - 2.0, 1.25, cz - h), fence, true)
	_box(Vector3(h - 4.0, 2.2, 0.15), Vector3(cx + h * 0.5 + 2.0, 1.25, cz - h), fence, true)
	# esqueleto de concreto: 5 lajes + pilares (dá para escalar pelos andaimes)
	var bw := 22.0
	var bd := 16.0
	var bc := Vector3(cx - 4.0, 0, cz + 6.0)
	for f in 5:
		var y := 0.2 + f * 3.6
		if f > 0:
			_box(Vector3(bw, 0.35, bd), bc + Vector3(0, y, 0), conc, true)
		if f < 4:
			for ix in 4:
				for iz in 3:
					_box(Vector3(0.45, 3.6, 0.45), bc + Vector3(-bw * 0.5 + 0.5 + ix * (bw - 1.0) / 3.0, y + 1.8, -bd * 0.5 + 0.5 + iz * (bd - 1.0) / 2.0), conc, true)
	# andaime na frente com degraus (subida)
	for f in 4:
		_box(Vector3(bw, 0.1, 1.2), bc + Vector3(0, 3.6 + f * 3.6 - 0.1, -bd * 0.5 - 0.8), M.wood(), true)
		for k in 6:
			_box(Vector3(0.6, 0.15, 1.0), bc + Vector3(bw * 0.5 - 1.0 - k * 0.6, 0.6 + f * 3.6 + k * 0.6, -bd * 0.5 - 2.2), M.wood(), true)
		for ix in 6:
			_box(Vector3(0.06, 3.6, 0.06), bc + Vector3(-bw * 0.5 + ix * bw / 5.0, 1.8 + f * 3.6, -bd * 0.5 - 1.4), steel, false)
	# guindaste
	var gc := Vector3(cx + 13.0, 0, cz - 10.0)
	_box(Vector3(2.0, 1.0, 2.0), gc + Vector3(0, 0.5, 0), conc, true)
	_box(Vector3(1.3, 34.0, 1.3), gc + Vector3(0, 17.5, 0), steel, true)
	_box(Vector3(28.0, 1.0, 1.0), gc + Vector3(-8.0, 34.5, 0), steel, false)
	_box(Vector3(3.0, 2.0, 2.0), gc + Vector3(5.0, 33.5, 0), conc, false)
	_box(Vector3(2.2, 2.0, 2.0), gc + Vector3(0, 33.0, 0), M.plain(Color(0.25, 0.3, 0.35), 0.4), false)
	_box(Vector3(0.05, 18.0, 0.05), gc + Vector3(-18.0, 25.0, 0), M.plain(Color(0.1, 0.1, 0.1), 0.5), false)
	_box(Vector3(2.5, 1.0, 1.2), gc + Vector3(-18.0, 15.5, 0), M.plain(Color(0.55, 0.3, 0.15), 0.8), false)
	# pilhas de material, tubos e caçamba
	for k in 4:
		_box(Vector3(2.4, 0.8, 1.2), Vector3(cx - 15.0, 0.6 + k * 0.8, cz - 14.0), M.plain(Color(0.7, 0.3, 0.2), 0.9), true)
	for k in 5:
		_box(Vector3(6.0, 0.4, 0.4), Vector3(cx + 2.0, 0.4 + (k % 3) * 0.4, cz - 15.0 + k * 0.45), M.plain(Color(0.4, 0.42, 0.45), 0.4, 0.8), true)
	_box(Vector3(5.0, 1.6, 2.4), Vector3(cx + 14.0, 0.95, cz + 14.0), M.plain(Color(0.9, 0.5, 0.1), 0.6), true)
	_house_spots.append(Vector3(cx - 8.0, 0.6, cz - 13.0))

# ---------------------------------------------------------------- galpões e contêineres
func _warehouses(cx: float, cz: float, inner: float) -> void:
	var h := inner * 0.5
	_box(Vector3(inner, 0.06, inner), Vector3(cx, 0.18, cz), M.concrete(Color(0.45, 0.45, 0.46)), false)
	var shed := M.plain(Color.from_hsv(rng.randf_range(0.0, 0.7), 0.25, 0.6), 0.7, 0.3)
	_box(Vector3(inner - 4.0, 8.0, h), Vector3(cx, 4.2, cz + h * 0.5), shed, true)
	_box(Vector3(inner - 3.0, 0.5, h + 1.0), Vector3(cx, 8.45, cz + h * 0.5), M.plain(Color(0.3, 0.3, 0.32), 0.5, 0.6), true)
	for k in 3:
		_box(Vector3(5.0, 5.0, 0.12), Vector3(cx - 12.0 + k * 12.0, 2.7, cz - 0.05), M.plain(Color(0.35, 0.37, 0.4), 0.4, 0.7), false)
	var ccols := [Color(0.75, 0.15, 0.1), Color(0.1, 0.35, 0.65), Color(0.2, 0.55, 0.25), Color(0.85, 0.6, 0.1), Color(0.5, 0.5, 0.52)]
	for k in 6:
		var lvl := k / 3
		_box(Vector3(6.0, 2.6, 2.45), Vector3(cx - 12.0 + (k % 3) * 7.0, 1.5 + lvl * 2.6, cz - h + 5.0 + lvl * 0.3), M.plain(ccols[rng.randi() % ccols.size()], 0.6, 0.3), true)
	_house_spots.append(Vector3(cx + 12.0, 0.6, cz - h + 6.0))

# ---------------------------------------------------------------- esconderijo das gangues
## Complexo murado com portão (frente = +z local), pátio com sacos de areia/barris/contêiner e um
## bunker de concreto: sala da frente (drogas na mesa, caixas de armas) e cofre na sala dos fundos.
## Pontos para o gangs.gd: cofre, drogas, armas, esconderijos da senha, postos dos guardas, portão.
var gang_hq := {}
func _gang_hq(cx: float, cz: float, inner: float, g: String, yaw: float) -> void:
	var base := Transform3D(Basis(Vector3.UP, yaw), Vector3(cx, 0.15, cz))
	var h := inner * 0.5
	var gcol: Color = Color(0.15, 0.75, 0.3) if g == "g" else Color(0.95, 0.35, 0.7)
	var wallm := M.concrete(Color(0.55, 0.54, 0.52))
	var dark := M.concrete(Color(0.38, 0.38, 0.4))
	var stripe := M.plain(gcol.darkened(0.15), 0.8)
	var steel := M.plain(Color(0.3, 0.31, 0.33), 0.45, 0.7)
	_lb(base, Vector3(inner, 0.06, inner), Vector3(0, 0.03, 0), M.concrete(Color(0.42, 0.42, 0.43)), false)
	# muro de 2,8 m com portão de 7 m na frente, faixa na cor da gangue e arame no topo
	var WH := 2.8
	_lb(base, Vector3(inner, WH, 0.3), Vector3(0, WH * 0.5, -h), wallm, true)
	for sx in [-1.0, 1.0]:
		_lb(base, Vector3(0.3, WH, inner), Vector3(sx * h, WH * 0.5, 0), wallm, true)
		if sx < 0.0:
			_lb(base, Vector3(h - 3.5, WH, 0.3), Vector3(sx * (h + 3.5) * 0.5, WH * 0.5, h), wallm, true)
		else:
			# do lado direito a frente tem a entrada da viela (x de h−5 a h)
			_lb(base, Vector3(h - 8.5, WH, 0.3), Vector3((3.5 + h - 5.0) * 0.5, WH * 0.5, h), wallm, true)
		_lb(base, Vector3(0.6, WH + 0.6, 0.6), Vector3(sx * 3.8, (WH + 0.6) * 0.5, h), dark, true)
	# viela (canto da frente, lado direito): corredor de 5 m entre o muro de fora e um muro interno,
	# fechado no fundo; lixeiras, caixotes, grafite e luz fraca. É ali que a gangue passa os serviços.
	var al_h := 4.2
	_lb(base, Vector3(0.3, al_h, 14.0), Vector3(h - 5.0, al_h * 0.5, h - 7.0), dark, true)
	_lb(base, Vector3(5.0, al_h, 0.3), Vector3(h - 2.5, al_h * 0.5, h - 14.0), dark, true)
	_lb(base, Vector3(0.3, al_h - WH, 14.0), Vector3(h, WH + (al_h - WH) * 0.5, h - 7.0), dark, true)
	_lb(base, Vector3(5.0, 0.05, 14.0), Vector3(h - 2.5, 0.06, h - 7.0), M.plain(Color(0.2, 0.19, 0.18), 0.95), false)
	_lb(base, Vector3(1.6, 1.2, 1.0), Vector3(h - 1.0, 0.6, h - 12.5), M.plain(Color(0.15, 0.35, 0.18), 0.6, 0.3), true)
	_lb(base, Vector3(1.2, 0.8, 1.2), Vector3(h - 4.0, 0.4, h - 11.0), M.wood(), true)
	_lb(base, Vector3(0.05, 1.8, 4.0), Vector3(h - 4.83, 1.6, h - 8.0), M.emissive(gcol, 0.5), false)
	_lb(base, Vector3(0.05, 1.2, 3.0), Vector3(h - 0.18, 1.5, h - 5.0), M.emissive(gcol.lightened(0.3), 0.4), false)
	_lb(base, Vector3(0.4, 0.1, 0.4), Vector3(h - 2.5, al_h - 0.2, h - 9.0), M.emissive(Color(1.0, 0.75, 0.4), 1.5), false)
	for side in [[Vector3(inner, 0.35, 0.34), Vector3(0, 1.6, -h)], [Vector3(0.34, 0.35, inner), Vector3(-h, 1.6, 0)], [Vector3(0.34, 0.35, inner), Vector3(h, 1.6, 0)]]:
		_lb(base, side[0], side[1], stripe, false)
		_lb(base, side[0] * Vector3(1, 0.3, 1), side[1] + Vector3(0, WH - 1.45, 0), M.plain(Color(0.12, 0.12, 0.12), 0.5, 0.5), false)
	# bunker
	var bw := 15.0
	var bd := 11.0
	var bz := -5.0
	var H := 3.6
	var t := 0.35
	var fz := bz + bd * 0.5        # parede da frente
	var kz := bz - bd * 0.5        # parede do fundo
	var dx := -3.0                 # porta da frente
	_lb(base, Vector3(bw, H, t), Vector3(0, H * 0.5, kz), dark, true)
	for sx in [-1.0, 1.0]:
		_lb(base, Vector3(t, H, bd), Vector3(sx * bw * 0.5, H * 0.5, bz), dark, true)
	_lb(base, Vector3(dx - 0.9 + bw * 0.5, H, t), Vector3((-bw * 0.5 + dx - 0.9) * 0.5, H * 0.5, fz), dark, true)
	_lb(base, Vector3(bw * 0.5 - dx - 0.9, H, t), Vector3((bw * 0.5 + dx + 0.9) * 0.5, H * 0.5, fz), dark, true)
	_lb(base, Vector3(1.8, H - 2.3, t), Vector3(dx, H - (H - 2.3) * 0.5, fz), dark, true)
	_lb(base, Vector3(bw + 0.6, 0.3, bd + 0.6), Vector3(0, H + 0.15, bz), dark, true)
	_lb(base, Vector3(bw - 0.2, 0.05, bd - 0.2), Vector3(0, 0.08, bz), M.plain(Color(0.3, 0.28, 0.26), 0.9), false)
	# batente de aço, fendas de janela gradeadas, faixa e grafite
	for sx in [-1.0, 1.0]:
		_lb(base, Vector3(0.12, 2.3, 0.45), Vector3(dx + sx * 0.95, 1.15, fz), steel, false)
	for wx in [-6.0, 1.0, 4.5]:
		_lb(base, Vector3(1.6, 0.35, 0.4), Vector3(wx, 2.4, fz), M.plain(Color(0.05, 0.05, 0.06), 0.4), false)
	_lb(base, Vector3(bw + 0.1, 0.4, bd + 0.1), Vector3(0, H - 0.4, bz), stripe, false)
	_lb(base, Vector3(0.05, 1.6, 4.0), Vector3(bw * 0.5 + 0.2, 1.4, bz - 1.0), M.emissive(gcol, 0.4), false)
	# divisória: sala da frente × sala do cofre (passagem em x = +4)
	_lb(base, Vector3(10.7, H, 0.25), Vector3(-2.15, H * 0.5, bz), dark, true)
	_lb(base, Vector3(2.7, H, 0.25), Vector3(6.15, H * 0.5, bz), dark, true)
	_lb(base, Vector3(1.6, H - 2.3, 0.25), Vector3(4.0, H - (H - 2.3) * 0.5, bz), dark, true)
	# sala da frente: mesa (drogas), sofá, TV, lâmpadas; sala do cofre: prateleiras e lâmpada
	_lb(base, Vector3(2.6, 0.08, 1.2), Vector3(-4.5, 0.9, -2.4), M.wood(), true)
	for lx in [-5.6, -3.4]:
		for lz in [-2.9, -1.9]:
			_lb(base, Vector3(0.08, 0.86, 0.08), Vector3(lx, 0.43, lz), steel, false)
	_lb(base, Vector3(3.0, 0.5, 0.9), Vector3(1.0, 0.3, -4.2), M.plain(Color(0.3, 0.12, 0.1), 0.9), true)
	_lb(base, Vector3(3.0, 0.5, 0.25), Vector3(1.0, 0.75, -4.6), M.plain(Color(0.3, 0.12, 0.1), 0.9), false)
	_lb(base, Vector3(1.4, 0.8, 0.08), Vector3(1.0, 1.4, 0.25), M.plain(Color(0.02, 0.02, 0.03), 0.2, 0.5), false)
	for lp in [Vector3(-3.0, H - 0.1, -2.5), Vector3(3.0, H - 0.1, -2.5), Vector3(0.0, H - 0.1, -8.0)]:
		_lb(base, Vector3(0.5, 0.06, 0.5), lp, M.emissive(Color(1.0, 0.85, 0.6), 1.5), false)
	for k in 3:
		_lb(base, Vector3(0.5, 0.06, 2.6), Vector3(-6.9, 0.6 + k * 0.7, -8.2), steel, false)
		_lb(base, Vector3(0.4, 0.2, 2.2), Vector3(-6.9, 0.73 + k * 0.7, -8.2), M.plain(Color(0.35, 0.55, 0.3), 0.8), false)
	_lb(base, Vector3(0.06, 2.2, 2.6), Vector3(-7.15, 1.1, -8.2), steel, true)
	# pátio: sacos de areia no portão, barris, contêiner, pilha de caixas (sobe no telhado)
	for sx in [-1.0, 1.0]:
		_lb(base, Vector3(3.0, 1.0, 0.8), Vector3(sx * 6.5, 0.5, h - 4.0), M.plain(Color(0.6, 0.53, 0.38), 0.95), true)
	for bp in [Vector3(-12.0, 0, 6.0), Vector3(-11.2, 0, 6.6), Vector3(13.0, 0, -15.5), Vector3(12.0, 0, -16.2)]:
		_lb(base, Vector3(0.7, 1.0, 0.7), bp + Vector3(0, 0.5, 0), M.plain(Color(0.2, 0.3, 0.5) if g == "g" else Color(0.6, 0.2, 0.15), 0.6, 0.3), true)
	_lb(base, Vector3(6.0, 2.6, 2.45), Vector3(-14.0, 1.3, 12.0), M.plain(gcol.darkened(0.45), 0.6, 0.3), true)
	_lb(base, Vector3(1.4, 1.2, 1.4), Vector3(8.4, 0.6, -8.5), M.wood(), true)
	_lb(base, Vector3(1.4, 2.4, 1.4), Vector3(8.4, 1.2, -9.9), M.wood(), true)
	_lb(base, Vector3(2.4, 1.2, 2.2), Vector3(14.0, 0.6, 14.0), M.plain(Color(0.25, 0.4, 0.3), 0.7, 0.3), true)
	# planta para o minimapa
	var corners := PackedVector2Array()
	for cc in [Vector3(-bw * 0.5, 0, kz), Vector3(bw * 0.5, 0, kz), Vector3(bw * 0.5, 0, fz), Vector3(-bw * 0.5, 0, fz)]:
		var wp: Vector3 = base * cc
		corners.append(Vector2(wp.x, wp.z))
	map_houses.append(corners)
	var fwd: Vector3 = base.basis * Vector3(0, 0, 1)
	gang_hq[g] = {
		"c": Vector3(cx, 0, cz),
		"yaw": yaw,
		"safe": base * Vector3(0, 0.0, kz + 0.95),
		"drugs": base * Vector3(-4.5, 0.94, -2.4),
		"guns": base * Vector3(4.6, 0.0, -1.2),
		"door": base * Vector3(dx, 0.0, fz + 1.2),
		"inside": [base * Vector3(-1.5, 0, -1.5), base * Vector3(5.5, 0, -3.0), base * Vector3(-3.0, 0, -8.0), base * Vector3(3.0, 0, -8.5)],
		"yard": [base * Vector3(-5.0, 0, h - 5.5), base * Vector3(5.0, 0, h - 5.5), base * Vector3(-12.0, 0, 2.0), base * Vector3(12.0, 0, 3.0), base * Vector3(-13.0, 0, -14.0), base * Vector3(13.0, 0, -12.0), base * Vector3(0.0, 0, 6.0)],
		"roof": base * Vector3(4.0, H + 0.3, -7.0),
		"gate_out": base * Vector3(0, 0, h + 9.0),
		"fwd": fwd,
		"notes": [base * Vector3(-14.0, 2.62, 12.0), base * Vector3(5.5, H + 0.32, -9.5), base * Vector3(0.0, 0.0, kz - 1.0), base * Vector3(14.6, 0.0, 15.6), base * Vector3(-16.5, 0.0, -17.0)],
		"cars": [[base * Vector3(10.0, 0.7, 8.0), yaw + PI * 0.5], [base * Vector3(-8.0, 0.7, -17.5), yaw + PI * 0.5]],
		"alley": base * Vector3(h - 2.5, 0.0, h - 2.0),
		"alley_men": [base * Vector3(h - 2.0, 0.0, h - 8.0), base * Vector3(h - 3.2, 0.0, h - 9.2)],
		"alley_yaw": yaw,
	}

# ---------------------------------------------------------------- casa segura (casa de verdade)
## Casa térrea com porta que abre, sala (sofá, TV, rack), cozinha (geladeira, fogão, pia, mesa),
## banheiro (vaso, pia, box), quarto (cama, guarda-roupa, criado-mudo) e garagem ao lado.
var door_pivot: Node3D
func _safehouse(cx: float, cz: float, inner: float, downtown: float) -> void:
	var hh := inner * 0.5
	_building(Rect2(cx - hh, cz + 2.0, inner, hh - 2.0), downtown * 0.5)
	var fz := cz - hh + 3.0            # frente (sul)
	var x0 := cx - 10.0
	var x1 := cx + 4.0
	var bz := fz + 11.0
	var H := 3.0
	var wallm := M.plain(Color(0.92, 0.88, 0.8), 0.85)
	var inw := M.plain(Color(0.96, 0.95, 0.9), 0.9)
	var tile := M.plain(Color(0.85, 0.88, 0.9), 0.3)
	var roofm := M.plain(Color(0.55, 0.22, 0.15), 0.7)
	_box(Vector3(inner, 0.05, hh - 2.0), Vector3(cx, 0.17, cz - hh * 0.5 - 0.5), M.grass(), false)
	_box(Vector3(1.6, 0.06, 3.0), Vector3(cx - 3.0, 0.2, fz - 1.5), M.concrete(Color(0.7, 0.7, 0.68)), false)
	_box(Vector3(x1 - x0, 0.06, bz - fz), Vector3((x0 + x1) * 0.5, 0.2, (fz + bz) * 0.5), M.wood(), false)
	# paredes externas (porta de 1,2 m em x = cx−3,6..cx−2,4)
	var dx0 := cx - 3.6
	var dx1 := cx - 2.4
	_box(Vector3(dx0 - x0, H, 0.25), Vector3((x0 + dx0) * 0.5, H * 0.5 + 0.15, fz), wallm, true)
	_box(Vector3(x1 - dx1, H, 0.25), Vector3((dx1 + x1) * 0.5, H * 0.5 + 0.15, fz), wallm, true)
	_box(Vector3(dx1 - dx0, H - 2.2, 0.25), Vector3(cx - 3.0, H - 0.4 + 0.15, fz), wallm, true)
	_box(Vector3(x1 - x0, H, 0.25), Vector3((x0 + x1) * 0.5, H * 0.5 + 0.15, bz), wallm, true)
	_box(Vector3(0.25, H, bz - fz), Vector3(x0, H * 0.5 + 0.15, (fz + bz) * 0.5), wallm, true)
	_box(Vector3(0.25, H, bz - fz), Vector3(x1, H * 0.5 + 0.15, (fz + bz) * 0.5), wallm, true)
	# janelas
	for wx in [x0 + 2.0, x1 - 2.0]:
		_box(Vector3(1.4, 1.1, 0.06), Vector3(wx, 1.8, fz - 0.14), M.plain(Color(0.2, 0.3, 0.38), 0.05, 0.6), false)
		_box(Vector3(1.6, 0.1, 0.2), Vector3(wx, 1.2, fz - 0.16), M.plain(Color(0.95, 0.95, 0.95), 0.6), false)
	# telhado de duas águas
	_roof(Transform3D(Basis(), Vector3((x0 + x1) * 0.5, 0.15, (fz + bz) * 0.5)), x1 - x0, bz - fz, H, roofm, 0.45)
	_box(Vector3(x1 - x0 - 0.4, 0.12, bz - fz - 0.4), Vector3((x0 + x1) * 0.5, H + 0.12, (fz + bz) * 0.5), inw, true)    # forro com colisão: a câmera não sai pelo teto
	# paredes internas: sala (frente esq.), cozinha (fundo esq.), banheiro (fundo dir.), quarto (frente dir.)
	var mx := cx - 1.0          # divisória vertical
	var mz := fz + 5.5          # divisória horizontal
	_box(Vector3(0.15, H, 3.0), Vector3(mx, H * 0.5 + 0.15, fz + 1.5), inw, true)
	_box(Vector3(0.15, H, mz - fz - 4.2), Vector3(mx, H * 0.5 + 0.15, mz - (mz - fz - 4.2) * 0.5), inw, true)
	_box(Vector3(0.15, H, bz - mz), Vector3(mx, H * 0.5 + 0.15, (mz + bz) * 0.5), inw, true)
	_box(Vector3(mx - x0 - 2.0, H, 0.15), Vector3(x0 + (mx - x0 - 2.0) * 0.5, H * 0.5 + 0.15, mz), inw, true)
	_box(Vector3(x1 - mx - 1.8, H, 0.15), Vector3(x1 - (x1 - mx - 1.8) * 0.5, H * 0.5 + 0.15, mz), inw, true)
	_box(Vector3(0.15, H, bz - mz - 1.4), Vector3(x1 - 3.0, H * 0.5 + 0.15, (mz + 1.4 + bz) * 0.5), inw, true)   # porta do banheiro junto ao corredor
	# ---- sala: sofá em L, mesa de centro, rack com TV, tapete
	_box(Vector3(3.0, 0.45, 0.9), Vector3(x0 + 2.4, 0.4, mz - 0.7), M.plain(Color(0.25, 0.3, 0.5), 0.9), true)
	_box(Vector3(3.0, 0.5, 0.25), Vector3(x0 + 2.4, 0.85, mz - 0.25), M.plain(Color(0.25, 0.3, 0.5), 0.9), false)
	_box(Vector3(0.9, 0.45, 1.8), Vector3(x0 + 0.75, 0.4, mz - 2.0), M.plain(Color(0.25, 0.3, 0.5), 0.9), true)
	_box(Vector3(1.2, 0.08, 0.7), Vector3(x0 + 2.6, 0.5, mz - 2.3), M.wood(), false)
	_box(Vector3(2.8, 0.02, 2.0), Vector3(x0 + 2.6, 0.22, mz - 2.3), M.plain(Color(0.6, 0.25, 0.2), 1.0), false)
	_box(Vector3(2.2, 0.5, 0.45), Vector3(x0 + 2.6, 0.4, fz + 0.45), M.wood(), true)
	_box(Vector3(1.7, 1.0, 0.08), Vector3(x0 + 2.6, 1.25, fz + 0.4), M.plain(Color(0.02, 0.02, 0.03), 0.15, 0.6), false)
	_box(Vector3(1.55, 0.86, 0.02), Vector3(x0 + 2.6, 1.25, fz + 0.45), M.emissive(Color(0.25, 0.45, 0.7), 0.8), false)
	# ---- cozinha: geladeira, fogão com bocas, balcão com pia, armários, mesa e cadeiras
	_box(Vector3(0.8, 1.9, 0.7), Vector3(x0 + 0.6, 1.1, bz - 0.5), M.plain(Color(0.92, 0.93, 0.95), 0.3, 0.2), true)
	_box(Vector3(0.03, 0.5, 0.05), Vector3(x0 + 0.95, 1.4, bz - 0.86), M.plain(Color(0.6, 0.6, 0.62), 0.3, 0.8), false)
	_box(Vector3(0.75, 0.9, 0.65), Vector3(x0 + 1.6, 0.6, bz - 0.5), M.plain(Color(0.85, 0.85, 0.87), 0.3, 0.4), true)
	for bx in 2:
		for bz2 in 2:
			_box(Vector3(0.18, 0.02, 0.18), Vector3(x0 + 1.43 + bx * 0.34, 1.06, bz - 0.66 + bz2 * 0.3), M.plain(Color(0.08, 0.08, 0.08), 0.4), false)
	_box(Vector3(2.4, 0.9, 0.65), Vector3(x0 + 3.2, 0.6, bz - 0.5), M.plain(Color(0.55, 0.4, 0.28), 0.6), true)
	_box(Vector3(2.4, 0.05, 0.7), Vector3(x0 + 3.2, 1.07, bz - 0.5), M.plain(Color(0.2, 0.2, 0.22), 0.3), false)
	_box(Vector3(0.6, 0.04, 0.4), Vector3(x0 + 3.6, 1.08, bz - 0.5), M.plain(Color(0.7, 0.72, 0.75), 0.2, 0.9), false)
	_box(Vector3(3.4, 0.7, 0.35), Vector3(x0 + 2.5, 2.2, bz - 0.3), M.plain(Color(0.55, 0.4, 0.28), 0.6), false)
	_box(Vector3(1.4, 0.06, 0.9), Vector3(x0 + 2.6, 0.95, mz + 2.0), M.wood(), true)
	for k in 4:
		_box(Vector3(0.42, 0.06, 0.42), Vector3(x0 + 2.0 + (k % 2) * 1.2, 0.6, mz + 1.3 + float(k / 2) * 1.4), M.wood(), false)
	# ---- banheiro: vaso, pia com espelho, box de vidro com chuveiro, azulejo
	var bx0 := x1 - 3.0
	_box(Vector3(2.8, 0.06, bz - mz - 0.2), Vector3(bx0 + 1.5, 0.21, (mz + bz) * 0.5), tile, false)
	_box(Vector3(0.45, 0.45, 0.6), Vector3(bx0 + 0.5, 0.4, bz - 0.5), M.plain(Color(0.97, 0.97, 0.98), 0.15), true)
	_box(Vector3(0.45, 0.45, 0.15), Vector3(bx0 + 0.5, 0.85, bz - 0.2), M.plain(Color(0.97, 0.97, 0.98), 0.15), false)
	_box(Vector3(0.6, 0.15, 0.4), Vector3(bx0 + 1.4, 0.95, bz - 0.3), M.plain(Color(0.97, 0.97, 0.98), 0.15), false)
	_box(Vector3(0.6, 0.7, 0.03), Vector3(bx0 + 1.4, 1.6, bz - 0.12), M.plain(Color(0.7, 0.8, 0.85), 0.02, 1.0), false)
	var gl: StandardMaterial3D = M.plain(Color(0.7, 0.85, 0.95), 0.05, 0.3).duplicate()
	gl.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gl.albedo_color.a = 0.3
	_box(Vector3(0.05, 2.0, 1.2), Vector3(x1 - 1.3, 1.15, mz + 0.8), gl, false)
	_box(Vector3(0.3, 0.06, 0.3), Vector3(x1 - 0.5, 2.3, mz + 0.8), M.plain(Color(0.7, 0.72, 0.75), 0.2, 0.9), false)
	# ---- quarto: cama de casal, guarda-roupa, criado-mudo com abajur
	var bed := Vector3(x1 - 2.2, 0.2, fz + 2.3)
	_box(Vector3(2.0, 0.45, 2.4), bed + Vector3(0, 0.28, 0), M.wood(), true)
	_box(Vector3(1.9, 0.2, 2.3), bed + Vector3(0, 0.6, 0), M.plain(Color(0.92, 0.92, 0.95), 0.9), false)
	_box(Vector3(1.9, 0.12, 0.5), bed + Vector3(0, 0.75, -0.9), M.plain(Color(0.95, 0.95, 0.97), 0.9), false)
	_box(Vector3(1.9, 0.22, 1.3), bed + Vector3(0, 0.68, 0.4), M.plain(Color(0.6, 0.15, 0.2), 0.9), false)
	_box(Vector3(2.1, 0.9, 0.12), bed + Vector3(0, 0.9, -1.2), M.wood(), false)
	_box(Vector3(0.5, 0.5, 0.5), bed + Vector3(-1.4, 0.45, -0.9), M.wood(), false)
	_box(Vector3(0.25, 0.3, 0.25), bed + Vector3(-1.4, 0.9, -0.9), M.emissive(Color(1.0, 0.85, 0.5), 1.5), false)
	_box(Vector3(1.8, 2.2, 0.6), Vector3(mx + 1.2, 1.25, mz - 0.45), M.plain(Color(0.45, 0.3, 0.2), 0.6), true)
	_box(Vector3(0.02, 2.0, 0.02), Vector3(mx + 1.2, 1.25, mz - 0.76), M.plain(Color(0.2, 0.15, 0.1), 0.6), false)
	# porta de entrada (abre sozinha quando o jogador chega perto)
	door_pivot = Node3D.new()
	door_pivot.position = Vector3(dx0, 0.15, fz)
	add_child(door_pivot)
	var dm := MeshInstance3D.new()
	var dbm := BoxMesh.new()
	dbm.size = Vector3(1.2, 2.2, 0.08)
	dm.mesh = dbm
	dm.position = Vector3(0.6, 1.1, 0)
	dm.material_override = M.plain(Color(0.4, 0.25, 0.15), 0.6)
	door_pivot.add_child(dm)
	var db := StaticBody3D.new()
	var dcs := CollisionShape3D.new()
	var dsh := BoxShape3D.new()
	dsh.size = Vector3(1.2, 2.2, 0.08)
	dcs.shape = dsh
	dcs.position = Vector3(0.6, 1.1, 0)
	db.add_child(dcs)
	door_pivot.add_child(db)
	# garagem ao lado (portão aberto para a rua)
	_box(Vector3(0.25, 3.0, 9.0), Vector3(x1 + 6.0, 1.65, fz + 4.5), wallm, true)
	_box(Vector3(6.0, 3.0, 0.25), Vector3(x1 + 3.0, 1.65, fz + 9.0), wallm, true)
	_box(Vector3(6.5, 0.3, 9.5), Vector3(x1 + 3.0, 3.2, fz + 4.5), roofm, true)
	_box(Vector3(6.0, 0.05, 9.0), Vector3(x1 + 3.0, 0.2, fz + 4.5), M.concrete(Color(0.5, 0.5, 0.5)), false)
	var li := OmniLight3D.new()
	li.omni_range = 10.0
	li.light_energy = 0.9
	li.position = Vector3((x0 + x1) * 0.5, H - 0.4, (fz + bz) * 0.5)
	add_child(li)
	safehouse = {"spawn": Vector3(x0 + 2.4, 0.3, mz - 1.6), "bed": bed + Vector3(-1.4, 0.1, 0.6), "door": Vector3(cx - 3.0, 0.3, fz - 1.5), "garage": [Vector3(x1 + 3.0, 0.7, fz + 4.5), PI], "door_hinge": Vector3(dx0, 0.15, fz), "rect": [x0, x1, fz, bz, H]}

# ---------------------------------------------------------------- distritos fora da grade
## Norte: bairro residencial (2 ruas só de casas), morros com estrada de terra até um mirante.
## Sul: rua sob um viaduto (rua elevada com rampas), obra grande, galpões, casas e a ponte para a ilha.
## Ilha ao sul: estrada de terra, morro, casas de praia e o farol.
var extra_roads: Array = []      # [a, b, largura, cor] para o minimapa/mapa
var hills: Array = []            # [centro (x,z), raio, altura]

func hill_h(x: float, z: float) -> float:
	var h := 0.0
	for hl in hills:
		var d := Vector2(x, z).distance_to(hl[0])
		if d < hl[1]:
			h = maxf(h, hl[2] * (cos(PI * d / hl[1]) + 1.0) * 0.5)
	return h

func _road(a: Vector3, b: Vector3, w: float, dirt := false) -> void:
	var c := (a + b) * 0.5
	var L := Vector2(a.x - b.x, a.z - b.z).length()
	var yaw := atan2(b.x - a.x, b.z - a.z)
	var mat: Material = M.plain(Color(0.42, 0.33, 0.22), 0.95) if dirt else M.asphalt()
	_boxr(Vector3(w, 0.06, L), Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, 0.04 if not dirt else 0.05, c.z)), mat, false)
	if not dirt:
		# faixa central tracejada
		var n := int(L / 6.0)
		for k in n:
			var p := a.lerp(b, (k + 0.5) / n)
			_boxr(Vector3(0.2, 0.02, 2.5), Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0.08, p.z)), M.plain(Color(0.95, 0.8, 0.2), 0.6), false)
	extra_roads.append([a, b, w, Color(0.42, 0.33, 0.22) if dirt else Color(0.16, 0.16, 0.18)])

## estrada de terra que acompanha o relevo (pedaços inclinados sobre o morro)
func _dirt_path(pts: Array, w: float) -> void:
	var mat := M.plain(Color(0.45, 0.35, 0.24), 0.95)
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var n := int(a.distance_to(b) / 3.0) + 1
		for k in n:
			var p0 := a.lerp(b, float(k) / n)
			var p1 := a.lerp(b, float(k + 1) / n)
			p0.y = hill_h(p0.x, p0.z) + 0.08
			p1.y = hill_h(p1.x, p1.z) + 0.08
			var dir := p1 - p0
			var xf := Transform3D(Basis.looking_at(-dir.normalized(), Vector3.UP), (p0 + p1) * 0.5)
			_boxr(Vector3(w, 0.08, dir.length() + 0.3), xf, mat, false)
		extra_roads.append([a, b, w, Color(0.45, 0.35, 0.24)])

func _hill_mesh(c: Vector2, r: float) -> void:
	var step := 3.0
	var n := int(r * 2.0 / step) + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var o := c - Vector2(r, r)
	for i in n:
		for j in n:
			var q := []
			for v in [Vector2(i, j), Vector2(i + 1, j), Vector2(i + 1, j + 1), Vector2(i, j + 1)]:
				var px: float = o.x + v.x * step
				var pz: float = o.y + v.y * step
				q.append(Vector3(px, hill_h(px, pz) + 0.01, pz))
			for k in [0, 1, 2, 0, 2, 3]:      # sentido horário visto de cima (antes as faces olhavam para baixo: morro invisível no celular)
				st.set_uv(Vector2(q[k].x, q[k].z) * 0.1)
				st.add_vertex(q[k])
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = M.grass()
	add_child(mi)
	var cs := CollisionShape3D.new()
	var tri: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	tri.backface_collision = true      # o personagem atravessava o morro (só um lado das faces colidia)
	cs.shape = tri
	body.add_child(cs)

func _districts() -> void:
	var e := extent()           # 224
	# ---- NORTE: ruas só de casas
	_road(Vector3(-236, 0, 300), Vector3(290, 0, 300), 12.0)
	_road(Vector3(-40, 0, 378), Vector3(290, 0, 378), 12.0)
	for x in [-96.0, 96.0, 224.0]:
		_road(Vector3(x, 0, e + 7.0), Vector3(x, 0, 378.0 if x > 0.0 else 300.0), 12.0)
	for street in [[300.0, -30.0, 285.0, true, true], [378.0, -20.0, 285.0, true, true]]:
		var zz: float = street[0]
		var xx: float = street[1]
		while xx < street[2]:
			var near_cross := false
			for cxr in [-96.0, 96.0, 224.0]:
				if absf(xx - cxr) < 13.0:
					near_cross = true
			if not near_cross:
				for sg in [-1.0, 1.0]:
					var lc := Vector3(xx, 0.0, zz + sg * 17.0)
					if lc.z > 432.0 or (lc.z < e + 12.0):
						continue
					_box(Vector3(22.0, 0.05, 22.0), lc + Vector3(0, 0.07, 0), M.grass(), false)
					_house(Transform3D(Basis(Vector3.UP, PI if sg > 0.0 else 0.0), lc), 22.0, rng.randf() < 0.25)
			xx += 24.0
	# pedestres nas ruas de casas (norte e sul): percursos pela beira da rua, em trechos de ~70 m
	for st in [[300.0, -30.0, 285.0], [378.0, -20.0, 285.0], [-400.0, -190.0, 160.0]]:
		var x0: float = st[1]
		while x0 < st[2] - 20.0:
			var x1: float = minf(x0 + 70.0, st[2])
			var zz2: float = st[0]
			house_loops.append(walk_loops.size())
			walk_loops.append([Vector3(x0, 0.1, zz2 - 7.6), Vector3(x1, 0.1, zz2 - 7.6), Vector3(x1, 0.1, zz2 + 7.6), Vector3(x0, 0.1, zz2 + 7.6)])
			x0 = x1
	# morros com estrada de terra até o mirante (noroeste)
	hills = [[Vector2(-165, 385), 62.0, 24.0], [Vector2(-80, 418), 34.0, 11.0], [Vector2(-215, 330), 26.0, 8.0]]
	for hl in hills:
		_hill_mesh(hl[0], hl[1])
	_dirt_path([Vector3(-140, 0, 306), Vector3(-120, 0, 345), Vector3(-150, 0, 372), Vector3(-165, 0, 385)], 5.0)
	_dirt_path([Vector3(-60, 0, 306), Vector3(-75, 0, 395), Vector3(-80, 0, 418)], 4.0)
	var top := Vector3(-165, hill_h(-165, 385), 385)
	_box(Vector3(8.0, 0.3, 8.0), top + Vector3(0, 0.15, 0), M.wood(), true)
	for sx in [-1.0, 1.0]:
		_box(Vector3(8.0, 0.9, 0.1), top + Vector3(0, 0.75, 4.0 * sx), M.wood(), true)
	_box(Vector3(2.0, 0.45, 0.5), top + Vector3(0, 0.5, -2.0), M.wood(), false)
	# ---- SUL: rua sob o viaduto, viaduto com rampas, obra, galpões, casas
	_road(Vector3(-236, 0, -330), Vector3(236, 0, -330), 12.0)
	for x in [-160.0, 32.0, 210.0]:
		_road(Vector3(x, 0, -e - 7.0), Vector3(x, 0, -436.0 if x == 210.0 else -330.0), 12.0)
	_road(Vector3(-200, 0, -400), Vector3(170, 0, -400), 11.0)
	_road(Vector3(-160, 0, -330), Vector3(-160, 0, -400), 11.0)
	_viaduct(-150.0, 160.0, -330.0, 8.0)
	_construction(40.0, -282.0, 42.0)
	_gang_hq(-90.0, -282.0, 42.0, "g", 0.0)
	_warehouses(150.0, -282.0, 42.0)
	var xx2 := -190.0
	while xx2 < 160.0:
		if absf(xx2 + 160.0) > 13.0:
			for sg in [-1.0, 1.0]:
				var lc2 := Vector3(xx2, 0.0, -400.0 + sg * 16.0)
				if lc2.z < -432.0 or lc2.z > -348.0:
					continue
				_box(Vector3(20.0, 0.05, 20.0), lc2 + Vector3(0, 0.07, 0), M.grass(), false)
				_house(Transform3D(Basis(Vector3.UP, PI if sg > 0.0 else 0.0), lc2), 20.0, rng.randf() < 0.2)
		xx2 += 24.0
	# ---- PONTE para a ilha
	_bridge(Vector3(210, 0, -414), Vector3(210, 0, -516), 3.2)
	# ---- ILHA: estrada de terra, morro, casas de praia
	var isl: Rect2 = W2.ISLAND
	hills.append([Vector2(isl.position.x + 70.0, isl.position.y + 60.0), 45.0, 16.0])
	_hill_mesh(hills[-1][0], 45.0)
	_road(Vector3(210, 0, -516), Vector3(210, 0, -560), 7.0, true)
	_road(Vector3(210, 0, -560), Vector3(isl.end.x - 14.0, 0, isl.position.y + 24.0), 6.0, true)
	_road(Vector3(210, 0, -560), Vector3(isl.position.x + 20.0, 0, -540.0), 6.0, true)
	for k in 3:
		var hc := Vector3(isl.position.x + 30.0 + k * 22.0, 0.0, -512.0)
		_house(Transform3D(Basis(Vector3.UP, PI), hc), 18.0, k == 1)

## rua elevada: tabuleiro a 'h' m de altura entre x0 e x1 (sobre a rua z), rampas de 60 m nas pontas
func _viaduct(x0: float, x1: float, z: float, h: float) -> void:
	var conc := M.concrete(Color(0.62, 0.62, 0.6))
	var deck := M.asphalt()
	var w := 12.0
	_box(Vector3(x1 - x0, 0.6, w), Vector3((x0 + x1) * 0.5, h - 0.3, z), conc, true)
	_box(Vector3(x1 - x0, 0.06, w - 0.6), Vector3((x0 + x1) * 0.5, h + 0.03, z), deck, false)
	for sz in [-1.0, 1.0]:
		_box(Vector3(x1 - x0, 1.0, 0.3), Vector3((x0 + x1) * 0.5, h + 0.5, z + sz * (w * 0.5 - 0.15)), conc, true)
	var x := x0 + 10.0
	while x < x1:
		_box(Vector3(1.6, h - 0.6, 1.6), Vector3(x, (h - 0.6) * 0.5, z - 3.5), conc, true)
		_box(Vector3(1.6, h - 0.6, 1.6), Vector3(x, (h - 0.6) * 0.5, z + 3.5), conc, true)
		x += 24.0
	for side in [-1.0, 1.0]:
		var xa: float = x0 if side < 0 else x1
		var xb: float = xa + side * 60.0
		var a := Vector3(xa, h, z)
		var b := Vector3(xb, 0.1, z)
		var dir := b - a
		var xf := Transform3D(Basis.looking_at(-dir.normalized(), Vector3.UP), (a + b) * 0.5 + Vector3(0, -0.3, 0))
		_boxr(Vector3(w, 0.6, dir.length()), xf, conc, true)
		for sz in [-1.0, 1.0]:
			_boxr(Vector3(0.3, 1.0, dir.length()), xf * Transform3D(Basis(), Vector3(sz * (w * 0.5 - 0.15), 0.7, 0)), conc, true)
	extra_roads.append([Vector3(x0 - 60.0, 0, z), Vector3(x1 + 60.0, 0, z), 10.0, Color(0.5, 0.5, 0.52)])

## ponte sobre o mar: rampas nas duas pontas, tabuleiro, pilares até o fundo, guarda-corpo e arco
func _bridge(a: Vector3, b: Vector3, h: float) -> void:
	var conc := M.concrete(Color(0.7, 0.7, 0.68))
	var steel := M.plain(Color(0.75, 0.2, 0.15), 0.5, 0.6)
	var w := 10.0
	var r0 := a + (b - a).normalized() * 22.0
	var r1 := b - (b - a).normalized() * 22.0
	for seg in [[a, r0, 0.1, h], [r0, r1, h, h], [r1, b, h, 0.1]]:
		var p0: Vector3 = seg[0] + Vector3(0, seg[2], 0)
		var p1: Vector3 = seg[1] + Vector3(0, seg[3], 0)
		var dir := p1 - p0
		var xf := Transform3D(Basis.looking_at(-dir.normalized(), Vector3.UP), (p0 + p1) * 0.5 + Vector3(0, -0.3, 0))
		_boxr(Vector3(w, 0.6, dir.length()), xf, conc, true)
		for sx in [-1.0, 1.0]:
			_boxr(Vector3(0.25, 1.1, dir.length()), xf * Transform3D(Basis(), Vector3(sx * (w * 0.5 - 0.12), 0.8, 0)), steel, true)
	var L := r0.distance_to(r1)
	for k in 4:
		var p := r0.lerp(r1, (k + 0.5) / 4.0)
		_box(Vector3(2.0, h + 12.0, 2.0), Vector3(p.x, (h - 12.0) * 0.5, p.z), conc, true)
	# arco metálico decorativo
	for k in 12:
		var t0 := float(k) / 12.0
		var t1 := float(k + 1) / 12.0
		for sx in [-1.0, 1.0]:
			var q0 := r0.lerp(r1, t0) + Vector3(sx * (w * 0.5 + 0.3), h + sin(t0 * PI) * 9.0, 0)
			var q1 := r0.lerp(r1, t1) + Vector3(sx * (w * 0.5 + 0.3), h + sin(t1 * PI) * 9.0, 0)
			var d := q1 - q0
			_boxr(Vector3(0.5, 0.5, d.length()), Transform3D(Basis.looking_at(-d.normalized(), Vector3.UP), (q0 + q1) * 0.5), steel, false)
			if k % 2 == 1:
				_box(Vector3(0.12, sin(t1 * PI) * 9.0, 0.12), Vector3(q1.x, h + sin(t1 * PI) * 4.5, q1.z), steel, false)
	extra_roads.append([a, b, w, Color(0.6, 0.6, 0.6)])

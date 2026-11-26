extends RefCounted
## Oficina tuning: catálogo de peças e aplicação no veículo (visual + desempenho).
## Cada categoria tem níveis 0..n (0 = original). As peças visuais vão num nó "mods" dentro do modelo.

const CM := preload("res://scripts/carmodel.gd")
const M := preload("res://scripts/mats.gd")

## id -> {name, opts: [nomes], price: [preço por opção]}
const CATS := {
	"paint": {"name": "Pintura", "opts": [], "price": 250},
	"wheels": {"name": "Rodas", "opts": ["Originais", "Cromadas", "Pretas esportivas", "Douradas", "Vermelhas", "Raios finos"], "price": [0, 600, 500, 900, 500, 750]},
	"interior": {"name": "Interior", "opts": ["Original", "Couro preto", "Couro vermelho", "Caramelo", "Branco", "Esportivo azul"], "price": [0, 400, 450, 450, 500, 450]},
	"hood": {"name": "Capô", "opts": ["Original", "Entrada de ar", "Fibra de carbono", "Duplo respiro"], "price": [0, 700, 900, 800]},
	"trunk": {"name": "Porta-malas", "opts": ["Original", "Fibra de carbono", "Rabo de pato"], "price": [0, 600, 650]},
	"sticker": {"name": "Adesivo", "opts": ["Nenhum", "Faixas de corrida", "Chamas", "Número 77", "Faixa lateral", "Xadrez"], "price": [0, 350, 450, 300, 250, 400]},
	"engine": {"name": "Motor (velocidade)", "opts": ["Original", "Nível 1 (+15%)", "Nível 2 (+30%)", "Nível 3 (+50%)"], "price": [0, 1500, 3500, 7000]},
	"armor": {"name": "Blindagem", "opts": ["Nenhuma", "Leve (-25% dano)", "Média (-45% dano)", "Pesada (-60% dano)"], "price": [0, 1800, 4000, 8000]},
	"tint": {"name": "Película dos vidros", "opts": ["Original", "Fumê leve", "Fumê escuro", "Limusine"], "price": [0, 200, 300, 450]},
	"spoiler": {"name": "Aerofólio", "opts": ["Nenhum", "Lip discreto", "Asa esportiva", "Asa GT"], "price": [0, 400, 900, 1500]},
	"fbumper": {"name": "Para-choque dianteiro", "opts": ["Original", "Splitter esportivo", "Quebra-mato"], "price": [0, 650, 800]},
	"rbumper": {"name": "Para-choque traseiro", "opts": ["Original", "Difusor", "Escape duplo"], "price": [0, 650, 700]},
	"susp": {"name": "Suspensão", "opts": ["Original", "Esportiva (-6 cm)", "Rebaixada (-12 cm)", "Elevada (+14 cm)"], "price": [0, 800, 1200, 1000]},
}
const CAR_CATS := ["paint", "wheels", "interior", "hood", "trunk", "sticker", "spoiler", "fbumper", "rbumper", "tint", "susp", "engine", "armor"]
const MOTO_CATS := ["paint", "wheels", "sticker", "engine", "armor"]
const BIG_CATS := ["paint", "wheels", "sticker", "engine", "armor", "tint"]

const RIM := [Color(0, 0, 0, 0), Color(0.88, 0.89, 0.92), Color(0.07, 0.07, 0.08), Color(0.85, 0.66, 0.2), Color(0.75, 0.06, 0.05), Color(0.7, 0.72, 0.75)]
const SEAT := [Color(0, 0, 0, 0), Color(0.05, 0.05, 0.055), Color(0.55, 0.05, 0.05), Color(0.6, 0.38, 0.2), Color(0.9, 0.88, 0.84), Color(0.1, 0.22, 0.6)]
const ENG := [1.0, 1.15, 1.3, 1.5]
const VMX := [1.0, 1.06, 1.12, 1.2]
const ARM := [1.0, 0.75, 0.55, 0.4]
const SUSP := [0.0, -0.06, -0.12, 0.14]
const TINT := [0.62, 0.76, 0.88, 0.96]

static func cats_for(c) -> Array:
	if c.kind == "moto":
		return MOTO_CATS
	if c.kind in ["bus", "truck"]:
		return BIG_CATS
	return CAR_CATS

static func price(cat: String, lv) -> int:
	var p = CATS[cat].price
	if p is Array:
		return p[clampi(int(lv), 0, p.size() - 1)]
	return p

## custo de passar de "old" para "new" (só o que mudou)
static func cost(old: Dictionary, new: Dictionary) -> int:
	var t := 0
	for k in new:
		if str(new[k]) != str(old.get(k, 0 if k != "paint" else "")):
			if k == "paint":
				t += price("paint", 0)
			elif int(new[k]) > 0:
				t += price(k, new[k])
	return t

## aplica todos os mods no carro (pode ser chamado várias vezes: refaz do zero)
static func apply(c, mods: Dictionary) -> void:
	if not c.has_meta("paint0"):
		c.set_meta("paint0", c.paint_c.to_html())
	c.mods = mods.duplicate()
	var pc: String = str(mods.get("paint", ""))
	if pc == "":
		pc = c.get_meta("paint0")
	if c.has_method("repaint") and Color.html(pc) != c.paint_c:
		c.repaint(Color.html(pc))
	c.eng_mult = ENG[clampi(int(mods.get("engine", 0)), 0, 3)]
	c.vmax_mult = VMX[clampi(int(mods.get("engine", 0)), 0, 3)]
	c.dmg_mult = ARM[clampi(int(mods.get("armor", 0)), 0, 3)]
	var old = c.model_root.get_node_or_null("mods")
	if old:
		c.model_root.remove_child(old)
		old.queue_free()
	var root := Node3D.new()
	root.name = "mods"
	c.model_root.add_child(root)
	_wheels(c, int(mods.get("wheels", 0)))
	_susp(c, int(mods.get("susp", 0)))
	_tint(c, int(mods.get("tint", 0)))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	if c.kind == "moto":
		n += _moto_sticker(c, st, int(mods.get("sticker", 0)))
	else:
		var kk: String = c.kind if CM.KINDS.has(c.kind) else ("sedan" if c.kind in ["police", "taxi"] else "")
		if kk != "":
			var k: Dictionary = CM.KINDS[kk]
			n += _body_parts(c, st, k, mods, root)
			n += _interior(c, st, int(mods.get("interior", 0)))
		elif c.kind in ["bus", "truck"]:
			n += _big_sticker(c, st, int(mods.get("sticker", 0)))
	if n > 0:
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = CM.vc_mat()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)

# ---------------------------------------------------------------- peças
static func _top(k: Dictionary, z: float) -> float:
	return CM._top(k.top, z)

## faixa fina que acompanha o perfil de cima do carro (capô, teto, tampa traseira)
static func _strip(st: SurfaceTool, k: Dictionary, z0: float, z1: float, x: float, w: float, col: Color, lift := 0.012, th := 0.012) -> void:
	var segs := maxi(2, int(absf(z1 - z0) / 0.22))
	for i in segs:
		var za := lerpf(z0, z1, float(i) / segs)
		var zb := lerpf(z0, z1, float(i + 1) / segs)
		var ya := _top(k, za) + lift
		var yb := _top(k, zb) + lift
		var mid := Vector3(x, (ya + yb) * 0.5, (za + zb) * 0.5)
		var ang := atan2(yb - ya, zb - za)
		var bm := BoxMesh.new()
		bm.size = Vector3(w, th, Vector2(zb - za, yb - ya).length() + 0.02)
		CM._prim(st, bm, Transform3D(Basis(Vector3.RIGHT, -ang), mid), col)

static func _bx(st: SurfaceTool, size: Vector3, pos: Vector3, col: Color, rot := Basis()) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	CM._prim(st, bm, Transform3D(rot, pos), col)

static func _body_parts(c, st: SurfaceTool, k: Dictionary, mods: Dictionary, root: Node3D) -> int:
	var L: float = k.L
	var W: float = k.W
	var belt: float = k.belt
	var hz := L * 0.5
	var n := 0
	var carbon := Color(0.08, 0.08, 0.09)
	var paint: Color = c.paint_c
	var dark := Color(0.06, 0.06, 0.065)
	# capô: frente do carro até ~1,3 m para trás
	var hood_z0 := hz - 0.18
	var hood_z1 := hz - 1.35
	match int(mods.get("hood", 0)):
		1:
			var z := hz - 0.85
			_bx(st, Vector3(0.62, 0.1, 0.72), Vector3(0, _top(k, z) + 0.06, z), paint.darkened(0.1))
			_bx(st, Vector3(0.5, 0.07, 0.04), Vector3(0, _top(k, z) + 0.07, z + 0.36), dark)
			n += 1
		2:
			_strip(st, k, hood_z0, hood_z1, 0.0, W * 0.78, carbon, 0.014, 0.016)
			n += 1
		3:
			for s in [-1.0, 1.0]:
				var z2 := hz - 0.75
				_bx(st, Vector3(0.32, 0.05, 0.42), Vector3(0.36 * s, _top(k, z2) + 0.03, z2), dark)
				for q in 3:
					_bx(st, Vector3(0.3, 0.02, 0.03), Vector3(0.36 * s, _top(k, z2) + 0.06, z2 - 0.14 + q * 0.14), Color(0.2, 0.2, 0.21))
			n += 1
	# porta-malas
	var tz0 := -hz + 0.12
	var tz1 := -hz + 0.95
	match int(mods.get("trunk", 0)):
		1:
			_strip(st, k, tz0, tz1, 0.0, W * 0.76, carbon, 0.014, 0.016)
			n += 1
		2:
			var z := -hz + 0.2
			_bx(st, Vector3(W * 0.8, 0.07, 0.24), Vector3(0, _top(k, z) + 0.06, z), paint, Basis(Vector3.RIGHT, 0.35))
			n += 1
	# adesivos
	match int(mods.get("sticker", 0)):
		1:
			for s in [-1.0, 1.0]:
				_strip(st, k, hz - 0.08, -hz + 0.12, 0.2 * s, 0.2, Color(0.95, 0.95, 0.95) if paint.v < 0.7 else Color(0.08, 0.08, 0.1), 0.006, 0.008)
			n += 1
		2:
			for s in [-1.0, 1.0]:
				for q in 5:
					var z := hz - 0.4 - q * 0.32
					var h := 0.32 - q * 0.05
					var col := Color(1.0, 0.75 - q * 0.12, 0.05)
					_bx(st, Vector3(0.012, h, 0.42), Vector3((W * 0.5 + 0.012) * s, belt - 0.32 + h * 0.3, z), col, Basis(Vector3.RIGHT, 0.45))
			n += 1
		3:
			for s in [-1.0, 1.0]:
				var disc := CylinderMesh.new()
				disc.top_radius = 0.3
				disc.bottom_radius = 0.3
				disc.height = 0.01
				disc.radial_segments = 20
				CM._prim(st, disc, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3((W * 0.5 + 0.012) * s, belt - 0.3, 0.1)), Color(0.96, 0.96, 0.96))
				var lb := Label3D.new()
				lb.text = "77"
				lb.font_size = 64
				lb.pixel_size = 0.0055
				lb.outline_size = 0
				lb.modulate = Color(0.05, 0.05, 0.06)
				lb.position = Vector3((W * 0.5 + 0.02) * s, belt - 0.3, 0.1)
				lb.rotation.y = PI * 0.5 * s
				lb.double_sided = false
				root.add_child(lb)
			n += 1
		4:
			for s in [-1.0, 1.0]:
				_bx(st, Vector3(0.012, 0.09, L * 0.78), Vector3((W * 0.5 + 0.012) * s, belt - 0.14, 0), Color(0.95, 0.95, 0.95))
				_bx(st, Vector3(0.012, 0.04, L * 0.78), Vector3((W * 0.5 + 0.012) * s, belt - 0.24, 0), Color(0.85, 0.1, 0.08))
			n += 1
		5:
			for q in 8:
				for r in 2:
					var col := Color(0.95, 0.95, 0.95) if (q + r) % 2 == 0 else Color(0.06, 0.06, 0.07)
					var z := hz - 0.25 - r * 0.16
					var x := -0.56 + q * 0.16
					_bx(st, Vector3(0.16, 0.01, 0.16), Vector3(x, _top(k, z) + 0.008, z), col)
			n += 1
	# aerofólio
	var rz := -hz + 0.22
	var ry := _top(k, rz)
	match int(mods.get("spoiler", 0)):
		1:
			_bx(st, Vector3(W * 0.82, 0.06, 0.12), Vector3(0, ry + 0.04, rz - 0.02), dark, Basis(Vector3.RIGHT, -0.3))
			n += 1
		2:
			for s in [-1.0, 1.0]:
				_bx(st, Vector3(0.05, 0.26, 0.08), Vector3(0.55 * s, ry + 0.13, rz + 0.05), dark)
			_bx(st, Vector3(W * 0.86, 0.04, 0.28), Vector3(0, ry + 0.27, rz + 0.02), paint, Basis(Vector3.RIGHT, -0.12))
			n += 1
		3:
			for s in [-1.0, 1.0]:
				_bx(st, Vector3(0.05, 0.48, 0.12), Vector3(0.48 * s, ry + 0.24, rz + 0.1), dark)
				_bx(st, Vector3(0.03, 0.2, 0.42), Vector3((W * 0.5 + 0.06) * s, ry + 0.5, rz), carbon)
			_bx(st, Vector3(W + 0.12, 0.05, 0.4), Vector3(0, ry + 0.5, rz), carbon, Basis(Vector3.RIGHT, -0.16))
			n += 1
	# para-choques
	match int(mods.get("fbumper", 0)):
		1:
			_bx(st, Vector3(W * 0.98, 0.04, 0.3), Vector3(0, 0.22, hz - 0.02), carbon)
			for s in [-1.0, 1.0]:
				_bx(st, Vector3(0.04, 0.14, 0.3), Vector3(W * 0.47 * s, 0.28, hz - 0.02), carbon)
			n += 1
		2:
			var tube := Color(0.15, 0.15, 0.16)
			for s in [-1.0, 1.0]:
				_bx(st, Vector3(0.07, 0.62, 0.07), Vector3(0.42 * s, 0.6, hz + 0.16), tube)
			_bx(st, Vector3(W * 0.85, 0.07, 0.07), Vector3(0, 0.88, hz + 0.16), tube)
			_bx(st, Vector3(W * 0.85, 0.07, 0.07), Vector3(0, 0.48, hz + 0.18), tube)
			_bx(st, Vector3(0.6, 0.3, 0.05), Vector3(0, 0.62, hz + 0.18), Color(0.25, 0.25, 0.27))
			n += 1
	match int(mods.get("rbumper", 0)):
		1:
			_bx(st, Vector3(W * 0.8, 0.05, 0.32), Vector3(0, 0.22, -hz + 0.05), carbon)
			for q in 5:
				_bx(st, Vector3(0.03, 0.14, 0.3), Vector3(-0.5 + q * 0.25, 0.28, -hz + 0.05), carbon)
			n += 1
		2:
			for s in [-1.0, 1.0]:
				var cy := CylinderMesh.new()
				cy.top_radius = 0.07
				cy.bottom_radius = 0.07
				cy.height = 0.3
				cy.radial_segments = 12
				CM._prim(st, cy, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.45 * s, 0.3, -hz - 0.05)), Color(0.75, 0.75, 0.78))
				_bx(st, Vector3(0.1, 0.1, 0.02), Vector3(0.45 * s, 0.3, -hz - 0.2), Color(0.02, 0.02, 0.02))
			n += 1
	return n

static func _interior(c, st: SurfaceTool, lv: int) -> int:
	if lv <= 0:
		return 0
	var col: Color = SEAT[lv]
	var s: Vector3 = c.seat
	# altura do encosto limitada pelo teto do modelo (não atravessa o teto em carro baixo)
	var roof := 9.0
	var kk: String = c.kind if CM.KINDS.has(c.kind) else ("sedan" if c.kind in ["police", "taxi"] else "")
	if kk != "":
		roof = CM._top(CM.KINDS[kk].top, s.z - 0.3) - 0.1
	var bh := clampf(roof - (s.y + 0.1), 0.25, 0.62)
	for sx in [-1.0, 1.0]:
		var x: float = absf(s.x) * sx
		_bx(st, Vector3(0.5, 0.1, 0.5), Vector3(x, s.y + 0.06, s.z), col)
		_bx(st, Vector3(0.5, bh, 0.11), Vector3(x, s.y + 0.1 + bh * 0.5, s.z - 0.28), col, Basis(Vector3.RIGHT, -0.12))
		if bh > 0.55:
			_bx(st, Vector3(0.3, 0.14, 0.09), Vector3(x, s.y + 0.1 + bh + 0.04, s.z - 0.33), col)
		if lv == 5 or lv == 2:
			_bx(st, Vector3(0.08, bh - 0.02, 0.115), Vector3(x, s.y + 0.1 + bh * 0.5, s.z - 0.28), Color(0.9, 0.9, 0.9) if lv == 5 else Color(0.1, 0.1, 0.1), Basis(Vector3.RIGHT, -0.12))
	return 1

static func _moto_sticker(c, st: SurfaceTool, lv: int) -> int:
	if lv <= 0:
		return 0
	var cols := [Color.WHITE, Color(0.95, 0.95, 0.95), Color(1, 0.55, 0.05), Color(0.95, 0.95, 0.95), Color(0.9, 0.1, 0.08), Color(0.06, 0.06, 0.07)]
	for s in [-1.0, 1.0]:
		_bx(st, Vector3(0.012, 0.07, 0.5), Vector3(0.19 * s, 0.9, 0.2), cols[lv])
		_bx(st, Vector3(0.012, 0.04, 0.4), Vector3(0.17 * s, 0.74, -0.45), cols[lv])
	_bx(st, Vector3(0.08, 0.012, 0.45), Vector3(0, 1.0, 0.2), cols[lv])
	return 1

static func _big_sticker(c, st: SurfaceTool, lv: int) -> int:
	if lv <= 0:
		return 0
	var sz: Vector3 = c.body_size
	var cols := [Color.WHITE, Color(0.95, 0.95, 0.95), Color(1, 0.55, 0.05), Color(0.1, 0.1, 0.12), Color(0.9, 0.1, 0.08), Color(0.06, 0.06, 0.07)]
	for s in [-1.0, 1.0]:
		_bx(st, Vector3(0.015, 0.25, sz.z * 0.6), Vector3((sz.x * 0.5 + 0.04) * s, 1.6, -0.6), cols[lv])
	return 1

static func _wheels(c, lv: int) -> void:
	for w in c.wheels:
		var host: Node3D = null
		for ch in w.get_children():
			if ch is Node3D:
				host = ch
				break
		if host == null:
			continue
		var old = host.get_node_or_null("rim_mod")
		if old:
			host.remove_child(old)
			old.queue_free()
		if lv <= 0:
			continue
		var r: float = c.wheel_r
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rz := Basis(Vector3.FORWARD, PI * 0.5)
		var wdt := 0.3 if c.kind != "moto" else 0.14
		var disc := CylinderMesh.new()
		disc.top_radius = r * 0.64
		disc.bottom_radius = r * 0.64
		disc.height = wdt + 0.02
		disc.radial_segments = 20
		CM._prim(st, disc, Transform3D(rz, Vector3.ZERO), RIM[lv].darkened(0.35))
		var spokes := 10 if lv == 5 else 5
		for q in spokes:
			var a := TAU * q / spokes
			var bm := BoxMesh.new()
			bm.size = Vector3(wdt + 0.05, r * (0.07 if lv == 5 else 0.16), r * 1.22)
			CM._prim(st, bm, Transform3D(Basis(Vector3.RIGHT, a), Vector3.ZERO), RIM[lv])
		var hub := CylinderMesh.new()
		hub.top_radius = r * 0.17
		hub.bottom_radius = r * 0.17
		hub.height = wdt + 0.07
		hub.radial_segments = 12
		CM._prim(st, hub, Transform3D(rz, Vector3.ZERO), RIM[lv].lightened(0.2))
		var mi := MeshInstance3D.new()
		mi.name = "rim_mod"
		mi.mesh = st.commit()
		var mat := M.plain(Color.WHITE, 0.25, 0.85 if lv in [1, 3, 5] else 0.3)
		mat.vertex_color_use_as_albedo = true
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.add_child(mi)

static func _susp(c, lv: int) -> void:
	if not c.has_meta("rest0"):
		c.set_meta("rest0", c.wheels[0].wheel_rest_length if c.wheels.size() > 0 else 0.14)
	var r0: float = c.get_meta("rest0")
	for w in c.wheels:
		w.wheel_rest_length = maxf(0.03, r0 + SUSP[lv])
		w.suspension_stiffness = 48.0 * (1.25 if lv in [1, 2] else 1.0)

static func _tint(c, lv: int) -> void:
	for mi in c.model_root.find_children("*", "MeshInstance3D", true, false):
		var m = mi.material_override
		if not (m is StandardMaterial3D) or m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		if not mi.has_meta("glass0"):
			if m.albedo_color.a > 0.9 or m.vertex_color_use_as_albedo:
				continue
			mi.set_meta("glass0", m)
		var g0: StandardMaterial3D = mi.get_meta("glass0")
		if lv <= 0:
			mi.material_override = g0
			continue
		var g: StandardMaterial3D = g0.duplicate()
		g.albedo_color = Color(0.02, 0.025, 0.03, TINT[lv])
		mi.material_override = g

extends RefCounted
## Motos e ônibus gerados por código, no mesmo formato de carmodel.gd:
## {"root", "wheels": [{node, pos, front}], "wr", "seat", "size", "spin": [nós visuais que giram], "fork": nó que esterça, "lean": nó que inclina}
## Frente = +Z, chão em y = 0.

const CM := preload("res://scripts/carmodel.gd")
const M := preload("res://scripts/mats.gd")

static func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

static func _cyl(r: float, h: float, seg := 14) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c

## roda visual (pneu + aro + cubo), eixo ao longo de X
static func _wheel_mesh(wr: float, width: float, rim: Color) -> Mesh:
	var st := _st()
	var rz := Basis(Vector3.FORWARD, PI * 0.5)
	CM._prim(st, _cyl(wr, width, 18), Transform3D(rz, Vector3.ZERO), Color(0.05, 0.05, 0.055))
	CM._prim(st, _cyl(wr * 0.68, width + 0.01, 14), Transform3D(rz, Vector3.ZERO), rim)
	CM._prim(st, _cyl(wr * 0.2, width + 0.03, 8), Transform3D(rz, Vector3.ZERO), Color(0.75, 0.75, 0.77))
	for q in 4:
		var b := BoxMesh.new()
		b.size = Vector3(width + 0.02, wr * 1.25, 0.035)
		CM._prim(st, b, Transform3D(Basis(Vector3.RIGHT, q * PI / 4.0), Vector3.ZERO), rim.darkened(0.25))
	return st.commit()

static func build(kind: String, paint: Color) -> Dictionary:
	match kind:
		"bike": return _bike(paint)
		"sportbike":
			var d := _moto(paint)
			# carenagem esportiva e bolha (para-brisa) na frente
			var fs := _st()
			CM._ell(fs, Vector3(0, 0.82, 0.5), Vector3(0.42, 0.38, 0.62), paint)
			CM._ell(fs, Vector3(0, 0.62, 0.1), Vector3(0.36, 0.3, 0.7), paint.darkened(0.15))
			CM._ell(fs, Vector3(0, 1.05, 0.62), Vector3(0.28, 0.2, 0.1), Color(0.15, 0.2, 0.25))
			var fm := MeshInstance3D.new()
			fm.mesh = fs.commit()
			fm.material_override = CM.vc_mat()
			d.lean.add_child(fm)
			return d
		"truck": return _truck(paint)
		"moto": return _moto(paint)
	return _bus(paint)

# ---------------------------------------------------------------- moto
static func _moto(paint: Color) -> Dictionary:
	var root := Node3D.new()
	var lean := Node3D.new()      # inclina nas curvas (só visual)
	root.add_child(lean)
	var wr := 0.33
	var zf := 0.72
	var zr := -0.68
	var body := _st()
	var lit := _st()
	var dark := Color(0.06, 0.06, 0.07)
	var chrome := Color(0.7, 0.71, 0.74)
	# quadro e motor
	CM._box(body, Vector3(0.2, 0.32, 0.55), Vector3(0, 0.42, -0.02), Color(0.22, 0.22, 0.24))
	CM._prim(body, _cyl(0.11, 0.3, 10), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 0.38, 0.12)), Color(0.35, 0.35, 0.37))
	CM._prim(body, _cyl(0.035, 0.9, 6), Transform3D(Basis(Vector3.RIGHT, 1.15), Vector3(0, 0.6, 0.18)), dark)
	# tanque, banco e rabeta na cor da moto
	CM._ell(body, Vector3(0, 0.82, 0.22), Vector3(0.34, 0.24, 0.5), paint)
	CM._ell(body, Vector3(0, 0.78, -0.24), Vector3(0.28, 0.1, 0.55), Color(0.08, 0.08, 0.09))
	CM._ell(body, Vector3(0, 0.8, -0.58), Vector3(0.22, 0.14, 0.34), paint)
	# escapamento
	CM._prim(body, _cyl(0.05, 0.7, 8), Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - 0.15), Vector3(0.16, 0.38, -0.38)), chrome)
	# para-lama traseiro e balança
	CM._box(body, Vector3(0.06, 0.06, 0.62), Vector3(0.1, 0.36, -0.36), dark)
	CM._box(body, Vector3(0.06, 0.06, 0.62), Vector3(-0.1, 0.36, -0.36), dark)
	CM._ell(body, Vector3(0, 0.62, zr - 0.05), Vector3(0.16, 0.06, 0.5), paint.darkened(0.2))
	# lanterna
	CM._ell(lit, Vector3(0, 0.8, -0.76), Vector3(0.12, 0.05, 0.04), Color(0.95, 0.06, 0.05))
	var bm := MeshInstance3D.new()
	bm.mesh = body.commit()
	bm.material_override = CM.vc_mat()
	lean.add_child(bm)
	var lm := MeshInstance3D.new()
	lm.mesh = lit.commit()
	lm.material_override = CM.vc_lit()
	lean.add_child(lm)
	# garfo dianteiro (esterça): bengalas, guidão, farol, painel, para-lama
	var fork := Node3D.new()
	fork.position = Vector3(0, 0.98, zf - 0.28)
	fork.rotation.x = 0.42
	lean.add_child(fork)
	var fs := _st()
	var fl := _st()
	for s in [-1.0, 1.0]:
		CM._prim(fs, _cyl(0.028, 0.72, 6), Transform3D(Basis(), Vector3(0.09 * s, -0.36, 0)), chrome)
	CM._prim(fs, _cyl(0.018, 0.62, 6), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 0.06, -0.03)), dark)
	for s in [-1.0, 1.0]:
		CM._prim(fs, _cyl(0.025, 0.1, 6), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.33 * s, 0.06, -0.03)), Color(0.1, 0.1, 0.1))
		CM._box(fs, Vector3(0.07, 0.04, 0.02), Vector3(0.2 * s, 0.2, 0.0), chrome)
	CM._ell(fs, Vector3(0, -0.02, 0.1), Vector3(0.2, 0.18, 0.12), paint)
	CM._ell(fl, Vector3(0, -0.02, 0.16), Vector3(0.12, 0.12, 0.04), Color(1, 0.97, 0.88))
	CM._ell(fs, Vector3(0, -0.72, 0.06), Vector3(0.14, 0.05, 0.42), paint.darkened(0.2))
	var fm := MeshInstance3D.new()
	fm.mesh = fs.commit()
	fm.material_override = CM.vc_mat()
	fork.add_child(fm)
	var flm := MeshInstance3D.new()
	flm.mesh = fl.commit()
	flm.material_override = CM.vc_lit()
	fork.add_child(flm)
	# rodas visuais (giram; a da frente fica no garfo)
	var wm := _wheel_mesh(wr, 0.12, Color(0.6, 0.6, 0.62))
	var front_w := MeshInstance3D.new()
	front_w.mesh = wm
	front_w.material_override = CM.vc_mat()
	var fp := Node3D.new()        # pivô da roda dianteira no garfo
	fork.add_child(fp)
	fp.transform = Transform3D(Basis(Vector3.RIGHT, -0.42), fork.transform.affine_inverse() * Vector3(0, wr, zf))
	fp.add_child(front_w)
	var rear_w := MeshInstance3D.new()
	rear_w.mesh = wm
	rear_w.material_override = CM.vc_mat()
	rear_w.position = Vector3(0, wr, zr)
	lean.add_child(rear_w)
	# 4 rodas físicas estreitas e invisíveis (a moto não depende de equilíbrio real)
	var wheels := []
	for wz in [zf, zr]:
		for s in [-1.0, 1.0]:
			wheels.append({"node": Node3D.new(), "pos": Vector3(0.26 * s, wr, wz), "front": wz > 0})
	return {"root": root, "wheels": wheels, "wr": wr, "seat": Vector3(0, 0.62, -0.2), "size": Vector3(0.7, 1.25, 2.1),
		"spin": [front_w, rear_w], "fork": fork, "lean": lean, "moto": true}

# ---------------------------------------------------------------- ônibus
static func _bus(paint: Color) -> Dictionary:
	var root := Node3D.new()
	var L := 11.0
	var W := 2.5
	var H := 3.05
	var wr := 0.5
	var body := _st()
	var lit := _st()
	var glass := _st()
	var white := Color(0.92, 0.92, 0.9)
	var dark := Color(0.07, 0.07, 0.08)
	var hz := L * 0.5
	# saia (cor da linha), faixa de janelas, teto branco
	# lataria com recorte nas rodas: faixa de cima inteira, faixa de baixo em 3 trechos
	CM._box(body, Vector3(W, 0.44, L), Vector3(0, 1.2, 0), paint)
	for seg in [[-hz, -3.8], [-2.2, 2.8], [4.4, hz]]:
		var zl: float = seg[1] - seg[0]
		CM._box(body, Vector3(W, 0.55, zl), Vector3(0, 0.73, (seg[0] + seg[1]) * 0.5), paint)
	for wz in [3.6, -3.0]:
		CM._box(body, Vector3(W - 0.75, 0.6, 1.6), Vector3(0, 0.72, wz), dark)   # interior da caixa de roda
	CM._box(body, Vector3(W - 0.02, 0.12, L - 0.02), Vector3(0, 1.48, 0), white)
	CM._box(body, Vector3(W, 0.32, L), Vector3(0, H - 0.16, 0), white)
	CM._box(body, Vector3(W - 0.3, 0.12, L - 1.6), Vector3(0, H + 0.06, -0.3), Color(0.75, 0.76, 0.78))   # ar-condicionado
	# colunas entre as janelas
	var n := 8
	for i in n + 1:
		var z := lerpf(-hz + 0.25, hz - 1.9, float(i) / n)
		for s in [-1.0, 1.0]:
			CM._box(body, Vector3(0.06, 1.1, 0.14), Vector3((W * 0.5 - 0.02) * s, 2.1, z), white)
	# vidros laterais e frontal/traseiro (malha separada)
	for s in [-1.0, 1.0]:
		CM._box(glass, Vector3(0.02, 1.1, L - 2.2), Vector3((W * 0.5 - 0.01) * s, 2.1, -0.85), Color(0.1, 0.14, 0.18))
	CM._box(glass, Vector3(W - 0.15, 1.45, 0.04), Vector3(0, 2.0, hz - 0.02), Color(0.1, 0.14, 0.18))
	CM._box(glass, Vector3(W - 0.5, 0.8, 0.04), Vector3(0, 2.2, -hz + 0.02), Color(0.1, 0.14, 0.18))
	# porta dianteira e do meio (lado direito = -X)
	for dz in [hz - 1.0, -0.5]:
		CM._box(glass, Vector3(0.03, 2.2, 1.1), Vector3(-W * 0.5 - 0.005, 1.55, dz), Color(0.12, 0.16, 0.2))
		CM._box(body, Vector3(0.04, 2.25, 0.05), Vector3(-W * 0.5 - 0.01, 1.55, dz), dark)
	# parachoques, painel frontal, letreiro
	CM._box(body, Vector3(W + 0.04, 0.35, 0.14), Vector3(0, 0.45, hz + 0.02), dark)
	CM._box(body, Vector3(W + 0.04, 0.35, 0.14), Vector3(0, 0.45, -hz - 0.02), dark)
	CM._box(lit, Vector3(1.5, 0.26, 0.03), Vector3(0, H - 0.18, hz + 0.02), Color(1.0, 0.62, 0.1))
	for s in [-1.0, 1.0]:
		CM._ell(lit, Vector3(0.95 * s, 0.75, hz + 0.03), Vector3(0.3, 0.16, 0.06), Color(1, 0.97, 0.88))
		CM._ell(lit, Vector3(0.98 * s, 1.0, -hz - 0.03), Vector3(0.18, 0.3, 0.06), Color(0.95, 0.06, 0.05))
		CM._box(body, Vector3(0.05, 0.4, 0.05), Vector3(1.32 * s, 2.3, hz + 0.15), dark)   # retrovisores
		CM._box(body, Vector3(0.12, 0.3, 0.2), Vector3(1.36 * s, 2.0, hz + 0.18), dark)
	# interior: bancos aos pares, motorista, barras
	var seat_c := Color(0.15, 0.22, 0.45)
	for i in 8:
		var z := lerpf(hz - 2.6, -hz + 0.9, float(i) / 7.0)
		for s in [-1.0, 1.0]:
			CM._box(body, Vector3(0.85, 0.12, 0.45), Vector3(0.72 * s, 0.95, z), seat_c)
			CM._box(body, Vector3(0.85, 0.6, 0.1), Vector3(0.72 * s, 1.25, z - 0.22), seat_c)
	CM._box(body, Vector3(0.5, 0.12, 0.5), Vector3(0.7, 1.0, hz - 1.3), Color(0.1, 0.1, 0.1))
	CM._box(body, Vector3(W - 0.2, 0.4, 0.5), Vector3(0, 1.45, hz - 0.35), Color(0.12, 0.12, 0.13))
	CM._prim(body, _cyl(0.025, L - 2.0, 6), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 2.6, -0.6)), Color(0.75, 0.75, 0.2))
	var bm := MeshInstance3D.new()
	bm.mesh = body.commit()
	bm.material_override = CM.vc_mat()
	root.add_child(bm)
	var lm := MeshInstance3D.new()
	lm.mesh = lit.commit()
	lm.material_override = CM.vc_lit()
	root.add_child(lm)
	var gm := MeshInstance3D.new()
	gm.mesh = glass.commit()
	var g := StandardMaterial3D.new()
	g.vertex_color_use_as_albedo = true
	g.albedo_color = Color(1, 1, 1, 0.6)
	g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.metallic = 0.8
	g.roughness = 0.05
	gm.material_override = g
	root.add_child(gm)
	# rodas: dianteira simples, traseira dupla (visual)
	var wheels := []
	var wm := _wheel_mesh(wr, 0.32, Color(0.7, 0.7, 0.72))
	for wz in [3.6, -3.0]:
		for s in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			mi.mesh = wm
			mi.material_override = CM.vc_mat()
			if wz < 0:
				var dual := MeshInstance3D.new()
				dual.mesh = wm
				dual.material_override = CM.vc_mat()
				dual.position = Vector3(-0.3 * s, 0, 0)
				mi.add_child(dual)
			wheels.append({"node": mi, "pos": Vector3((W * 0.5 - 0.14) * s, wr, wz), "front": wz > 0})
	return {"root": root, "wheels": wheels, "wr": wr, "seat": Vector3(0.7, 1.05, hz - 1.3), "size": Vector3(W, H, L)}

# ---------------------------------------------------------------- bicicleta
static func _bike(paint: Color) -> Dictionary:
	var root := Node3D.new()
	var lean := Node3D.new()
	root.add_child(lean)
	var wr := 0.34
	var zf := 0.55
	var zr := -0.5
	var fr := _st()
	var dark := Color(0.06, 0.06, 0.07)
	# quadro em diamante (tubos finos na cor da bike), selim, pedivela
	CM._prim(fr, _cyl(0.022, 0.75, 6), Transform3D(Basis(Vector3.RIGHT, 1.2), Vector3(0, 0.62, 0.12)), paint)
	CM._prim(fr, _cyl(0.022, 0.62, 6), Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0, 0.62, -0.18)), paint)
	CM._prim(fr, _cyl(0.02, 0.55, 6), Transform3D(Basis(Vector3.RIGHT, 1.0), Vector3(0, 0.4, -0.26)), paint)
	CM._prim(fr, _cyl(0.02, 0.45, 6), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.36, -0.28)), paint)
	CM._ell(fr, Vector3(0, 0.92, -0.25), Vector3(0.12, 0.05, 0.24), dark)
	CM._prim(fr, _cyl(0.07, 0.04, 10), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.05, 0.34, -0.02)), Color(0.6, 0.6, 0.62))
	for s in [-1.0, 1.0]:
		CM._box(fr, Vector3(0.1, 0.03, 0.06), Vector3(0.12 * s, 0.34 + 0.12 * s, -0.02 + 0.1 * s), dark)
	var bm := MeshInstance3D.new()
	bm.mesh = fr.commit()
	bm.material_override = CM.vc_mat()
	lean.add_child(bm)
	var fork := Node3D.new()
	fork.position = Vector3(0, 0.9, zf - 0.2)
	fork.rotation.x = 0.3
	lean.add_child(fork)
	var fs := _st()
	CM._prim(fs, _cyl(0.018, 0.65, 6), Transform3D(Basis(), Vector3(0, -0.3, 0)), Color(0.6, 0.6, 0.62))
	CM._prim(fs, _cyl(0.015, 0.55, 6), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 0.08, -0.05)), dark)
	var fm := MeshInstance3D.new()
	fm.mesh = fs.commit()
	fm.material_override = CM.vc_mat()
	fork.add_child(fm)
	var wst := _st()
	var rz := Basis(Vector3.FORWARD, PI * 0.5)
	CM._prim(wst, _cyl(wr, 0.045, 22), Transform3D(rz, Vector3.ZERO), Color(0.05, 0.05, 0.05))
	CM._prim(wst, _cyl(wr * 0.9, 0.05, 22), Transform3D(rz, Vector3.ZERO), Color(0.75, 0.75, 0.78))
	CM._prim(wst, _cyl(wr * 0.82, 0.055, 22), Transform3D(rz, Vector3.ZERO), Color(0.12, 0.12, 0.12))
	var wm := wst.commit()
	var front_w := MeshInstance3D.new()
	front_w.mesh = wm
	front_w.material_override = CM.vc_mat()
	var fp := Node3D.new()
	fork.add_child(fp)
	fp.transform = Transform3D(Basis(Vector3.RIGHT, -0.3), fork.transform.affine_inverse() * Vector3(0, wr, zf))
	fp.add_child(front_w)
	var rear_w := MeshInstance3D.new()
	rear_w.mesh = wm
	rear_w.material_override = CM.vc_mat()
	rear_w.position = Vector3(0, wr, zr)
	lean.add_child(rear_w)
	var wheels := []
	for wz in [zf, zr]:
		for s in [-1.0, 1.0]:
			wheels.append({"node": Node3D.new(), "pos": Vector3(0.22 * s, wr, wz), "front": wz > 0})
	return {"root": root, "wheels": wheels, "wr": wr, "seat": Vector3(0, 0.62, -0.2), "size": Vector3(0.6, 1.1, 1.7),
		"spin": [front_w, rear_w], "fork": fork, "lean": lean, "moto": true}

# ---------------------------------------------------------------- caminhão (cabine + baú)
static func _truck(paint: Color) -> Dictionary:
	var root := Node3D.new()
	var L := 8.6
	var W := 2.45
	var wr := 0.52
	var body := _st()
	var lit := _st()
	var glass := _st()
	var dark := Color(0.08, 0.08, 0.09)
	var hz := L * 0.5
	# cabine na frente (cor do caminhão), para-brisa, grade, para-choque
	CM._box(body, Vector3(W, 1.5, 2.2), Vector3(0, 1.35, hz - 1.1), paint)
	CM._box(body, Vector3(W, 1.05, 1.7), Vector3(0, 2.6, hz - 1.35), paint)
	CM._box(body, Vector3(W - 0.1, 0.5, 0.06), Vector3(0, 1.25, hz + 0.01), dark)
	CM._box(body, Vector3(W + 0.1, 0.35, 0.25), Vector3(0, 0.6, hz + 0.05), Color(0.6, 0.6, 0.62))
	CM._box(glass, Vector3(W - 0.2, 0.85, 0.04), Vector3(0, 2.6, hz - 0.48), Color(0.1, 0.14, 0.18))
	for s in [-1.0, 1.0]:
		CM._box(glass, Vector3(0.03, 0.7, 1.0), Vector3((W * 0.5 + 0.005) * s, 2.6, hz - 1.3), Color(0.1, 0.14, 0.18))
		CM._ell(lit, Vector3(0.85 * s, 1.0, hz + 0.04), Vector3(0.26, 0.16, 0.05), Color(1, 0.97, 0.88))
		CM._box(body, Vector3(0.06, 0.5, 0.06), Vector3((W * 0.5 + 0.2) * s, 2.7, hz - 0.6), dark)
		CM._box(body, Vector3(0.1, 0.36, 0.24), Vector3((W * 0.5 + 0.26) * s, 2.6, hz - 0.55), dark)
		CM._ell(lit, Vector3(0.95 * s, 0.9, -hz - 0.02), Vector3(0.16, 0.22, 0.05), Color(0.95, 0.06, 0.05))
	# interior da cabine
	CM._box(body, Vector3(W - 0.3, 0.12, 0.6), Vector3(0, 1.95, hz - 1.5), Color(0.12, 0.12, 0.13))
	CM._box(body, Vector3(W - 0.3, 0.5, 0.4), Vector3(0, 2.2, hz - 0.7), Color(0.1, 0.1, 0.1))
	# chassi e baú de carga
	CM._box(body, Vector3(W - 0.6, 0.35, L - 1.0), Vector3(0, 0.75, -0.3), dark)
	CM._box(body, Vector3(W + 0.05, 2.9, L - 2.6), Vector3(0, 2.4, -1.25), Color(0.92, 0.92, 0.9))
	CM._box(body, Vector3(W + 0.07, 0.35, L - 2.6), Vector3(0, 1.1, -1.25), paint)
	CM._box(body, Vector3(0.04, 2.6, 0.06), Vector3(0, 2.4, -hz + 0.02), dark)
	var bm := MeshInstance3D.new()
	bm.mesh = body.commit()
	bm.material_override = CM.vc_mat()
	root.add_child(bm)
	var lm := MeshInstance3D.new()
	lm.mesh = lit.commit()
	lm.material_override = CM.vc_lit()
	root.add_child(lm)
	var gm := MeshInstance3D.new()
	gm.mesh = glass.commit()
	var g := StandardMaterial3D.new()
	g.vertex_color_use_as_albedo = true
	g.albedo_color = Color(1, 1, 1, 0.6)
	g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.metallic = 0.8
	g.roughness = 0.05
	gm.material_override = g
	root.add_child(gm)
	var wheels := []
	var wm := _wheel_mesh(wr, 0.32, Color(0.7, 0.7, 0.72))
	for wz in [hz - 1.2, -2.6]:
		for s in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			mi.mesh = wm
			mi.material_override = CM.vc_mat()
			if wz < 0:
				var dual := MeshInstance3D.new()
				dual.mesh = wm
				dual.material_override = CM.vc_mat()
				dual.position = Vector3(-0.3 * s, 0, 0)
				mi.add_child(dual)
			wheels.append({"node": mi, "pos": Vector3((W * 0.5 - 0.15) * s, wr, wz), "front": wz > 0})
	return {"root": root, "wheels": wheels, "wr": wr, "seat": Vector3(0.55, 1.95, hz - 1.5), "size": Vector3(W, 3.9, L)}

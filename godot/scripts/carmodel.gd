extends RefCounted
## Gerador de carros próprio (sem modelo externo): carroceria lisa feita por "loft" de seções
## transversais ao longo do comprimento, com caixas de roda, vidros, colunas, faróis, lanternas,
## grade, retrovisores e rodas com aro. Categorias: sedan, hatch, suv, pickup, sport, police.
## Frente = +Z, chão em y = 0.

const M := preload("res://scripts/mats.gd")

const KINDS := {
	"sedan": {"L": 4.65, "W": 1.82, "wb": 2.75, "wr": 0.33, "belt": 0.95,
		"top": [[-2.33, 0.6], [-2.2, 0.93], [-1.75, 1.0], [-1.25, 1.03], [-0.7, 1.42], [0.35, 1.44], [1.1, 1.0], [1.9, 0.89], [2.33, 0.66]]},
	"hatch": {"L": 4.15, "W": 1.78, "wb": 2.55, "wr": 0.31, "belt": 0.97,
		"top": [[-2.08, 1.02], [-2.03, 1.3], [-1.85, 1.42], [-1.45, 1.45], [0.3, 1.46], [0.95, 1.01], [1.7, 0.9], [2.08, 0.66]]},
	"suv": {"L": 4.75, "W": 1.92, "wb": 2.8, "wr": 0.38, "belt": 1.15,
		"top": [[-2.38, 1.5], [-2.33, 1.68], [-2.18, 1.76], [-1.6, 1.8], [0.55, 1.8], [1.25, 1.2], [2.0, 1.1], [2.38, 0.82]]},
	"pickup": {"L": 5.2, "W": 1.95, "wb": 3.2, "wr": 0.38, "belt": 1.12,
		"top": [[-2.6, 0.78], [-2.55, 1.1], [-0.45, 1.12], [-0.4, 1.78], [0.75, 1.8], [1.4, 1.2], [2.2, 1.1], [2.6, 0.82]]},
	"van": {"L": 5.0, "W": 1.98, "wb": 3.05, "wr": 0.36, "belt": 1.18,
		"top": [[-2.5, 1.86], [-2.45, 2.04], [-2.35, 2.1], [-1.4, 2.12], [1.2, 2.1], [1.7, 1.55], [2.15, 1.18], [2.5, 0.86]]},
	"offroad": {"L": 4.3, "W": 1.98, "wb": 2.55, "wr": 0.46, "belt": 1.3,
		"top": [[-2.15, 1.7], [-2.1, 1.9], [-2.02, 1.98], [0.4, 2.0], [0.85, 1.4], [1.75, 1.32], [2.15, 1.0]]},
	"super": {"L": 4.55, "W": 2.02, "wb": 2.7, "wr": 0.35, "belt": 0.74,
		"top": [[-2.28, 0.55], [-2.12, 0.86], [-1.3, 0.92], [-0.7, 1.1], [0.15, 1.13], [0.95, 0.8], [1.85, 0.6], [2.28, 0.48]]},
	"sport": {"L": 4.45, "W": 1.95, "wb": 2.65, "wr": 0.34, "belt": 0.82,
		"top": [[-2.23, 0.6], [-2.15, 0.86], [-1.6, 0.92], [-0.85, 1.18], [0.15, 1.22], [1.0, 0.86], [1.85, 0.74], [2.23, 0.55]]},
}

## Devolve {"root": Node3D com a carroceria, "wheels": [{"node": Node3D, "pos": Vector3, "front": bool}], "wr": raio, "seat": Vector3, "size": Vector3}
static func build(kind: String, paint: Color) -> Dictionary:
	var police := kind == "police"
	var taxi := kind == "taxi"
	if taxi:
		paint = Color(0.95, 0.72, 0.05)
	var k: Dictionary = KINDS["sedan" if police or taxi else kind]
	var L: float = k.L
	var W: float = k.W
	var wb: float = k.wb
	var wr: float = k.wr
	var belt: float = k.belt
	var top: Array = k.top
	var wheel_z := [wb * 0.5 + 0.02, -wb * 0.5 + 0.02]
	var NZ := 56
	var paint_m: Material = M.car_paint(Color(0.04, 0.04, 0.05) if police else paint)
	var door_m: Material = M.car_paint(Color(0.93, 0.93, 0.94)) if police else paint_m
	var glass_m := StandardMaterial3D.new()
	glass_m.albedo_color = Color(0.05, 0.07, 0.09, 0.62)
	glass_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_m.metallic = 0.85
	glass_m.roughness = 0.04
	var trim_m := M.plain(Color(0.05, 0.05, 0.055), 0.6)
	var st_p := SurfaceTool.new()
	var st_d := SurfaceTool.new()
	var st_g := SurfaceTool.new()
	var st_t := SurfaceTool.new()
	for s in [st_p, st_d, st_g, st_t]:
		s.begin(Mesh.PRIMITIVE_TRIANGLES)
		s.set_smooth_group(0)
	# --- anéis de seção ---
	var rings: Array = []
	var meta: Array = []
	var roof_max := 0.0
	for p in top:
		roof_max = maxf(roof_max, p[1])
	for i in NZ + 1:
		var z := lerpf(-L * 0.5, L * 0.5, float(i) / NZ)
		var yt := _top(top, z)
		var slope := absf(_top(top, z + 0.05) - _top(top, z - 0.05)) / 0.1
		var e := clampf((absf(z) - (L * 0.5 - 0.65)) / 0.65, 0.0, 1.0)
		var hw := W * 0.5 * (1.0 - 0.18 * e * e)
		var yb := 0.24 + 0.14 * e * e
		for wz in wheel_z:
			var d := absf(z - wz)
			var ra := wr + 0.07
			if d < ra:
				yb = maxf(yb, wr + sqrt(ra * ra - d * d))
		var bl := minf(yt, belt + (0.03 if z < 0.0 else 0.0))
		var g := clampf((yt - bl) / maxf(0.05, roof_max - belt), 0.0, 1.0)
		var r := [
			Vector2(0, yb), Vector2(hw * 0.82, yb), Vector2(hw * 0.97, yb + 0.05),
			Vector2(hw, lerpf(yb, bl, 0.35)), Vector2(hw * 0.995, lerpf(yb, bl, 0.78)),
			Vector2(hw * 0.965, bl), Vector2(hw * 0.9, bl + 0.025 * (1.0 - g) + 0.01),
			Vector2(lerpf(hw * 0.78, hw * 0.86, g), bl + (yt - bl) * 0.5 + 0.01),
			Vector2(lerpf(hw * 0.56, hw * 0.74, g), yt - 0.015 * g),
			Vector2(lerpf(hw * 0.28, hw * 0.42, g), yt + 0.012),
			Vector2(0, yt + 0.025)]
		rings.append([z, r])
		meta.append({"g": g, "slope": slope, "yt": yt, "bl": bl})
	# --- quads ---
	var b_pillar: float = (top[3][0] + top[5][0]) * 0.5 if kind != "pickup" else 0.2
	# porta do motorista (+x) e tampa do porta-malas são recortadas da carroceria e vão para nós próprios
	var zc0 := _first_cabin_z(top, belt, false)
	var zc1 := _first_cabin_z(top, belt, true)
	var d_zf := zc1 - 0.05
	var d_zb: float = b_pillar if kind != "pickup" else zc0 + 0.1
	var d_piv := Vector3(W * 0.5, 0.0, d_zf)
	var t_piv := Vector3(0.0, _top(top, zc0 - 0.12), zc0 - 0.12)
	var has_trunk: bool = kind in ["sedan", "sport", "police", "taxi", "super"] or (kind == "hatch")
	var dst := {}
	var tst := {}
	for kst in [st_p, st_d, st_g, st_t]:
		var sa := SurfaceTool.new()
		sa.begin(Mesh.PRIMITIVE_TRIANGLES)
		dst[kst] = sa
		var sb := SurfaceTool.new()
		sb.begin(Mesh.PRIMITIVE_TRIANGLES)
		tst[kst] = sb
	# capô: recortado da carroceria (dobradiça junto ao para-brisa) — amassa e abre nas batidas de frente
	var h_z0 := zc1 + 0.08
	var h_z1 := L * 0.5 - 0.2
	var h_piv := Vector3(0.0, _top(top, h_z0), h_z0)
	var has_hood: bool = h_z1 - h_z0 > 0.45
	var hst := {}
	for kst in [st_p, st_d, st_g, st_t]:
		var sh := SurfaceTool.new()
		sh.begin(Mesh.PRIMITIVE_TRIANGLES)
		hst[kst] = sh
	var h_in := SurfaceTool.new()
	h_in.begin(Mesh.PRIMITIVE_TRIANGLES)
	var d_in := SurfaceTool.new()
	d_in.begin(Mesh.PRIMITIVE_TRIANGLES)
	var t_in := SurfaceTool.new()
	t_in.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in NZ:
		var z0: float = rings[i][0]
		var z1: float = rings[i + 1][0]
		var r0: Array = rings[i][1]
		var r1: Array = rings[i + 1][1]
		var m0: Dictionary = meta[i]
		var m1: Dictionary = meta[i + 1]
		var zc := (z0 + z1) * 0.5
		var g := minf(m0.g, m1.g)
		var slope := maxf(m0.slope, m1.slope)
		for side in [1.0, -1.0]:
			for j in 10:
				var a0: Vector2 = r0[j]
				var a1: Vector2 = r0[j + 1]
				var b0: Vector2 = r1[j]
				var b1: Vector2 = r1[j + 1]
				var p00 := Vector3(a0.x * side, a0.y, z0)
				var p01 := Vector3(a1.x * side, a1.y, z0)
				var p10 := Vector3(b0.x * side, b0.y, z1)
				var p11 := Vector3(b1.x * side, b1.y, z1)
				var st := st_p
				if j <= 1:
					st = st_t
				elif j >= 6 and j <= 7:
					if g > 0.55 and absf(zc - b_pillar) > 0.07:
						st = st_g
					elif police and j >= 2 and j <= 4:
						st = st_d
				elif j >= 8:
					if g > 0.3 and slope > 0.32:
						st = st_g
				if police and j >= 3 and j <= 5 and absf(zc) < 1.1:
					st = st_d
				if j == 2 and absf(zc) > L * 0.5 - 0.45:
					st = st_t
				var in_door: bool = side > 0 and j >= 2 and j <= 7 and zc > d_zb and zc < d_zf
				var in_trunk: bool = has_trunk and j >= 8 and zc < zc0 - 0.12 and zc > -L * 0.5 + 0.12
				var in_hood: bool = has_hood and j >= 7 and zc > h_z0 and zc < h_z1 and st != st_g
				if in_hood:
					var o3 := h_piv
					if side > 0:
						_quad(hst[st], p00 - o3, p10 - o3, p11 - o3, p01 - o3)
						_quad(h_in, p00 - o3 + Vector3(0, -0.03, 0), p01 - o3 + Vector3(0, -0.03, 0), p11 - o3 + Vector3(0, -0.03, 0), p10 - o3 + Vector3(0, -0.03, 0))
					else:
						_quad(hst[st], p00 - o3, p01 - o3, p11 - o3, p10 - o3)
						_quad(h_in, p00 - o3 + Vector3(0, -0.03, 0), p10 - o3 + Vector3(0, -0.03, 0), p11 - o3 + Vector3(0, -0.03, 0), p01 - o3 + Vector3(0, -0.03, 0))
				elif in_door:
					var o := d_piv
					_quad(dst[st], p00 - o, p10 - o, p11 - o, p01 - o)
					if j <= 5:      # face interna só na chapa (abaixo do vidro): antes cobria a janela de preto
						_quad(d_in, p00 - o + Vector3(-0.03, 0, 0), p01 - o + Vector3(-0.03, 0, 0), p11 - o + Vector3(-0.03, 0, 0), p10 - o + Vector3(-0.03, 0, 0))
				elif in_trunk:
					var o2 := t_piv
					if side > 0:
						_quad(tst[st], p00 - o2, p10 - o2, p11 - o2, p01 - o2)
						_quad(t_in, p00 - o2 + Vector3(0, -0.03, 0), p01 - o2 + Vector3(0, -0.03, 0), p11 - o2 + Vector3(0, -0.03, 0), p10 - o2 + Vector3(0, -0.03, 0))
					else:
						_quad(tst[st], p00 - o2, p01 - o2, p11 - o2, p10 - o2)
						_quad(t_in, p00 - o2 + Vector3(0, -0.03, 0), p10 - o2 + Vector3(0, -0.03, 0), p11 - o2 + Vector3(0, -0.03, 0), p01 - o2 + Vector3(0, -0.03, 0))
				elif side > 0:
					_quad(st, p00, p10, p11, p01)
				else:
					_quad(st, p00, p01, p11, p10)
	# tampas da frente e de trás
	var cap_p := SurfaceTool.new()
	var cap_t := SurfaceTool.new()
	cap_p.begin(Mesh.PRIMITIVE_TRIANGLES)
	cap_t.begin(Mesh.PRIMITIVE_TRIANGLES)
	for end in [0, NZ]:
		var z: float = rings[end][0]
		var r: Array = rings[end][1]
		var c := Vector3(0, (r[0].y + r[10].y) * 0.5, z)
		for side in [1.0, -1.0]:
			for j in 10:
				var a := Vector3(r[j].x * side, r[j].y, z)
				var b := Vector3(r[j + 1].x * side, r[j + 1].y, z)
				var front: bool = end == NZ
				var cw: bool = (side > 0) != front      # (estava invertido: a tampa de trás sumia)
				# tampas em malhas próprias: normais retas (antes se misturavam com as laterais e a
				# traseira da van/SUV ficava escura)
				if cw:
					_tri(cap_t if j < 3 else cap_p, c, a, b)
				else:
					_tri(cap_t if j < 3 else cap_p, c, b, a)
	var root := Node3D.new()
	root.name = "Carroceria"
	_add(root, st_p, paint_m)
	_add(root, st_d, door_m)
	_add(root, st_g, glass_m)
	_add(root, st_t, trim_m)
	_add_flat(root, cap_p, paint_m)
	_add_flat(root, cap_t, trim_m)
	var inner_m := M.plain(Color(0.07, 0.07, 0.075), 0.9)
	var door_node := Node3D.new()
	door_node.name = "porta"
	door_node.position = d_piv
	root.add_child(door_node)
	var mats := {st_p: paint_m, st_d: door_m, st_g: glass_m, st_t: trim_m}
	for kd in dst:
		_add(door_node, dst[kd], mats[kd])
	_add(door_node, d_in, inner_m)
	var trunk_node: Node3D = null
	if has_trunk:
		trunk_node = Node3D.new()
		trunk_node.name = "portamalas"
		trunk_node.position = t_piv
		root.add_child(trunk_node)
		for kt in tst:
			_add(trunk_node, tst[kt], mats[kt])
		_add(trunk_node, t_in, inner_m)
	var hood_node: Node3D = null
	if has_hood:
		hood_node = Node3D.new()
		hood_node.name = "capo"
		hood_node.position = h_piv
		root.add_child(hood_node)
		for kh in hst:
			_add(hood_node, hst[kh], mats[kh])
		_add(hood_node, h_in, inner_m)
		# vão do motor (visto quando o capô abre/amassa)
		var bay := SurfaceTool.new()
		bay.begin(Mesh.PRIMITIVE_TRIANGLES)
		var hb := (h_z1 - h_z0)
		_box(bay, Vector3(W * 0.7, 0.05, hb), Vector3(0, _top(top, h_z0 + hb * 0.5) - 0.32, h_z0 + hb * 0.5), Color(0.06, 0.06, 0.065))
		_box(bay, Vector3(W * 0.42, 0.22, hb * 0.6), Vector3(0, _top(top, h_z0 + hb * 0.5) - 0.2, h_z0 + hb * 0.5), Color(0.25, 0.26, 0.28))
		_commit(root, bay, vc_mat())
	# --- para-choques: peças próprias (amassam, ficam penduradas e caem em batida forte) ---
	var bumpers := {}
	for bs in [1.0, -1.0]:
		var bn := Node3D.new()
		bn.name = "pc_d" if bs > 0.0 else "pc_t"
		var zb: float = (L * 0.5 - 0.05) * bs
		bn.position = Vector3(0, 0.37, zb)
		root.add_child(bn)
		var bst := SurfaceTool.new()
		bst.begin(Mesh.PRIMITIVE_TRIANGLES)
		_ell(bst, Vector3.ZERO, Vector3(W * 0.88, 0.2, 0.22), Color.WHITE)
		var bmi := MeshInstance3D.new()
		bmi.mesh = bst.commit()
		bmi.material_override = paint_m
		bmi.name = "pc_body"
		bn.add_child(bmi)
		var lst := SurfaceTool.new()
		lst.begin(Mesh.PRIMITIVE_TRIANGLES)
		_box(lst, Vector3(W * 0.8, 0.07, 0.2), Vector3(0, -0.12, 0.04 * bs), Color(0.05, 0.05, 0.055))
		_box(lst, Vector3(0.5, 0.12, 0.02), Vector3(0, 0.0, 0.13 * bs), Color(0.92, 0.92, 0.9))      # placa
		_commit(bn, lst, vc_mat())
		bumpers[bs] = bn
	# --- detalhes (fundidos: 1 malha com cor por vértice + 1 malha de luzes) ---
	var det := SurfaceTool.new()
	det.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lit := SurfaceTool.new()
	var litf := SurfaceTool.new()
	litf.begin(Mesh.PRIMITIVE_TRIANGLES)
	lit.begin(Mesh.PRIMITIVE_TRIANGLES)
	var zf := L * 0.5
	var yf: float = _top(top, zf - 0.15)
	var hwf := W * 0.5 * 0.84
	var head_c := Color(1.0, 0.97, 0.88)
	var tail_c := Color(0.95, 0.06, 0.05)
	var chrome := Color(0.78, 0.79, 0.8)
	var pc: Color = Color(0.04, 0.04, 0.05) if police else paint
	var za := _first_cabin_z(top, belt, true)
	for s in [-1.0, 1.0]:
		_ell(litf, Vector3(hwf * 0.72 * s, maxf(yf - 0.08, 0.56), zf - 0.03), Vector3(0.36, 0.11, 0.14), head_c)
		var ty := minf(_top(top, -zf + 0.15) - 0.1, belt + 0.08)
		if top[0][1] > belt + 0.2:
			_box(lit, Vector3(0.12, 0.42, 0.06), Vector3(W * 0.5 * 0.78 * s, belt - 0.05, -zf - 0.01), tail_c)   # lanterna vertical
		else:
			_ell(lit, Vector3(hwf * 0.75 * s, ty, -zf + 0.06), Vector3(0.34, 0.09, 0.1), tail_c)
		_ell(det, Vector3((W * 0.5 + 0.06) * s, belt + 0.1, za - 0.15), Vector3(0.14, 0.09, 0.2), pc)
		_ell(det, Vector3((W * 0.5 - 0.01) * s, belt - 0.08, 0.25), Vector3(0.03, 0.03, 0.14), chrome)
		_ell(det, Vector3((W * 0.5 - 0.01) * s, belt - 0.08, -0.75), Vector3(0.03, 0.03, 0.14), chrome)
	_ell(det, Vector3(0, yf - 0.22, zf - 0.03), Vector3(0.75, 0.13, 0.06), Color(0.05, 0.05, 0.055))
	# interior: bancos da frente logo atrás do volante (antes ficavam no meio da cabine: na van o
	# motorista ia sentado lá atrás), banco traseiro só em cabine longa; altura pela linha de cintura
	var seat_c := Color(0.09, 0.09, 0.1)
	var seat_y := clampf(belt - 0.45, 0.36, 0.85)
	var drv_z := maxf(zc1 - 1.15, zc0 + 0.5)
	var z_lo := maxf(zc0 - 0.1, -L * 0.5 + 0.45)
	var z_hi := zc1 + 0.12
	var floor_y := minf(0.36, seat_y - 0.12)
	for s in [-1.0, 1.0]:
		var bz := drv_z - 0.3
		var bh := clampf(_top(top, bz) - 0.14 - seat_y, 0.25, 0.62)
		_box(det, Vector3(0.48, 0.12, 0.5), Vector3(0.38 * s, seat_y, drv_z), seat_c)
		_box(det, Vector3(0.48, seat_y - floor_y, 0.4), Vector3(0.38 * s, (seat_y + floor_y) * 0.5, drv_z), Color(0.06, 0.06, 0.065))
		_box(det, Vector3(0.48, bh, 0.12), Vector3(0.38 * s, seat_y + 0.01 + bh * 0.5, bz), seat_c)
	var rear_z := drv_z - 0.95
	if rear_z - 0.3 > z_lo + 0.1 and kind != "pickup":
		var rbh := clampf(_top(top, rear_z - 0.3) - 0.14 - seat_y, 0.25, 0.58)
		_box(det, Vector3(W * 0.74, 0.12, 0.5), Vector3(0, seat_y, rear_z), seat_c)
		_box(det, Vector3(W * 0.74, rbh, 0.12), Vector3(0, seat_y + 0.01 + rbh * 0.5, rear_z - 0.3), seat_c)
	# forro interno da cabine: assoalho, laterais, parede traseira e painel — dentro da lataria (antes
	# era maior que a carroceria e saía como uma "caixa preta" atrás da van/SUV/hatch/jipe)
	var cab_mid := (z_lo + z_hi) * 0.5
	var cab_len := z_hi - z_lo
	var lining := Color(0.16, 0.15, 0.15)
	var hw_in := W * 0.5 * (1.0 - 0.18 * pow(clampf((absf(z_lo) - (L * 0.5 - 0.65)) / 0.65, 0.0, 1.0), 2.0)) - 0.12
	_box(det, Vector3(hw_in * 2.0, 0.05, cab_len), Vector3(0, floor_y, cab_mid), Color(0.07, 0.07, 0.075))
	for s in [-1.0, 1.0]:
		# laterais subdivididas: amassam junto com a lataria (senão apareciam pelo amassado)
		var lb := BoxMesh.new()
		lb.size = Vector3(0.05, belt - floor_y - 0.02, cab_len)
		lb.subdivide_depth = int(cab_len / 0.15)
		lb.subdivide_height = 4
		_prim(det, lb, Transform3D(Basis(), Vector3(s * hw_in, (belt + floor_y) * 0.5, cab_mid)), lining)
	_box(det, Vector3(hw_in * 2.0, belt - floor_y - 0.02, 0.05), Vector3(0, (belt + floor_y) * 0.5, z_lo), lining)
	_box(det, Vector3(W * 0.86, belt - 0.3, 0.05), Vector3(0, (belt + 0.36) * 0.5, z_hi), Color(0.05, 0.05, 0.055))
	_box(det, Vector3(W * 0.8, 0.14, 0.4), Vector3(0, belt + 0.02, zc1 - 0.15), Color(0.06, 0.06, 0.065))   # painel
	_ell(det, Vector3(0.38, belt - 0.04, drv_z + 0.6), Vector3(0.34, 0.3, 0.04), Color(0.04, 0.04, 0.045))   # volante
	_box(det, Vector3(0.05, 0.05, 0.3), Vector3(0.38, belt - 0.07, drv_z + 0.74), Color(0.04, 0.04, 0.045))   # coluna de direção
	# traseira reta (van/SUV/hatch/jipe): vidro traseiro na tampa
	var yr: float = top[0][1]
	if yr > belt + 0.2:
		var hwr := W * 0.5 * 0.82
		_box(det, Vector3(hwr * 1.5, yr - belt - 0.22, 0.03), Vector3(0, (yr + belt) * 0.5 + 0.02, -L * 0.5 - 0.005), Color(0.04, 0.06, 0.08))
	if kind == "pickup":
		_box(det, Vector3(W * 0.86, 0.05, 1.9), Vector3(0, 1.06, -1.5), Color(0.1, 0.1, 0.11))
	if kind == "offroad":
		# para-choque de impulsão, estepe atrás, rack no teto e faróis auxiliares
		_box(det, Vector3(W * 0.9, 0.35, 0.12), Vector3(0, 0.75, L * 0.5 + 0.1), Color(0.1, 0.1, 0.11))
		_prim(det, preload("res://scripts/vehmodel.gd")._cyl(0.42, 0.26, 16), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.25, -L * 0.5 - 0.14)), Color(0.05, 0.05, 0.05))
		_box(det, Vector3(W * 0.8, 0.06, 1.6), Vector3(0, 2.08, -0.6), Color(0.15, 0.15, 0.16))
		for s in [-1.0, 1.0]:
			_box(det, Vector3(0.05, 0.12, 1.6), Vector3(s * W * 0.38, 2.12, -0.6), Color(0.15, 0.15, 0.16))
			_ell(litf, Vector3(0.35 * s, 2.15, 0.3), Vector3(0.14, 0.1, 0.05), head_c)
	if kind == "van":
		for s in [-1.0, 1.0]:
			_box(det, Vector3(0.02, 0.06, 2.4), Vector3(s * (W * 0.5 + 0.005), 1.1, -0.3), Color(0.12, 0.12, 0.13))   # trilho da porta corrediça
	if kind == "super":
		_box(det, Vector3(W * 0.9, 0.05, 0.4), Vector3(0, 1.0, -L * 0.5 + 0.25), Color(0.05, 0.05, 0.06))     # aerofólio
		for s in [-1.0, 1.0]:
			_box(det, Vector3(0.05, 0.3, 0.12), Vector3(s * W * 0.35, 0.85, -L * 0.5 + 0.3), Color(0.05, 0.05, 0.06))
	if police:
		_box(det, Vector3(1.2, 0.1, 0.3), Vector3(0, _top(top, 0.0) + 0.07, -0.1), Color(0.1, 0.1, 0.12))
	if taxi:
		_box(lit, Vector3(0.7, 0.22, 0.3), Vector3(0, _top(top, 0.0) + 0.14, -0.1), Color(1.0, 0.9, 0.35))
		_box(det, Vector3(0.74, 0.04, 0.34), Vector3(0, _top(top, 0.0) + 0.02, -0.1), Color(0.1, 0.1, 0.1))
		for zz in range(-10, 11):
			_box(det, Vector3(0.02, 0.08, 0.16), Vector3(W * 0.5 - 0.02, 0.62, zz * 0.18), Color(0.05, 0.05, 0.05) if zz % 2 == 0 else Color(0.95, 0.95, 0.95))
			_box(det, Vector3(0.02, 0.08, 0.16), Vector3(-W * 0.5 + 0.02, 0.62, zz * 0.18), Color(0.05, 0.05, 0.05) if zz % 2 == 0 else Color(0.95, 0.95, 0.95))
	_commit(root, det, vc_mat())
	_commit(root, lit, vc_lit())
	_commit(root, litf, vc_lit())
	root.get_child(root.get_child_count() - 1).name = "lights_front"
	# --- rodas (1 malha cada: pneu + aro + raios) ---
	var wheels := []
	var tire := CylinderMesh.new()
	tire.top_radius = wr
	tire.bottom_radius = wr
	tire.height = 0.24
	tire.radial_segments = 20
	tire.rings = 1
	var rimm := CylinderMesh.new()
	rimm.top_radius = wr * 0.66
	rimm.bottom_radius = wr * 0.66
	rimm.height = 0.245
	rimm.radial_segments = 16
	rimm.rings = 1
	var spoke := BoxMesh.new()
	spoke.size = Vector3(0.03, wr * 1.2, 0.06)
	var wmesh := {}
	for s in [-1.0, 1.0]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rz := Basis(Vector3.FORWARD, PI * 0.5)
		_prim(st, tire, Transform3D(rz, Vector3.ZERO), Color(0.06, 0.06, 0.065))
		_prim(st, rimm, Transform3D(rz, Vector3.ZERO), Color(0.55, 0.56, 0.58))
		for q in 5:
			_prim(st, spoke, Transform3D(Basis(Vector3.RIGHT, q * TAU / 5.0), Vector3(0.125 * s, 0, 0)), Color(0.82, 0.82, 0.84))
		wmesh[s] = st.commit()
	for wz in wheel_z:
		for s in [-1.0, 1.0]:
			var n := MeshInstance3D.new()
			n.mesh = wmesh[s]
			n.material_override = vc_mat()
			wheels.append({"node": n, "pos": Vector3((W * 0.5 - 0.15) * s, wr, wz), "front": wz > 0})
	var seat_z := drv_z
	var door := {"zf": d_zf, "zb": d_zb, "y0": 0.32, "y1": belt + 0.02, "x": W * 0.5, "node": door_node, "trunk": trunk_node, "trunk_z": zc0, "L": L, "hood": hood_node, "bumpers": bumpers, "hood_z": [h_z0, h_z1]}
	return {"root": root, "wheels": wheels, "wr": wr, "seat": Vector3(0.38, seat_y, seat_z), "size": Vector3(W, roof_max, L), "door": door, "paint": paint}

static func _first_cabin_z(top: Array, belt: float, front: bool) -> float:
	# z onde o teto (vidro) encontra a linha de cintura, na frente ou atrás
	var a := -3.0
	var b := 3.0
	var best := 0.0
	var steps := 120
	for i in steps + 1:
		var z := lerpf(-2.6, 2.6, float(i) / steps)
		if _top(top, z) > belt + 0.25:
			if not front and best == 0.0:
				return z
			best = z
	return best

static func _top(pts: Array, z: float) -> float:
	# Catmull-Rom sobre os pontos [z, y]
	var n := pts.size()
	if z <= pts[0][0]: return pts[0][1]
	if z >= pts[n - 1][0]: return pts[n - 1][1]
	for i in n - 1:
		if z <= pts[i + 1][0]:
			var p0 = pts[maxi(i - 1, 0)]
			var p1 = pts[i]
			var p2 = pts[i + 1]
			var p3 = pts[mini(i + 2, n - 1)]
			var t: float = (z - p1[0]) / maxf(0.0001, p2[0] - p1[0])
			var t2 := t * t
			var t3 := t2 * t
			var y: float = 0.5 * ((2.0 * p1[1]) + (-p0[1] + p2[1]) * t + (2.0 * p0[1] - 5.0 * p1[1] + 4.0 * p2[1] - p3[1]) * t2 + (-p0[1] + 3.0 * p1[1] - 3.0 * p2[1] + p3[1]) * t3)
			return clampf(y, minf(p1[1], p2[1]) - 0.03, maxf(p1[1], p2[1]) + 0.03)
	return pts[n - 1][1]

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

## tampa: cada triângulo com a própria normal (sem suavizar com as laterais)
static func _add_flat(root: Node3D, st: SurfaceTool, mat: Material) -> void:
	st.generate_normals()
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.name = "tampas"
	root.add_child(mi)

static func _add(root: Node3D, st: SurfaceTool, mat: Material) -> void:
	st.index()
	st.generate_normals()
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	root.add_child(mi)

static var _vc: StandardMaterial3D
static var _vl: StandardMaterial3D

static func vc_mat() -> StandardMaterial3D:
	if _vc == null:
		_vc = StandardMaterial3D.new()
		_vc.vertex_color_use_as_albedo = true
		_vc.vertex_color_is_srgb = true
		_vc.roughness = 0.45
		_vc.metallic = 0.3
	return _vc

static func vc_lit() -> StandardMaterial3D:
	if _vl == null:
		_vl = StandardMaterial3D.new()
		_vl.vertex_color_use_as_albedo = true
		_vl.vertex_color_is_srgb = true
		_vl.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _vl

static func _prim(st: SurfaceTool, mesh: Mesh, xf: Transform3D, col: Color) -> void:
	var arr: Array = mesh.get_mesh_arrays()
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for i in ix:
		st.set_color(col)
		st.set_normal((xf.basis * ns[i]).normalized())
		st.add_vertex(xf * vs[i])

static var _sph: SphereMesh
static func _ell(st: SurfaceTool, pos: Vector3, size: Vector3, col: Color) -> void:
	if _sph == null:
		_sph = SphereMesh.new()
		_sph.radius = 0.5
		_sph.height = 1.0
		_sph.radial_segments = 10
		_sph.rings = 5
	_prim(st, _sph, Transform3D(Basis().scaled(size), pos), col)

static func _box(st: SurfaceTool, size: Vector3, pos: Vector3, col: Color) -> void:
	var b := BoxMesh.new()
	b.size = size
	_prim(st, b, Transform3D(Basis(), pos), col)

static func _commit(root: Node3D, st: SurfaceTool, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	root.add_child(mi)

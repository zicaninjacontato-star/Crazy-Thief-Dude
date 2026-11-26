extends Node3D
## Corpo humano (provisório até termos um modelo com esqueleto): 10 ossos, cada um uma malha só
## (todas as partes do osso fundidas, 1 material com cor por vértice → poucas draw calls).
## Animação procedural de andar/correr/sentar e ragdoll físico de verdade (RigidBody3D + juntas).

const M := preload("res://scripts/mats.gd")
const FXW := preload("res://scripts/fx.gd")

static var _mat: StandardMaterial3D

var phase := 0.0
var sitting := false
var bones := {}          # nome -> Node3D (pivô)
var spec := {}           # nome -> {len, rad, parent, mass}
var skin_c := Color.WHITE
var ragdolled := false
var parts: Array = []    # RigidBody3D do ragdoll
var aiming := false
var punch_t := 0.0
var punch_kind := 0      # 0 direto direita, 1 direto esquerda, 2 chute
var swimming := false
var moto_pose := false
var guard := false       # guarda alta (modo luta)
var arm_pose := ""       # só os braços: "handsup" (rendido), "phone" (ligando para a polícia)
var hurt_t := 0.0        # reação a um soco (cabeça e tronco jogados para trás)
var hurt_side := 1.0
var rag_alive := false   # o próximo ragdoll é só uma derrubada (vai levantar): músculos mais firmes
var limp := 0.0          # 0..1: mancando (tiro na perna)
var arm_hurt := 0.0      # >0: segurando o braço ferido
var throw_t := 0.0
var dive := false
var crouching := false
var slumped := false
var pose := ""            # vault, climb, carry, drag, tackle, pull, break, lockpick, cover, carried
var pose_t := 0.0
var gun_kind := ""
var aim_pitch := 0.0
var reload_t := 0.0
var reload_dur := 1.0
var gun: Node3D

## arma na mão direita (apontando para frente quando o braço está esticado)
## ponta do cano da arma na mão (o tiro sai daqui); fallback = peito
func muzzle_pos(fallback: Vector3) -> Vector3:
	if gun == null or not is_instance_valid(gun) or not gun.visible or gun_kind in ["", "fist", "grenade"]:
		return fallback
	var L: float = {"pistol": 0.22, "smg": 0.42, "rifle": 0.85, "sniper": 0.85, "shotgun": 0.75, "rpg": 0.65}.get(gun_kind, 0.3)
	var tip: Vector3 = gun.global_transform * Vector3(0, -L + 0.04, 0.03)
	return tip if tip.distance_to(fallback) < 1.6 else fallback

func give_gun(g: Node3D) -> void:
	if gun:
		gun.queue_free()
	gun = g
	bones.foreR.add_child(g)
	g.position = Vector3(0, -0.33, 0.02)

static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.vertex_color_is_srgb = true
		_mat.roughness = 0.78
	return _mat

## ex (opcional): jacket (Color, alfa 0 = sem), hat (0 nenhum, 1 boné, 2 touca), hat_c (Color), glasses (bool)
var _pc := [Color.WHITE, Color.GRAY, Color.WHITE]
func build(shirt: Color, pants: Color, skin: Color, hair: Color, ex := {}) -> void:
	skin_c = skin
	_pc = [shirt if not ex.get("beach", false) else skin, pants, skin]
	var shoe := Color(0.07, 0.07, 0.08)
	var shin_c := pants
	if ex.get("beach", false):
		# praia: sem camiseta, de short e descalço
		shirt = skin
		shin_c = skin
		shoe = skin.darkened(0.1)
	# ossos (pivôs)
	_bone("hips", null, Vector3(0, 0.98, 0))
	_bone("chest", "hips", Vector3(0, 0.08, 0))
	_bone("head", "chest", Vector3(0, 0.6, 0))
	for s in [-1.0, 1.0]:
		var sd := "L" if s < 0 else "R"
		_bone("thigh" + sd, "hips", Vector3(0.1 * s, 0.0, 0))
		_bone("shin" + sd, "thigh" + sd, Vector3(0, -0.47, 0))
		_bone("upper" + sd, "chest", Vector3(0.22 * s, 0.47, 0))
		_bone("fore" + sd, "upper" + sd, Vector3(0, -0.29, 0))
	# geometria fundida por osso
	_mesh("hips", [[_cap(0.17, 0.32), Transform3D(Basis().scaled(Vector3(1.05, 1, 0.75)), Vector3(0, 0.02, 0)), pants]])
	var jacket: Color = ex.get("jacket", Color(0, 0, 0, 0))
	var has_j := jacket.a > 0.5
	var chest_items := [[_cap(0.19, 0.58), Transform3D(Basis().scaled(Vector3(1.0, 1, 0.68)), Vector3(0, 0.26, 0)), shirt],
		[_cap(0.055, 0.14), Transform3D(Basis(), Vector3(0, 0.56, 0)), skin]]
	if has_j:
		# jaqueta aberta: casca um pouco maior + camiseta aparecendo na frente + gola
		chest_items.append([_cap(0.2, 0.56), Transform3D(Basis().scaled(Vector3(1.04, 1, 0.72)), Vector3(0, 0.25, -0.004)), jacket])
		chest_items.append([_box(Vector3(0.11, 0.36, 0.03)), Transform3D(Basis(), Vector3(0, 0.27, 0.138)), shirt])
		chest_items.append([_box(Vector3(0.3, 0.06, 0.2)), Transform3D(Basis(), Vector3(0, 0.5, -0.01)), jacket.darkened(0.15)])
	_mesh("chest", chest_items)
	var head_items := [[_sph(0.115), Transform3D(Basis().scaled(Vector3(0.9, 1.08, 1.0)), Vector3(0, 0.12, 0)), skin],
		[_sph(0.12), Transform3D(Basis().scaled(Vector3(0.96, 0.82, 1.02)), Vector3(0, 0.17, -0.015)), hair],
		[_sph(0.018), Transform3D(Basis(), Vector3(-0.04, 0.13, 0.103)), Color(0.04, 0.04, 0.04)],
		[_sph(0.018), Transform3D(Basis(), Vector3(0.04, 0.13, 0.103)), Color(0.04, 0.04, 0.04)],
		[_sph(0.022), Transform3D(Basis().scaled(Vector3(1, 1.2, 1)), Vector3(0, 0.1, 0.113)), skin],
		[_sph(0.03), Transform3D(Basis().scaled(Vector3(0.4, 1, 0.7)), Vector3(-0.11, 0.12, 0)), skin],
		[_sph(0.03), Transform3D(Basis().scaled(Vector3(0.4, 1, 0.7)), Vector3(0.11, 0.12, 0)), skin]]
	var hat: int = ex.get("hat", 0)
	var hat_c: Color = ex.get("hat_c", Color(0.1, 0.1, 0.12))
	if hat == 1:
		head_items.append([_sph(0.125), Transform3D(Basis().scaled(Vector3(0.98, 0.62, 1.02)), Vector3(0, 0.2, -0.01)), hat_c])
		head_items.append([_box(Vector3(0.2, 0.018, 0.13)), Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(0, 0.205, 0.13)), hat_c.darkened(0.1)])
	elif hat == 2:
		head_items.append([_sph(0.128), Transform3D(Basis().scaled(Vector3(0.97, 0.8, 1.0)), Vector3(0, 0.205, -0.012)), hat_c])
		head_items.append([_sph(0.035), Transform3D(Basis(), Vector3(0, 0.31, -0.015)), hat_c.lightened(0.2)])
	if ex.get("glasses", false):
		var gl := Color(0.03, 0.03, 0.035)
		for gx in [-0.045, 0.045]:
			head_items.append([_box(Vector3(0.07, 0.04, 0.012)), Transform3D(Basis(), Vector3(gx, 0.135, 0.112)), gl])
		head_items.append([_box(Vector3(0.21, 0.012, 0.012)), Transform3D(Basis(), Vector3(0, 0.145, 0.11)), gl])
	_mesh("head", head_items)
	for sd in ["L", "R"]:
		_mesh("thigh" + sd, [[_cap(0.085, 0.5), Transform3D(Basis(), Vector3(0, -0.23, 0)), pants]])
		_mesh("shin" + sd, [[_cap(0.065, 0.48), Transform3D(Basis(), Vector3(0, -0.23, 0)), shin_c],
			[_box(Vector3(0.11, 0.08, 0.27)), Transform3D(Basis(), Vector3(0, -0.47, 0.05)), shoe]])
		if has_j:
			_mesh("upper" + sd, [[_cap(0.066, 0.33), Transform3D(Basis(), Vector3(0, -0.14, 0)), jacket]])
			_mesh("fore" + sd, [[_cap(0.054, 0.22), Transform3D(Basis(), Vector3(0, -0.1, 0)), jacket], [_cap(0.047, 0.28), Transform3D(Basis(), Vector3(0, -0.13, 0)), skin],
				[_sph(0.05), Transform3D(Basis().scaled(Vector3(0.8, 1.1, 0.6)), Vector3(0, -0.3, 0)), skin]])
			continue
		_mesh("upper" + sd, [[_cap(0.06, 0.32), Transform3D(Basis(), Vector3(0, -0.14, 0)), shirt]])
		_mesh("fore" + sd, [[_cap(0.047, 0.28), Transform3D(Basis(), Vector3(0, -0.13, 0)), skin],
			[_sph(0.05), Transform3D(Basis().scaled(Vector3(0.8, 1.1, 0.6)), Vector3(0, -0.3, 0)), skin]])
	spec = {"hips": {"len": 0.3, "rad": 0.16, "mass": 12.0}, "chest": {"len": 0.55, "rad": 0.17, "mass": 22.0},
		"head": {"len": 0.24, "rad": 0.12, "mass": 5.0}}
	for sd in ["L", "R"]:
		spec["thigh" + sd] = {"len": 0.47, "rad": 0.08, "mass": 9.0}
		spec["shin" + sd] = {"len": 0.5, "rad": 0.065, "mass": 5.0}
		spec["upper" + sd] = {"len": 0.29, "rad": 0.06, "mass": 3.0}
		spec["fore" + sd] = {"len": 0.33, "rad": 0.05, "mass": 2.0}

func _bone(name: String, parent, pos: Vector3) -> void:
	var b := Node3D.new()
	b.name = name
	b.position = pos
	if parent == null:
		add_child(b)
	else:
		bones[parent].add_child(b)
	bones[name] = b

func _cap(r: float, h: float) -> Mesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0)
	c.radial_segments = 8
	c.rings = 2
	return c

func _sph(r: float) -> Mesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 8
	s.rings = 4
	return s

func _box(size: Vector3) -> Mesh:
	var b := BoxMesh.new()
	b.size = size
	return b

func _mesh(bone: String, items: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for it in items:
		var arr: Array = (it[0] as Mesh).get_mesh_arrays()
		var xf: Transform3D = it[1]
		var col: Color = it[2]
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for i in ix:
			st.set_color(col)
			st.set_normal((xf.basis * ns[i]).normalized())
			st.add_vertex(xf * vs[i])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = material()
	bones[bone].add_child(mi)

## pessoa vista de longe: troca os 11 ossos por um boneco simples (~100 triângulos, 1 malha) e
## deixa de animar (animate() sai cedo). Perto volta o modelo completo.
var _proxy: MeshInstance3D
var _lod_d := 0.0
var _far_now := false
func set_far(dist: float) -> void:
	_lod_d = minf(M.lod_person(), dist)
	for b in bones.values():
		for c in b.get_children():
			if c is MeshInstance3D:
				c.visibility_range_end = _lod_d
				c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _proxy == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var bm := BoxMesh.new()
		var add := func(size: Vector3, pos: Vector3, col: Color) -> void:
			bm.size = size
			var arr: Array = bm.get_mesh_arrays()
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in arr[Mesh.ARRAY_INDEX]:
				st.set_color(col)
				st.set_normal(ns[i])
				st.add_vertex(vs[i] + pos)
		add.call(Vector3(0.42, 0.62, 0.24), Vector3(0, 1.3, 0), _pc[0])      # tronco
		add.call(Vector3(0.36, 0.86, 0.2), Vector3(0, 0.5, 0), _pc[1])       # pernas
		add.call(Vector3(0.22, 0.25, 0.22), Vector3(0, 1.72, 0), _pc[2])     # cabeça
		add.call(Vector3(0.6, 0.12, 0.14), Vector3(0, 1.5, 0), _pc[0])       # ombros
		_proxy = MeshInstance3D.new()
		_proxy.mesh = st.commit()
		_proxy.material_override = material()
		_proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_proxy)
	_proxy.visibility_range_begin = _lod_d
	_proxy.visibility_range_end = dist
	_proxy.visible = not ragdolled

## speed em m/s (0 = parado). Animação procedural: passada com fase por perna, joelho dobrando no
## balanço, quadril sobe/desce e gira, tronco contra-gira, inclinação na corrida, transição suave.
var _w := 0.0
var _run := 0.0
var _t := 0.0
func animate(speed: float, dt: float) -> void:
	if ragdolled:
		return
	# longe da câmera: só o boneco simples aparece, não precisa mexer os ossos
	if _lod_d > 0.0:
		var cam := get_viewport().get_camera_3d()
		if cam:
			_far_now = global_position.distance_squared_to(cam.global_position) > (_lod_d + 2.0) * (_lod_d + 2.0)
			if _far_now:
				return
	_t += dt
	var th: Array = [bones.thighL, bones.thighR]
	var sh: Array = [bones.shinL, bones.shinR]
	var up: Array = [bones.upperL, bones.upperR]
	var fo: Array = [bones.foreL, bones.foreR]
	for k in 2:
		th[k].rotation = Vector3.ZERO
		sh[k].rotation = Vector3.ZERO
		up[k].rotation = Vector3.ZERO
		fo[k].rotation = Vector3.ZERO
	bones.chest.rotation = Vector3.ZERO
	bones.head.rotation = Vector3.ZERO
	bones.hips.rotation = Vector3.ZERO
	bones.hips.position.y = 0.98
	if gun and is_instance_valid(gun):
		gun.visible = not swimming
		if not aiming or swimming:
			gun.basis = Basis()
	if swimming:
		_swim(speed, dt, th, sh, up, fo)
		return
	var wt := clampf(speed / 1.4, 0.0, 1.0)
	_w = lerpf(_w, wt, minf(1.0, dt * 7.0))
	_run = lerpf(_run, clampf((speed - 2.6) / 3.0, 0.0, 1.0), minf(1.0, dt * 5.0))
	if speed > 0.05:
		phase += dt * lerpf(5.4, 9.2, _run) * clampf(speed / 1.2, 0.6, 1.4)
	if pose == "getup":
		_gu += dt
		pose_t = clampf(_gu / GETUP_T, 0.0, 1.0)
		if _gu >= GETUP_T:
			pose = ""
	if pose != "":
		_pose(dt, th, sh, up, fo)
		return
	if sitting and moto_pose:
		for k in 2:
			var sg := 1.0 if k == 0 else -1.0
			th[k].rotation = Vector3(-1.15, 0, sg * 0.18)
			sh[k].rotation.x = 1.55
			up[k].rotation = Vector3(-1.05, 0, sg * 0.12)
			fo[k].rotation.x = -0.35
		bones.chest.rotation.x = 0.15
		bones.head.rotation.x = -0.1
		return
	if sitting:
		for k in 2:
			th[k].rotation.x = -1.45
			sh[k].rotation.x = 1.35
			up[k].rotation.x = -0.75
			fo[k].rotation.x = -0.55
		bones.chest.rotation.x = -0.32
		bones.head.rotation.x = 0.25
		if slumped:
			bones.chest.rotation.x = 0.75
			bones.head.rotation = Vector3(0.6, 0.3, 0.2)
			up[0].rotation.x = 0.1
			up[1].rotation.x = 0.1
		return
	# ---- passada ----
	var w := _w
	var run := _run
	var crouch := 1.0 if crouching else 0.0
	for k in 2:
		var sg := 1.0 if k == 0 else -1.0
		var p := phase + (0.0 if k == 0 else PI)
		th[k].rotation.x = -sin(p) * lerpf(0.42, 0.95, run) * w - crouch * 1.25
		sh[k].rotation.x = (0.08 + maxf(0.0, sin(p + 1.1)) * lerpf(0.65, 1.95, run) + run * 0.2) * w + crouch * 1.9
		th[k].rotation.z = sg * 0.03
		# braço oposto à perna, cotovelo dobra mais correndo
		up[k].rotation.x = sin(p) * lerpf(0.35, 0.85, run) * w
		up[k].rotation.z = sg * (0.07 + 0.06 * run)
		fo[k].rotation.x = -(0.12 + run * 1.25 + maxf(0.0, -sin(p)) * 0.25 * w)
	var s := sin(phase)
	var c := cos(phase)
	bones.chest.rotation.x = 0.03 * w + run * 0.2 + crouch * 0.3
	bones.chest.rotation.y = -s * lerpf(0.1, 0.16, run) * w
	bones.hips.rotation.y = s * lerpf(0.08, 0.12, run) * w
	bones.hips.rotation.z = c * 0.035 * w * (1.0 - run)
	bones.hips.position.y = 0.98 - run * 0.05 - crouch * 0.42 + absf(c) * lerpf(0.025, 0.075, run) * w + sin(_t * 1.7) * 0.005 * (1.0 - w)
	bones.head.rotation.x = -bones.chest.rotation.x * 0.6
	bones.head.rotation.y = -bones.chest.rotation.y * 0.6
	if limp > 0.01 and w > 0.1:
		# mancando: a perna direita (ferida) quase não dobra e o quadril cai para ela; passo curto
		th[1].rotation.x *= 1.0 - 0.55 * limp
		sh[1].rotation.x *= 1.0 - 0.7 * limp
		bones.hips.rotation.z += sin(phase) * 0.14 * limp
		bones.chest.rotation.z = -sin(phase) * 0.1 * limp
		bones.hips.position.y -= maxf(0.0, sin(phase)) * 0.06 * limp
	if w < 0.2:
		# parado: peso apoiado, braços relaxados
		bones.hips.rotation.z = sin(_t * 0.5) * 0.02
		for k in 2:
			up[k].rotation.z = (0.08 if k == 0 else -0.08)
	_upper(dt, up, fo)

## braços: soco/chute, arremesso, guarda, mira (pistola com duas mãos, fuzil no ombro)
func _upper(dt: float, up: Array, fo: Array) -> void:
	var th: Array = [bones.thighL, bones.thighR]
	var sh: Array = [bones.shinL, bones.shinR]
	if hurt_t > 0.0:
		hurt_t -= dt
		var hk := sin(clampf(hurt_t / 0.35, 0.0, 1.0) * PI)
		bones.chest.rotation.x -= 0.35 * hk
		bones.chest.rotation.z = 0.25 * hk * hurt_side
		bones.head.rotation.x = -0.6 * hk
		bones.head.rotation.y = 0.5 * hk * hurt_side
		for k3 in 2:
			up[k3].rotation = Vector3(-0.4 * hk, 0, (0.6 if k3 == 0 else -0.6) * hk)
		return
	if arm_hurt > 0.0 and not aiming and arm_pose == "":
		# segurando o braço ferido com a outra mão
		arm_hurt -= dt
		up[1].rotation = Vector3(-0.25, 0, -0.05)
		fo[1].rotation.x = -0.9
		up[0].rotation = Vector3(-0.7, 0, -0.55)
		fo[0].rotation.x = -1.7
		bones.chest.rotation.z = 0.08
		return
	if arm_pose == "handsup":
		for k3 in 2:
			up[k3].rotation = Vector3(-2.85, 0, 0.35 if k3 == 0 else -0.35)
			fo[k3].rotation.x = -0.35 + sin(_t * 9.0 + k3) * 0.05
		bones.head.rotation.x = 0.15
		return
	if arm_pose == "phone":
		up[1].rotation = Vector3(-0.35, 0, -0.75)
		fo[1].rotation.x = -2.35
		up[0].rotation = Vector3(-0.2, 0, 0.1)
		fo[0].rotation.x = -0.4
		bones.head.rotation.z = -0.15
		return
	if throw_t > 0.0:
		throw_t -= dt
		var tk := clampf(throw_t / 0.5, 0.0, 1.0)
		up[1].rotation.x = lerpf(-2.4, 1.2, 1.0 - tk) if tk < 0.6 else lerpf(-0.3, -2.4, (1.0 - tk) / 0.4)
		fo[1].rotation.x = -0.4
		bones.chest.rotation.y = -0.4 * tk
	elif punch_t > 0.0:
		punch_t -= dt
		var k := sin(clampf(punch_t / 0.3, 0.0, 1.0) * PI)
		bones.chest.rotation.y = (0.4 if punch_kind == 0 else -0.4) * k
		if punch_kind == 3:
			# gancho de baixo para cima (uppercut)
			up[1].rotation = Vector3(-0.4 - 1.6 * k, 0, -0.1)
			fo[1].rotation.x = -1.9 + 0.6 * k
			up[0].rotation = Vector3(-1.1, 0, 0.2)
			fo[0].rotation.x = -1.8
			bones.chest.rotation.x = -0.25 * k
			for i2 in 2:
				th[i2].rotation.x -= 0.35 * k
				sh[i2].rotation.x += 0.5 * k
		elif punch_kind == 4:
			# cruzado lateral (hook)
			up[0].rotation = Vector3(-1.45, 0, 1.2 * k)
			fo[0].rotation.x = -1.5
			fo[0].rotation.y = -0.8 * k
			up[1].rotation = Vector3(-1.1, 0, -0.25)
			fo[1].rotation.x = -1.8
			bones.chest.rotation.y = -0.7 * k
		elif punch_kind == 2:
			th[1].rotation.x = -1.65 * k
			sh[1].rotation.x = 0.15 * (1.0 - k)
			bones.chest.rotation.x = 0.3 * k
			up[0].rotation.x = -0.9
			up[1].rotation.x = -0.9
			fo[0].rotation.x = -1.6
			fo[1].rotation.x = -1.6
		else:
			var a := 1 if punch_kind == 0 else 0
			var o := 1 - a
			up[a].rotation = Vector3(-1.55 * k - (1.0 - k) * 1.1, 0, 0)
			fo[a].rotation.x = -0.1 * k - (1.0 - k) * 1.8
			up[o].rotation = Vector3(-1.1, 0, 0)
			fo[o].rotation.x = -1.8
	elif guard:
		for k2 in 2:
			up[k2].rotation = Vector3(-1.1, 0, 0.25 if k2 == 0 else -0.25)
			fo[k2].rotation.x = -1.9
		bones.chest.rotation.y = 0.15
	elif reload_t > 0.0:
		# recarga: mão de apoio vai até a arma, arma inclinada para o lado
		reload_t -= dt
		var rk := sin(clampf(1.0 - reload_t / maxf(reload_dur, 0.01), 0.0, 1.0) * PI)
		up[1].rotation = Vector3(-0.75, 0, -0.35)
		fo[1].rotation = Vector3(-1.0, 0.5 * rk, 0)
		up[0].rotation = Vector3(-0.55 - 0.35 * rk, 0, 0.55)
		fo[0].rotation.x = -1.3 + sin(_t * 12.0) * 0.12 * rk
		bones.head.rotation.x = 0.35
	elif aiming:
		var ap := aim_pitch
		if gun_kind in ["rifle", "sniper", "smg", "shotgun"]:
			# arma longa no ombro: cotovelo baixo, antebraço na horizontal; mão de apoio no cano
			bones.chest.rotation.y = 0.12
			bones.head.rotation.y = -0.12
			up[1].rotation = Vector3(-0.7 - ap, 0, -0.22)
			fo[1].rotation.x = -0.9
			up[0].rotation = Vector3(-1.25 - ap, 0, 0.5)
			fo[0].rotation.x = -0.25
		elif gun_kind == "rpg":
			# bazuca no ombro
			up[1].rotation = Vector3(-0.35, 0, -0.35)
			fo[1].rotation.x = -1.3
			up[0].rotation = Vector3(-1.1 - ap, 0, 0.45)
			fo[0].rotation.x = -0.4
		else:
			# pistola com as duas mãos, mãos juntas no centro
			up[1].rotation = Vector3(-1.5 - ap, 0, -0.3)
			fo[1].rotation.x = -0.05
			up[0].rotation = Vector3(-1.45 - ap, 0, 0.5)
			fo[0].rotation.x = -0.25
		bones.chest.rotation.x = -ap * 0.35
		bones.head.rotation.x = -ap * 0.4
		if gun and is_instance_valid(gun) and gun_kind in ["rifle", "sniper", "smg", "shotgun", "rpg"]:
			# cano sempre alinhado com a mira (a pose do braço sozinha deixava a arma inclinada)
			gun.global_basis = global_basis * Basis(Vector3.RIGHT, -PI * 0.5 - ap)
	elif gun_kind in ["rifle", "sniper", "smg", "shotgun"]:
		# andando com arma longa: segura na frente do peito (pronto baixo)
		up[1].rotation = Vector3(-0.45, 0, -0.25)
		fo[1].rotation.x = -0.95
		up[0].rotation = Vector3(-0.65, 0, 0.45)
		fo[0].rotation.x = -0.7
	elif gun_kind == "rpg":
		up[1].rotation = Vector3(-0.3, 0, -0.3)
		fo[1].rotation.x = -1.4
		up[0].rotation = Vector3(-0.5, 0, 0.3)
		fo[0].rotation.x = -0.8

func _swim(speed: float, dt: float, th: Array, sh: Array, up: Array, fo: Array) -> void:
	var mv := clampf(speed / 2.0, 0.0, 1.0)
	_w = lerpf(_w, mv, minf(1.0, dt * 4.0))
	phase += dt * lerpf(2.2, 6.0, _w)
	if _w > 0.25 or dive:
		# crawl: corpo deitado, braços girando em círculo alternados, pernada curta e rápida
		bones.hips.rotation.x = 1.3 + (0.6 if dive else 0.0)
		bones.hips.position.y = 0.6
		bones.head.rotation.x = -1.0 + (0.6 if dive else 0.0)
		bones.chest.rotation.y = sin(phase) * 0.25
		for k in 2:
			var sg := 1.0 if k == 0 else -1.0
			var a := fmod(phase + k * PI, TAU)
			up[k].rotation = Vector3(-a, 0, sg * 0.15)
			fo[k].rotation.x = -0.25 - maxf(0.0, sin(a)) * 0.6
			th[k].rotation.x = sin(phase * 3.0 + k * PI) * 0.3
			sh[k].rotation.x = 0.2 + maxf(0.0, sin(phase * 3.0 + k * PI)) * 0.35
	else:
		# boiando: corpo em pé na água, pernas pedalando, braços abrindo e fechando
		# boiando: tronco levemente inclinado, pernas juntas batendo curto (não parece passada),
		# braços abertos na horizontal "remando" para frente e para trás
		bones.hips.rotation.x = 0.35
		bones.hips.position.y = 0.5
		bones.head.rotation.x = -0.3
		for k in 2:
			var sg := 1.0 if k == 0 else -1.0
			th[k].rotation = Vector3(-0.25 + sin(phase * 2.4 + k * 0.6) * 0.12, 0, sg * 0.08)
			sh[k].rotation.x = 0.35 + sin(phase * 2.4 + k * 0.6 + 1.0) * 0.12
			up[k].rotation = Vector3(-0.35, sg * sin(phase * 1.6) * 0.45, sg * 1.25)
			fo[k].rotation.x = -0.35

## levantar do chão depois do ragdoll (de costas: senta → ajoelha → em pé; de bruços: empurra → ajoelha → em pé)
const GETUP_T := 1.35
var _gu := 0.0
var _gu_down := false
func start_getup(face_down: bool) -> void:
	pose = "getup"
	_gu = 0.0
	pose_t = 0.0
	_gu_down = face_down

func _getup_pose(k: float, th: Array, sh: Array, up: Array, fo: Array) -> void:
	var e := func(a: float, b: float, x: float) -> float: return smoothstep(a, b, x)
	if k < 0.38:
		var a: float = e.call(0.0, 0.38, k)
		bones.hips.position.y = lerpf(0.16, 0.24, a)
		if _gu_down:
			# de bruços → empurra o chão com os braços e recolhe as pernas
			bones.hips.rotation.x = lerpf(1.45, 0.9, a)
			bones.chest.rotation.x = lerpf(0.0, -0.5, a)
			for i in 2:
				up[i].rotation.x = lerpf(-1.4, -0.6, a)
				fo[i].rotation.x = lerpf(-1.2, -0.2, a)
				th[i].rotation.x = lerpf(0.0, -1.3, a) * (1.0 if i == 0 else 0.6)
				sh[i].rotation.x = lerpf(0.0, 1.9, a)
		else:
			# de costas → senta, mãos apoiadas atrás
			bones.hips.rotation.x = lerpf(-1.45, 0.0, a)
			bones.chest.rotation.x = lerpf(0.0, 0.25, a)
			for i in 2:
				th[i].rotation.x = lerpf(0.0, -1.45, a)
				sh[i].rotation.x = lerpf(0.0, 0.5 + i * 0.6, a)
				up[i].rotation = Vector3(lerpf(0.0, 0.7, a), 0, (0.25 if i == 0 else -0.25) * a)
				fo[i].rotation.x = -0.2 * a
	elif k < 0.7:
		# ajoelhado numa perna, mão no joelho
		var a: float = e.call(0.38, 0.7, k)
		bones.hips.position.y = lerpf(0.24, 0.55, a)
		bones.hips.rotation.x = lerpf(0.9 if _gu_down else 0.0, 0.15, a)
		bones.chest.rotation.x = lerpf(-0.5 if _gu_down else 0.25, 0.45, a)
		th[0].rotation.x = lerpf(-1.3 if _gu_down else -1.45, -1.45, a)
		sh[0].rotation.x = lerpf(1.9 if _gu_down else 0.5, 1.5, a)
		th[1].rotation.x = lerpf(-0.8, 0.05, a)
		sh[1].rotation.x = lerpf(1.9 if _gu_down else 1.1, 1.65, a)
		up[0].rotation.x = -0.9
		fo[0].rotation.x = -0.6
		up[1].rotation.x = lerpf(0.4, -0.3, a)
	else:
		# levanta empurrando o joelho
		var a: float = e.call(0.7, 1.0, k)
		bones.hips.position.y = lerpf(0.55, 0.98, a)
		bones.hips.rotation.x = lerpf(0.15, 0.0, a)
		bones.chest.rotation.x = lerpf(0.45, 0.0, a)
		th[0].rotation.x = lerpf(-1.45, 0.0, a)
		sh[0].rotation.x = lerpf(1.5, 0.0, a)
		th[1].rotation.x = lerpf(0.05, 0.0, a)
		sh[1].rotation.x = lerpf(1.65, 0.0, a)
		up[0].rotation.x = lerpf(-0.9, 0.0, a)
		fo[0].rotation.x = lerpf(-0.6, 0.0, a)

## o ragdoll terminou de bruços? (peito virado para baixo)
func rag_face_down() -> bool:
	if parts.size() > 1 and is_instance_valid(parts[1]):
		return parts[1].global_transform.basis.z.y < 0.0
	return false

## poses especiais (parkour, carregar/arrastar corpo, derrubar, puxar da porta, quebrar vidro, mixa, cobertura)
func _pose(dt: float, th: Array, sh: Array, up: Array, fo: Array) -> void:
	var k := pose_t
	match pose:
		"vault":
			var tuck := sin(k * PI)
			for i in 2:
				th[i].rotation.x = -1.35 * tuck
				sh[i].rotation.x = 1.7 * tuck
				up[i].rotation.x = -0.55 - 0.4 * (1.0 - tuck)
				fo[i].rotation.x = -0.2
			bones.chest.rotation.x = 0.45 * tuck
			bones.hips.rotation.z = 0.25 * tuck
		"climb":
			if k < 0.45:
				for i in 2:
					up[i].rotation = Vector3(-2.9, 0, 0.15 if i == 0 else -0.15)
					fo[i].rotation.x = -0.35
					th[i].rotation.x = -0.25 + sin(_t * 9.0 + i * PI) * 0.25
					sh[i].rotation.x = 0.5
			else:
				var kk := (k - 0.45) / 0.55
				for i in 2:
					up[i].rotation.x = lerpf(-2.9, -0.4, kk)
					fo[i].rotation.x = lerpf(-0.35, -1.4, kk)
				th[1].rotation.x = -1.5 * sin(kk * PI)
				sh[1].rotation.x = 1.6 * sin(kk * PI)
				bones.chest.rotation.x = 0.7 * sin(kk * PI)
		"carry":
			up[1].rotation = Vector3(-2.7, 0, -0.2)
			fo[1].rotation.x = -1.7
			bones.chest.rotation.x = 0.12
			var p := phase
			for i in 2:
				th[i].rotation.x = -sin(p + i * PI) * 0.45 * _w
				sh[i].rotation.x = (0.1 + maxf(0.0, sin(p + i * PI + 1.1)) * 0.7) * _w
			up[0].rotation.x = sin(p) * 0.3 * _w
		"drag":
			bones.chest.rotation.x = 0.6
			bones.hips.position.y = 0.86
			for i in 2:
				up[i].rotation.x = -0.75
				fo[i].rotation.x = -0.25
				th[i].rotation.x = -0.5 - sin(phase + i * PI) * 0.35 * _w
				sh[i].rotation.x = 0.7
		"getup":
			_getup_pose(k, th, sh, up, fo)
		"exit":
			# saindo do carro: começa agachado/encolhido e se levanta
			var ke := 1.0 - k
			for i in 2:
				th[i].rotation.x = -1.2 * ke
				sh[i].rotation.x = 1.4 * ke
				up[i].rotation.x = -0.5 * ke
			bones.hips.position.y = 0.98 - 0.42 * ke
			bones.chest.rotation.x = 0.45 * ke
		"tackle":
			bones.hips.rotation.x = 1.0 * k
			bones.hips.position.y = lerpf(0.98, 0.5, k)
			for i in 2:
				up[i].rotation.x = -2.8 * k
				th[i].rotation.x = 0.5 * k
		"pull":
			var pl := sin(_t * 9.0)
			bones.chest.rotation.x = 0.25 - k * 0.35
			for i in 2:
				up[i].rotation.x = -1.3 + pl * 0.15 + k * 0.6
				fo[i].rotation.x = -0.6 - k * 0.8
			th[0].rotation.x = -0.35
			sh[0].rotation.x = 0.4
		"break":
			var hit := sin(clampf(k * 2.0, 0.0, 1.0) * PI)
			up[1].rotation = Vector3(-1.4 + hit * 0.5, 0, 0.5)
			fo[1].rotation.x = -2.0 + hit * 0.8
			bones.chest.rotation.y = -0.6 * hit
		"lockpick":
			bones.hips.position.y = 0.8
			bones.chest.rotation.x = 0.35
			for i in 2:
				th[i].rotation.x = -0.6
				sh[i].rotation.x = 0.9
				up[i].rotation.x = -1.0
				fo[i].rotation.x = -0.9 + sin(_t * 14.0 + i) * 0.08
		"cover":
			bones.hips.position.y = 0.56
			bones.chest.rotation.x = 0.35
			for i in 2:
				th[i].rotation.x = -1.3
				sh[i].rotation.x = 1.95
				up[i].rotation.x = -0.9
				fo[i].rotation.x = -0.9
		"kick":
			# sentado chutando a porta / quebrando o vidro debaixo d'água
			var kk2 := sin(clampf(k * 3.0, 0.0, 3.0) * PI)
			th[0].rotation.x = -1.45 + kk2 * 0.9
			sh[0].rotation.x = 1.35 - kk2 * 1.3
			th[1].rotation.x = -1.45
			sh[1].rotation.x = 1.35
			up[1].rotation = Vector3(-1.2 + kk2 * 0.4, 0, -0.6)
			fo[1].rotation.x = -1.4
			bones.chest.rotation.x = -0.2
		"carried":
			# jogado no ombro de alguém: corpo dobrado, braços e pernas pendurados
			bones.chest.rotation.x = 1.4
			bones.head.rotation.x = 0.6
			for i in 2:
				up[i].rotation.x = -2.6 + sin(_t * 4.0 + i) * 0.1
				th[i].rotation.x = -0.3
				sh[i].rotation.x = 0.6

## Ragdoll físico: cada osso vira um corpo rígido ligado por juntas com limites.
## gore = arranca um membro se o impacto for forte.
func ragdoll(impulse: Vector3, ignore: PhysicsBody3D = null, gore := false) -> Array:
	if ragdolled:
		return []
	ragdolled = true
	if _proxy:
		_proxy.visible = false
	var world := get_tree().current_scene
	var rbs := {}
	var order := ["hips", "chest", "head", "thighL", "thighR", "shinL", "shinR", "upperL", "upperR", "foreL", "foreR"]
	var parent_of := {"chest": "hips", "head": "chest", "thighL": "hips", "thighR": "hips", "shinL": "thighL", "shinR": "thighR", "upperL": "chest", "upperR": "chest", "foreL": "upperL", "foreR": "upperR"}
	for n in order:
		var b: Node3D = bones[n]
		var sp: Dictionary = spec[n]
		var rb := RigidBody3D.new()
		rb.mass = sp.mass
		rb.linear_damp = 0.1
		rb.angular_damp = 1.5
		rb.collision_layer = 4
		rb.collision_mask = 1
		world.add_child(rb)
		rb.add_to_group("tmp")
		rb.global_transform = b.global_transform
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = sp.rad
		cap.height = maxf(sp.len, sp.rad * 2.0 + 0.01)
		cs.shape = cap
		var down := -1.0 if not (n in ["chest", "head", "hips"]) else 1.0
		cs.position = Vector3(0, down * sp.len * 0.5, 0) if n != "hips" else Vector3(0, 0.02, 0)
		rb.add_child(cs)
		for c in b.get_children():
			if c is MeshInstance3D:
				var gx: Transform3D = c.global_transform
				b.remove_child(c)
				rb.add_child(c)
				c.global_transform = gx
		if ignore:
			rb.add_collision_exception_with(ignore)
		rbs[n] = rb
	var torn := ""
	if gore and impulse.length() > 13.0:
		torn = ["upperL", "upperR", "thighL", "thighR", "head"][randi() % 5]
	for n in parent_of:
		if n == torn:
			continue
		# PinJoint3D (articulação esférica) é a junta mais estável na física padrão do Godot
		var j := PinJoint3D.new()
		world.add_child(j)
		j.global_position = bones[n].global_position
		j.set_param(PinJoint3D.PARAM_BIAS, 0.6)
		j.set_param(PinJoint3D.PARAM_DAMPING, 1.0)
		j.node_a = rbs[parent_of[n]].get_path()
		j.node_b = rbs[n].get_path()
		rbs[n].set_meta("joint", j)
		# a junta vai embora junto com a peça (antes ficavam soltas na cena para sempre)
		j.add_to_group("tmp")
		rbs[n].tree_exiting.connect(func(): if is_instance_valid(j): j.queue_free())
	for n in rbs:
		var rb: RigidBody3D = rbs[n]
		var k := 1.0 if n in ["hips", "chest"] else 0.7
		rb.linear_velocity = impulse * k + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		rb.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-2, 2), randf_range(-4, 4))
	parts = rbs.values()
	visible = false
	# músculos (ragdoll ativo) + boiar na água
	var mu = preload("res://scripts/ragmuscle.gd").new()
	mu.alive = rag_alive
	mu.world2 = world.get("world2")
	for n in rbs:
		mu.parts[n] = rbs[n]
		var sp: Dictionary = spec[n]
		mu.inertia[n] = rbs[n].mass * (sp.len * sp.len / 12.0 + sp.rad * sp.rad * 0.25) + 0.01
	for n in parent_of:
		if n == torn:
			continue
		mu.parent_of[n] = parent_of[n]
		mu.rel0[n] = (bones[parent_of[n]].global_basis.inverse() * bones[n].global_basis).orthonormalized()
	world.add_child(mu)
	mu.add_to_group("tmp")
	rag_alive = false
	return [rbs, torn]

## ferimento visível na parte do corpo (tiro, queda, explosão): mancha de sangue presa ao osso
## (no ragdoll, ao corpo rígido daquele osso); wound_data guarda tudo para o corpo novo ao levantar
const RAG_ORDER := ["hips", "chest", "head", "thighL", "thighR", "shinL", "shinR", "upperL", "upperR", "foreL", "foreR"]
var wounds := 0
var wound_data: Array = []     # [{bn, xf (local ao osso), big}]
func _wound_host(bn: String) -> Node3D:
	if ragdolled:
		var i := RAG_ORDER.find(bn)
		if i >= 0 and i < parts.size() and is_instance_valid(parts[i]):
			return parts[i]
		return null
	return bones.get(bn)

func add_wound(zone: String, dir: Vector3, big := false) -> void:
	if wounds >= 14 or not FXW.blood_on:
		return
	var opts: Array = {"head": ["head"], "torso": ["chest", "chest", "hips"], "leg": ["thighL", "thighR", "shinL", "shinR"], "arm": ["upperL", "upperR", "foreL", "foreR"], "any": ["chest", "hips", "thighL", "thighR", "upperL", "upperR", "head", "shinL", "foreR"]}.get(zone, ["chest"])
	var bn: String = opts[randi() % opts.size()]
	if not spec.has(bn):
		return
	var host := _wound_host(bn)
	if host == null:
		return
	var sp: Dictionary = spec[bn]
	var down := -1.0 if not (bn in ["chest", "head", "hips"]) else 1.0
	var along: float = sp.len * randf_range(0.25, 0.75) * down
	var center: Vector3 = host.global_transform * Vector3(0, along, 0)
	var out := -dir
	out.y *= 0.3
	if out.length() < 0.1:
		out = host.global_transform.basis.z
	out = out.normalized()
	var surf: Vector3 = center + out * float(sp.rad) * 0.92
	FXW.wound(host, surf, out, 0.07 if not big else 0.12)
	var w: Node3D = host.get_child(host.get_child_count() - 1)
	wound_data.append({"bn": bn, "xf": host.global_transform.affine_inverse() * w.global_transform})
	wounds += 1

## recria os ferimentos num corpo novo (levantou do ragdoll / trocou de roupa)
func apply_wounds(data: Array) -> void:
	for d in data:
		var host := _wound_host(d.bn)
		if host == null:
			continue
		FXW.wound(host, Vector3.ZERO, Vector3.FORWARD)
		var w: Node3D = host.get_child(host.get_child_count() - 1)
		w.transform = d.xf
		wound_data.append(d)
		wounds += 1

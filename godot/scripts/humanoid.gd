extends Node3D
## Corpo humano (provisório até termos um modelo com esqueleto): 10 ossos, cada um uma malha só
## (todas as partes do osso fundidas, 1 material com cor por vértice → poucas draw calls).
## Animação procedural de andar/correr/sentar e ragdoll físico de verdade (RigidBody3D + juntas).

const M := preload("res://scripts/mats.gd")

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
var gun: Node3D

## arma na mão direita (apontando para frente quando o braço está esticado)
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
func build(shirt: Color, pants: Color, skin: Color, hair: Color, ex := {}) -> void:
	skin_c = skin
	var shoe := Color(0.07, 0.07, 0.08)
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
		_mesh("shin" + sd, [[_cap(0.065, 0.48), Transform3D(Basis(), Vector3(0, -0.23, 0)), pants],
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
	c.radial_segments = 12
	c.rings = 4
	return c

func _sph(r: float) -> Mesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
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

func set_far(dist: float) -> void:
	for b in bones.values():
		for c in b.get_children():
			if c is MeshInstance3D:
				c.visibility_range_end = dist
				c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## speed em m/s (0 = parado). Corrida acima de ~3 m/s.
func animate(speed: float, dt: float) -> void:
	if ragdolled:
		return
	var th: Array = [bones.thighL, bones.thighR]
	var sh: Array = [bones.shinL, bones.shinR]
	var up: Array = [bones.upperL, bones.upperR]
	var fo: Array = [bones.foreL, bones.foreR]
	if sitting:
		for k in 2:
			th[k].rotation.x = -1.45
			sh[k].rotation.x = 1.35
			up[k].rotation.x = -0.75
			fo[k].rotation.x = -0.55
		bones.chest.rotation.x = -0.32
		bones.head.rotation.x = 0.25
		return
	var run := clampf((speed - 2.2) / 3.0, 0.0, 1.0)
	phase += dt * (2.2 + speed * 1.65)
	var walk := clampf(speed / 1.6, 0.0, 1.0)
	var amp := walk * lerpf(0.5, 0.85, run)
	var s := sin(phase)
	for k in 2:
		var sg := 1.0 if k == 0 else -1.0
		var ls := s * sg
		# coxa: negativo = para frente
		th[k].rotation.x = -ls * amp
		# joelho dobra mais quando a perna volta (fase de balanço), e muito mais correndo
		var swing := maxf(0.0, -cos(phase) * sg)
		sh[k].rotation.x = (0.15 + swing * lerpf(0.7, 1.7, run)) * walk
		# braço oposto à perna
		up[k].rotation.x = ls * amp * lerpf(0.7, 1.1, run)
		up[k].rotation.z = sg * (0.06 + run * 0.08)
		fo[k].rotation.x = -lerpf(0.25, 1.5, run) * walk - 0.1
	bones.chest.rotation.x = run * 0.22
	bones.chest.rotation.y = s * 0.12 * amp
	bones.hips.rotation.y = -s * 0.08 * amp
	bones.hips.position.y = 0.98 - run * 0.04 + absf(cos(phase)) * lerpf(0.025, 0.07, run) * walk
	bones.head.rotation.x = -run * 0.15
	if punch_t > 0.0:
		punch_t -= dt
		var k := sin(clampf(punch_t / 0.3, 0.0, 1.0) * PI)
		up[1].rotation.x = -1.5 * k
		up[1].rotation.z = 0.0
		fo[1].rotation.x = -0.2 * k
	elif aiming:
		up[1].rotation.x = -1.48
		up[1].rotation.z = 0.0
		fo[1].rotation.x = 0.0
		up[0].rotation.x = -1.25
		up[0].rotation.z = -0.45
		fo[0].rotation.x = -0.35
		bones.chest.rotation.y = 0.0

## Ragdoll físico: cada osso vira um corpo rígido ligado por juntas com limites.
## gore = arranca um membro se o impacto for forte.
func ragdoll(impulse: Vector3, ignore: PhysicsBody3D = null, gore := false) -> Array:
	if ragdolled:
		return []
	ragdolled = true
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
		rb.angular_damp = 3.0
		rb.collision_layer = 4
		rb.collision_mask = 1
		world.add_child(rb)
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
	for n in rbs:
		var rb: RigidBody3D = rbs[n]
		var k := 1.0 if n in ["hips", "chest"] else 0.7
		rb.linear_velocity = impulse * k + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		rb.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-2, 2), randf_range(-4, 4))
	parts = rbs.values()
	visible = false
	return [rbs, torn]

extends RefCounted
## Efeitos: sangue (jato de partículas, poça no chão, rastro de membro arrancado), faíscas de batida.

const M := preload("res://scripts/mats.gd")

static var blood_on := true   # configuração "Sangue"
static var _blood_mat: StandardMaterial3D
static var _pool_mesh: CylinderMesh

## tudo o que é temporário entra no grupo "tmp" (o main apaga tudo ao reiniciar o mundo)
## e os efeitos que duram muito (poças, marcas, destroços) têm um limite: o mais antigo sai.
static var _caps := {}
static var _meshes := {}
static var _mats := {}

static func tmp(n: Node) -> void:
	n.add_to_group("tmp")

static func _capped(kind: String, n: Node, maxn: int) -> void:
	tmp(n)
	if not _caps.has(kind):
		_caps[kind] = []
	var arr: Array = _caps[kind]
	arr.append(n)
	while arr.size() > maxn:
		var old = arr.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	if arr.size() > 4 and not is_instance_valid(arr[0]):
		_caps[kind] = arr.filter(func(x): return is_instance_valid(x))

static func _sphere(r: float, seg := 6, rings := 3) -> SphereMesh:
	var k := "s%f_%d" % [r, seg]
	if not _meshes.has(k):
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = seg
		s.rings = rings
		_meshes[k] = s
	return _meshes[k]

static func _boxm(sz: Vector3) -> BoxMesh:
	var k := "b%s" % [sz]
	if not _meshes.has(k):
		var b := BoxMesh.new()
		b.size = sz
		_meshes[k] = b
	return _meshes[k]

static func blood_mat() -> StandardMaterial3D:
	if _blood_mat == null:
		_blood_mat = StandardMaterial3D.new()
		_blood_mat.albedo_color = Color(0.42, 0.02, 0.02)
		_blood_mat.roughness = 0.25
		_blood_mat.metallic_specular = 0.7
	return _blood_mat

static func blood_burst(world: Node, pos: Vector3, dir: Vector3, amount := 20) -> void:
	if not blood_on:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = 1.1
	p.explosiveness = 0.95
	p.mesh = _sphere(0.035)
	p.material_override = blood_mat()
	p.direction = (dir + Vector3(0, 0.8, 0)).normalized()
	p.spread = 45.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.5
	p.gravity = Vector3(0, -14, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	world.add_child(p)
	tmp(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(2.0).timeout.connect(p.queue_free)

static func blood_pool(world: Node, pos: Vector3) -> void:
	if not blood_on:
		return
	if _pool_mesh == null:
		_pool_mesh = CylinderMesh.new()
		_pool_mesh.top_radius = 0.5
		_pool_mesh.bottom_radius = 0.5
		_pool_mesh.height = 0.01
		_pool_mesh.radial_segments = 20
	var mi := MeshInstance3D.new()
	mi.mesh = _pool_mesh
	mi.material_override = blood_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	_capped("pool", mi, 30)
	var ground := 0.16 if absf(pos.y - 0.15) < 0.4 else 0.01
	mi.global_position = Vector3(pos.x, ground + 0.006, pos.z)
	mi.scale = Vector3(0.1, 1, 0.1)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(1.6, 1, 1.3), 6.0).set_ease(Tween.EASE_OUT)
	mi.get_tree().create_timer(60.0).timeout.connect(mi.queue_free)

## pequenas gotas saindo de um membro arrancado durante 2 s
static func blood_trail(rb: Node3D) -> void:
	if not blood_on:
		return
	var p := CPUParticles3D.new()
	p.amount = 24
	p.lifetime = 0.7
	p.mesh = _sphere(0.025)
	p.material_override = blood_mat()
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0, -12, 0)
	rb.add_child(p)
	p.emitting = true
	p.get_tree().create_timer(2.5).timeout.connect(func(): if is_instance_valid(p): p.emitting = false)

static func sparks(world: Node, pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 18
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.mesh = _boxm(Vector3(0.03, 0.03, 0.12))
	p.material_override = M.emissive(Color(1.0, 0.7, 0.25), 4.0)
	p.spread = 90.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 8.0
	p.gravity = Vector3(0, -15, 0)
	world.add_child(p)
	tmp(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(1.0).timeout.connect(p.queue_free)

# ---------------------------------------------------------------- fumaça, fogo, explosão, destroços
static var _puff: SphereMesh
static func _puff_mesh() -> SphereMesh:
	if _puff == null:
		_puff = SphereMesh.new()
		_puff.radius = 0.5
		_puff.height = 1.0
		_puff.radial_segments = 8
		_puff.rings = 4
	return _puff

static func _smoke_mat(c: Color) -> StandardMaterial3D:
	var key := "sm" + c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	_mats[key] = m
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	return m

static var _fade_g: Gradient
static func _fade() -> Gradient:
	if _fade_g:
		return _fade_g
	var g := Gradient.new()
	_fade_g = g
	g.set_color(0, Color(1, 1, 1, 0.75))
	g.set_color(1, Color(1, 1, 1, 0.0))
	return g

## fumaça contínua (carro danificado); devolve o emissor (filho de 'parent')
static func smoke_emitter(parent: Node3D, local: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 14
	p.lifetime = 2.2
	p.mesh = _puff_mesh()
	p.material_override = _smoke_mat(Color(0.25, 0.25, 0.27))
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0, 0.6, 0)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.2
	p.color_ramp = _fade()
	p.local_coords = false
	p.position = local
	parent.add_child(p)
	return p

static func fire_emitter(parent: Node3D, local: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 22
	p.lifetime = 0.8
	p.mesh = _puff_mesh()
	p.material_override = emissive_alpha(Color(1.0, 0.45, 0.08), 3.0)
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, 1.5, 0)
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.9
	p.color_ramp = _fade()
	p.local_coords = false
	p.position = local
	parent.add_child(p)
	smoke_emitter(p, Vector3(0, 0.8, 0))
	return p

static func emissive_alpha(c: Color, e: float) -> StandardMaterial3D:
	var key := "ea%s%f" % [c.to_html(), e]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	_mats[key] = m
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	return m

## bola de fogo + fumaça + clarão + destroços + marca no chão (só visual; o dano é do main)
static func explosion(world: Node, pos: Vector3, size := 1.0) -> void:
	var f := CPUParticles3D.new()
	f.one_shot = true
	f.explosiveness = 0.95
	f.amount = 26
	f.lifetime = 0.9
	f.mesh = _puff_mesh()
	f.material_override = emissive_alpha(Color(1.0, 0.55, 0.12), 5.0)
	f.spread = 180.0
	f.initial_velocity_min = 3.0 * size
	f.initial_velocity_max = 8.0 * size
	f.damping_min = 6.0
	f.damping_max = 9.0
	f.gravity = Vector3(0, 3, 0)
	f.scale_amount_min = 1.2 * size
	f.scale_amount_max = 3.2 * size
	f.color_ramp = _fade()
	world.add_child(f)
	tmp(f)
	f.global_position = pos
	f.emitting = true
	f.get_tree().create_timer(1.5).timeout.connect(f.queue_free)
	var s := CPUParticles3D.new()
	s.one_shot = true
	s.explosiveness = 0.7
	s.amount = 20
	s.lifetime = 3.5
	s.mesh = _puff_mesh()
	s.material_override = _smoke_mat(Color(0.14, 0.13, 0.13))
	s.spread = 60.0
	s.direction = Vector3.UP
	s.initial_velocity_min = 2.0
	s.initial_velocity_max = 5.0 * size
	s.damping_min = 1.5
	s.damping_max = 2.5
	s.gravity = Vector3(0, 1.2, 0)
	s.scale_amount_min = 1.5 * size
	s.scale_amount_max = 4.0 * size
	s.color_ramp = _fade()
	world.add_child(s)
	tmp(s)
	s.global_position = pos + Vector3(0, 0.6, 0)
	s.emitting = true
	s.get_tree().create_timer(4.5).timeout.connect(s.queue_free)
	# clarão (luz real por 0,35 s)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.25)
	l.light_energy = 8.0
	l.omni_range = 18.0 * size
	world.add_child(l)
	tmp(l)
	l.global_position = pos + Vector3(0, 1.5, 0)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.45)
	tw.tween_callback(l.queue_free)
	sparks(world, pos + Vector3(0, 0.5, 0))
	for k in int(6 * size):
		debris(world, pos + Vector3(randf_range(-0.6, 0.6), 0.8, randf_range(-0.6, 0.6)), Color(0.08, 0.08, 0.08), Vector3(randf_range(-7, 7), randf_range(6, 12), randf_range(-7, 7)) * size)
	# marca de queimado
	var mk := MeshInstance3D.new()
	if not _meshes.has("scorch"):
		var cm := CylinderMesh.new()
		cm.top_radius = 2.2
		cm.bottom_radius = 2.2
		cm.height = 0.01
		cm.radial_segments = 16
		_meshes["scorch"] = cm
	mk.mesh = _meshes["scorch"]
	mk.scale = Vector3(size, 1.0, size)
	mk.material_override = _scorch()
	mk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mk)
	_capped("scorch", mk, 20)
	mk.global_position = Vector3(pos.x, 0.17 if absf(pos.y) < 2.0 else pos.y, pos.z)
	mk.get_tree().create_timer(60.0).timeout.connect(mk.queue_free)

static var _sc: StandardMaterial3D
static func _scorch() -> StandardMaterial3D:
	if _sc == null:
		_sc = StandardMaterial3D.new()
		_sc.albedo_color = Color(0.02, 0.02, 0.02, 0.75)
		_sc.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_sc.roughness = 1.0
	return _sc

## pedaço que voa (corpo rígido, some em 20 s)
static func debris(world: Node, pos: Vector3, col: Color, vel: Vector3, size := Vector3(0.35, 0.12, 0.5)) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.collision_layer = 4
	rb.collision_mask = 1
	rb.mass = 6.0
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = _boxm(size)
	mi.material_override = M.plain(col, 0.6)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rb.add_child(mi)
	world.add_child(rb)
	_capped("debris", rb, 36)
	rb.global_position = pos
	rb.linear_velocity = vel
	rb.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	rb.get_tree().create_timer(14.0).timeout.connect(rb.queue_free)
	return rb

## respingo de água
static func splash(world: Node, pos: Vector3, size := 1.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 24
	p.lifetime = 1.0
	p.mesh = _puff_mesh()
	p.material_override = _smoke_mat(Color(0.85, 0.92, 1.0))
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 3.0 * size
	p.initial_velocity_max = 7.0 * size
	p.gravity = Vector3(0, -14, 0)
	p.scale_amount_min = 0.2 * size
	p.scale_amount_max = 0.6 * size
	p.color_ramp = _fade()
	world.add_child(p)
	tmp(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(1.6).timeout.connect(p.queue_free)


## apaga fogo e fumaça de um veículo (caiu na água)
static func extinguish(node: Node) -> void:
	for p in node.find_children("*", "CPUParticles3D", true, false):
		p.emitting = false
	for p in node.find_children("*", "GPUParticles3D", true, false):
		p.emitting = false

## marca de bala: furo escuro com borda clara, preso ao que foi atingido (carro leva junto)
static var _hole_mesh: QuadMesh
static var _hole_mat: StandardMaterial3D
static var _wound_mat: StandardMaterial3D
static func bullet_hole(world: Node, pos: Vector3, normal: Vector3, parent: Node3D = null, size := 0.11) -> void:
	if _hole_mesh == null:
		_hole_mesh = QuadMesh.new()
		_hole_mesh.size = Vector2(1, 1)
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			for x in 32:
				var d := Vector2(x - 15.5, y - 15.5).length() / 16.0
				var a := 0.0
				var c := Color(0.03, 0.03, 0.03)
				if d < 0.35:
					a = 1.0
				elif d < 0.75:
					a = 0.75 * (1.0 - (d - 0.35) / 0.4)
					c = Color(0.25, 0.23, 0.2)
				img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
		_hole_mat = StandardMaterial3D.new()
		_hole_mat.albedo_texture = ImageTexture.create_from_image(img)
		_hole_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_hole_mat.roughness = 1.0
	var n := MeshInstance3D.new()
	n.mesh = _hole_mesh
	n.material_override = _hole_mat
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.scale = Vector3.ONE * size
	n.visibility_range_end = 45.0
	var nn := normal.normalized() if normal.length() > 0.1 else Vector3.UP
	var up := Vector3.UP if absf(nn.y) < 0.95 else Vector3.RIGHT
	var xf := Transform3D(Basis.looking_at(-nn, up), pos + nn * 0.012)
	if parent and is_instance_valid(parent):
		parent.add_child(n)
		n.global_transform = xf
		n.scale = Vector3.ONE * size
	else:
		world.add_child(n)
		n.global_transform = xf
		n.scale = Vector3.ONE * size
	_capped("hole", n, 70)

## ferimento visível (mancha de sangue) colado na parte do corpo atingida
static func wound(part: Node3D, world_pos: Vector3, normal: Vector3, size := 0.09) -> void:
	if not blood_on or part == null or not is_instance_valid(part):
		return
	if _wound_mat == null:
		_wound_mat = StandardMaterial3D.new()
		_wound_mat.albedo_color = Color(0.38, 0.02, 0.02)
		_wound_mat.roughness = 0.35
	var n := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 0.35
	sm.radial_segments = 8
	sm.rings = 4
	n.mesh = sm
	n.material_override = _wound_mat
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.add_child(n)
	var nn := normal.normalized() if normal.length() > 0.1 else Vector3.UP
	var up := Vector3.UP if absf(nn.y) < 0.95 else Vector3.RIGHT
	n.global_transform = Transform3D(Basis.looking_at(-nn, up).scaled(Vector3(size, size, size * 0.5)), world_pos)
	n.add_to_group("wound")

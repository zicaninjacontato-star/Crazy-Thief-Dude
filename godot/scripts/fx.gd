extends RefCounted
## Efeitos: sangue (jato de partículas, poça no chão, rastro de membro arrancado), faíscas de batida.

const M := preload("res://scripts/mats.gd")

static var blood_on := true   # configuração "Sangue"
static var _blood_mat: StandardMaterial3D
static var _pool_mesh: CylinderMesh

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
	var s := SphereMesh.new()
	s.radius = 0.035
	s.height = 0.07
	s.radial_segments = 6
	s.rings = 3
	p.mesh = s
	p.material_override = blood_mat()
	p.direction = (dir + Vector3(0, 0.8, 0)).normalized()
	p.spread = 45.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.5
	p.gravity = Vector3(0, -14, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	world.add_child(p)
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
	var s := SphereMesh.new()
	s.radius = 0.025
	s.height = 0.05
	s.radial_segments = 6
	s.rings = 3
	p.mesh = s
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
	var s := BoxMesh.new()
	s.size = Vector3(0.03, 0.03, 0.12)
	p.mesh = s
	p.material_override = M.emissive(Color(1.0, 0.7, 0.25), 4.0)
	p.spread = 90.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 8.0
	p.gravity = Vector3(0, -15, 0)
	world.add_child(p)
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
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	return m

static func _fade() -> Gradient:
	var g := Gradient.new()
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
	var m := StandardMaterial3D.new()
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
	s.global_position = pos + Vector3(0, 0.6, 0)
	s.emitting = true
	s.get_tree().create_timer(4.5).timeout.connect(s.queue_free)
	# clarão (luz real por 0,35 s)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.25)
	l.light_energy = 8.0
	l.omni_range = 18.0 * size
	world.add_child(l)
	l.global_position = pos + Vector3(0, 1.5, 0)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.45)
	tw.tween_callback(l.queue_free)
	sparks(world, pos + Vector3(0, 0.5, 0))
	for k in int(6 * size):
		debris(world, pos + Vector3(randf_range(-0.6, 0.6), 0.8, randf_range(-0.6, 0.6)), Color(0.08, 0.08, 0.08), Vector3(randf_range(-7, 7), randf_range(6, 12), randf_range(-7, 7)) * size)
	# marca de queimado
	var mk := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 2.2 * size
	cm.bottom_radius = 2.2 * size
	cm.height = 0.01
	cm.radial_segments = 16
	mk.mesh = cm
	mk.material_override = _scorch()
	mk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mk)
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
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = M.plain(col, 0.6)
	rb.add_child(mi)
	world.add_child(rb)
	rb.global_position = pos
	rb.linear_velocity = vel
	rb.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	rb.get_tree().create_timer(20.0).timeout.connect(rb.queue_free)
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
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(1.6).timeout.connect(p.queue_free)

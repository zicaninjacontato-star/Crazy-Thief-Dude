extends RefCounted
## Efeitos: sangue (jato de partículas, poça no chão, rastro de membro arrancado), faíscas de batida.

const M := preload("res://scripts/mats.gd")

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

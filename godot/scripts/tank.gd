extends CharacterBody3D
## Tanque do exército (5 estrelas): segue as ruas até o jogador, gira a torre e dispara obuses
## que explodem no impacto. Aguenta muito (só cai com bazuca/granadas ou muito tiro de fuzil).

const CM := preload("res://scripts/carmodel.gd")
const FX := preload("res://scripts/fx.gd")

var main: Node3D
var hp := 700.0
var dead := false
var kind := "tank"
var body_size := Vector3(3.6, 2.6, 7.0)
var turret: Node3D
var barrel: Node3D
var _path := PackedVector3Array()
var _path_t := 0.0
var _cool := 3.0
var _shells: Array = []
var _tread := 0.0
var rng := RandomNumberGenerator.new()

func setup(m: Node3D) -> void:
	main = m
	rng.randomize()
	collision_layer = 1
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(3.4, 1.8, 6.6)
	cs.shape = bx
	cs.position.y = 0.95
	add_child(cs)
	var olive := Color(0.3, 0.34, 0.2)
	var dark := Color(0.12, 0.13, 0.1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	CM._box(st, Vector3(3.2, 1.0, 6.6), Vector3(0, 1.15, 0), olive)
	CM._box(st, Vector3(2.6, 0.5, 5.4), Vector3(0, 1.85, -0.2), olive.darkened(0.1))
	for s in [-1.0, 1.0]:
		CM._box(st, Vector3(0.75, 1.0, 7.0), Vector3(1.55 * s, 0.55, 0), dark)
		for k in 6:
			CM._box(st, Vector3(0.8, 0.7, 0.7), Vector3(1.55 * s, 0.45, -2.7 + k * 1.08), Color(0.2, 0.2, 0.18))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = CM.vc_mat()
	add_child(mi)
	turret = Node3D.new()
	turret.position = Vector3(0, 2.1, -0.3)
	add_child(turret)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	CM._box(st2, Vector3(2.3, 0.9, 2.8), Vector3(0, 0.45, 0), olive.lightened(0.05))
	CM._box(st2, Vector3(0.7, 0.35, 0.7), Vector3(0.6, 1.05, -0.5), dark)
	var mt := MeshInstance3D.new()
	mt.mesh = st2.commit()
	mt.material_override = CM.vc_mat()
	turret.add_child(mt)
	barrel = Node3D.new()
	barrel.position = Vector3(0, 0.5, 1.3)
	turret.add_child(barrel)
	var st3 := SurfaceTool.new()
	st3.begin(Mesh.PRIMITIVE_TRIANGLES)
	CM._box(st3, Vector3(0.28, 0.28, 3.8), Vector3(0, 0, 1.9), dark)
	CM._box(st3, Vector3(0.4, 0.4, 0.6), Vector3(0, 0, 3.7), dark)
	var mb := MeshInstance3D.new()
	mb.mesh = st3.commit()
	mb.material_override = CM.vc_mat()
	barrel.add_child(mb)

func take_damage(d: float) -> void:
	if dead:
		return
	hp -= d
	if hp <= 0.0:
		dead = true
		main.explode_at(global_position + Vector3(0, 1.5, 0), 8.0, 60.0)
		FX.smoke_emitter(self, Vector3(0, 2.4, 0))
		FX.fire_emitter(self, Vector3(0, 2.0, 0))
		for n in find_children("*", "MeshInstance3D", true, false):
			n.material_override = CM.vc_mat().duplicate()
			n.material_override.albedo_color = Color(0.15, 0.13, 0.12)
		get_tree().create_timer(30.0).timeout.connect(queue_free)

func _physics_process(dt: float) -> void:
	_shell_tick(dt)
	if dead or main == null:
		return
	var pl = main.player
	var tgt: Vector3 = pl.vehicle.global_position if pl.vehicle else pl.global_position
	var d := global_position.distance_to(tgt)
	# rota pelas ruas (recalcula a cada 2 s)
	_path_t -= dt
	if _path_t <= 0.0:
		_path_t = 2.0
		_path = main.route_path(global_position, tgt)
	var goal := tgt
	while _path.size() > 1 and Vector2(_path[0].x - global_position.x, _path[0].z - global_position.z).length() < 4.0:
		_path.remove_at(0)
	if _path.size() > 0:
		goal = _path[0]
	var to := goal - global_position
	to.y = 0
	var spd := 7.5 if d > 28.0 else 0.0
	var yaw := atan2(to.x, to.z)
	rotation.y = lerp_angle(rotation.y, yaw, minf(1.0, dt * 1.2))
	var f := Vector3(sin(rotation.y), 0, cos(rotation.y))
	var hv := f * spd * clampf(1.0 - absf(angle_difference(rotation.y, yaw)) / 1.2, 0.15, 1.0)
	velocity.x = hv.x
	velocity.z = hv.z
	velocity.y = velocity.y - 18.0 * dt if not is_on_floor() else -0.5
	move_and_slide()
	# esmaga carros pequenos no caminho
	for i in get_slide_collision_count():
		var col = get_slide_collision(i).get_collider()
		if col is RigidBody3D and col.has_method("take_damage") and col != pl.vehicle:
			col.apply_central_impulse(f * col.mass * 2.0 + Vector3(0, col.mass * 1.5, 0))
			col.take_damage(8.0)
	# torre mira no jogador
	var lt: Vector3 = turret.global_transform.affine_inverse() * tgt
	turret.rotation.y += clampf(atan2(lt.x, lt.z), -dt * 1.4, dt * 1.4)
	barrel.rotation.x = clampf(-atan2(tgt.y + 1.0 - barrel.global_position.y, Vector2(tgt.x - barrel.global_position.x, tgt.z - barrel.global_position.z).length()), -0.35, 0.15)
	_cool -= dt
	if _cool <= 0.0 and d < 70.0 and absf(atan2(lt.x, lt.z)) < 0.12:
		_cool = rng.randf_range(3.5, 5.0)
		_fire(tgt)

func _fire(tgt: Vector3) -> void:
	var tip: Vector3 = barrel.global_transform * Vector3(0, 0, 4.0)
	var aim := tgt + Vector3(rng.randf_range(-3, 3), 0.5, rng.randf_range(-3, 3))
	var n := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.18
	sm.height = 0.36
	n.mesh = sm
	n.material_override = preload("res://scripts/mats.gd").emissive(Color(1.0, 0.7, 0.3), 3.0)
	main.add_child(n)
	n.global_position = tip
	_shells.append({"n": n, "v": (aim - tip).normalized() * 80.0, "t": 0.0})
	FX.sparks(main, tip)
	main.audio.play("tank", tip, 8.0)

func _shell_tick(dt: float) -> void:
	for sh in _shells.duplicate():
		var n: MeshInstance3D = sh.n
		sh.t += dt
		var from := n.global_position
		var to: Vector3 = from + sh.v * dt
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		var pp: Vector3 = main.player.global_position
		var near_p := Geometry3D.get_closest_point_to_segment(pp + Vector3(0, 1, 0), from, to).distance_to(pp + Vector3(0, 1, 0)) < 1.5
		if not hit.is_empty() or near_p or sh.t > 2.0 or to.y < main.world2.WATER_Y - 0.5:
			var at: Vector3 = hit.position if not hit.is_empty() else to
			main.explode_at(at, 7.0, 75.0)
			n.queue_free()
			_shells.erase(sh)
		else:
			n.global_position = to

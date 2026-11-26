extends CharacterBody3D
## Caça do exército (5 estrelas): passa rasante sobre o jogador e dispara pares de mísseis.
## Dá para derrubar (bazuca ou muito tiro).

const CM := preload("res://scripts/carmodel.gd")
const FX := preload("res://scripts/fx.gd")
const M := preload("res://scripts/mats.gd")

var main: Node3D
var hp := 260.0
var dead := false
var kind := "jet"
var _dir := Vector3.FORWARD
var _turn := 0.0
var _cool := 2.0
var _missiles: Array = []
var _fall_v := Vector3.ZERO
var rng := RandomNumberGenerator.new()

func setup(m: Node3D) -> void:
	main = m
	rng.randomize()
	collision_layer = 1
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(9.0, 1.6, 12.0)
	cs.shape = bx
	add_child(cs)
	var grey := Color(0.42, 0.45, 0.48)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	CM._ell(st, Vector3.ZERO, Vector3(1.4, 1.3, 12.0), grey)
	CM._ell(st, Vector3(0, 0.6, 2.2), Vector3(0.9, 0.8, 3.0), Color(0.15, 0.2, 0.28))
	CM._box(st, Vector3(10.0, 0.18, 3.2), Vector3(0, -0.1, -0.6), grey)
	CM._box(st, Vector3(4.2, 0.14, 1.6), Vector3(0, 0.1, -5.2), grey)
	CM._box(st, Vector3(0.16, 2.4, 2.0), Vector3(0, 1.3, -5.0), grey)
	for s in [-1.0, 1.0]:
		CM._box(st, Vector3(0.3, 0.3, 2.2), Vector3(2.8 * s, -0.35, -0.2), Color(0.85, 0.85, 0.85))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = CM.vc_mat()
	add_child(mi)
	FX.fire_emitter(self, Vector3(0, 0, -6.2))

func start(pp: Vector3) -> void:
	var a := rng.randf() * TAU
	global_position = pp + Vector3(cos(a) * 520.0, 70.0, sin(a) * 520.0)
	_dir = (pp - global_position)
	_dir.y = 0
	_dir = _dir.normalized()
	main.audio.play("jet", global_position, 10.0)

## decola da base do exército: sai baixo, sobe e vem atacar
func start_from(p: Vector3) -> void:
	global_position = p + Vector3(0, 8.0, 0)
	var pp: Vector3 = main.player.global_position
	_dir = Vector3(pp.x - p.x, 0, pp.z - p.z).normalized()
	main.audio.play("jet", global_position, 10.0)

func take_damage(d: float) -> void:
	if dead:
		return
	hp -= d
	if hp <= 0.0:
		dead = true
		_fall_v = _dir * 55.0
		FX.smoke_emitter(self, Vector3.ZERO)

func _physics_process(dt: float) -> void:
	_missile_tick(dt)
	if main == null:
		return
	if dead:
		_fall_v.y -= 14.0 * dt
		global_position += _fall_v * dt
		rotation.z += dt * 3.0
		if global_position.y < main.world2.WATER_Y + 0.5 or (global_position.y < 2.0):
			main.explode_at(global_position, 10.0, 80.0)
			queue_free()
		return
	var pp: Vector3 = main.player.global_position
	var to := pp - global_position
	to.y = 0
	var d := to.length()
	# passa por cima, se afasta ~350 m e volta
	if d > 350.0 or (to.normalized().dot(_dir) > 0.0):
		var want := to.normalized()
		var cr := _dir.cross(want).y
		_turn = clampf(cr * 2.0, -0.8, 0.8)
		_dir = _dir.rotated(Vector3.UP, _turn * dt * (1.2 if d > 350.0 else 0.6)).normalized()
	else:
		_turn = lerpf(_turn, 0.0, dt * 2.0)
	var alt: float = 55.0 if d > 160.0 else 38.0
	var vy := clampf((pp.y + alt - global_position.y) * 0.6, -12.0, 12.0)
	global_position += _dir * 62.0 * dt + Vector3(0, vy * dt, 0)
	look_at(global_position + _dir, Vector3.UP)
	rotation.z = -_turn * 0.9
	_cool -= dt
	if _cool <= 0.0 and d < 220.0 and d > 70.0 and to.normalized().dot(_dir) > 0.92:
		_cool = rng.randf_range(6.0, 9.0)
		for s in [-1.0, 1.0]:
			_launch(global_transform * Vector3(2.8 * s, -0.4, 1.0), pp + Vector3(rng.randf_range(-5, 5), 0, rng.randf_range(-5, 5)))

func _launch(from: Vector3, tgt: Vector3) -> void:
	var n := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.22, 0.22, 1.4)
	n.mesh = bm
	n.material_override = M.plain(Color(0.85, 0.85, 0.85), 0.5)
	main.add_child(n)
	n.add_to_group("tmp")
	n.global_position = from
	FX.fire_emitter(n, Vector3(0, 0, -0.8))
	_missiles.append({"n": n, "tgt": tgt, "v": _dir * 62.0, "t": 0.0})
	main.audio.play("rocket", from, 6.0)

func _missile_tick(dt: float) -> void:
	for m in _missiles.duplicate():
		var n: MeshInstance3D = m.n
		m.t += dt
		var want: Vector3 = (m.tgt - n.global_position).normalized() * 70.0
		m.v = m.v.lerp(want, minf(1.0, dt * 2.5))
		var from := n.global_position
		var to: Vector3 = from + m.v * dt
		n.global_position = to
		n.look_at(to + m.v, Vector3.UP if absf(m.v.normalized().y) < 0.98 else Vector3.RIGHT)
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() or n.global_position.distance_to(m.tgt) < 2.0 or m.t > 6.0:
			main.explode_at(hit.position if not hit.is_empty() else to, 8.0, 80.0)
			n.queue_free()
			_missiles.erase(m)

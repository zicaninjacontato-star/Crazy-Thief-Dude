extends Node3D
## Pedestre: caminha pela calçada; atropelado → ragdoll físico, sangue e (opcional) gore.

const Humanoid := preload("res://scripts/humanoid.gd")
const FX := preload("res://scripts/fx.gd")

var loop: Array = []
var idx := 0
var speed := 1.3
var body: Node3D
var down := false
var flee := 0.0
var _rag: Array = []
var _t := 0.0

func setup(path: Array, start: int, rng: RandomNumberGenerator) -> void:
	loop = path
	idx = start % path.size()
	position = path[idx]
	speed = rng.randf_range(1.1, 1.6)
	body = Humanoid.new()
	var shirts := [Color(0.7, 0.2, 0.2), Color(0.2, 0.35, 0.65), Color(0.85, 0.75, 0.3), Color(0.9, 0.9, 0.88), Color(0.2, 0.2, 0.22), Color(0.45, 0.6, 0.35), Color(0.55, 0.35, 0.6)]
	var skins := [Color(0.92, 0.75, 0.6), Color(0.55, 0.36, 0.22), Color(0.78, 0.56, 0.38), Color(0.35, 0.22, 0.14)]
	body.build(shirts[rng.randi() % shirts.size()], Color(0.15, 0.16, 0.2).lightened(rng.randf() * 0.3), skins[rng.randi() % skins.size()], Color(0.1, 0.07, 0.05).lightened(rng.randf() * 0.4))
	add_child(body)
	body.set_far(55.0)

func hit(from_body: PhysicsBody3D, vel: Vector3, gore: bool) -> void:
	if down:
		return
	down = true
	var v := vel * 0.85 + Vector3(0, 2.5 + vel.length() * 0.18, 0)
	var r: Array = body.ragdoll(v, from_body, gore)
	if r.is_empty():
		return
	_rag = body.parts
	var chest: RigidBody3D = r[0]["chest"]
	FX.blood_burst(get_tree().current_scene, chest.global_position, vel.normalized(), 30 if vel.length() > 8.0 else 16)
	if r[1] != "":
		var torn: RigidBody3D = r[0][r[1]]
		FX.blood_burst(get_tree().current_scene, torn.global_position, Vector3.UP, 40)
		FX.blood_trail(torn)

func scare() -> void:
	if not down:
		flee = 6.0

func _process(dt: float) -> void:
	if down:
		_t += dt
		if _t > 1.6 and _t - dt <= 1.6 and _rag.size() > 1:
			FX.blood_pool(get_tree().current_scene, _rag[1].global_position)
		if _t > 40.0:
			for p in _rag:
				if is_instance_valid(p):
					p.queue_free()
			queue_free()
		return
	var target: Vector3 = loop[(idx + 1) % loop.size()]
	var to := target - position
	to.y = 0
	if to.length() < 0.3:
		idx = (idx + 1) % loop.size()
		return
	var sp := speed * (2.8 if flee > 0.0 else 1.0)
	flee -= dt
	var step := to.normalized() * sp * dt
	position += step
	body.rotation.y = lerp_angle(body.rotation.y, atan2(step.x, step.z), minf(1.0, dt * 8.0))
	body.animate(sp, dt)

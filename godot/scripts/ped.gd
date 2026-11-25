extends Node3D
## Pedestre: caminha pela calçada em volta da quadra; se for atropelado, cai e o jogador ganha procurado.

const Humanoid := preload("res://scripts/humanoid.gd")

var loop: Array = []
var idx := 0
var speed := 1.3
var body: Node3D
var down := false
var vel := Vector3.ZERO
var spin := Vector3.ZERO
var t_down := 0.0

func setup(path: Array, start: int, rng: RandomNumberGenerator) -> void:
	loop = path
	idx = start % path.size()
	position = path[idx]
	speed = rng.randf_range(1.1, 1.6)
	body = Humanoid.new()
	var shirts := [Color(0.7, 0.2, 0.2), Color(0.2, 0.35, 0.65), Color(0.85, 0.75, 0.3), Color(0.9, 0.9, 0.88), Color(0.2, 0.2, 0.22), Color(0.45, 0.6, 0.35)]
	var skins := [Color(0.92, 0.75, 0.6), Color(0.55, 0.36, 0.22), Color(0.78, 0.56, 0.38), Color(0.35, 0.22, 0.14)]
	body.build(shirts[rng.randi() % shirts.size()], Color(0.15, 0.16, 0.2).lightened(rng.randf() * 0.3), skins[rng.randi() % skins.size()], Color(0.1, 0.07, 0.05).lightened(rng.randf() * 0.4))
	add_child(body)

func hit(from: Vector3, impulse: float) -> void:
	if down:
		return
	down = true
	var d := (global_position - from)
	d.y = 0
	vel = d.normalized() * impulse * 0.6 + Vector3(0, 3.5 + impulse * 0.15, 0)
	spin = Vector3(randf_range(-6, 6), randf_range(-3, 3), randf_range(-6, 6))

func _process(dt: float) -> void:
	if down:
		t_down += dt
		vel.y -= 18.0 * dt
		position += vel * dt
		if position.y <= 0.15:
			position.y = 0.15
			vel = vel * 0.6
			vel.y = 0
			spin *= 0.5
			if t_down > 0.3:
				body.rotation.x = lerp_angle(body.rotation.x, -PI * 0.5, minf(1.0, dt * 6.0))
				return
		body.rotation += spin * dt
		return
	var target: Vector3 = loop[(idx + 1) % loop.size()]
	var to := target - position
	to.y = 0
	if to.length() < 0.3:
		idx = (idx + 1) % loop.size()
		return
	var step := to.normalized() * speed * dt
	position += step
	body.rotation.y = lerp_angle(body.rotation.y, atan2(step.x, step.z), minf(1.0, dt * 8.0))
	body.animate(speed, dt)

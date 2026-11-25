extends Node3D
## Policial a pé: sai da viatura, corre até o jogador, atira quando tem linha de visão e pode ser
## derrubado (ragdoll). O dano ao jogador é aplicado pelo main (sinal shot_player).

const Humanoid := preload("res://scripts/humanoid.gd")
const W := preload("res://scripts/weapons.gd")
const FX := preload("res://scripts/fx.gd")

signal shot_player(dmg: float, from: Vector3)

var target: Node3D
var body: Node3D
var hp := 100.0
var down := false
var cool := 1.0
var speed := 4.2
var _t := 0.0
var rng := RandomNumberGenerator.new()

func setup(seed: int) -> void:
	rng.seed = seed
	body = Humanoid.new()
	body.build(Color(0.12, 0.2, 0.42), Color(0.08, 0.1, 0.2), [Color(0.92, 0.75, 0.6), Color(0.55, 0.36, 0.22), Color(0.78, 0.56, 0.38)][rng.randi() % 3], Color(0.05, 0.06, 0.12))
	add_child(body)
	body.set_far(70.0)
	body.give_gun(W.gun_mesh("pistol"))
	cool = rng.randf_range(0.8, 1.8)

func damage(amount: float, dir: Vector3, gore: bool, src: PhysicsBody3D = null) -> bool:
	if down:
		return false
	hp -= amount
	FX.blood_burst(get_tree().current_scene, global_position + Vector3(0, 1.3, 0), dir, 10)
	if hp <= 0.0:
		down = true
		body.ragdoll(dir * 4.0 + Vector3(0, 1.5, 0), src, gore and amount > 60.0)
		get_tree().create_timer(30.0).timeout.connect(_cleanup)
		return true
	return false

func _cleanup() -> void:
	for p in body.parts:
		if is_instance_valid(p):
			p.queue_free()
	queue_free()

func _process(dt: float) -> void:
	if down or target == null or not is_instance_valid(target):
		return
	_t += dt
	var to := target.global_position - global_position
	to.y = 0
	var d := to.length()
	var face := atan2(to.x, to.z)
	body.rotation.y = lerp_angle(body.rotation.y, face, minf(1.0, dt * 8.0))
	if d > 7.0:
		position += to.normalized() * speed * dt
		body.aiming = false
		body.animate(speed, dt)
	else:
		body.aiming = true
		body.animate(0.0, dt)
	cool -= dt
	if cool <= 0.0 and d < 26.0:
		cool = rng.randf_range(0.9, 1.6)
		var muzzle := global_position + Vector3(0, 1.4, 0) + to.normalized() * 0.6
		var hitp: bool = rng.randf() < clampf(0.6 - d * 0.015, 0.2, 0.6)
		var aim := target.global_position + Vector3(0, 1.2, 0)
		if not hitp:
			aim += Vector3(rng.randf_range(-1.5, 1.5), rng.randf_range(-0.5, 1.0), rng.randf_range(-1.5, 1.5))
		W.tracer(get_tree().current_scene, muzzle, aim)
		shot_player.emit(8.0 if hitp else 0.0, global_position)

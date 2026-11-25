extends CharacterBody3D
## Policial a pé (também usado para capangas de missão com 'hostile_skin').
## Corpo físico (não atravessa paredes), mantém distância preferida do alvo, anda de lado (strafe),
## só atira com linha de visão. Com 'arrest_only' corre para prender sem atirar.
## O dano ao jogador é aplicado pelo main/combat (sinal shot_player).

const Humanoid := preload("res://scripts/humanoid.gd")
const W := preload("res://scripts/weapons.gd")
const FX := preload("res://scripts/fx.gd")

signal shot_player(dmg: float, from: Vector3)
signal died(cop)

var target: Node3D
var body: Node3D
var hp := 100.0
var down := false
var cool := 1.0
var speed := 4.4
var accuracy := 0.45
var dmg := 8.0
var rate := 1.3
var arrest_only := false
var pref := 10.0
var unit = null              # viatura de origem
var weapon := "pistol"
var _strafe := 1.0
var _strafe_t := 0.0
var _los := false
var _los_t := 0.0
var _t := 0.0
var rng := RandomNumberGenerator.new()

func setup(seed: int, kind := "cop") -> void:
	rng.seed = seed
	collision_layer = 0
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.88
	add_child(cs)
	body = Humanoid.new()
	var skin: Color = [Color(0.92, 0.75, 0.6), Color(0.55, 0.36, 0.22), Color(0.78, 0.56, 0.38)][rng.randi() % 3]
	match kind:
		"swat":
			body.build(Color(0.1, 0.1, 0.12), Color(0.08, 0.08, 0.1), skin, Color(0.05, 0.05, 0.06), {"hat": 2, "hat_c": Color(0.08, 0.08, 0.1), "glasses": true, "jacket": Color(0.12, 0.13, 0.15)})
			hp = 160.0
			weapon = "rifle"
			dmg = 9.0
			rate = 0.55
		"thug":
			body.build(Color(0.15, 0.15, 0.15), Color(0.1, 0.1, 0.32), skin, Color(0.05, 0.04, 0.03), {"hat": 1, "hat_c": Color(0.7, 0.1, 0.1), "jacket": Color(0.6, 0.05, 0.05)})
			weapon = "smg" if rng.randf() < 0.5 else "pistol"
			rate = 0.5 if weapon == "smg" else 1.1
			dmg = 6.0 if weapon == "smg" else 8.0
		_:
			body.build(Color(0.12, 0.2, 0.42), Color(0.08, 0.1, 0.2), skin, Color(0.05, 0.06, 0.12), {"hat": 1, "hat_c": Color(0.08, 0.1, 0.22)})
	add_child(body)
	body.set_far(80.0)
	body.give_gun(W.gun_mesh(weapon))
	cool = rng.randf_range(0.8, 1.8)
	pref = rng.randf_range(7.0, 14.0)
	_strafe = 1.0 if rng.randf() < 0.5 else -1.0

func damage(amount: float, dir: Vector3, gore: bool, src: PhysicsBody3D = null) -> bool:
	if down:
		return false
	hp -= amount
	FX.blood_burst(get_tree().current_scene, global_position + Vector3(0, 1.3, 0), dir, 10)
	if hp <= 0.0:
		_die(dir * (4.0 if amount < 60.0 else 9.0) + Vector3(0, 1.5, 0), src, gore and amount > 60.0)
		return true
	pref = maxf(5.0, pref - 2.0)    # ferido: avança
	return false

## atropelado / explosão
func hit(from_body: PhysicsBody3D, vel: Vector3, gore: bool) -> void:
	if down:
		return
	FX.blood_burst(get_tree().current_scene, global_position + Vector3(0, 1.2, 0), vel.normalized(), 24)
	_die(vel * 0.85 + Vector3(0, 2.5 + vel.length() * 0.18, 0), from_body, gore)

func _die(imp: Vector3, src, gore: bool) -> void:
	down = true
	collision_mask = 0
	body.ragdoll(imp, src, gore)
	died.emit(self)
	get_tree().create_timer(30.0).timeout.connect(_cleanup)

func _cleanup() -> void:
	for p in body.parts:
		if is_instance_valid(p):
			p.queue_free()
	queue_free()

func _physics_process(dt: float) -> void:
	if down:
		return
	_t += dt
	if not is_on_floor():
		velocity.y -= 18.0 * dt
	else:
		velocity.y = -0.5
	if target == null or not is_instance_valid(target):
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		body.animate(0.0, dt)
		return
	var tp: Vector3 = target.global_position
	var to := tp - global_position
	to.y = 0
	var d := to.length()
	var dirv := to / maxf(d, 0.01)
	var face := atan2(to.x, to.z)
	body.rotation.y = lerp_angle(body.rotation.y, face, minf(1.0, dt * 8.0))
	# linha de visão (2x por segundo)
	_los_t -= dt
	if _los_t <= 0.0:
		_los_t = 0.5
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.5, 0), tp + Vector3(0, 1.2, 0), 1)
		q.exclude = [get_rid()]
		var r := get_world_3d().direct_space_state.intersect_ray(q)
		_los = r.is_empty() or r.collider == target or (r.collider is Node and (r.collider as Node).get_meta("player", false))
	var want := Vector3.ZERO
	var goal := 1.1 if arrest_only else pref
	if d > goal + 1.5 or not _los:
		want = dirv * speed
	elif d < goal - 3.0 and not arrest_only:
		want = -dirv * speed * 0.6
	elif not arrest_only:
		_strafe_t -= dt
		if _strafe_t <= 0.0:
			_strafe_t = rng.randf_range(1.2, 2.8)
			_strafe = -_strafe if rng.randf() < 0.6 else _strafe
		want = Vector3(-dirv.z, 0, dirv.x) * _strafe * 2.0
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(want, 18.0 * dt)
	velocity.x = hv.x
	velocity.z = hv.z
	move_and_slide()
	body.aiming = not arrest_only and d < 30.0
	body.animate(hv.length(), dt)
	if arrest_only:
		return
	cool -= dt
	if cool <= 0.0 and d < 34.0 and _los:
		cool = rng.randf_range(rate * 0.7, rate * 1.3)
		var muzzle := global_position + Vector3(0, 1.4, 0) + dirv * 0.6
		var hitp: bool = rng.randf() < clampf(accuracy - d * 0.01, 0.12, 0.85)
		var aim := tp + Vector3(0, 1.2, 0)
		if not hitp:
			aim += Vector3(rng.randf_range(-1.5, 1.5), rng.randf_range(-0.5, 1.0), rng.randf_range(-1.5, 1.5))
		W.tracer(get_tree().current_scene, muzzle, aim)
		shot_player.emit(dmg if hitp else 0.0, global_position)

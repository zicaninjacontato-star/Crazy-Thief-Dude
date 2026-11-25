extends Node3D
## Pedestre: caminha pela calçada em volta da quadra e às vezes atravessa na faixa (só quando o
## semáforo fecha para os carros daquela rua). Colisão estilo "Euphoria": encostar andando empurra
## e ele cambaleia; passar correndo ou bater de leve com carro derruba (ragdoll) e ele levanta depois.
## Atropelado forte / morto → ragdoll definitivo, sangue e (opcional) gore.

const Humanoid := preload("res://scripts/humanoid.gd")
const FX := preload("res://scripts/fx.gd")
const Traffic := preload("res://scripts/traffic.gd")

var loop: Array = []
var idx := 0
var speed := 1.3
var body: Node3D
var down := false
var flee := 0.0
var _rag: Array = []
var _t := 0.0
var hp := 100.0
var knocked := 0.0           # >0: caído, vai levantar
var stagger := 0.0
var cross_to := Vector3.INF  # atravessando a rua
var cross_axis := ""
var _cross_loop: Array = []
var _cross_idx := 0
var _look := Vector3.ZERO
var _cols := []
var _rng := RandomNumberGenerator.new()
signal died(ped)

func setup(path: Array, start: int, rng: RandomNumberGenerator) -> void:
	loop = path
	idx = start % path.size()
	position = path[idx]
	speed = rng.randf_range(1.1, 1.6)
	_rng.seed = rng.randi()
	var shirts := [Color(0.7, 0.2, 0.2), Color(0.2, 0.35, 0.65), Color(0.85, 0.75, 0.3), Color(0.9, 0.9, 0.88), Color(0.2, 0.2, 0.22), Color(0.45, 0.6, 0.35), Color(0.55, 0.35, 0.6)]
	var skins := [Color(0.92, 0.75, 0.6), Color(0.55, 0.36, 0.22), Color(0.78, 0.56, 0.38), Color(0.35, 0.22, 0.14)]
	beach = path.size() > 0 and path[0].x > 170.0     # laço da praia
	_cols = [shirts[rng.randi() % shirts.size()], Color(0.15, 0.16, 0.2).lightened(rng.randf() * 0.3), skins[rng.randi() % skins.size()], Color(0.1, 0.07, 0.05).lightened(rng.randf() * 0.4)]
	if beach:
		_cols[1] = Color.from_hsv(rng.randf(), 0.65, 0.75)
	_make_body()

var beach := false
func _make_body() -> void:
	body = Humanoid.new()
	body.build(_cols[0], _cols[1], _cols[2], _cols[3], {"beach": beach})
	add_child(body)
	body.set_far(55.0)

func hit(from_body: PhysicsBody3D, vel: Vector3, gore: bool) -> void:
	if down:
		return
	down = true
	knocked = 0.0
	died.emit(self)
	if body.ragdolled:
		FX.blood_burst(get_tree().current_scene, global_position + Vector3(0, 0.5, 0), vel.normalized(), 16)
		for p in body.parts:
			if is_instance_valid(p):
				p.apply_central_impulse(vel * p.mass * 0.5)
		_rag = body.parts
		return
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

## derruba sem matar (empurrão forte, carro devagar). Se a vida acabar, vira morte.
func knock(vel: Vector3, dmg: float) -> void:
	if down:
		return
	hp -= dmg
	if hp <= 0.0:
		hit(null, vel, false)
		return
	if knocked > 0.0:
		return
	knocked = 3.2
	flee = 0.0
	body.ragdoll(vel + Vector3(0, 1.5, 0), null, false)
	_rag = body.parts

func _get_up() -> void:
	var hips := global_position
	if body.parts.size() > 0 and is_instance_valid(body.parts[0]):
		hips = body.parts[0].global_position
	for p in body.parts:
		if is_instance_valid(p):
			p.queue_free()
	body.queue_free()
	global_position = Vector3(hips.x, global_position.y, hips.z)
	_make_body()
	_rag = []
	flee = 6.0
	cross_to = Vector3.INF

## dano de arma/soco; true se morreu
func damage(amount: float, dir: Vector3, gore: bool, src: PhysicsBody3D = null) -> bool:
	if down:
		return false
	hp -= amount
	FX.blood_burst(get_tree().current_scene, global_position + Vector3(0, 1.3, 0), dir, 10)
	if hp <= 0.0:
		hit(src, dir * (5.0 if amount < 60.0 else 9.0), gore and amount > 60.0)
		return true
	flee = 8.0
	stagger = 0.35
	return false

func scare() -> void:
	if not down:
		flee = 6.0

func _process(dt: float) -> void:
	if down:
		_t += dt
		if _t > 1.6 and _t - dt <= 1.6 and _rag.size() > 1 and is_instance_valid(_rag[1]):
			FX.blood_pool(get_tree().current_scene, _rag[1].global_position)
		if _t > 40.0:
			for p in _rag:
				if is_instance_valid(p):
					p.queue_free()
			queue_free()
		return
	if knocked > 0.0:
		knocked -= dt
		if knocked <= 0.0:
			_get_up()
		return
	_bump(dt)
	if stagger > 0.0:
		stagger -= dt
		body.animate(0.5, dt)
		return
	var sp := speed * (2.8 if flee > 0.0 else 1.0)
	flee -= dt
	var target: Vector3
	if cross_to != Vector3.INF:
		# esperando o sinal na beira da calçada / atravessando
		var moving := Vector2(position.x - cross_to.x, position.z - cross_to.z).length() < _cross_len - 0.3
		if not moving and Traffic.green(cross_axis) or not moving and Traffic.yellow(cross_axis):
			body.animate(0.0, dt)
			if flee <= 0.0:
				return
		target = cross_to
		if Vector2(position.x - target.x, position.z - target.z).length() < 0.3:
			loop = _cross_loop
			idx = _cross_idx
			cross_to = Vector3.INF
			return
	else:
		target = loop[(idx + 1) % loop.size()]
	var to := target - position
	to.y = 0
	if to.length() < 0.3:
		idx = (idx + 1) % loop.size()
		if loop.size() == 4 and _rng.randf() < 0.3 and flee <= 0.0:
			_try_cross()
		return
	var step := to.normalized() * sp * dt
	position += step
	body.rotation.y = lerp_angle(body.rotation.y, atan2(step.x, step.z), minf(1.0, dt * 8.0))
	body.animate(sp, dt)

var _cross_len := 0.0
## na esquina: atravessa para a quadra vizinha (na faixa de pedestres)
func _try_cross() -> void:
	var main := get_tree().current_scene
	if main == null or not ("city" in main):
		return
	var city = main.city
	var here: Vector3 = loop[idx]
	var c: Vector3 = (loop[0] + loop[2]) * 0.5
	var sx := signf(here.x - c.x)
	var sz := signf(here.z - c.z)
	var r: float = absf(here.x - c.x)
	var opts := []
	# atravessar a rua N-S (andando em x): carros dessa rua têm que estar parados (eixo "ns" fechado)
	opts.append([Vector3(c.x + sx * (city.CELL - r), here.y, here.z), "ns"])
	opts.append([Vector3(here.x, here.y, c.z + sz * (city.CELL - r)), "ew"])
	var o: Array = opts[_rng.randi() % 2]
	var dest: Vector3 = o[0]
	for l in city.walk_loops:
		for k in 4:
			if l[k].distance_to(dest) < 0.6:
				_cross_loop = l
				_cross_idx = k
				cross_to = dest
				cross_axis = o[1]
				_cross_len = Vector2(here.x - dest.x, here.z - dest.z).length()
				return

## colisão com o jogador a pé (empurra / derruba se ele vier correndo)
func _bump(dt: float) -> void:
	var main := get_tree().current_scene
	if main == null or not ("player" in main):
		return
	var pl = main.player
	if pl == null or pl.vehicle != null or not pl.visible:
		return
	var rel: Vector3 = global_position - pl.global_position
	rel.y = 0
	var d := rel.length()
	if d > 0.75 or d < 0.001:
		return
	var pv := Vector2(pl.velocity.x, pl.velocity.z).length()
	var away := rel / d
	if pv > 4.6:
		knock(Vector3(pl.velocity.x, 0, pl.velocity.z) * 1.15 + away * 2.0, 8.0)
		main.audio.play("hit", global_position, -2.0)
		if main.wanted == 0 and pl.has_method("is_on_floor"):
			pass
	else:
		position += away * (0.75 - d)
		if pv > 1.5:
			stagger = 0.4
			body.rotation.y = atan2(-away.x, -away.z)

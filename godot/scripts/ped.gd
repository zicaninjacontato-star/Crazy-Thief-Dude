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
# reações: "" normal · "handsup" rendido · "call" ligando para a polícia · "brawl" brigando · "hostage" refém
var mode := ""
var mode_t := 0.0
var reacted := false
var robbed := false
var blocking := false
var _atk_cd := 0.8
var _atk_hit := -1.0

func setup(path: Array, start: int, rng: RandomNumberGenerator) -> void:
	add_to_group("tmp")
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
	body.rag_alive = true
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

## dano de arma/soco; true se morreu. zone = parte atingida (cabeça mata quase sempre; perna faz
## mancar e às vezes cair; braço faz segurar o braço; tronco faz cambalear para trás)
var limp_t := 0.0
func damage(amount: float, dir: Vector3, gore: bool, src: PhysicsBody3D = null, zone := "torso") -> bool:
	if down:
		return false
	amount *= {"head": 3.2, "leg": 0.55, "arm": 0.45}.get(zone, 1.0)
	hp -= amount
	if hp > 0.0 and amount > 5.0:
		match zone:
			"leg":
				limp_t = 14.0
				body.limp = 1.0
				if _rng.randf() < 0.35:
					knock(dir * 2.0 + Vector3(0, 0.5, 0), 0.0)       # a perna cede
					return false
			"arm":
				body.arm_hurt = 10.0
			"torso":
				position += Vector3(dir.x, 0, dir.z).normalized() * 0.35   # empurrão do impacto
			"head":
				knock(dir * 3.0 + Vector3(0, 1.0, 0), 0.0)
				return false
	FX.blood_burst(get_tree().current_scene, global_position + Vector3(0, 1.3, 0), dir, 10)
	if hp <= 0.0:
		hit(src, dir * (5.0 if amount < 60.0 else 9.0), gore and amount > 60.0)
		return true
	stagger = 0.35
	if mode == "brawl":
		stagger = 0.18
		return false
	if mode == "hostage":
		return false
	# soco: alguns revidam e começam uma briga
	if amount < 40.0 and _rng.randf() < 0.45 and not beach and get_tree().current_scene.combat.weapon == "fist":
		start_brawl()
		return false
	_end_mode()
	flee = 8.0
	return false

func scare() -> void:
	if not down and mode != "hostage" and mode != "handsup" and mode != "clerk":
		_end_mode()
		flee = 6.0

func _end_mode() -> void:
	mode = ""
	blocking = false
	if body:
		body.arm_pose = ""
		body.guard = false

func start_brawl() -> void:
	_end_mode()
	mode = "brawl"
	mode_t = 25.0
	flee = 0.0
	cross_to = Vector3.INF
	body.guard = true
	_atk_cd = 0.6

func dodge(dir: Vector3) -> void:
	var side := Vector3(dir.z, 0, -dir.x) * (1.0 if _rng.randf() < 0.5 else -1.0)
	position += side * 0.9 + dir * 0.3
	stagger = 0.15

## arma apontada para ele: foge, liga para a polícia, parte para cima ou se rende
func react_aim() -> void:
	if reacted or down or mode != "" or knocked > 0.0:
		return
	reacted = true
	var r := _rng.randf()
	cross_to = Vector3.INF
	var main := get_tree().current_scene
	if r < 0.32:
		flee = 10.0
		main.audio.play("scream", global_position, -6.0)
	elif r < 0.52:
		mode = "call"
		mode_t = 3.5
		body.arm_pose = "phone"
		flee = 0.0
	elif r < 0.67:
		start_brawl()
	else:
		mode = "handsup"
		mode_t = 6.0
		body.arm_pose = "handsup"
		flee = 0.0

func _mode_tick(dt: float) -> void:
	var main := get_tree().current_scene
	var pl = main.player
	if mode == "clerk":
		# atendente atrás do balcão: olha para o cliente quando ele chega perto
		var tp: Vector3 = pl.global_position - global_position
		if tp.length() < 6.0:
			body.rotation.y = lerp_angle(body.rotation.y, atan2(tp.x, tp.z), minf(1.0, dt * 4.0))
		body.animate(0.0, dt)
		return
	var to: Vector3 = pl.global_position - global_position
	to.y = 0
	var d := to.length()
	mode_t -= dt
	match mode:
		"handsup":
			body.rotation.y = lerp_angle(body.rotation.y, atan2(to.x, to.z), minf(1.0, dt * 6.0))
			body.animate(0.0, dt)
			if main.combat.aiming_at(self):
				mode_t = maxf(mode_t, 3.0)
			if mode_t <= 0.0 or d > 20.0:
				_end_mode()
				flee = 10.0
		"call":
			# corre um pouco para longe enquanto liga
			var away := -to.normalized() if d > 0.01 else Vector3.FORWARD
			position += away * 1.6 * dt
			body.rotation.y = lerp_angle(body.rotation.y, atan2(away.x, away.z), minf(1.0, dt * 6.0))
			body.animate(1.6, dt)
			if mode_t <= 0.0:
				_end_mode()
				flee = 10.0
				if main.wanted == 0:
					main._add_wanted(1)
				main._msg("Alguém chamou a polícia!")
		"brawl":
			if pl.vehicle != null or main.combat.dead or d > 24.0 or mode_t <= 0.0:
				_end_mode()
				flee = 6.0
				return
			body.guard = true
			mode_t = maxf(mode_t, 8.0) if d < 4.0 else mode_t
			body.rotation.y = lerp_angle(body.rotation.y, atan2(to.x, to.z), minf(1.0, dt * 8.0))
			blocking = pl.body != null and pl.body.punch_t > 0.15 and _rng.randf() < 0.02 + 0.3 * dt
			if d > 1.15:
				var sp := 3.6 if d > 3.0 else 2.0
				position += to.normalized() * sp * dt
				body.animate(sp, dt)
			else:
				# círculo de luta: passinhos laterais
				position += Vector3(to.z, 0, -to.x).normalized() * sin(_t * 2.3) * 0.6 * dt
				_t += dt
				body.animate(0.4, dt)
				_atk_cd -= dt
				if _atk_cd <= 0.0:
					_atk_cd = _rng.randf_range(0.7, 1.4)
					body.punch_kind = [0, 1, 4, 3][_rng.randi() % 4]
					body.punch_t = 0.3
					_atk_hit = 0.14
			if _atk_hit > 0.0:
				_atk_hit -= dt
				if _atk_hit <= 0.0 and d < 1.6:
					main.combat.melee_hit_player(_rng.randf_range(6.0, 13.0) * (1.6 if body.punch_kind == 3 else 1.0), global_position)
				elif _atk_hit <= 0.0:
					main.audio.play("swoosh", global_position, -6.0)
		"hostage":
			body.animate(0.0, dt)

## otimização: pedestre longe do jogador (fora da distância em que é desenhado) atualiza 5×/s
var _acc := 0.0
var _far_t := 0.0
var _is_far := false
func _process(dt: float) -> void:
	_far_t -= dt
	if _far_t <= 0.0:
		_far_t = 0.4 + _rng.randf() * 0.2
		var pl = get_tree().current_scene.get("player")
		_is_far = pl != null and mode == "" and knocked <= 0.0 and global_position.distance_squared_to(pl.global_position) > 62.0 * 62.0
	if _is_far:
		_acc += dt
		if _acc < 0.2:
			return
		dt = _acc
	_acc = 0.0
	_ped_tick(dt)

func _ped_tick(dt: float) -> void:
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
	if mode != "" and stagger <= 0.0:
		_mode_tick(dt)
		return
	if mode == "":
		_bump(dt)
	if stagger > 0.0:
		stagger -= dt
		body.animate(0.5, dt)
		return
	if limp_t > 0.0:
		limp_t -= dt
		body.limp = clampf(limp_t / 4.0, 0.0, 1.0)
	var sp: float = speed * (2.8 if flee > 0.0 else 1.0) * (1.0 - 0.6 * body.limp)
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

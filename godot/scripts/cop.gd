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
signal hurt(cop)
var gang := ""             # "g" verde / "p" rosa (membro de gangue)

var target: Node3D
var searching := false
var _idle_skip := 0.0     # a polícia ainda não sabe onde o jogador está (zona amarela): não atira
var body: Node3D
var hp := 170.0
var _base_speed := -1.0
var down := false
var cool := 1.0
var speed := 4.4
var accuracy := 0.45
var dmg := 8.0
var rate := 1.3
var arrest_only := false
var pref := 10.0
var unit = null              # viatura de origem
var patrol: Array = []       # patrulha a pé: laço da calçada (sem alvo)
var _pi := 0
var weapon := "pistol"
var _strafe := 1.0
var _strafe_t := 0.0
var _los := false
var _los_t := 0.0
var _t := 0.0
var rng := RandomNumberGenerator.new()

var kind := "cop"
var swimming := false
func setup(seed: int, kind := "cop") -> void:
	self.kind = kind
	rng.seed = seed
	add_to_group("tmp")
	collision_layer = 0
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.88
	add_child(cs)
	_skin = [Color(0.92, 0.75, 0.6), Color(0.55, 0.36, 0.22), Color(0.78, 0.56, 0.38)][rng.randi() % 3]
	_rebuild_body(true)
	cool = rng.randf_range(0.8, 1.8)
	pref = rng.randf_range(7.0, 14.0)
	_strafe = 1.0 if rng.randf() < 0.5 else -1.0

var _skin := Color.WHITE
func _rebuild_body(first := false) -> void:
	body = Humanoid.new()
	var skin := _skin
	match kind:
		"swat":
			body.build(Color(0.1, 0.1, 0.12), Color(0.08, 0.08, 0.1), skin, Color(0.05, 0.05, 0.06), {"hat": 2, "hat_c": Color(0.08, 0.08, 0.1), "glasses": true, "jacket": Color(0.12, 0.13, 0.15)})
			if first:
				hp = 240.0
				weapon = "rifle"
				dmg = 9.0
				rate = 0.55
		"heavy":
			# policial de armadura (5 estrelas): colete pesado, capacete, fuzil potente, aguenta muito
			body.build(Color(0.16, 0.17, 0.14), Color(0.1, 0.1, 0.09), skin, Color(0.05, 0.05, 0.05), {"hat": 2, "hat_c": Color(0.12, 0.13, 0.11), "glasses": true, "jacket": Color(0.22, 0.24, 0.18)})
			body.scale = Vector3(1.1, 1.06, 1.15)
			if first:
				hp = 420.0
				weapon = "rifle"
				dmg = 13.0
				rate = 0.38
		"gang_g", "gang_p":
			# gangue: camiseta/bandana na cor da gangue
			var gc: Color = Color(0.1, 0.62, 0.22) if kind == "gang_g" else Color(0.95, 0.32, 0.68)
			body.build(gc, Color(0.12, 0.12, 0.14), skin, Color(0.04, 0.03, 0.02), {"hat": 2 if rng.randf() < 0.5 else 1, "hat_c": gc.darkened(0.2), "jacket": Color(0.06, 0.06, 0.07) if rng.randf() < 0.4 else Color(0, 0, 0, 0)})
			if first:
				hp = 120.0
				speed = 4.8
		"thug":
			body.build(Color(0.15, 0.15, 0.15), Color(0.1, 0.1, 0.32), skin, Color(0.05, 0.04, 0.03), {"hat": 1, "hat_c": Color(0.7, 0.1, 0.1), "jacket": Color(0.6, 0.05, 0.05)})
			if first:
				weapon = "smg" if rng.randf() < 0.5 else "pistol"
				rate = 0.5 if weapon == "smg" else 1.1
				dmg = 6.0 if weapon == "smg" else 8.0
		_:
			body.build(Color(0.12, 0.2, 0.42), Color(0.08, 0.1, 0.2), skin, Color(0.05, 0.06, 0.12), {"hat": 1, "hat_c": Color(0.08, 0.1, 0.22)})
	add_child(body)
	body.set_far(80.0)
	body.give_gun(W.gun_mesh(weapon))
	body.gun_kind = weapon

## polícia aguenta mais (hp maior), mas também sente: perna = manca e anda devagar, braço = mira
## pior por um tempo, tronco = cambaleia e para de atirar um instante, cabeça = muito dano
var limp_t := 0.0
var arm_t := 0.0
func damage(amount: float, dir: Vector3, gore: bool, src: PhysicsBody3D = null, zone := "torso") -> bool:
	if down:
		return false
	hurt.emit(self)
	amount *= {"head": 2.4 if kind != "heavy" else 1.5, "leg": 0.6, "arm": 0.5}.get(zone, 1.0)
	hp -= amount
	if hp > 0.0:
		match zone:
			"leg":
				limp_t = 12.0
				body.limp = 1.0
			"arm":
				arm_t = 8.0
				body.arm_hurt = 8.0
			_:
				body.hurt_t = 0.35
				cool = maxf(cool, 0.6)
				velocity += Vector3(dir.x, 0, dir.z).normalized() * 2.0
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

## derrubado (queda da moto, empurrão): ragdoll e levanta com animação depois de ~3 s
var knocked := 0.0
func knock(vel: Vector3, _dmg := 0.0) -> void:
	if down or knocked > 0.0:
		return
	knocked = 3.0
	collision_mask = 0
	body.rag_alive = true
	body.ragdoll(vel, null, false)

## troca a arma (gangue sobe de nível: pistola → submetralhadora/escopeta)
func set_weapon(w: String) -> void:
	weapon = w
	rate = {"pistol": 1.1, "smg": 0.45, "shotgun": 1.4, "rifle": 0.6}.get(w, 1.0)
	dmg = {"pistol": 8.0, "smg": 6.0, "shotgun": 16.0, "rifle": 9.0}.get(w, 8.0)
	if body and is_instance_valid(body) and not body.ragdolled:
		body.give_gun(W.gun_mesh(w))
		body.gun_kind = w

func _get_up() -> void:
	var hips := global_position
	if body.parts.size() > 0 and is_instance_valid(body.parts[0]):
		hips = body.parts[0].global_position
	var fd: bool = body.rag_face_down()
	var wd: Array = body.wound_data.duplicate()
	var col_parts: Array = body.parts.duplicate()
	for p in col_parts:
		if is_instance_valid(p):
			p.queue_free()
	body.queue_free()
	global_position = Vector3(hips.x, maxf(hips.y - 0.9, 0.05), hips.z)
	_rebuild_body()
	body.apply_wounds(wd)
	body.start_getup(fd)
	collision_mask = 1
	knocked = -body.GETUP_T

func _die(imp: Vector3, src, gore: bool) -> void:
	down = true
	collision_mask = 0
	body.ragdoll(imp, src, gore)
	died.emit(self)
	if kind in ["cop", "swat", "heavy"]:
		var mn = get_tree().current_scene
		if mn.get("cop_kills") != null and mn.wanted > 0:
			mn.cop_kills += 1
	get_tree().create_timer(30.0).timeout.connect(_cleanup)

var _stuck_t := 0.0
var _side_t := 0.0
var _side_dir := 1.0
var cover_pos := Vector3.INF
var _cover_t := 0.0
var _peek := 0.0
var rescue_rb: RigidBody3D = null
var rescue_dest := Vector3.ZERO
var _rescue_t := 0.0
var anim := ""            # "tackle" / "pull" (prisão a 1 estrela)
var anim_t := 0.0
var anim_cb: Callable

func _find_cover(tp: Vector3) -> Vector3:
	var main := get_tree().current_scene
	var best := Vector3.INF
	var bs := 1e9
	for c in main.cars:
		if not is_instance_valid(c) or c.linear_velocity.length() > 2.0 or c == main.player.vehicle:
			continue
		var cp: Vector3 = c.global_position
		if cp.distance_to(global_position) > 22.0:
			continue
		var away := cp - tp
		away.y = 0
		if away.length() < 5.0:
			continue
		var pt: Vector3 = cp + away.normalized() * (c.body_size.x * 0.5 + 0.9)
		pt.y = global_position.y
		var dt_ := pt.distance_to(tp)
		if dt_ < 6.0 or dt_ > 32.0:
			continue
		var taken := false
		for o in main.police.cops:
			if o != self and is_instance_valid(o) and o.cover_pos.distance_to(pt) < 1.4:
				taken = true
		if taken:
			continue
		var sc := pt.distance_to(global_position)
		if sc < bs:
			bs = sc
			best = pt
	return best

## arrasta um colega caído para um lugar seguro
func start_rescue(rb: RigidBody3D, dest: Vector3) -> void:
	rescue_rb = rb
	rescue_dest = dest
	_rescue_t = 0.0

func _rescue_tick(dt: float) -> void:
	_rescue_t += dt
	if not is_instance_valid(rescue_rb) or _rescue_t > 9.0:
		rescue_rb = null
		body.pose = ""
		return
	if not is_on_floor():
		velocity.y -= 18.0 * dt
	var bp: Vector3 = rescue_rb.global_position
	var to_b := bp - global_position
	to_b.y = 0
	if to_b.length() > 1.3 and body.pose != "drag":
		velocity = Vector3(to_b.normalized().x * speed, velocity.y, to_b.normalized().z * speed)
		body.rotation.y = atan2(to_b.x, to_b.z)
		move_and_slide()
		body.animate(speed, dt)
		return
	body.pose = "drag"
	var to_d := rescue_dest - global_position
	to_d.y = 0
	if to_d.length() < 1.0:
		rescue_rb = null
		body.pose = ""
		return
	var mv := to_d.normalized() * 1.7
	velocity = Vector3(mv.x, velocity.y, mv.z)
	move_and_slide()
	# anda de costas, de frente para o corpo, e puxa o corpo junto
	body.rotation.y = atan2(-mv.x, -mv.z)
	var hand: Vector3 = global_position - mv.normalized() * 0.9 + Vector3(0, 0.5, 0)
	rescue_rb.linear_velocity = (hand - rescue_rb.global_position) * 6.0
	body.animate(1.7, dt)

## animação curta de prisão; 'cb' roda no fim
func play_anim(a: String, dur: float, cb: Callable) -> void:
	anim = a
	anim_t = 0.0
	_anim_dur = dur
	anim_cb = cb
	body.pose = a

var _anim_dur := 1.0
func _anim_tick(dt: float) -> void:
	anim_t += dt
	body.pose_t = clampf(anim_t / _anim_dur, 0.0, 1.0)
	if anim == "tackle" and target and is_instance_valid(target):
		var to := target.global_position - global_position
		to.y = 0
		if to.length() > 0.5:
			global_position += to.normalized() * minf(to.length(), 7.0 * dt)
	body.animate(0.0, dt)
	if anim_t >= _anim_dur:
		anim = ""
		body.pose = ""
		if anim_cb.is_valid():
			anim_cb.call()

func _cleanup() -> void:
	for p in body.parts:
		if is_instance_valid(p):
			p.queue_free()
	queue_free()

func _physics_process(dt: float) -> void:
	if down:
		return
	if knocked > 0.0:
		knocked -= dt
		if knocked <= 0.0:
			_get_up()
		return
	if knocked < 0.0:
		knocked = minf(0.0, knocked + dt)
		body.animate(0.0, dt)
		return
	# sem alvo (gangue parada, patrulha) e longe do jogador: pensa só 4×/s e não move a física
	if target == null:
		_idle_skip -= dt
		if _idle_skip > 0.0:
			return
		var pl = get_tree().current_scene.get("player")
		if pl and global_position.distance_squared_to(pl.global_position) > 55.0 * 55.0:
			_idle_skip = 0.25
			return
	_t += dt
	if _base_speed < 0.0:
		_base_speed = speed
	if limp_t > 0.0:
		limp_t -= dt
		body.limp = clampf(limp_t / 4.0, 0.0, 1.0)
	arm_t -= dt
	speed = _base_speed * (1.0 - 0.55 * body.limp)
	if not is_on_floor():
		velocity.y -= 18.0 * dt
	else:
		velocity.y = -0.5
	# no mar: nada na superfície (mais devagar e sem atirar)
	var w2 = get_tree().current_scene.get("world2")
	swimming = w2 != null and w2.is_swim(global_position.x, global_position.z) and global_position.y < w2.WATER_Y - 0.2
	body.swimming = swimming
	if swimming:
		velocity.y = clampf((w2.WATER_Y - 0.9 - global_position.y) * 3.0, -3.0, 3.0)
		speed = _base_speed * 0.5
		cool = maxf(cool, 0.3)
	if anim != "":
		_anim_tick(dt)
		return
	if rescue_rb != null:
		_rescue_tick(dt)
		return
	if target == null or not is_instance_valid(target):
		body.pose = ""
		body.aiming = false
		if not patrol.is_empty():
			# patrulha: anda pela calçada em volta da quadra
			var wp: Vector3 = patrol[_pi % patrol.size()]
			var tw := wp - global_position
			tw.y = 0
			if tw.length() < 0.6:
				_pi += 1
			var v := tw.normalized() * 1.35
			velocity.x = v.x
			velocity.z = v.z
			body.rotation.y = lerp_angle(body.rotation.y, atan2(v.x, v.z), minf(1.0, dt * 6.0))
			move_and_slide()
			body.animate(1.35, dt)
			return
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
	var in_cover := false
	# cobertura: corre para trás de um veículo entre ele e o alvo, abaixa e levanta para atirar
	if not arrest_only:
		_cover_t -= dt
		if _cover_t <= 0.0:
			_cover_t = rng.randf_range(2.5, 4.0)
			cover_pos = _find_cover(tp)
	if cover_pos != Vector3.INF and not arrest_only:
		var tc := cover_pos - global_position
		tc.y = 0
		if tc.length() > 0.7:
			want = tc.normalized() * speed
			body.pose = ""
		else:
			in_cover = true
			_peek += dt
			var cyc := fmod(_peek, 3.0)
			body.pose = "cover" if cyc < 1.6 else ""
			if body.pose == "cover":
				cool = maxf(cool, 0.25)
	elif arrest_only and d > 1.0:
		want = dirv * speed * 1.1
	elif d > goal + 1.5 or not _los:
		want = dirv * speed
	elif d < goal - 3.0 and not arrest_only:
		want = -dirv * speed * 0.6
	elif not arrest_only:
		_strafe_t -= dt
		if _strafe_t <= 0.0:
			_strafe_t = rng.randf_range(1.2, 2.8)
			_strafe = -_strafe if rng.randf() < 0.6 else _strafe
		want = Vector3(-dirv.z, 0, dirv.x) * _strafe * 2.0
	# preso num obstáculo (viatura, poste, quina): contorna pelo lado por um instante
	if _side_t > 0.0:
		_side_t -= dt
		want = Vector3(-want.z, 0, want.x).normalized() * speed * _side_dir + want * 0.3
	elif want.length() > 1.0 and Vector2(velocity.x, velocity.z).length() < 0.5:
		_stuck_t += dt
		if _stuck_t > 0.5:
			_stuck_t = 0.0
			_side_t = 0.9
			_side_dir = -_side_dir if rng.randf() < 0.5 else _side_dir
	else:
		_stuck_t = 0.0
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(want, 18.0 * dt)
	velocity.x = hv.x
	velocity.z = hv.z
	move_and_slide()
	if not in_cover and body.pose == "cover":
		body.pose = ""
	body.aiming = not arrest_only and d < 30.0 and body.pose == ""
	body.animate(hv.length(), dt)
	if arrest_only:
		return
	cool -= dt
	if get_tree().current_scene.combat.hostage != null and d < 40.0:
		return     # refém: a polícia não atira
	if cool <= 0.0 and d < 34.0 and _los and not searching:
		cool = rng.randf_range(rate * 0.7, rate * 1.3)
		var muzzle := global_position + Vector3(0, 1.4, 0) + dirv * 0.6
		if body and body.has_method("muzzle_pos"):
			muzzle = body.muzzle_pos(muzzle)
		var hitp: bool = rng.randf() < clampf(accuracy * (0.45 if arm_t > 0.0 else 1.0) - d * 0.01, 0.06, 0.85)
		var aim := tp + Vector3(0, 1.2, 0)
		if not hitp:
			aim += Vector3(rng.randf_range(-1.5, 1.5), rng.randf_range(-0.5, 1.0), rng.randf_range(-1.5, 1.5))
		# bala com física: parede/carro no caminho segura o tiro (antes atravessava)
		var sc := get_tree().current_scene
		var q := PhysicsRayQueryParameters3D.create(muzzle, aim + (aim - muzzle).normalized() * 0.5, 1)
		q.exclude = [get_rid()]
		var pv = sc.player.vehicle
		var r := get_world_3d().direct_space_state.intersect_ray(q)
		if not r.is_empty() and r.collider != pv:
			var col = r.collider
			W.tracer(sc, muzzle, r.position)
			if col != null and col.has_method("take_damage"):
				col.take_damage(dmg * 0.3)
			sc.bullet_mark(r.position, r.normal, col)
		else:
			W.tracer(sc, muzzle, aim)
			shot_player.emit(dmg if hitp else 0.0, global_position)

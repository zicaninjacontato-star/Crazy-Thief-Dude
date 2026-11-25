extends Node
## Combate: armas do jogador (soco, pistola, submetralhadora, espingarda) com mira automática
## para celular, policiais a pé, dinheiro que cai dos pedestres, morte ("WASTED") e hospital,
## e prisão ("PRESO") a pé.

const W := preload("res://scripts/weapons.gd")
const Cop := preload("res://scripts/cop.gd")
const FX := preload("res://scripts/fx.gd")
const M := preload("res://scripts/mats.gd")
const Humanoid := preload("res://scripts/humanoid.gd")

var main: Node3D
var weapon := "pistol"
var owned := {"fist": true, "pistol": true, "smg": true, "shotgun": true}
var ammo := {"pistol": 60, "smg": 240, "shotgun": 30}
var cool := 0.0
var aim_t := 0.0
var fire_held := false
var cops: Array = []
var cops_from := {}        # viatura -> já desceram
var cash: Array = []
var dead := false
var dead_t := 0.0
var bust_t := 0.0
var rng := RandomNumberGenerator.new()

func setup(m: Node3D) -> void:
	main = m
	rng.seed = 99
	_equip()

func cycle() -> void:
	var i := W.ORDER.find(weapon)
	for k in W.ORDER.size():
		i = (i + 1) % W.ORDER.size()
		var w: String = W.ORDER[i]
		if owned.get(w, false) and (w == "fist" or ammo.get(w, 0) > 0):
			weapon = w
			break
	_equip()

func _equip() -> void:
	var p = main.player
	if p.body:
		p.body.give_gun(W.gun_mesh(weapon))

func label() -> String:
	var d: Dictionary = W.DATA[weapon]
	return d.name if weapon == "fist" else "%s  %d" % [d.name, ammo.get(weapon, 0)]

func _process(dt: float) -> void:
	cool -= dt
	aim_t -= dt
	var p = main.player
	if p.body:
		p.body.aiming = aim_t > 0.0 and weapon != "fist" and p.vehicle == null
	_cash_tick()
	_cops_tick(dt)
	if dead:
		dead_t += dt
		if dead_t > 5.0:
			_respawn(main.city.hospital_pos, "Você acordou no hospital (-$100)")
		return
	if main.hp <= 0.0:
		_die()
		return
	if p.vehicle != null:
		return
	if fire_held and cool <= 0.0:
		var auto: bool = W.DATA[weapon].auto
		shoot()
		if not auto:
			fire_held = false

func shoot() -> void:
	var p = main.player
	var d: Dictionary = W.DATA[weapon]
	cool = d.rate
	var fwd := Vector3(sin(main.cam_yaw + PI), 0, cos(main.cam_yaw + PI))
	if weapon == "fist":
		p.body.punch_t = 0.3
		var t = _target(fwd, 1.9, 0.9)
		if t:
			_face(t.global_position)
			main.audio.play("punch", t.global_position)
			_damage(t, d.dmg, (t.global_position - p.global_position).normalized())
		return
	if ammo.get(weapon, 0) <= 0:
		cycle()
		return
	ammo[weapon] -= 1
	aim_t = 1.6
	var t = _target(fwd, d.range, 0.55)
	var muzzle: Vector3 = p.global_position + Vector3(0, 1.38, 0)
	var dir := fwd
	if t:
		dir = (t.global_position + Vector3(0, 1.2, 0) - muzzle).normalized()
		_face(t.global_position)
	muzzle += Vector3(dir.x, 0, dir.z).normalized() * 0.65
	main.audio.play("shot", muzzle, 2.0 if weapon == "shotgun" else 0.0)
	var pellets: int = d.get("pellets", 1)
	for k in pellets:
		var sd: Vector3 = dir + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 0.5), rng.randf_range(-1, 1)) * d.spread
		var hit_target: bool = t != null and rng.randf() < (0.9 if pellets == 1 else 0.6)
		var end: Vector3 = muzzle + sd.normalized() * d.range
		if hit_target:
			end = t.global_position + Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.9, 1.5), rng.randf_range(-0.2, 0.2))
			_damage(t, d.dmg, sd.normalized())
		else:
			var q := PhysicsRayQueryParameters3D.create(muzzle, end, 1)
			var r := main.get_world_3d().direct_space_state.intersect_ray(q)
			if r:
				end = r.position
				FX.sparks(main, end)
		W.tracer(main, muzzle, end)
	# tiros assustam quem está perto
	for q in main.peds:
		if is_instance_valid(q) and q.global_position.distance_to(p.global_position) < 28.0:
			q.scare()
	if ammo[weapon] <= 0:
		cycle()

func _face(pos: Vector3) -> void:
	var p = main.player
	var to: Vector3 = pos - p.global_position
	p.body.rotation.y = atan2(to.x, to.z)

## alvo mais próximo à frente (pedestre ou policial vivo)
func _target(fwd: Vector3, rng_max: float, cone: float):
	var p = main.player
	var best = null
	var bs := 1e9
	var cands: Array = main.peds + cops
	for c in cands:
		if not is_instance_valid(c) or c.down:
			continue
		var to: Vector3 = c.global_position - p.global_position
		to.y = 0
		var dd := to.length()
		if dd > rng_max or dd < 0.1:
			continue
		var ang := fwd.angle_to(to / dd)
		if ang > cone:
			continue
		var score := dd * (1.0 + ang * 2.0)
		if score < bs:
			bs = score
			best = c
	return best

func _damage(t, dmg: float, dir: Vector3) -> void:
	var was_cop: bool = t in cops
	if t.damage(dmg, dir, main.gore):
		main._add_wanted(2 if was_cop else 1)
		main.audio.play("scream", t.global_position, -4.0)
	elif not was_cop and main.wanted == 0:
		main._add_wanted(1)

## dinheiro: nota no chão quando um pedestre morre
func drop_cash(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.35, 0.06, 0.2)
	mi.mesh = bm
	mi.material_override = M.emissive(Color(0.2, 0.75, 0.25), 0.8)
	main.add_child(mi)
	mi.global_position = Vector3(pos.x, 0.45, pos.z)
	cash.append({"n": mi, "v": rng.randi_range(8, 60), "t": 0.0})

func _cash_tick() -> void:
	var p = main.player
	for c in cash.duplicate():
		var n: MeshInstance3D = c.n
		c.t += get_process_delta_time()
		n.rotation.y += get_process_delta_time() * 2.5
		n.position.y = 0.45 + sin(c.t * 3.0) * 0.08
		if p.vehicle == null and not dead and n.global_position.distance_to(p.global_position + Vector3(0, 0.4, 0)) < 1.4:
			main.money += c.v
			main._msg("+$%d" % c.v)
			main.audio.play("cash")
			n.queue_free()
			cash.erase(c)
		elif c.t > 45.0:
			n.queue_free()
			cash.erase(c)

## policiais descem da viatura quando ela chega perto
func _cops_tick(dt: float) -> void:
	cops = cops.filter(func(c): return is_instance_valid(c))
	var pc = main.police_car
	if pc and is_instance_valid(pc) and not cops_from.has(pc) and not dead:
		if pc.global_position.distance_to(main.player.global_position) < 20.0:
			cops_from[pc] = true
			pc.ai_target = null
			pc.throttle = 0.0
			pc.brake_in = 1.0
			for s in [-1.0, 1.0]:
				var c := Cop.new()
				main.add_child(c)
				c.setup(rng.randi())
				c.global_position = pc.global_position + pc.global_transform.basis.x * 1.8 * s
				c.target = main.player
				c.shot_player.connect(_on_cop_shot)
				cops.append(c)
	# preso a pé: policial encostado por 2 s
	if not dead and main.player.vehicle == null and main.wanted > 0:
		var near := false
		for c in cops:
			if not c.down and c.global_position.distance_to(main.player.global_position) < 1.6:
				near = true
		bust_t = bust_t + dt if near else 0.0
		if bust_t > 2.0:
			bust_t = 0.0
			_respawn(main.city.police_pos, "PRESO! Você saiu da delegacia (-$100)")

func _on_cop_shot(dmg: float, _from: Vector3) -> void:
	main.audio.play("shot", _from, -3.0)
	if dead or dmg <= 0.0:
		return
	var d: float = dmg * (0.4 if main.player.vehicle != null else 1.0)
	# colete absorve 70% do dano enquanto durar
	if main.armor > 0.0:
		var a := minf(main.armor, d * 0.7)
		main.armor -= a
		d -= a
	main.hp -= d
	main.hud.flash = 0.25

func clear_police() -> void:
	for c in cops:
		if is_instance_valid(c) and not c.down:
			c.queue_free()
	cops.clear()
	cops_from.clear()

func _die() -> void:
	dead = true
	dead_t = 0.0
	var p = main.player
	if p.vehicle != null:
		main._toggle_car()
	p.collision_layer = 0
	p.collision_mask = 0
	p.body.ragdoll(Vector3(rng.randf_range(-2, 2), 2.0, rng.randf_range(-2, 2)), null, false)
	FX.blood_burst(main, p.global_position + Vector3(0, 1.2, 0), Vector3.UP, 20)
	main.hud.wasted = "WASTED"
	main.audio.play("scream", p.global_position)

func _respawn(pos: Vector3, text: String) -> void:
	var p = main.player
	dead = false
	main.hud.wasted = ""
	if p.vehicle != null:
		main._toggle_car()
	if p.body.ragdolled:
		for part in p.body.parts:
			if is_instance_valid(part):
				part.get_tree().create_timer(20.0).timeout.connect(part.queue_free)
		p.rebuild_body()
		_equip()
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.collision_layer = 1
	p.collision_mask = 1
	main.hp = 100.0
	main.cam_yaw = 0.0
	main.money = maxi(0, main.money - 100)
	main.wanted = 0
	if main.police_car:
		main.police_car.queue_free()
		main.cars.erase(main.police_car)
		main.police_car = null
	clear_police()
	main._msg(text)

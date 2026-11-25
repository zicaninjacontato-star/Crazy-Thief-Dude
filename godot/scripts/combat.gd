extends Node
## Combate do jogador:
## - armas (soco em combo, pistola, submetralhadora, espingarda, fuzil, sniper, bazuca, granada);
## - tiro "do quadril" com mira automática, ou MIRA manual (raio pela câmera, retícula no centro);
## - tiros danificam veículos; bazuca (foguete) e granada explodem (main.explode_at);
## - queda de altura (dano e derrubada), derrubada genérica (knockdown) e levantar;
## - morte (WASTED → hospital), prisão (PRESO → delegacia), dinheiro dos pedestres mortos.

const W := preload("res://scripts/weapons.gd")
const FX := preload("res://scripts/fx.gd")
const M := preload("res://scripts/mats.gd")

var main: Node3D
var weapon := "pistol"
var owned := {"fist": true, "pistol": true, "smg": true, "shotgun": true}
var ammo := {"pistol": 60, "smg": 240, "shotgun": 30}
var cool := 0.0
var aim_t := 0.0
var fire_held := false
var aim := false             # mira manual ligada (botão MIRA)
var cash: Array = []
var dead := false
var dead_t := 0.0
var down_t := 0.0            # >0: jogador no chão (derrubado)
var combo := 0
var combo_t := 0.0
var _vy := 0.0
var rockets: Array = []
var grenades: Array = []
var rng := RandomNumberGenerator.new()

var cops: Array:
	get:
		return main.police.cops

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

func select(w: String) -> void:
	reload_t = 0.0
	if owned.get(w, false) and (w == "fist" or ammo.get(w, 0) > 0):
		weapon = w
		_equip()

func _equip() -> void:
	var p = main.player
	if p.body and not p.body.ragdolled:
		p.body.give_gun(W.gun_mesh(weapon))
		p.body.gun_kind = weapon

## pente: balas carregadas na arma (o total fica em 'ammo'); acabou o pente = recarrega
const MAG := {"pistol": 12, "smg": 30, "shotgun": 6, "rifle": 30, "sniper": 5, "rpg": 1}
const RELOAD := {"pistol": 1.2, "smg": 1.6, "shotgun": 2.2, "rifle": 1.8, "sniper": 2.4, "rpg": 2.6}
var clip := {}
var reload_t := 0.0

func _clip(w: String) -> int:
	if not MAG.has(w):
		return ammo.get(w, 0)
	if not clip.has(w):
		clip[w] = mini(MAG[w], ammo.get(w, 0))
	return mini(clip[w], ammo.get(w, 0))

func reload() -> void:
	if not MAG.has(weapon) or reload_t > 0.0 or ammo.get(weapon, 0) <= _clip(weapon) or _clip(weapon) >= MAG[weapon]:
		return
	reload_t = RELOAD[weapon]
	var p = main.player
	if p.body:
		p.body.reload_t = reload_t
		p.body.reload_dur = reload_t
	main.audio.play("reload", p.global_position, -2.0)

func label() -> String:
	var d: Dictionary = W.DATA[weapon]
	if weapon == "fist":
		return d.name
	if MAG.has(weapon):
		var c := _clip(weapon)
		return "%s  %d/%d%s" % [d.name, c, maxi(0, ammo.get(weapon, 0) - c), "  ⟳" if reload_t > 0.0 else ""]
	return "%s  %d" % [d.name, ammo.get(weapon, 0)]

func _process(dt: float) -> void:
	if main.god and not force_dead:
		main.hp = 100.0
	if reload_t > 0.0:
		reload_t -= dt
		if reload_t <= 0.0 and MAG.has(weapon):
			clip[weapon] = mini(MAG[weapon], ammo.get(weapon, 0))
			main.audio.play("click", main.player.global_position, -4.0)
	elif MAG.has(weapon) and _clip(weapon) <= 0 and ammo.get(weapon, 0) > 0 and main.player.vehicle == null:
		reload()
	cool -= dt
	aim_t -= dt
	combo_t -= dt
	var p = main.player
	if p.body and not p.body.ragdolled:
		p.body.aiming = (aim_t > 0.0 or aim) and weapon != "fist" and weapon != "grenade" and p.vehicle == null
		p.body.guard = aim and weapon == "fist" and p.vehicle == null
	_cash_tick()
	_projectiles(dt)
	_threat_tick(dt)
	if dead:
		dead_t += dt
		if dead_t > 5.0:
			_respawn(main.city.hospital_pos, "Você acordou no hospital (-$100)")
		return
	if main.hp <= 0.0:
		_die()
		return
	if down_t > 0.0:
		down_t -= dt
		# caindo (ex.: pulou do avião): continua no chão até parar; dano pelo impacto
		if p.body.parts.size() > 0 and is_instance_valid(p.body.parts[0]):
			var hv: Vector3 = p.body.parts[0].linear_velocity
			if hv.y < fall_peak:
				fall_peak = hv.y
			if hv.length() > 3.0:
				down_t = maxf(down_t, 0.8)
			elif fall_peak < -13.0:
				main.hp -= (-fall_peak - 13.0) * 8.0
				main.audio.play("hit", p.body.parts[0].global_position, 4.0)
				FX.blood_burst(main, p.body.parts[0].global_position, Vector3.UP, 12)
				fall_peak = 0.0
		if down_t <= 0.0:
			_get_up()
		return
	if p.vehicle != null:
		_vy = 0.0
		return
	# queda: dano ao bater no chão rápido demais
	if p.is_on_floor():
		if _vy < -12.0 and not p.swimming:
			var impact := -_vy
			main.hp -= (impact - 12.0) * 7.0
			main.audio.play("hit", p.global_position, 2.0)
			if impact > 15.0 and main.hp > 0.0:
				knockdown(Vector3(rng.randf_range(-1, 1), 1.0, rng.randf_range(-1, 1)), 2.2)
		_vy = 0.0
	else:
		_vy = p.velocity.y
	if fire_held and cool <= 0.0 and not p.swimming and carrying == null:
		var auto: bool = W.DATA[weapon].auto
		shoot()
		if not auto:
			fire_held = false

## direção de disparo: câmera (mira manual) ou para onde a câmera está virada (quadril)
func _aim_ray() -> Array:
	var cam: Camera3D = main.cam
	var vp := main.get_viewport()
	var c := vp.get_visible_rect().size * 0.5
	return [cam.project_ray_origin(c), cam.project_ray_normal(c)]

func shoot() -> void:
	var p = main.player
	var d: Dictionary = W.DATA[weapon]
	cool = d.rate
	var fwd := Vector3(sin(main.cam_yaw + PI), 0, cos(main.cam_yaw + PI))
	if weapon == "fist":
		_punch(fwd)
		return
	if ammo.get(weapon, 0) <= 0:
		cycle()
		return
	if reload_t > 0.0:
		return
	if MAG.has(weapon) and _clip(weapon) <= 0:
		reload()
		return
	ammo[weapon] -= 1
	if MAG.has(weapon):
		clip[weapon] = _clip(weapon) - 1
	aim_t = 1.6
	main.police.armed_t = 5.0
	if d.get("throw", false):
		_throw_grenade(fwd)
		return
	var muzzle: Vector3 = p.global_position + Vector3(0, 1.38, 0)
	var dir := fwd
	var t = null
	var ray := _aim_ray()
	if aim:
		# mira manual: o ponto sob a retícula
		var hit := _ray_hit(ray[0], ray[1], d.range + 10.0)
		var aim_pt: Vector3 = hit.pos
		dir = (aim_pt - muzzle).normalized()
		_face(aim_pt)
	else:
		t = _target(fwd, d.range, 0.55)
		if t:
			dir = (t.global_position + Vector3(0, 1.2, 0) - muzzle).normalized()
			_face(t.global_position)
	muzzle += Vector3(dir.x, 0, dir.z).normalized() * 0.65
	if d.get("rocket", false):
		_fire_rocket(muzzle, dir)
		return
	main.audio.play("shot_" + weapon if main.audio.sounds.has("shot_" + weapon) else "shot", muzzle, 2.0 if weapon in ["shotgun", "sniper"] else 0.0)
	var pellets: int = d.get("pellets", 1)
	for k in pellets:
		var sd: Vector3 = (dir + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 0.5), rng.randf_range(-1, 1)) * d.spread).normalized()
		var end: Vector3
		if t != null and not aim:
			if rng.randf() < (0.9 if pellets == 1 else 0.6):
				end = t.global_position + Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.9, 1.5), rng.randf_range(-0.2, 0.2))
				_damage(t, d.dmg, sd)
				W.tracer(main, muzzle, end)
				continue
		var h := _ray_hit(muzzle, sd, d.range)
		var vh := _vehicle_parts(muzzle, sd, muzzle.distance_to(h.pos) + 0.3)
		if not vh.is_empty():
			end = vh.pos
			_hit_vehicle_part(vh, d.dmg)
			W.tracer(main, muzzle, end)
			continue
		end = h.pos
		if h.car != null and h.car.has_method("burst_tire"):
			var lp: Vector3 = h.car.global_transform.affine_inverse() * end
			if lp.y > 0.95:
				h.car.unlocked = true       # tiro no vidro: porta destrancada
		if h.who != null:
			_damage(h.who, d.dmg * (2.0 if h.get("head", false) else 1.0), sd)
		elif h.car != null:
			h.car.take_damage(d.dmg * 0.35)
			FX.sparks(main, end)
		elif h.hit:
			FX.sparks(main, end)
		W.tracer(main, muzzle, end)
	# tiros assustam quem está perto
	for q in main.peds:
		if is_instance_valid(q) and q.global_position.distance_to(p.global_position) < 28.0:
			q.scare()
	if main.wanted == 0 and _peds_near(p.global_position, 22.0):
		main._add_wanted(1)
	if ammo[weapon] <= 0:
		cycle()

## pneus e motoristas na linha do tiro (antes do primeiro obstáculo)
func _vehicle_parts(from: Vector3, dir: Vector3, maxd: float) -> Dictionary:
	var best := {}
	var bt := maxd
	for c in main.cars:
		if not is_instance_valid(c) or c == main.player.vehicle or not (c is VehicleBody3D):
			continue
		if c.global_position.distance_to(from) > maxd + 6.0:
			continue
		for w in c.wheels:
			var cpos: Vector3 = w.global_position
			var t := (cpos - from).dot(dir)
			if t < 0.3 or t > bt:
				continue
			if (from + dir * t).distance_to(cpos) < c.wheel_r * 1.05:
				bt = t
				best = {"kind": "wheel", "car": c, "w": w, "pos": from + dir * t}
		var drv = main.traffic_sys.driver_of(c)
		if drv and is_instance_valid(drv):
			var dc: Vector3 = drv.global_transform * Vector3(0, 1.15, 0)
			var t2 := (dc - from).dot(dir)
			if t2 > 0.3 and t2 < bt and (from + dir * t2).distance_to(dc) < 0.38:
				bt = t2
				best = {"kind": "driver", "car": c, "pos": from + dir * t2}
	return best

func _hit_vehicle_part(vh: Dictionary, dmg: float) -> void:
	var c = vh.car
	if vh.kind == "wheel":
		c.burst_tire(vh.w)
		main.audio.play("hit", vh.pos, 2.0)
	else:
		FX.blood_burst(main, vh.pos, Vector3.UP, 14)
		main.traffic_sys.kill_driver(c)
		main._add_wanted(1)
		main.audio.play("scream", vh.pos, -4.0)

func _peds_near(pos: Vector3, r: float) -> bool:
	for q in main.peds:
		if is_instance_valid(q) and not q.down and q.global_position.distance_to(pos) < r:
			return true
	return false

## raio contra pedestres/policiais (cápsulas) e contra o mundo/veículos (física)
func _ray_hit(from: Vector3, dir: Vector3, length: float) -> Dictionary:
	var best_t := length
	var who = null
	var head := false
	for c in main.peds + cops + main.missions.hostiles():
		if not is_instance_valid(c) or c.down:
			continue
		var base: Vector3 = c.global_position
		# ponto do raio mais próximo do eixo vertical do corpo
		var rel := base - from
		var tt := rel.dot(dir)
		if tt < 0.3 or tt > best_t:
			continue
		var pt := from + dir * tt
		var dy := pt.y - base.y
		if dy < 0.0 or dy > 1.85:
			continue
		var horiz := Vector2(pt.x - base.x, pt.z - base.z).length()
		if horiz < 0.38:
			best_t = tt
			who = c
			head = dy > 1.5
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * length, 1)
	q.exclude = [main.player.get_rid()]
	var r := main.get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		var rd: float = from.distance_to(r.position)
		if rd < best_t:
			var col = r.collider
			var car = col if col != null and col.has_method("take_damage") else null
			return {"pos": r.position, "who": null, "car": car, "hit": true}
	return {"pos": from + dir * best_t, "who": who, "car": null, "hit": who != null, "head": head}

# ---------------------------------------------------------------- soco em combo
func _punch(fwd: Vector3) -> void:
	var p = main.player
	if combo_t <= 0.0:
		combo = 0
	# combo: jab, direto, cruzado, gancho e chute (os dois últimos derrubam)
	var seq := [0, 1, 4, 3, 2]
	var kind: int = seq[combo % seq.size()]
	combo += 1
	combo_t = 0.9
	cool = {0: 0.26, 1: 0.3, 4: 0.36, 3: 0.45, 2: 0.55}[kind]
	p.body.punch_kind = kind
	p.body.punch_t = 0.3
	var t = _target(fwd, 2.8, 1.2)
	if t:
		_face(t.global_position)
		var to: Vector3 = t.global_position - p.global_position
		to.y = 0
		if to.length() > 1.3:
			p.velocity += to.normalized() * 6.0      # avança até o alvo
		if to.length() < 2.3:
			# esquiva do NPC que está brigando
			if t.get("mode") == "brawl" and rng.randf() < 0.22 and kind != 2:
				t.dodge(to.normalized())
				main.audio.play("swoosh", t.global_position, -4.0)
				return
			var dmg: float = {0: 12.0, 1: 14.0, 4: 18.0, 3: 26.0, 2: 30.0}[kind]
			if t.get("mode") == "brawl" and t.get("blocking"):
				dmg *= 0.35
			main.audio.play("kick" if kind == 2 else "punch", t.global_position, 2.0 if kind >= 2 else 0.0)
			var dir: Vector3 = to.normalized()
			var finisher := kind == 2 or kind == 3
			if t.has_method("hit") and finisher and t.hp - dmg <= 0.0:
				t.hit(p, dir * 7.0 + Vector3(0, 2.5 if kind == 3 else 1.5, 0), false)
				main._add_wanted(2 if t in cops else 1)
				if not (t in cops):
					main.audio.play("scream", t.global_position, -4.0)
			elif t.has_method("knock") and finisher and t.hp - dmg > 0.0 and rng.randf() < 0.7:
				t.knock(dir * (6.0 if kind == 2 else 3.0) + Vector3(0, 3.0 if kind == 3 else 1.0, 0), dmg)
				if t.get("mode") != "brawl" and main.wanted == 0 and not (t in main.missions.hostiles()):
					main._add_wanted(1)
			else:
				if t.get("body") and not t.body.ragdolled:
					t.body.hurt_t = 0.35
					t.body.hurt_side = 1.0 if kind in [0, 4] else -1.0
				if t is Node3D:
					t.global_position += dir * (0.25 + 0.1 * kind)
				_damage(t, dmg, dir)
			if t in cops and main.wanted == 0:
				main._add_wanted(1)
			return
	main.audio.play("swoosh", p.global_position, -6.0)

## NPC brigando acerta o jogador
func melee_hit_player(dmg: float, from: Vector3) -> void:
	if dead or down_t > 0.0 or main.player.vehicle != null:
		return
	var p = main.player
	main.hp -= dmg
	main.hud.flash = 0.2
	main.audio.play("punch", p.global_position, 0.0)
	var dir: Vector3 = p.global_position - from
	dir.y = 0
	dir = dir.normalized()
	p.velocity += dir * 3.5
	if p.body and not p.body.ragdolled:
		p.body.hurt_t = 0.35
		p.body.hurt_side = 1.0 if rng.randf() < 0.5 else -1.0
	if dmg > 15.0 and rng.randf() < 0.35 and main.hp > 0.0:
		knockdown(dir * 3.0 + Vector3(0, 1.0, 0), 1.8)

# ---------------------------------------------------------------- foguete e granada
func _fire_rocket(from: Vector3, dir: Vector3) -> void:
	main.audio.play("rocket", from)
	var n := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.12, 0.6)
	n.mesh = bm
	n.material_override = M.plain(Color(0.25, 0.3, 0.18), 0.6)
	main.add_child(n)
	n.global_position = from
	n.look_at(from + dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT)
	FX.fire_emitter(n, Vector3(0, 0, 0.35))
	rockets.append({"n": n, "dir": dir, "t": 0.0})

func _throw_grenade(fwd: Vector3) -> void:
	var p = main.player
	p.body.throw_t = 0.5
	var dir := fwd
	if aim:
		var ray := _aim_ray()
		dir = ray[1]
	var rb := RigidBody3D.new()
	rb.collision_layer = 4
	rb.collision_mask = 1
	rb.mass = 0.5
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.08
	cs.shape = sp
	rb.add_child(cs)
	rb.add_child(W.gun_mesh("grenade"))
	main.add_child(rb)
	rb.global_position = p.global_position + Vector3(0, 1.7, 0) + Vector3(dir.x, 0, dir.z).normalized() * 0.5
	rb.linear_velocity = Vector3(dir.x, 0, dir.z).normalized() * 13.0 + Vector3(0, 5.5 + dir.y * 8.0, 0)
	rb.angular_velocity = Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6))
	grenades.append({"n": rb, "t": 2.3})
	for q in main.peds:
		if is_instance_valid(q) and q.global_position.distance_to(rb.global_position) < 20.0:
			q.scare()

func _projectiles(dt: float) -> void:
	for r in rockets.duplicate():
		var n: Node3D = r.n
		r.t += dt
		var step: Vector3 = r.dir * 48.0 * dt
		var from := n.global_position
		var to := from + step
		var boom: bool = r.t > 3.0
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		q.exclude = [main.player.get_rid()]
		var hit := main.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			to = hit.position
			boom = true
		for c in main.peds + cops + main.missions.hostiles():
			if is_instance_valid(c) and not c.down and c.global_position.distance_to(to - Vector3(0, 1.0, 0)) < 1.0:
				boom = true
		n.global_position = to
		if boom:
			main.explode_at(to, 7.0, 220.0)
			n.queue_free()
			rockets.erase(r)
	for g in grenades.duplicate():
		g.t -= dt
		if g.t <= 0.0:
			if is_instance_valid(g.n):
				main.explode_at(g.n.global_position, 7.5, 200.0)
				g.n.queue_free()
			grenades.erase(g)

func _face(pos: Vector3) -> void:
	var p = main.player
	var to: Vector3 = pos - p.global_position
	p.body.rotation.y = atan2(to.x, to.z)

## alvo mais próximo à frente (pedestre, policial ou capanga vivo)
func _target(fwd: Vector3, rng_max: float, cone: float):
	var p = main.player
	var best = null
	var bs := 1e9
	var cands: Array = main.peds + cops + main.missions.hostiles()
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
	var hostile: bool = t in main.missions.hostiles()
	if t.damage(dmg, dir, main.gore):
		if not hostile:
			main._add_wanted(2 if was_cop else 1)
		main.audio.play("scream", t.global_position, -4.0)
		main.missions.on_kill(t)
	elif was_cop and main.wanted < 2:
		main._add_wanted(1)
	elif not was_cop and not hostile and main.wanted == 0:
		main._add_wanted(1)

## dinheiro: nota no chão quando um pedestre morre
func drop_cash(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.35, 0.06, 0.2)
	mi.mesh = bm
	mi.material_override = M.emissive(Color(0.2, 0.75, 0.25), 0.8)
	main.add_child(mi)
	mi.global_position = Vector3(pos.x, pos.y + 0.3, pos.z)
	cash.append({"n": mi, "v": rng.randi_range(8, 60), "t": 0.0, "y": pos.y + 0.3})

func _cash_tick() -> void:
	var p = main.player
	for c in cash.duplicate():
		var n: MeshInstance3D = c.n
		c.t += get_process_delta_time()
		n.rotation.y += get_process_delta_time() * 2.5
		n.position.y = c.y + sin(c.t * 3.0) * 0.08
		if p.vehicle == null and not dead and n.global_position.distance_to(p.global_position + Vector3(0, 0.4, 0)) < 1.4:
			main.money += c.v
			main._msg("+$%d" % c.v)
			main.audio.play("cash")
			n.queue_free()
			cash.erase(c)
		elif c.t > 45.0:
			n.queue_free()
			cash.erase(c)

func _on_cop_shot(dmg: float, _from: Vector3) -> void:
	main.audio.play("shot_rifle" if main.wanted >= 3 else "shot_pistol", _from, -3.0)
	if dead or dmg <= 0.0:
		return
	var d: float = dmg * (0.4 if main.player.vehicle != null else 1.0)
	if main.player.vehicle != null and main.player.vehicle.has_method("take_damage"):
		main.player.vehicle.take_damage(dmg * 0.25)
	# colete absorve 70% do dano enquanto durar
	if main.armor > 0.0:
		var a := minf(main.armor, d * 0.7)
		main.armor -= a
		d -= a
	main.hp -= d
	main.hud.flash = 0.25

func clear_police() -> void:
	main.police.clear()

# ---------------------------------------------------------------- derrubada, morte, prisão
## joga o jogador no chão (ragdoll) e ele levanta depois de 'dur' segundos
var fall_peak := 0.0
var force_dead := false
var carrying: Node3D = null     # corpo no ombro
var carry_cols := []

func knockdown(impulse: Vector3, dur := 2.4) -> void:
	var p = main.player
	if dead or down_t > 0.0 or p.body.ragdolled:
		return
	fall_peak = minf(0.0, impulse.y)
	drop_body()
	if p.vehicle != null:
		main.eject_player(impulse)
	p.collision_layer = 0
	p.collision_mask = 0
	p.body.ragdoll(impulse, null, false)
	down_t = dur

func _get_up() -> void:
	var p = main.player
	if not p.body.ragdolled:
		return
	var hips: Vector3 = p.global_position
	if p.body.parts.size() > 0 and is_instance_valid(p.body.parts[0]):
		hips = p.body.parts[0].global_position
	for part in p.body.parts:
		if is_instance_valid(part):
			part.queue_free()
	p.rebuild_body()
	_equip()
	p.global_position = Vector3(hips.x, maxf(hips.y - 0.9, p.global_position.y if p.global_position.y > 0.5 else 0.05), hips.z)
	p.velocity = Vector3.ZERO
	p.collision_layer = 2
	p.collision_mask = 1

func _die() -> void:
	force_dead = false
	drop_body()
	dead = true
	dead_t = 0.0
	down_t = 0.0
	var p = main.player
	if p.vehicle != null:
		main.eject_player(Vector3.UP * 3.0)
	p.collision_layer = 0
	p.collision_mask = 0
	if not p.body.ragdolled:
		p.body.ragdoll(Vector3(rng.randf_range(-2, 2), 2.0, rng.randf_range(-2, 2)), null, false)
	FX.blood_burst(main, p.global_position + Vector3(0, 1.2, 0), Vector3.UP, 20)
	main.hud.wasted = "WASTED"
	main.audio.play("scream", p.global_position)
	main.missions.fail("Você morreu")

## preso: tela "PRESO" por 3 s, perde as armas e 10% do dinheiro (mín. $100), sai da delegacia
var busted_t := 0.0
func busted() -> void:
	if busted_t > 0.0 or dead:
		return
	main.hud.wasted = "PRESO"
	main.hud.flash = 0.6
	main.missions.fail("Você foi preso")
	busted_t = 3.0
	var p = main.player
	if p.vehicle != null:
		main.eject_player(Vector3.ZERO)
	p.collision_layer = 0
	p.collision_mask = 0
	main.get_tree().create_timer(3.0).timeout.connect(_busted_end)

func _busted_end() -> void:
	busted_t = 0.0
	var lost := maxi(100, int(main.money * 0.1))
	owned = {"fist": true}
	ammo = {}
	weapon = "fist"
	main.money += 100 - lost      # _respawn tira mais 100
	_respawn(main.city.police_pos + Vector3(0, 0, 3.0), "PRESO! Perdeu as armas e $%d" % lost)
	main.hud.wasted = ""

## mordida do tubarão etc.: morre mesmo com vida infinita
func kill_now() -> void:
	force_dead = true
	main.hp = 0.0

# ---------------------------------------------------------------- carregar corpos
func pick_body(ped) -> void:
	if carrying or ped == null or not is_instance_valid(ped) or not ped.down:
		return
	carry_cols = ped._cols.duplicate()
	for part in ped.body.parts:
		if is_instance_valid(part):
			part.queue_free()
	ped.queue_free()
	main.peds.erase(ped)
	_make_carried()

func _make_carried() -> void:
	var p = main.player
	var h = preload("res://scripts/humanoid.gd").new()
	h.build(carry_cols[0], carry_cols[1], carry_cols[2], carry_cols[3])
	h.pose = "carried"
	p.body.bones.chest.add_child(h)
	h.scale = Vector3.ONE * 0.95
	h.position = Vector3(0.05, 0.45, -0.1)
	h.rotation = Vector3(0, PI * 0.5, PI * 0.5)
	h.animate(0, 0)
	carrying = h
	p.body.pose = "carry"
	weapon = "fist"
	_equip()

## solta o corpo no chão (ragdoll)
func drop_body() -> void:
	if carrying == null:
		return
	var p = main.player
	var pos: Vector3 = carrying.global_position
	carrying.queue_free()
	carrying = null
	if p.body:
		p.body.pose = ""
	var Ped := preload("res://scripts/ped.gd")
	var d = Ped.new()
	main.add_child(d)
	d.setup([pos, pos, pos, pos], 0, rng)
	d._cols = carry_cols.duplicate()
	d.body.queue_free()
	d._make_body()
	d.global_position = Vector3(pos.x, p.global_position.y, pos.z)
	main.peds.append(d)
	d.down = true
	d.body.ragdoll(Vector3(0, -1, 0), null, false)
	d._rag = d.body.parts

## põe o corpo carregado no porta-malas (ou tira de lá)
func trunk_action(car) -> void:
	if carrying:
		carrying.queue_free()
		carrying = null
		main.player.body.pose = ""
		car.cargo += 1
		main._msg("Corpo no porta-malas (%d)" % car.cargo)
	elif car.cargo > 0:
		car.cargo -= 1
		carry_cols = [Color(0.5, 0.5, 0.5), Color(0.15, 0.16, 0.2), Color(0.78, 0.56, 0.38), Color(0.1, 0.07, 0.05)]
		_make_carried()

func _respawn(pos: Vector3, text: String) -> void:
	var p = main.player
	dead = false
	down_t = 0.0
	if main.hud.wasted == "WASTED":
		main.hud.wasted = ""
	if p.vehicle != null:
		main.eject_player(Vector3.ZERO)
	if p.body.ragdolled:
		for part in p.body.parts:
			if is_instance_valid(part):
				part.get_tree().create_timer(20.0).timeout.connect(part.queue_free)
		p.rebuild_body()
		_equip()
	main.leave_interior()
	p.swimming = false
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.collision_layer = 2
	p.collision_mask = 1
	main.hp = 100.0
	main.cam_yaw = 0.0
	main.money = maxi(0, main.money - 100)
	main.wanted = 0
	clear_police()
	main._msg(text)

# ---------------------------------------------------------------- arma apontada: reações, assalto e refém
var hostage = null
var _thr_t := 0.0
var _surrender: Array = []     # [{car, t}]

func _aim_dir() -> Array:
	var ray := _aim_ray()
	return ray

## o jogador está apontando uma arma para este alvo?
func aiming_at(t) -> bool:
	var p = main.player
	if not aim or weapon in ["fist", "grenade"] or p.vehicle != null or dead:
		return false
	var ray := _aim_ray()
	var c: Vector3 = t.global_position + Vector3(0, 1.1, 0)
	var rel: Vector3 = c - ray[0]
	var d := rel.length()
	if d > 26.0 or d < 0.5:
		return false
	var ang: float = (ray[1] as Vector3).angle_to(rel / d)
	return ang < atan(1.1 / d) + 0.04

func _threat_tick(dt: float) -> void:
	var p = main.player
	# motoristas que se renderam descem do carro com as mãos para cima
	for sr in _surrender.duplicate():
		sr.t -= dt
		if sr.t <= 0.0:
			_surrender.erase(sr)
			_driver_out(sr.car)
	if hostage != null:
		if not is_instance_valid(hostage) or hostage.down or p.vehicle != null or dead or down_t > 0.0:
			release_hostage()
		else:
			var f := Vector3(sin(p.body.rotation.y), 0, cos(p.body.rotation.y))
			hostage.global_position = p.global_position + f * 0.55 + Vector3(0, 0, 0)
			hostage.body.rotation.y = p.body.rotation.y
			p.velocity.x *= 0.6
			p.velocity.z *= 0.6
	_thr_t -= dt
	if _thr_t > 0.0:
		return
	_thr_t = 0.15
	var rob := false
	if aim and weapon not in ["fist", "grenade"] and p.vehicle == null and not dead:
		for q in main.peds:
			if not is_instance_valid(q) or q.down or q == hostage:
				continue
			if aiming_at(q):
				if q.mode == "":
					q.react_aim()
			if q.mode == "handsup" and not q.robbed and q.global_position.distance_to(p.global_position) < 4.0:
				rob = true
		for a in main.traffic_sys.agents:
			var c = a.car
			if is_instance_valid(c) and c.global_position.distance_to(p.global_position) < 22.0 and aiming_at(c) and c.kind != "bus":
				var r: String = main.traffic_sys.aim_reaction(c)
				if r == "stop":
					_surrender.append({"car": c, "t": 1.2})
	main.hud.rob_avail = rob and hostage == null
	main.hud.hostage_on = hostage != null

func _nearest_handsup():
	var p = main.player
	var best = null
	var bd := 4.0
	for q in main.peds:
		if is_instance_valid(q) and not q.down and q.mode == "handsup":
			var d: float = q.global_position.distance_to(p.global_position)
			if d < bd:
				bd = d
				best = q
	return best

## assalto: o NPC rendido entrega uma quantia aleatória e foge
func rob_target() -> void:
	var q = _nearest_handsup()
	if q == null:
		return
	var v := rng.randi_range(15, 380)
	main.money += v
	main._msg("Assalto: +$%d" % v)
	main.audio.play("cash")
	q.robbed = true
	q._end_mode()
	q.flee = 12.0
	if main.police.seen_by_cop(q.global_position) or rng.randf() < 0.35:
		main._add_wanted(1)

## refém: segura o NPC rendido na frente (a polícia não atira); de novo solta
func toggle_hostage() -> void:
	if hostage != null:
		release_hostage()
		return
	var q = _nearest_handsup()
	if q == null:
		return
	hostage = q
	q.mode = "hostage"
	q.body.arm_pose = "handsup"
	main.audio.play("scream", q.global_position, -6.0)
	if main.wanted < 2:
		main._add_wanted(2 - main.wanted)

func release_hostage() -> void:
	if hostage != null and is_instance_valid(hostage) and not hostage.down:
		hostage._end_mode()
		hostage.flee = 12.0
	hostage = null
	main.hud.hostage_on = false

func _driver_out(car) -> void:
	if not is_instance_valid(car) or car.dead or car == main.player.vehicle:
		return
	var info: Dictionary = main.traffic_sys.release(car)
	if info.is_empty() or not is_instance_valid(info.get("drv")):
		return
	var h: Node3D = info.drv
	var pos: Vector3 = car.door_world() + car.global_transform.basis.x * 1.0
	pos.y = car.global_position.y - 0.4
	var Ped := preload("res://scripts/ped.gd")
	var q = Ped.new()
	main.add_child(q)
	var loop: Array = main.city.walk_loops[0]
	for l in main.city.walk_loops:
		if l[0].distance_to(pos) < loop[0].distance_to(pos):
			loop = l
	q.setup(loop, 0, rng)
	q._cols = info.cols.duplicate()
	q.body.queue_free()
	q._make_body()
	q.global_position = pos
	q.died.connect(main._on_ped_died)
	main.peds.append(q)
	h.queue_free()
	car.set_door(1.0)
	main.audio.play("door", car.global_position)
	q.reacted = true
	q.mode = "handsup"
	q.mode_t = 7.0
	q.body.arm_pose = "handsup"
	car.unlocked = true
	main.get_tree().create_timer(0.8).timeout.connect(func(): if is_instance_valid(car): car.set_door(0.0))

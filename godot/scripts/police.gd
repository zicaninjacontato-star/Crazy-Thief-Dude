extends Node
## Nível de procurado e resposta da polícia por estrela (como na versão antiga):
## 1★ 1 viatura, policiais tentam prender (só atiram se você estiver armado/atirando)
## 2★ 2 viaturas, atiram
## 3★ 3 viaturas pretas + 1 SWAT (4 policiais com fuzil)
## 4★ + helicóptero da polícia com atirador
## 5★ 4 viaturas + 2 SWAT, mira melhor
## Fugir: fique fora da vista da polícia; as estrelas piscam e caem uma a uma.

const Cop := preload("res://scripts/cop.gd")
const Arcade := preload("res://scripts/arcade.gd")
const W := preload("res://scripts/weapons.gd")
const FX := preload("res://scripts/fx.gd")
const Tank := preload("res://scripts/tank.gd")
const Jet := preload("res://scripts/jet.gd")

var main: Node3D
var units: Array = []       # {car, kind, out, crew}
var cops: Array = []
var heli = null
var heli_cool := 1.0
var heli_cd := 0.0        # depois que os atiradores morrem, outro helicóptero só vem um tempo depois
var unseen := 0.0
var seen := true
var spawn_cd := 0.0
var bust_t := 0.0
var armed_t := 0.0          # >0: jogador sacou/atirou recentemente
var rng := RandomNumberGenerator.new()
var _mk: Marker3D
# busca: a polícia sabe onde você está (knows) ou procura numa zona em volta do último ponto conhecido
var knows := true
var search_pos := Vector3.ZERO
var last_known := Vector3.ZERO
const ZONE_R := 75.0
var _sk: Marker3D
var _sw_t := 0.0
var army: Array = []        # tanques e caças (5 estrelas)
var patrol_cops: Array = []  # policiais a pé patrulhando (viram perseguidores com estrela)
var jet_cd := 0.0
var tank_cd := 3.0
var _out_i := 0
var boat_cd := 0.0

func setup(m: Node3D) -> void:
	main = m
	rng.seed = 404
	_mk = Marker3D.new()
	m.add_child(_mk)
	_sk = Marker3D.new()
	m.add_child(_sk)

func clear() -> void:
	for c in cops:
		if is_instance_valid(c) and not c.down:
			c.queue_free()
	cops.clear()
	for u in units:
		if is_instance_valid(u.car) and u.car != main.player.vehicle:
			main.cars.erase(u.car)
			u.car.queue_free()
	units.clear()
	if heli and is_instance_valid(heli):
		main.cars.erase(heli)
		heli.queue_free()
	heli = null
	for a in army:
		if is_instance_valid(a):
			a.queue_free()
	army.clear()
	for c in patrol_cops:
		if is_instance_valid(c):
			c.queue_free()
	patrol_cops.clear()
	unseen = 0.0
	knows = true
	main.police_car = null

func on_crime() -> void:
	unseen = 0.0
	seen = true

## algum policial/viatura vê este ponto?
func seen_by_cop(pos: Vector3) -> bool:
	for cp in cops:
		if is_instance_valid(cp) and not cp.down and cp.global_position.distance_to(pos) < 30.0:
			return true
	for u in units:
		if is_instance_valid(u.car) and u.car.global_position.distance_to(pos) < 40.0:
			return true
	return false

func is_unit_car(c) -> bool:
	for u in units:
		if u.car == c and (not u.out or u.crew > 0):
			return true
	return c == heli

func tick(dt: float) -> void:
	if main.wanted == 0 and units.is_empty() and cops.is_empty() and heli == null and army.is_empty():
		main.police_car = null
		return            # sem polícia em campo: nada a fazer
	cops = cops.filter(func(c): return is_instance_valid(c))
	units = units.filter(func(u): return is_instance_valid(u.car) and not u.car.dead)
	armed_t -= dt
	var s: int = main.wanted
	var p: Node3D = main.player.vehicle if main.player.vehicle else main.player
	var pp: Vector3 = p.global_position
	# sem saber onde você está: as unidades vasculham pontos da zona amarela
	if knows or main.wanted >= 5:
		last_known = pp
	else:
		_sw_t -= dt
		if _sw_t <= 0.0:
			_sw_t = 7.0
			var a := rng.randf() * TAU
			_sk.global_position = search_pos + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, ZONE_R * 0.8)
	var real_p := p
	if not knows and main.wanted < 5:
		p = _sk
		pp = _sk.global_position
	# viatura mais próxima (sirene e minimapa)
	var near = null
	var nd := 1e9
	for u in units:
		if u.car == main.player.vehicle:
			continue
		var d: float = u.car.global_position.distance_to(pp)
		if d < nd:
			nd = d
			near = u.car
	main.police_car = near
	if s == 0:
		_retreat(pp)
		return
	_activate_patrols(pp)
	var want_cars: int = [0, 1, 2, 3, 3, 4][s]
	var want_moto: int = 0 if s < 2 else 1
	var want_swat: int = 0 if s < 3 else (1 if s < 5 else 1)
	var want_arm: int = 2 if s >= 5 else 0
	var n_car := units.filter(func(u): return u.kind == "car").size()
	var n_swat := units.filter(func(u): return u.kind == "swat").size()
	spawn_cd -= dt
	if spawn_cd <= 0.0:
		if n_car < want_cars:
			_spawn_unit("car", s, pp)
			spawn_cd = 2.5
		elif units.filter(func(u): return u.kind == "moto").size() < want_moto:
			_spawn_unit("moto", s, pp)
			spawn_cd = 2.5
		elif n_swat < want_swat:
			_spawn_unit("swat", s, pp)
			spawn_cd = 4.0
		elif units.filter(func(u): return u.kind == "armored").size() < want_arm:
			_spawn_unit("armored", s, pp)
			spawn_cd = 4.0
	# 3★+ e o jogador no mar: lanchas da polícia
	var in_sea: bool = main.world2.is_water(pp.x, pp.z) and main.world2.sea_dist(pp.x, pp.z) > 8.0
	if s >= 3 and in_sea and units.filter(func(u): return u.kind == "boat").size() < (1 if s < 4 else 2) and boat_cd <= 0.0:
		_spawn_boat(pp)
		boat_cd = 6.0
	boat_cd -= dt
	heli_cd -= dt
	if s >= 4 and heli_cd <= 0.0 and (heli == null or not is_instance_valid(heli) or heli.dead):
		if heli == null or not is_instance_valid(heli):
			_spawn_heli(pp)
	if heli and is_instance_valid(heli):
		# helicóptero: devagar até 4★ (dá para fugir); no máximo de estrelas, a toda velocidade
		heli.ai_speed = 34.0 if s >= 5 else 12.0
	_army_tick(dt, s, real_p.global_position)
	_units_tick(dt, s, p, pp)
	_cops_tick(dt, s, p)
	for cp in cops:
		cp.searching = not knows
	_heli_tick(dt, s, p)
	_visibility(dt, s, real_p.global_position)
	if knows:
		_bust(dt, s, real_p.global_position)

## ponto numa rua da grade a ~80 m do jogador, de preferência fora da tela
func _spawn_point(pp: Vector3) -> Array:
	var city = main.city
	var ext: float = city.extent() - 6.0
	var best := []
	var best_score := -1e9
	var cam_f: Vector3 = -main.cam.global_transform.basis.z
	for k in 12:
		var road: float = (rng.randi_range(0, city.N) - city.N * 0.5) * city.CELL
		var along := clampf((pp.z if k % 2 == 0 else pp.x) + rng.randf_range(-90.0, 90.0), -ext, ext)
		var pos := Vector3(road, 0.8, along) if k % 2 == 0 else Vector3(along, 0.8, road)
		var d := Vector2(pos.x - pp.x, pos.z - pp.z).length()
		var score := -absf(d - 80.0)
		if (pos - pp).normalized().dot(cam_f) > 0.3 and d < 120.0:
			score -= 40.0
		if score > best_score:
			best_score = score
			best = [pos, atan2(pp.x - pos.x, pp.z - pos.z)]
	return best

func _spawn_unit(kind: String, s: int, pp: Vector3) -> void:
	# reforços saem da garagem da delegacia (se ela existir), um atrás do outro
	var sp := _spawn_point(pp)
	var st: Dictionary = main.city.station
	if not st.is_empty():
		_out_i += 1
		sp = [st.garage_out + Vector3(((_out_i % 3) - 1) * 4.0, 0, 0), 0.0]
	var c
	if kind == "swat":
		c = main._spawn_car(sp[0], sp[1], Color(0.06, 0.06, 0.07), false, "suv")
		c.make_police()
		c.siren_on = true
		c.max_engine = 7400.0
	elif kind == "moto":
		c = main._spawn_car(sp[0], sp[1], Color(0.92, 0.92, 0.93), false, "moto")
		c.make_police()
		c.siren_on = true
	elif kind == "armored":
		# carro-forte da polícia: blindado, pesado, 4 policiais de armadura
		c = main._spawn_car(sp[0], sp[1], Color(0.18, 0.2, 0.16), false, "pickup")
		c.make_police()
		c.siren_on = true
		c.max_engine = 9000.0
		c.mass = 3200.0
		c.hp = 420.0
	else:
		c = main._spawn_car(sp[0], sp[1], Color(0.92, 0.92, 0.93), true)
		c.max_engine = 6600.0 + s * 300.0
		if s >= 3:
			c.paint_black()
	units.append({"car": c, "kind": kind, "out": false, "crew": 4 if kind in ["swat", "armored"] else (1 if kind == "moto" else 2)})
	main.traffic_sys._driver({"car": c})       # motorista visível (vira policial a pé ao descer)

func _spawn_heli(pp: Vector3) -> void:
	var h = Arcade.new()
	h.police = true
	main.add_child(h)
	h.setup("heli", Color(0.1, 0.18, 0.45))
	h.hp = 300.0
	var a := rng.randf() * TAU
	h.global_position = pp + Vector3(cos(a) * 140.0, 45.0, sin(a) * 140.0)
	if not main.city.station.is_empty():
		h.global_position = main.city.station.heli      # decola do heliponto da delegacia
	h.ai_mode = "follow"
	h.ai_target = main.player
	h.world2 = main.world2
	h.add_gunners()
	h.destroyed.connect(main._on_vehicle_destroyed)
	main.cars.append(h)
	heli = h

func _units_tick(dt: float, s: int, p: Node3D, pp: Vector3) -> void:
	var pv: Vector3 = main.player.vehicle.linear_velocity if main.player.vehicle else main.player.velocity
	for u in units:
		var c = u.car
		if c == main.player.vehicle:
			continue
		# moto da polícia: batida forte, tiro ou moto tombada → o policial voa (ragdoll)
		if u.kind == "moto" and not u.out and not u.get("fell", false) and is_instance_valid(c):
			var hit_hard: bool = c.get_meta("last_crash", 0.0) > 7.0
			if hit_hard or c.hp < 72.0 or c.down or c.dead:
				_moto_fall(u, c)
				continue
		var d: float = c.global_position.distance_to(pp)
		var on_foot: bool = main.player.vehicle == null
		if not u.out:
			# segue as ruas até perto; perto, mira à frente do jogador (bate) ou pelos lados (encurrala)
			c.ai_target = null
			if not u.has("nav"):
				u.nav = {}
			var k: int = units.find(u)
			var lead: Vector3 = pp + pv * clampf(d / 22.0, 0.0, 1.1)
			if pv.length() > 3.0 and d > 10.0:
				var side := Vector3(-pv.z, 0, pv.x).normalized()
				lead += side * (5.0 if k % 2 == 0 else -5.0) * clampf((d - 10.0) / 20.0, 0.0, 1.0)
			# jogador a pé: chega devagar (não atropela), para perto e a equipe desce
			var vmax: float = 30.0 if u.kind == "car" else 26.0
			if on_foot:
				vmax = clampf((d - 9.0) * 0.8, 2.0, vmax)
			if u.kind == "boat":
				_boat_chase(u, dt, s, pp, d)
				continue
			if on_foot:
				vmax = clampf((d - 8.0) * 0.7, 0.0, vmax)
			main.traffic_sys.chase(c, pp, lead, u.nav, dt, vmax)
			# só desce quando a viatura já parou perto do jogador
			var cs: float = c.linear_velocity.length()
			if d < 16.0 and cs < 1.6 and (on_foot or pv.length() < 4.0):
				u.stop_t = u.get("stop_t", 0.0) + dt
				if u.stop_t > 0.35:
					_crew_out(u, s)
			elif (d < 30.0 or (main.player.swimming and d < 150.0)) and cs < 2.5 and on_foot:
				u.stop_t = u.get("stop_t", 0.0) + dt
				if u.stop_t > 2.5:
					_crew_out(u, s)          # travou perto (ou na beira do mar): desce mesmo assim
			else:
				u.stop_t = maxf(0.0, u.get("stop_t", 0.0) - dt * 0.5)
		else:
			c.ai_target = null
			c.throttle = 0.0
			c.brake_in = 1.0
			c.steer_in = 0.0
			# jogador fugiu de carro: a equipe volta e a viatura retoma
			if not on_foot and d > 45.0:
				for cp in cops.duplicate():
					if is_instance_valid(cp) and cp.unit == c and not cp.down:
						cp.queue_free()
						cops.erase(cp)
				u.out = false
				c.brake_in = 0.0

## policial cai da moto: corpo em ragdoll com a velocidade da moto; levanta depois e continua a pé
func _moto_fall(u: Dictionary, c) -> void:
	u.fell = true
	u.out = true
	var vel: Vector3 = c.linear_velocity
	var pos: Vector3 = c.global_position + Vector3(0, 1.1, 0)
	if c.has_meta("drv_node"):
		var dn = c.get_meta("drv_node")
		if is_instance_valid(dn):
			dn.queue_free()
		c.remove_meta("drv_node")
	c.throttle = 0.0
	c.ai_target = null
	if c.has_method("fall_over"):
		c.fall_over()
	var cp := Cop.new()
	main.add_child(cp)
	cp.setup(rng.randi(), "cop")
	cp.global_position = pos
	cp.unit = null
	cp.shot_player.connect(main.combat._on_cop_shot)
	cp.died.connect(_on_cop_down)
	cops.append(cp)
	var sev := vel.length()
	main.audio.play("hit", pos, 2.0)
	if sev > 15.0:
		cp.hit(null, vel * 1.1 + Vector3(0, 3.0, 0), main.gore)      # rápido demais: morre na queda
	else:
		cp.knock(vel * 1.05 + Vector3(0, 2.5, 0))

func _crew_out(u: Dictionary, s: int) -> void:
	u.out = true
	var c = u.car
	c.ai_target = null
	c.throttle = 0.0
	c.brake_in = 1.0
	# o motorista que estava sentado vira um dos policiais que descem (não fica ninguém "preso" lá dentro)
	if c.has_meta("drv_node"):
		var dn = c.get_meta("drv_node")
		if is_instance_valid(dn):
			dn.queue_free()
		c.remove_meta("drv_node")
	if c.has_method("set_door"):
		c.set_door(1.0)
	main.audio.play("door", c.global_position)
	var n: int = u.crew
	for i in n:
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var back: float = (i / 2) * 1.6
		var pos: Vector3 = c.global_position + c.global_transform.basis.x * (c.body_size.x * 0.5 + 0.7) * side - c.global_transform.basis.z * back + Vector3(0, 0.2, 0)
		main.get_tree().create_timer(0.15 + i * 0.35).timeout.connect(func():
			if not is_instance_valid(c) or main.wanted == 0:
				return
			var cp := Cop.new()
			main.add_child(cp)
			cp.setup(rng.randi(), {"swat": "swat", "armored": "heavy"}.get(u.kind, "cop"))
			cp.global_position = pos
			cp.body.rotation.y = atan2(c.global_transform.basis.x.x * side, c.global_transform.basis.x.z * side)
			cp.unit = c
			cp.shot_player.connect(main.combat._on_cop_shot)
			cp.died.connect(func(_x): u.crew -= 1)
			cp.died.connect(_on_cop_down)
			cops.append(cp)
			cp.play_anim("exit", 0.55, func(): pass))
	main.get_tree().create_timer(0.6 + n * 0.35).timeout.connect(func(): if is_instance_valid(c) and c.has_method("set_door"): c.set_door(0.0))

func _cops_tick(dt: float, s: int, p: Node3D) -> void:
	var armed: bool = main.combat.weapon != "fist" or armed_t > 0.0 or main.player.vehicle != null
	for cp in cops:
		if cp.down:
			continue
		cp.target = p
		cp.arrest_only = s <= 1 and not armed
		cp.accuracy = 0.32 + s * 0.07
		if cp.weapon == "rifle":
			cp.accuracy += 0.05

func _heli_tick(dt: float, s: int, p: Node3D) -> void:
	if heli == null or not is_instance_valid(heli) or heli.dead:
		return
	# os 2 atiradores mortos: o helicóptero vai embora e outro vem depois de um tempo
	if heli.crew_dead:
		if heli.ai_mode != "leave":
			heli.ai_mode = "leave"
			heli_cd = 45.0
			main._msg("Atiradores abatidos! O helicóptero recuou")
		if heli.global_position.distance_to(p.global_position) > 260.0:
			main.cars.erase(heli)
			heli.queue_free()
			heli = null
		return
	if heli._fall or not knows:
		return
	heli.ai_target = p
	var d: float = heli.global_position.distance_to(p.global_position)
	# quem atira são os atiradores nas portas (com linha de visão de verdade)
	for g in heli.gunners:
		g.cool -= dt
		if g.cool > 0.0 or d > 75.0 or not is_instance_valid(g.h):
			continue
		g.cool = rng.randf_range(0.8, 1.5)
		var from: Vector3 = g.h.muzzle_pos(g.h.global_position + Vector3(0, 1.0, 0))
		var hitp := rng.randf() < 0.28 + s * 0.02
		var aim: Vector3 = p.global_position + Vector3(0, 1.0, 0)
		if not hitp:
			aim += Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
		var q := PhysicsRayQueryParameters3D.create(from, aim + (aim - from).normalized() * 0.5, 1)
		q.exclude = [heli.get_rid()]
		var r := main.get_world_3d().direct_space_state.intersect_ray(q)
		if not r.is_empty() and r.collider != main.player.vehicle:
			W.tracer(main, from, r.position)
			main.bullet_mark(r.position, r.normal, r.collider)
			continue
		W.tracer(main, from, aim)
		main.combat._on_cop_shot(9.0 if hitp else 0.0, from)

func _visibility(dt: float, s: int, pp: Vector3) -> void:
	seen = false
	var sr := 1.0 if knows else 0.7       # procurando: precisa chegar mais perto para reconhecer
	for u in units:
		if u.car.global_position.distance_to(pp) < 55.0 * sr:
			seen = true
	for cp in cops:
		if not cp.down and cp.global_position.distance_to(pp) < 42.0 * sr:
			seen = true
	if heli and is_instance_valid(heli) and not heli.dead and heli.global_position.distance_to(pp) < (95.0 if s >= 5 else 60.0) * sr:
		seen = true
	if s >= 5:
		seen = true      # nível máximo: o exército não desiste (só acaba morrendo)
	if seen and not knows:
		knows = true
		main._msg("A polícia te encontrou!")
	if seen:
		unseen = 0.0
	else:
		unseen += dt
		# perdeu você de vista: volta a procurar na zona em volta do último ponto
		if knows and unseen > 7.0:
			knows = false
			search_pos = last_known
			_sw_t = 0.0
		# fora da zona amarela as estrelas caem mais rápido
		var out_zone: bool = not knows and pp.distance_to(search_pos) > ZONE_R
		if unseen > (7.0 + s * 2.0) * (0.5 if out_zone else 1.0):
			unseen = 0.0
			main.wanted -= 1
			if main.wanted == 0:
				main._msg("Você despistou a polícia!")

## 1★: o policial pula em cima (a pé) ou abre a porta e puxa você do carro parado → PRESO.
## 2★+: preso se ficar encostado num policial por 2 s.
var arresting := false
func _bust(dt: float, s: int, pp: Vector3) -> void:
	if arresting or main.combat.dead or main.combat.busted_t > 0.0:
		return
	var v = main.player.vehicle
	for cp in cops:
		if cp.down or cp.anim != "":
			continue
		var d: float = cp.global_position.distance_to(pp)
		if s <= 1 and cp.arrest_only:
			if v == null and d < 2.6:
				arresting = true
				cp.play_anim("tackle", 0.45, func():
					main.combat.knockdown((pp - cp.global_position).normalized() * 3.0 + Vector3(0, 1.0, 0), 4.0)
					main.get_tree().create_timer(1.4).timeout.connect(func(): arresting = false; main.combat.busted()))
				return
			if v != null and v.linear_velocity.length() < 2.0 and v.get("kind") not in ["plane", "heli", "boat"] and cp.global_position.distance_to(v.door_world()) < 1.8:
				arresting = true
				v.set_door(1.0)
				cp.play_anim("pull", 1.0, func():
					var c2 = main.player.vehicle
					if c2:
						main.eject_player(Vector3.ZERO)
						c2.set_door(0.0)
					main.combat.knockdown(cp.global_transform.basis.z * -2.0 + Vector3(0, 1.0, 0), 4.0)
					main.get_tree().create_timer(1.4).timeout.connect(func(): arresting = false; main.combat.busted()))
				return
		elif v == null and d < 1.6:
			bust_t += dt
			if bust_t > 2.0:
				bust_t = 0.0
				main.combat.busted()
			return
	bust_t = 0.0

## policial caído: outro colega (se houver pelo menos 2) arrasta o corpo para trás de uma viatura
func _on_cop_down(dead_cop) -> void:
	var alive := cops.filter(func(c): return is_instance_valid(c) and not c.down and c.rescue_rb == null and c.anim == "")
	if alive.size() < 2 or dead_cop.body.parts.is_empty():
		return
	var rb: RigidBody3D = dead_cop.body.parts[1] if dead_cop.body.parts.size() > 1 else dead_cop.body.parts[0]
	var best = null
	var bd := 1e9
	for c in alive:
		var d: float = c.global_position.distance_to(rb.global_position)
		if d < bd:
			bd = d
			best = c
	if best == null or bd > 25.0:
		return
	var pp: Vector3 = main.player.global_position
	var dest: Vector3 = rb.global_position + (rb.global_position - pp).normalized() * 6.0
	if dead_cop.unit and is_instance_valid(dead_cop.unit):
		var uc: Vector3 = dead_cop.unit.global_position
		dest = uc + (uc - pp).normalized() * 2.8
	dest.y = best.global_position.y
	best.start_rescue(rb, dest)

func _retreat(pp: Vector3) -> void:
	for u in units.duplicate():
		var c = u.car
		if c == main.player.vehicle:
			units.erase(u)
			continue
		c.ai_target = null
		c.brake_in = 0.0
		c.throttle = 0.4
		if c.global_position.distance_to(pp) > 70.0:
			main.cars.erase(c)
			c.queue_free()
			units.erase(u)
	for cp in cops.duplicate():
		if cp.down:
			continue
		cp.target = null
		if cp.global_position.distance_to(pp) > 35.0:
			cp.queue_free()
			cops.erase(cp)
	if heli and is_instance_valid(heli):
		heli.ai_target = null
		heli.ai_mode = "leave"
		if heli.global_position.distance_to(pp) > 140.0:
			main.cars.erase(heli)
			heli.queue_free()
			heli = null

## 5 estrelas: o exército entra — 2 tanques pelas ruas e um caça com mísseis (volta se for derrubado)
func _army_tick(dt: float, s: int, pp: Vector3) -> void:
	army = army.filter(func(a): return is_instance_valid(a))
	if s < 5:
		for a in army:
			if a.global_position.distance_to(pp) > 120.0 or a.kind == "jet":
				a.queue_free()
		return
	var tanks := army.filter(func(a): return a.kind == "tank" and not a.dead).size()
	tank_cd -= dt
	if tanks < 2 and tank_cd <= 0.0:
		var sp := _spawn_point(pp)
		var t := Tank.new()
		main.add_child(t)
		t.setup(main)
		t.global_position = sp[0] + Vector3(0, 0.6, 0)
		t.rotation.y = sp[1]
		var ts: Array = main.world2.tank_spots
		if not ts.is_empty():
			# sai da garagem da base do exército
			var spot: Array = ts[army.filter(func(a): return a.kind == "tank").size() % ts.size()]
			t.global_position = spot[0] + Vector3(0, 0.3, 0)
			t.rotation.y = spot[1]
		army.append(t)
		tank_cd = 8.0
		if tanks == 0:
			main.hud.banner("O EXÉRCITO CHEGOU!", Color(1, 0.3, 0.2))
	jet_cd -= dt
	var jets := army.filter(func(a): return a.kind == "jet").size()
	if jets == 0 and jet_cd <= 0.0:
		var j := Jet.new()
		main.add_child(j)
		j.setup(main)
		j.start(pp)
		if not main.world2.jet_spots.is_empty():
			j.start_from(main.world2.jet_spots[0][0])
		army.append(j)
		jet_cd = 20.0

## com estrela: as viaturas e a moto que patrulhavam e os policiais a pé passam a perseguir
func _activate_patrols(pp: Vector3) -> void:
	for a in main.traffic_sys.agents.duplicate():
		var c = a.car
		if is_instance_valid(c) and c.has_meta("patrol") and c.global_position.distance_to(pp) < 260.0:
			main.traffic_sys.agents.erase(a)
			c.remove_meta("patrol")
			c.siren_on = true
			units.append({"car": c, "kind": "moto" if c.kind == "moto" else "car", "out": false, "crew": 1 if c.kind == "moto" else 2})
	for cp in patrol_cops:
		if is_instance_valid(cp) and not cp.down:
			cp.patrol = []
			cp.shot_player.connect(main.combat._on_cop_shot)
			cp.died.connect(_on_cop_down)
			cops.append(cp)
	patrol_cops.clear()

# ---------------------------------------------------------------- lanchas da polícia
func _spawn_boat(pp: Vector3) -> void:
	var w2 = main.world2
	var best := pp
	var bd := -1e9
	for k in 12:
		var a := k * TAU / 12.0
		var q := pp + Vector3(cos(a), 0, sin(a)) * 110.0
		var sd: float = w2.sea_dist(q.x, q.z)
		if sd > bd:
			bd = sd
			best = q
	if bd < 10.0:
		return
	var b = main._spawn_arcade("boat", Vector3(best.x, w2.WATER_Y - 0.5, best.z), atan2(pp.x - best.x, pp.z - best.z), Color(0.1, 0.2, 0.5))
	b.police = true
	b.hp = 220.0
	for k in 2:
		var dh := preload("res://scripts/humanoid.gd").new()
		dh.build(Color(0.12, 0.2, 0.42), Color(0.08, 0.1, 0.2), Color(0.78, 0.56, 0.38), Color(0.06, 0.05, 0.05), {"hat": 1, "hat_c": Color(0.08, 0.1, 0.22)})
		dh.sitting = k == 0
		dh.scale = Vector3.ONE * 0.85
		dh.position = Vector3(b.seat.x - k * 0.8, b.seat.y + (0.07 - 0.98 * 0.85 if k == 0 else -0.6), b.seat.z - k * 1.4)
		b.model_root.add_child(dh)
		dh.aiming = k == 1
		dh.animate(0, 0)
		dh.set_far(80.0)
	units.append({"car": b, "kind": "boat", "out": false, "crew": 0, "cool": 1.5})
	main._msg("Lancha da polícia!")

func _boat_chase(u: Dictionary, dt: float, s: int, pp: Vector3, d: float) -> void:
	var b = u.car
	var to: Vector3 = pp - b.global_position
	var want := atan2(to.x, to.z)
	b.steer_in = clampf(wrapf(want - b.yaw, -PI, PI) * 1.6, -1.0, 1.0)
	b.throttle = 1.0 if d > 22.0 else (0.35 if d > 10.0 else 0.0)
	# atirador na lancha
	u.cool = u.get("cool", 1.5) - dt
	if u.cool <= 0.0 and d < 60.0:
		u.cool = rng.randf_range(0.9, 1.6)
		var from: Vector3 = b.global_position + Vector3(0, 1.6, 0)
		var hitp := rng.randf() < 0.3 + s * 0.04
		var aim: Vector3 = pp + Vector3(0, 1.0, 0)
		if not hitp:
			aim += Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
		W.tracer(main, from, aim)
		main.combat._on_cop_shot(8.0 if hitp else 0.0, from)

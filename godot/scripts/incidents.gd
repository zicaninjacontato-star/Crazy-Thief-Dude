extends Node
## Reações da polícia ao que acontece na cidade (sem o jogador ser o alvo):
##  • gangue atirando no jogador que NÃO revida → viaturas vêm e trocam tiro com os gangsters
##    (reforços a cada ~30 s enquanto o tiroteio continua)
##  • motorista NPC atropela alguém → viatura persegue o carro; o motorista se rende (algemado,
##    vai para a delegacia; outro policial leva o carro apreendido) ou reage (troca de tiros).
##    Carro destruído → o caminhão guincho da polícia vem rebocar a carcaça.

const Cop := preload("res://scripts/cop.gd")
const Ped := preload("res://scripts/ped.gd")

var main: Node3D
var rng := RandomNumberGenerator.new()
var gang_resp := {}          # {pos, units:[{car, nav, out}], cops:[], t, extra_t}
var cases: Array = []        # atropelamentos
var _scan_t := 0.0
var _leaving: Array = []     # nós que somem quando ninguém está olhando
var last_gang_shot := -99.0

func setup(m: Node3D) -> void:
	main = m
	rng.randomize()

func clear() -> void:
	for n in _all_nodes():
		if is_instance_valid(n):
			if n in main.cars:
				main.cars.erase(n)
			n.queue_free()
	gang_resp = {}
	cases = []
	_leaving = []

func _all_nodes() -> Array:
	var out: Array = _leaving.duplicate()
	if not gang_resp.is_empty():
		for u in gang_resp.units:
			out.append(u.car)
		out += gang_resp.cops
	for cs in cases:
		for k in ["unit", "tow", "suspect"]:
			if cs.get(k) != null:
				out.append(cs[k])
		out += cs.cops
	return out

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

# ---------------------------------------------------------------- utilidades
func _spawn_unit(pp: Vector3, tow := false):
	var sp: Array = main.police._spawn_point(pp)
	var c
	if tow:
		c = main._spawn_car(sp[0], sp[1], Color(0.95, 0.72, 0.1), false, "truck")
		c.set_meta("tow", true)
		main.traffic_sys._driver({"car": c})
	else:
		c = main._spawn_car(sp[0], sp[1], Color(0.92, 0.92, 0.93), true)
		c.siren_on = true
		c.max_engine = 6800.0
		main.traffic_sys._driver({"car": c})
	c.unlocked = false
	c.set_meta("incident", true)
	return c

func _crew(c, n: int) -> Array:
	var out: Array = []
	if c.has_meta("drv_node"):
		var dn = c.get_meta("drv_node")
		if is_instance_valid(dn):
			dn.queue_free()
		c.remove_meta("drv_node")
	if c.has_method("set_door"):
		c.set_door(1.0)
		main.get_tree().create_timer(1.2).timeout.connect(func(): if is_instance_valid(c): c.set_door(0.0))
	main.audio.play("door", c.global_position)
	for i in n:
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var cp := Cop.new()
		main.add_child(cp)
		cp.setup(rng.randi(), "cop")
		cp.global_position = c.global_position + c.global_transform.basis.x * (c.body_size.x * 0.5 + 0.8) * side + Vector3(0, 0.3, 0)
		cp.unit = c
		cp.shot_player.connect(main.combat._on_cop_shot)
		main.police.patrol_cops.append(cp)      # o jogador consegue bater/atirar neles
		out.append(cp)
	return out

func _drive(c, goal: Vector3, st: Dictionary, dt: float, vmax: float) -> void:
	if not is_instance_valid(c) or c.dead:
		return
	c.ai_target = null
	main.traffic_sys.chase(c, goal, goal, st, dt, vmax)

func _stop(c) -> void:
	if is_instance_valid(c):
		c.throttle = 0.0
		c.brake_in = 1.0
		c.steer_in = 0.0

## some quando ninguém está olhando (longe ou fora da tela)
func _leave(n) -> void:
	if n != null and is_instance_valid(n) and not (n in _leaving):
		_leaving.append(n)
		if n in main.police.patrol_cops:
			main.police.patrol_cops.erase(n)

func _leaving_tick() -> void:
	for n in _leaving.duplicate():
		if not is_instance_valid(n):
			_leaving.erase(n)
			continue
		var far: bool = n.global_position.distance_to(main.player.global_position) > 45.0
		if (far and not main._seen(n.global_position + Vector3(0, 1, 0))) or n.global_position.distance_to(main.player.global_position) > 160.0:
			if n == main.player.vehicle:
				_leaving.erase(n)
				continue
			if n in main.cars:
				main.cars.erase(n)
			_leaving.erase(n)
			n.queue_free()

func _nearest(from: Vector3, list: Array, maxd: float):
	var best = null
	var bd := maxd
	for q in list:
		if not is_instance_valid(q) or q.down:
			continue
		var d: float = q.global_position.distance_to(from)
		if d < bd:
			bd = d
			best = q
	return best

# ---------------------------------------------------------------- tick
func tick(dt: float) -> void:
	if main == null or main.combat.dead:
		return
	_leaving_tick()
	_gang_tick(dt)
	_scan_t -= dt
	if _scan_t <= 0.0:
		_scan_t = 0.15
		_scan_runover()
	for cs in cases.duplicate():
		_case_tick(cs, dt)

# ---------------------------------------------------------------- gangue × polícia
## um membro de gangue atirou no jogador
func on_gang_shot(m) -> void:
	last_gang_shot = _now()
	if main.wanted > 0 or not gang_resp.is_empty():
		return
	# o jogador está revidando: a polícia não se mete (só quem estiver passando)
	if _now() - main.combat.last_shot_t < 8.0:
		return
	if rng.randf() > 0.35:
		return            # nem todo tiro vira chamado; uma rajada sim
	var pos: Vector3 = m.global_position
	gang_resp = {"pos": pos, "units": [], "cops": [], "t": 0.0, "extra_t": 30.0}
	_gang_add_unit()

func _gang_add_unit() -> void:
	if gang_resp.units.size() >= 3:
		return
	var c = _spawn_unit(gang_resp.pos)
	gang_resp.units.append({"car": c, "nav": {}, "out": false})

func _gangsters_near(pos: Vector3, r: float) -> Array:
	var out: Array = []
	for g in ["g", "p"]:
		for q in main.gangs.members.get(g, []):
			if is_instance_valid(q) and not q.down and q.global_position.distance_to(pos) < r:
				out.append(q)
	return out

func _gang_tick(dt: float) -> void:
	if gang_resp.is_empty():
		return
	gang_resp.t += dt
	var pos: Vector3 = gang_resp.pos
	var gs := _gangsters_near(pos, 55.0)
	# reforços enquanto o tiroteio continua
	gang_resp.extra_t -= dt
	if gang_resp.extra_t <= 0.0 and gs.size() > 1:
		gang_resp.extra_t = 30.0
		_gang_add_unit()
	for u in gang_resp.units:
		var c = u.car
		if not is_instance_valid(c) or c.dead:
			continue
		if not u.out:
			# vai até a rua mais perto do tiroteio (o esconderijo é murado)
			if not gang_resp.has("road"):
				gang_resp.road = main.road_snap(pos)
				# perto de um esconderijo: para na rua em frente ao portão
				for hq in main.city.gang_hq.values():
					if hq.c.distance_to(pos) < 60.0:
						gang_resp.road = hq.gate_out
			var goal: Vector3 = gang_resp.road
			var d: float = c.global_position.distance_to(goal)
			_drive(c, goal, u.nav, dt, clampf((d - 6.0) * 0.8, 0.0, 28.0))
			if d < 14.0 and c.linear_velocity.length() < 2.0 or (d < 30.0 and gang_resp.t > 40.0):
				u.out = true
				_stop(c)
				gang_resp.cops += _crew(c, 2)
		else:
			_stop(c)
	# policiais miram nos gangsters; gangsters revidam nos policiais mais perto
	gang_resp.cops = gang_resp.cops.filter(func(q): return is_instance_valid(q))
	for cp in gang_resp.cops:
		if cp.down:
			continue
		var t = _nearest(cp.global_position, gs, 60.0)
		cp.target = t
		cp.searching = false
		cp.cool = minf(cp.cool, 1.2)
	for q in gs:
		var cp = _nearest(q.global_position, gang_resp.cops, 35.0)
		q.alt_target = cp
	# acabou: ninguém da gangue por perto (ou demorou demais) → voltam para as viaturas e vão embora
	if (gs.is_empty() and gang_resp.t > 8.0) or gang_resp.t > 150.0 or main.wanted > 0:
		for q in _gangsters_near(pos, 80.0):
			q.alt_target = null
		for cp in gang_resp.cops:
			if is_instance_valid(cp):
				cp.target = null
				_leave(cp)
		for u in gang_resp.units:
			if is_instance_valid(u.car):
				_leave(u.car)
		gang_resp = {}

## policial que passa num tiroteio jogador × gangue: atira nos dois (alterna o alvo)
func mixed_target(cp) -> void:
	if not main.gang_war():
		return
	var t: float = cp.get_meta("mix_t", 0.0) - 0.0
	if _now() < t:
		return
	cp.set_meta("mix_t", _now() + rng.randf_range(2.5, 4.0))
	if rng.randf() < 0.45:
		cp.alt_target = _nearest(cp.global_position, _gangsters_near(cp.global_position, 30.0), 30.0)
	else:
		cp.alt_target = null

# ---------------------------------------------------------------- atropelamento por NPC
func _scan_runover() -> void:
	if main.traffic_sys == null:
		return
	for a in main.traffic_sys.agents:
		var c = a.car
		if not is_instance_valid(c) or c.dead or c.get("police") == true:
			continue
		var v: Vector3 = c.linear_velocity
		if v.length() < 6.0:
			continue
		var cp: Vector3 = c.global_position
		for p in main.peds:
			if not is_instance_valid(p) or p.down or p.mode in ["swim", "fish"]:
				continue
			var d: Vector3 = p.global_position - cp
			if absf(d.x) > 3.0 or absf(d.z) > 3.0 or absf(d.y) > 1.6:
				continue
			var lp: Vector3 = c.global_transform.affine_inverse() * p.global_position
			if absf(lp.x) < c.body_size.x * 0.5 + 0.35 and absf(lp.z) < c.body_size.z * 0.5 + 0.35:
				p.hit(c, v, main.gore)
				main.audio.play("hit", p.global_position, 4.0)
				main.audio.play("scream", p.global_position, -2.0)
				for q in main.peds:
					if is_instance_valid(q) and q != p and q.global_position.distance_to(p.global_position) < 18.0:
						q.scare()
				_new_case(c)
				return

func _new_case(c) -> void:
	if main.wanted > 0 or cases.size() >= 2:
		return
	for cs in cases:
		if cs.car == c:
			return
	main.traffic_sys.crash_mode(c, "flee", 40.0)
	var u = _spawn_unit(c.global_position)
	cases.append({"car": c, "unit": u, "nav": {}, "state": "chase", "t": 0.0, "cops": [], "suspect": null, "tow": null, "tnav": {}, "arrest_t": 0.0, "snav": {}})
	if main.shot != "":
		print("INC new case car=", c.kind)

func _case_tick(cs: Dictionary, dt: float) -> void:
	cs.t += dt
	var car = cs.car
	var unit = cs.unit
	var car_ok: bool = is_instance_valid(car) and not car.dead
	# carro destruído: chama o guincho (uma vez) e o caso segue sem carro
	if is_instance_valid(car) and car.dead and cs.tow == null and car != main.player.vehicle:
		cs.tow = _spawn_unit(car.global_position, true)
	if cs.tow != null and is_instance_valid(cs.tow):
		_tow_tick(cs, dt)
	match cs.state:
		"chase":
			if not car_ok or not is_instance_valid(unit) or unit.dead or car == main.player.vehicle:
				cs.state = "end"
				return
			var d: float = unit.global_position.distance_to(car.global_position)
			_drive(unit, car.global_position, cs.nav, dt, 30.0 if d > 20.0 else clampf((d - 7.0), 0.0, 20.0))
			# encurralado (viatura colada) ou cansou de fugir: para e desce
			if (d < 11.0 and car.linear_velocity.length() < 4.0) or cs.t > 35.0 or (d < 9.0 and cs.t > 12.0):
				_suspect_out(cs)
		"stop":
			_stop(car)
			var d2: float = unit.global_position.distance_to(car.global_position) if is_instance_valid(unit) else 99.0
			if is_instance_valid(unit) and cs.cops.is_empty():
				_drive(unit, car.global_position, cs.nav, dt, clampf((d2 - 7.0) * 0.8, 0.0, 14.0))
				if d2 < 12.0 and unit.linear_velocity.length() < 1.5 or cs.t > 50.0:
					_stop(unit)
					cs.cops = _crew(unit, 2)
			_arrest_tick(cs, dt)
		"leave":
			# viatura leva o preso; o outro policial leva o carro apreendido (os dois somem longe da vista)
			var st: Dictionary = main.city.station
			var goal: Vector3 = st.garage_out if not st.is_empty() else Vector3.ZERO
			if is_instance_valid(unit) and not unit.dead:
				_drive(unit, goal, cs.nav, dt, 22.0)
			if car_ok and car.get_meta("seized", false):
				_drive(car, goal, cs.snav, dt, 20.0)
			var gone: bool = not is_instance_valid(unit) or (unit.global_position.distance_to(main.player.global_position) > 50.0 and not main._seen(unit.global_position))
			if cs.t > 60.0 or (gone and cs.t > 4.0):
				cs.state = "end"
		"end":
			for cp in cs.cops:
				if is_instance_valid(cp):
					cp.target = null
					_leave(cp)
			if is_instance_valid(unit):
				_leave(unit)
			if car_ok and car.get_meta("seized", false):
				_leave(car)
			if cs.suspect != null and is_instance_valid(cs.suspect):
				_leave(cs.suspect)
			# o guincho termina o serviço sozinho (engata, leva e some)
			if cs.tow == null or not is_instance_valid(cs.tow):
				cases.erase(cs)

## o motorista desce: 70% se rende (mãos para cima), 30% reage atirando
func _suspect_out(cs: Dictionary) -> void:
	var car = cs.car
	cs.state = "stop"
	cs.t = 0.0
	var info: Dictionary = main.traffic_sys.release(car)
	_stop(car)
	if info.get("drv") != null and is_instance_valid(info.drv):
		info.drv.queue_free()
	var pos: Vector3 = car.global_position + car.global_transform.basis.x * (car.body_size.x * 0.5 + 0.8) + Vector3(0, 0.3, 0)
	pos.y = main.ground_at(pos, [car.get_rid()])
	if rng.randf() < 0.3:
		var t := Cop.new()
		main.add_child(t)
		t.setup(rng.randi(), "thug")
		t.global_position = pos + Vector3(0, 0.2, 0)
		t.hp = 110.0
		t.shot_player.connect(main.combat._on_cop_shot)
		cs.suspect = t
		cs.fight = true
	else:
		var p := Ped.new()
		main.add_child(p)
		p.setup([pos, pos, pos, pos], 0, rng)
		p.global_position = pos
		p.mode = "handsup"
		p.mode_t = 999.0
		p.body.arm_pose = "handsup"
		p.died.connect(main._on_ped_died)
		main.peds.append(p)
		cs.suspect = p
		cs.fight = false

func _arrest_tick(cs: Dictionary, dt: float) -> void:
	var s = cs.suspect
	var alive: bool = s != null and is_instance_valid(s) and not s.down
	cs.cops = cs.cops.filter(func(q): return is_instance_valid(q))
	for cp in cs.cops:
		if cp.down:
			continue
		if alive:
			cp.target = s
			cp.arrest_only = not cs.fight
			cp.searching = false
		else:
			cp.target = null
	if alive and cs.fight:
		s.target = _nearest(s.global_position, cs.cops, 40.0)
	if cs.cops.is_empty():
		return
	if not alive:
		# reagiu e morreu: a equipe volta; o carro (se inteiro) vai apreendido
		cs.state = "leave"
		cs.t = 0.0
		for cp in cs.cops:
			_leave(cp)
		if is_instance_valid(cs.car) and not cs.car.dead:
			_seize(cs)
		return
	if not cs.fight:
		var cp0 = cs.cops[0]
		# travou (viatura no caminho, quina): o policial chega até o suspeito de qualquer jeito
		if cs.t > 20.0 and is_instance_valid(cp0) and not main._seen(cp0.global_position + Vector3(0, 1, 0)):
			cp0.global_position = s.global_position + Vector3(1.0, 0, 0)
		if is_instance_valid(cp0) and cp0.global_position.distance_to(s.global_position) < 1.8:
			cs.arrest_t += dt
			if cs.arrest_t > 1.6:
				# algemado: preso e policial entram na viatura
				main.audio.play("door", s.global_position)
				main.peds.erase(s)
				s.queue_free()
				cs.suspect = null
				cp0.queue_free()
				cs.cops.erase(cp0)
				if cs.cops.size() > 0:
					var cp1 = cs.cops[0]
					cs.cops.erase(cp1)
					cp1.queue_free()
					if is_instance_valid(cs.car) and not cs.car.dead:
						_seize(cs)
				main.traffic_sys._driver({"car": cs.unit})
				cs.state = "leave"
				cs.t = 0.0

func _seize(cs: Dictionary) -> void:
	var car = cs.car
	car.set_meta("seized", true)
	car.unlocked = false
	main.traffic_sys._driver({"car": car})

## guincho: vai até a carcaça, engata e reboca para a delegacia
func _tow_tick(cs: Dictionary, dt: float) -> void:
	var tw = cs.tow
	var wreck = cs.car
	if not is_instance_valid(wreck):
		_leave(tw)
		cs.tow = null
		return
	var hooked = tw.get_meta("towing", null)
	if hooked == null:
		var d: float = tw.global_position.distance_to(wreck.global_position)
		_drive(tw, wreck.global_position, cs.tnav, dt, clampf((d - 8.0) * 0.8, 0.0, 22.0))
		if d < 11.0 and tw.linear_velocity.length() < 1.5:
			tw.set_meta("towing", wreck)
			wreck.freeze = true
			wreck.collision_layer = 0
			wreck.collision_mask = 0
			main.audio.play("door", tw.global_position)
	else:
		# carcaça pendurada atrás, frente levantada
		var back: Transform3D = tw.global_transform * Transform3D(Basis(Vector3.RIGHT, -0.22), Vector3(0, 0.9, -tw.body_size.z * 0.5 - wreck.body_size.z * 0.45))
		wreck.global_transform = back
		var st: Dictionary = main.city.station
		_drive(tw, st.garage_out if not st.is_empty() else Vector3.ZERO, cs.tnav, dt, 16.0)
		var far: bool = tw.global_position.distance_to(main.player.global_position) > 50.0 and not main._seen(tw.global_position)
		if far or tw.global_position.distance_to(main.player.global_position) > 160.0:
			main.cars.erase(wreck)
			wreck.queue_free()
			main.cars.erase(tw)
			tw.queue_free()
			cs.tow = null
			cs.car = null
			if cs.state != "end":
				cs.state = "end"

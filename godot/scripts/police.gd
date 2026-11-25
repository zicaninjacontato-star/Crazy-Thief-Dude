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

var main: Node3D
var units: Array = []       # {car, kind, out, crew}
var cops: Array = []
var heli = null
var heli_cool := 1.0
var unseen := 0.0
var seen := true
var spawn_cd := 0.0
var bust_t := 0.0
var armed_t := 0.0          # >0: jogador sacou/atirou recentemente
var rng := RandomNumberGenerator.new()
var _mk: Marker3D

func setup(m: Node3D) -> void:
	main = m
	rng.seed = 404
	_mk = Marker3D.new()
	m.add_child(_mk)

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
	unseen = 0.0
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
	cops = cops.filter(func(c): return is_instance_valid(c))
	units = units.filter(func(u): return is_instance_valid(u.car) and not u.car.dead)
	armed_t -= dt
	var s: int = main.wanted
	var p: Node3D = main.player.vehicle if main.player.vehicle else main.player
	var pp: Vector3 = p.global_position
	# viatura mais próxima (sirene e minimapa)
	var near = null
	var nd := 1e9
	for u in units:
		var d: float = u.car.global_position.distance_to(pp)
		if d < nd:
			nd = d
			near = u.car
	main.police_car = near
	if s == 0:
		_retreat(pp)
		return
	var want_cars: int = [0, 1, 2, 3, 3, 4][s]
	var want_swat: int = 0 if s < 3 else (1 if s < 5 else 2)
	var n_car := units.filter(func(u): return u.kind == "car").size()
	var n_swat := units.filter(func(u): return u.kind == "swat").size()
	spawn_cd -= dt
	if spawn_cd <= 0.0:
		if n_car < want_cars:
			_spawn_unit("car", s, pp)
			spawn_cd = 2.5
		elif n_swat < want_swat:
			_spawn_unit("swat", s, pp)
			spawn_cd = 4.0
	if s >= 4 and (heli == null or not is_instance_valid(heli) or heli.dead):
		if heli == null or not is_instance_valid(heli):
			_spawn_heli(pp)
	_units_tick(dt, s, p, pp)
	_cops_tick(dt, s, p)
	_heli_tick(dt, s, p)
	_visibility(dt, s, pp)
	_bust(dt, s, pp)

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
	var sp := _spawn_point(pp)
	var c
	if kind == "swat":
		c = main._spawn_car(sp[0], sp[1], Color(0.06, 0.06, 0.07), false, "suv")
		c.make_police()
		c.max_engine = 7400.0
	else:
		c = main._spawn_car(sp[0], sp[1], Color(0.92, 0.92, 0.93), true)
		c.max_engine = 6600.0 + s * 300.0
		if s >= 3:
			c.paint_black()
	units.append({"car": c, "kind": kind, "out": false, "crew": 4 if kind == "swat" else 2})

func _spawn_heli(pp: Vector3) -> void:
	var h = Arcade.new()
	h.police = true
	main.add_child(h)
	h.setup("heli", Color(0.1, 0.18, 0.45))
	h.hp = 300.0
	var a := rng.randf() * TAU
	h.global_position = pp + Vector3(cos(a) * 140.0, 45.0, sin(a) * 140.0)
	h.ai_mode = "follow"
	h.ai_target = main.player
	h.world2 = main.world2
	h.destroyed.connect(main._on_vehicle_destroyed)
	main.cars.append(h)
	heli = h

func _units_tick(dt: float, s: int, p: Node3D, pp: Vector3) -> void:
	var pv: Vector3 = main.player.vehicle.linear_velocity if main.player.vehicle else main.player.velocity
	for u in units:
		var c = u.car
		if c == main.player.vehicle:
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
			main.traffic_sys.chase(c, pp, lead, u.nav, dt, vmax)
			if d < (22.0 if on_foot else 17.0) and (on_foot or pv.length() < 4.0):
				_crew_out(u, s)
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

func _crew_out(u: Dictionary, s: int) -> void:
	u.out = true
	var c = u.car
	c.ai_target = null
	c.throttle = 0.0
	c.brake_in = 1.0
	var n: int = u.crew
	for i in n:
		var cp := Cop.new()
		main.add_child(cp)
		cp.setup(rng.randi(), "swat" if u.kind == "swat" else "cop")
		var side: float = 1.0 if i % 2 == 0 else -1.0
		cp.global_position = c.global_position + c.global_transform.basis.x * (c.body_size.x * 0.5 + 0.8) * side - c.global_transform.basis.z * (i / 2) * 1.5 + Vector3(0, 0.2, 0)
		cp.unit = c
		cp.shot_player.connect(main.combat._on_cop_shot)
		cp.died.connect(func(_x): u.crew -= 1)
		cp.died.connect(_on_cop_down)
		cops.append(cp)
		main.audio.play("door", c.global_position)

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
	heli.ai_target = p
	heli_cool -= dt
	var d: float = heli.global_position.distance_to(p.global_position)
	if heli_cool <= 0.0 and d < 70.0:
		heli_cool = rng.randf_range(0.7, 1.3)
		var from: Vector3 = heli.global_position + Vector3(0, 0.5, 0)
		var hitp := rng.randf() < 0.3
		var aim: Vector3 = p.global_position + Vector3(0, 1.0, 0)
		if not hitp:
			aim += Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
		W.tracer(main, from, aim)
		main.combat._on_cop_shot(9.0 if hitp else 0.0, from)

func _visibility(dt: float, s: int, pp: Vector3) -> void:
	seen = false
	for u in units:
		if u.car.global_position.distance_to(pp) < 55.0:
			seen = true
	for cp in cops:
		if not cp.down and cp.global_position.distance_to(pp) < 42.0:
			seen = true
	if heli and is_instance_valid(heli) and not heli.dead and heli.global_position.distance_to(pp) < 95.0:
		seen = true
	if seen:
		unseen = 0.0
	else:
		unseen += dt
		if unseen > 7.0 + s * 2.0:
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

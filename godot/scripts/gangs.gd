extends Node
## Gangues VERDE e ROSA: território (círculo), bandos de até 4 a pé, carros exclusivos na cor da gangue,
## aviso para ir embora e nível de procurado por gangue (caveiras na cor da gangue):
##   1 caveira: pistolas · 2: pistolas + submetralhadoras · 3: + carros · 4: submetralhadoras, escopetas,
##   motos e carros. Cofre, drogas e armas guardados no território (dá para roubar). A polícia não se mete.

const Cop := preload("res://scripts/cop.gd")
const M := preload("res://scripts/mats.gd")
const FX := preload("res://scripts/fx.gd")

var main: Node3D
var rng := RandomNumberGenerator.new()
var T := {}                   # id -> {name, c: Vector3, r, col: Color}
var members := {"g": [], "p": []}
var skulls := 0
var hunter := ""              # gangue que está atrás do jogador
var warn_t := 0.0
var warn_g := ""
var loots: Array = []         # [{gang, kind, pos, node, cd}]
var hunters: Array = []       # carros/motos de perseguição [{car, crew, gang}]
var _reinf_t := 0.0
var _lost_t := 0.0
var _car_t := 0.0

func setup(m: Node3D) -> void:
	main = m
	rng.randomize()
	var city = m.city
	T = {
		"g": {"name": "Gangue Verde", "c": Vector3(-90.0, 0, -306.0), "r": 55.0, "col": Color(0.15, 0.85, 0.3)},
		"p": {"name": "Gangue Rosa", "c": Vector3(city._center(5), 0, city._center(6) + 8.0), "r": 52.0, "col": Color(1.0, 0.35, 0.72)},
	}
	# os raios de "ponto livre" só enxergam as colisões depois de alguns passos de física
	for k in 3:
		await main.get_tree().physics_frame
	_build_loot()
	_phys_ok = true
	if _pending_pop:
		populate()

var _phys_ok := false
var _pending_pop := false
## repovoa (início e depois de morrer/ser preso)
func populate() -> void:
	if not _phys_ok:
		_pending_pop = true
		return
	_pending_pop = false
	clear()
	for g in T:
		var c: Vector3 = T[g].c
		for k in 3:
			var gp: Vector3 = _free_spot(c, T[g].r * 0.15, T[g].r * 0.6)
			var n := rng.randi_range(2, 4)
			for i in n:
				_spawn_member(g, _free_spot(gp, 0.0, 2.5) + Vector3(0, 0.3, 0), "pistol", true)
		# carros da gangue estacionados
		for k in 2:
			var pc = main._spawn_car(_free_spot(c, T[g].r * 0.3, T[g].r * 0.6, 3.0) + Vector3(0, 0.7, 0), rng.randf() * TAU, T[g].col.darkened(0.1), false, ["sedan", "suv", "pickup"][k % 3])
			pc.parked = true
			pc.set_meta("gang", g)
	skulls = 0
	hunter = ""

func clear() -> void:
	for g in members:
		for q in members[g]:
			if is_instance_valid(q):
				q.queue_free()
		members[g] = []
	for h in hunters:
		if is_instance_valid(h.car):
			main.cars.erase(h.car)
			h.car.queue_free()
	hunters.clear()
	skulls = 0
	hunter = ""
	warn_t = 0.0

func alive() -> Array:
	var out := []
	for g in members:
		for q in members[g]:
			if is_instance_valid(q) and not q.down:
				out.append(q)
	return out

## ponto livre no chão (sem prédio, galpão, contêiner nem água) entre rmin e rmax do centro
func _free_spot(c: Vector3, rmin: float, rmax: float, clear := 0.8) -> Vector3:
	var ss = main.get_world_3d().direct_space_state
	for k in 24:
		var a := rng.randf() * TAU
		var p: Vector3 = c + Vector3(cos(a), 0, sin(a)) * rng.randf_range(rmin, rmax)
		if main.world2.is_water(p.x, p.z):
			continue
		var ok := true
		for o in [Vector3.ZERO, Vector3(clear, 0, 0), Vector3(-clear, 0, 0), Vector3(0, 0, clear), Vector3(0, 0, -clear)]:
			var q := PhysicsRayQueryParameters3D.create(p + o + Vector3(0, 14.0, 0), p + o + Vector3(0, -1.0, 0), 1)
			var r = ss.intersect_ray(q)
			if r.is_empty() or r.position.y > 0.45:
				ok = false
				break
		if ok:
			return Vector3(p.x, 0.0, p.z)
	return Vector3(c.x, 0.0, c.z)

func _spawn_member(g: String, pos: Vector3, weapon: String, idle: bool):
	var q = Cop.new()
	main.add_child(q)
	q.setup(rng.randi(), "gang_g" if g == "g" else "gang_p")
	q.gang = g
	q.global_position = pos
	q.set_weapon(weapon)
	q.accuracy = 0.3
	if idle:
		q.target = null
		var home: Vector3 = pos
		q.patrol = [home + Vector3(1.5, 0, 0), home + Vector3(0, 0, 1.5), home + Vector3(-1.5, 0, 0), home + Vector3(0, 0, -1.5)] if rng.randf() < 0.4 else []
	else:
		q.target = main.player
	q.shot_player.connect(main.combat._on_cop_shot)
	q.hurt.connect(_on_hurt)
	q.died.connect(_on_died)
	members[g].append(q)
	return q

# ---------------------------------------------------------------- cofres, drogas e armas
func _build_loot() -> void:
	var kinds := [["safe", "COFRE", Color(0.22, 0.23, 0.25), Vector3(0.9, 1.1, 0.8)], ["drugs", "DROGAS", Color(0.45, 0.32, 0.18), Vector3(1.0, 0.6, 0.7)], ["guns", "ARMAS", Color(0.28, 0.33, 0.2), Vector3(1.4, 0.55, 0.6)]]
	for g in T:
		var c: Vector3 = T[g].c
		for i in kinds.size():
			var kd: Array = kinds[i]
			var pos: Vector3 = _free_spot(c, T[g].r * 0.15, T[g].r * 0.45, 1.5)
			var n := StaticBody3D.new()
			main.add_child(n)
			n.global_position = pos
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = kd[3]
			mi.mesh = bm
			mi.material_override = M.plain(kd[2], 0.6, 0.3 if kd[0] == "safe" else 0.0)
			mi.position.y = kd[3].y * 0.5
			n.add_child(mi)
			var cs := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = kd[3]
			cs.shape = sh
			cs.position.y = kd[3].y * 0.5
			n.add_child(cs)
			if kd[0] == "safe":
				var dial := MeshInstance3D.new()
				var cy := CylinderMesh.new()
				cy.top_radius = 0.12
				cy.bottom_radius = 0.12
				cy.height = 0.05
				dial.mesh = cy
				dial.material_override = M.plain(Color(0.75, 0.75, 0.78), 0.3, 0.8)
				dial.rotation.x = PI * 0.5
				dial.position = Vector3(0, 0.6, kd[3].z * 0.5 + 0.02)
				n.add_child(dial)
			var lb := Label3D.new()
			lb.text = kd[1]
			lb.font_size = 48
			lb.pixel_size = 0.005
			lb.modulate = T[g].col
			lb.outline_size = 8
			lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lb.position.y = kd[3].y + 0.45
			lb.visibility_range_end = 30.0
			n.add_child(lb)
			loots.append({"gang": g, "kind": kd[0], "pos": pos, "node": n, "cd": 0.0})

func loot_near(pp: Vector3):
	for l in loots:
		if l.cd <= 0.0 and Vector2(l.pos.x - pp.x, l.pos.z - pp.z).length() < 1.9:
			return l
	return null

## pega o que estava guardado: dinheiro, drogas (vendidas na hora) ou armas/munição
func take_loot(l: Dictionary) -> void:
	l.cd = 600.0
	l.node.visible = false
	var c = main.combat
	match l.kind:
		"safe":
			var v := rng.randi_range(900, 2200)
			main.money += v
			main._msg("Cofre arrombado: +$%d" % v)
		"drugs":
			var v2 := rng.randi_range(400, 900)
			main.money += v2
			main._msg("Drogas vendidas: +$%d" % v2)
		"guns":
			for w in ["smg", "shotgun", "pistol"]:
				c.owned[w] = true
				c.add_ammo(w, 60 if w != "shotgun" else 16)
			main._msg("Caixa de armas: submetralhadora, escopeta e munição")
	main.audio.play("cash", null, 0.0)
	# roubar com a gangue por perto = guerra
	var g: String = l.gang
	if _near_count(g, main.player.global_position, 70.0) > 0:
		_hostile(g, maxi(skulls if hunter == g else 0, 2))

# ---------------------------------------------------------------- comportamento
func tick(dt: float) -> void:
	for l in loots:
		if l.cd > 0.0:
			l.cd -= dt
			if l.cd <= 0.0 and is_instance_valid(l.node):
				l.node.visible = true
	if main.combat.dead or main.interior != "":
		return
	var pp: Vector3 = main.player.global_position
	for g in members:
		members[g] = members[g].filter(func(q): return is_instance_valid(q))
	if skulls == 0:
		_warn_tick(dt, pp)
	else:
		_hunt_tick(dt, pp)
	_hunters_tick(dt, pp)

func _near_count(g: String, pp: Vector3, r: float) -> int:
	var n := 0
	for q in members[g]:
		if is_instance_valid(q) and not q.down and q.global_position.distance_to(pp) < r:
			n += 1
	return n

## entrou no território: "sai daqui!" — se não sair em alguns segundos, vira alvo (1 caveira)
func _warn_tick(dt: float, pp: Vector3) -> void:
	var inside := ""
	for g in T:
		var d: float = Vector2(pp.x - T[g].c.x, pp.z - T[g].c.z).length()
		if (d < T[g].r * 0.85 or _near_count(g, pp, 12.0) > 0) and _near_count(g, pp, 60.0) > 0:
			inside = g
	if inside == "":
		if warn_t > 0.0:
			warn_t = maxf(0.0, warn_t - dt * 2.0)
		warn_g = ""
		return
	if warn_g != inside:
		warn_g = inside
		warn_t = 0.0
	var prev := warn_t
	warn_t += dt
	# os mais próximos encaram o jogador
	for q in members[inside]:
		if is_instance_valid(q) and not q.down and q.global_position.distance_to(pp) < 25.0:
			var to: Vector3 = pp - q.global_position
			q.body.rotation.y = lerp_angle(q.body.rotation.y, atan2(to.x, to.z), minf(1.0, dt * 5.0))
	if prev == 0.0 or (prev < 4.0 and warn_t >= 4.0):
		main._msg("%s: \"Sai da nossa área, mano! Vaza!\"" % T[inside].name if prev == 0.0 else "%s: \"Último aviso!\"" % T[inside].name)
	if warn_t > 8.0:
		_hostile(inside, 1)

func _hostile(g: String, lvl: int) -> void:
	var changed := hunter != g or lvl > skulls
	if hunter != g:
		skulls = 0
	hunter = g
	skulls = clampi(maxi(skulls, lvl), 0, 4)
	_lost_t = 0.0
	if changed:
		main._msg("%s está atrás de você! (%d caveira%s)" % [T[g].name, skulls, "s" if skulls > 1 else ""])
	_arm_all()

## armas do bando conforme o nível
func _weapon_for(i: int) -> String:
	match skulls:
		1: return "pistol"
		2: return "smg" if i % 2 == 0 else "pistol"
		3: return "smg" if i % 3 != 2 else "pistol"
		_: return "shotgun" if i % 2 == 0 else "smg"

func _arm_all() -> void:
	var i := 0
	for q in members[hunter]:
		if is_instance_valid(q) and not q.down:
			q.target = main.player
			q.patrol = []
			var w := _weapon_for(i)
			if q.weapon != w:
				q.set_weapon(w)
			q.accuracy = 0.28 + skulls * 0.05
			i += 1

func _on_hurt(q) -> void:
	if q.gang == "":
		return
	if skulls == 0 or hunter != q.gang:
		_hostile(q.gang, 2)          # atacar a gangue = guerra na hora

func _on_died(q) -> void:
	main.combat.drop_cash(q.global_position)
	if hunter == q.gang and skulls < 4 and rng.randf() < 0.3:
		_hostile(q.gang, skulls + 1)

func _hunt_tick(dt: float, pp: Vector3) -> void:
	var g := hunter
	# reforços saindo do território (a pé; de carro a partir de 3 caveiras; motos com 4)
	_reinf_t -= dt
	var want: int = [0, 4, 6, 7, 8][skulls]
	if _reinf_t <= 0.0 and _near_count(g, pp, 1e9) < want:
		_reinf_t = 10.0
		var c: Vector3 = T[g].c
		var a := atan2(pp.z - c.z, pp.x - c.x)
		var sp: Vector3 = c + Vector3(cos(a), 0, sin(a)) * T[g].r * 0.8 + Vector3(0, 0.3, 0)
		for k in 2:
			_spawn_member(g, sp + Vector3(k * 1.2, 0, 0), _weapon_for(k), false)
	_car_t -= dt
	if skulls >= 3 and _car_t <= 0.0 and hunters.size() < (1 if skulls == 3 else 3):
		_car_t = 14.0
		_spawn_hunter(g, "moto" if skulls >= 4 and rng.randf() < 0.5 else "car", pp)
	# despistou: longe do território e ninguém da gangue perto por um tempo → caveiras caem
	var close := _near_count(g, pp, 45.0) > 0
	for h in hunters:
		if is_instance_valid(h.car) and h.car.global_position.distance_to(pp) < 50.0:
			close = true
	var far: bool = Vector2(pp.x - T[g].c.x, pp.z - T[g].c.z).length() > T[g].r + 110.0
	if close or not far:
		_lost_t = 0.0
	else:
		_lost_t += dt
		if _lost_t > 22.0:
			_lost_t = 0.0
			skulls -= 1
			if skulls <= 0:
				_calm()
			else:
				_arm_all()

## a gangue desiste: os que estão longe voltam para casa e ficam parados
func _calm() -> void:
	main._msg("%s desistiu de você" % T[hunter].name)
	for q in members[hunter]:
		if is_instance_valid(q) and not q.down:
			q.target = null
			if q.global_position.distance_to(T[hunter].c) > T[hunter].r * 1.5:
				q.queue_free()
	for h in hunters:
		if is_instance_valid(h.car) and h.car != main.player.vehicle:
			main.cars.erase(h.car)
			h.car.queue_free()
	hunters.clear()
	hunter = ""
	skulls = 0

## carro/moto da gangue que vai até o jogador e desce o bando
func _spawn_hunter(g: String, kind: String, pp: Vector3) -> void:
	var c: Vector3 = T[g].c
	var a := atan2(pp.z - c.z, pp.x - c.x)
	var sp: Vector3 = c + Vector3(cos(a), 0, sin(a)) * T[g].r + Vector3(0, 0.7, 0)
	var car = main._spawn_car(sp, a, T[g].col.darkened(0.05), false, "moto" if kind == "moto" else ["sedan", "suv", "sport"][rng.randi() % 3])
	car.set_meta("gang", g)
	car.ai_target = main.player
	car.max_engine *= 1.2
	main.traffic_sys._driver({"car": car})
	hunters.append({"car": car, "crew": 1 if kind == "moto" else 3, "gang": g})

func _hunters_tick(dt: float, pp: Vector3) -> void:
	for h in hunters.duplicate():
		var car = h.car
		if not is_instance_valid(car) or car.dead:
			hunters.erase(h)
			continue
		car.ai_target = main.player.vehicle if main.player.vehicle else main.player
		var d: float = car.global_position.distance_to(pp)
		if d < 16.0 and car.linear_velocity.length() < 6.0:
			# desce o bando
			if car.has_meta("drv_node"):
				var dn = car.get_meta("drv_node")
				if is_instance_valid(dn):
					dn.queue_free()
				car.remove_meta("drv_node")
			car.ai_target = null
			car.throttle = 0.0
			car.brake_in = 1.0
			if car.has_method("set_door"):
				car.set_door(1.0)
			for k in h.crew:
				var side := 1.0 if k % 2 == 0 else -1.0
				var pos: Vector3 = car.global_position + car.global_transform.basis.x * (car.body_size.x * 0.5 + 0.7) * side - car.global_transform.basis.z * (k / 2) * 1.5 + Vector3(0, 0.2, 0)
				var q = _spawn_member(h.gang, pos, _weapon_for(k), false)
				q.play_anim("exit", 0.55, func(): pass)
			hunters.erase(h)

## pontos do minimapa: território (círculo) e esconderijos
func zones() -> Array:
	var out := []
	for g in T:
		out.append({"pos": T[g].c, "r": T[g].r, "col": Color(T[g].col.r, T[g].col.g, T[g].col.b, 0.22)})
	return out

func blips() -> Array:
	var out := []
	for l in loots:
		if l.cd <= 0.0:
			out.append({"pos": l.pos, "col": T[l.gang].col, "icon": "loot"})
	return out

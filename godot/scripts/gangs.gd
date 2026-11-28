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
	var hq: Dictionary = city.gang_hq
	T = {
		"g": {"name": "Gangue Verde", "c": hq["g"].c if hq.has("g") else Vector3(-90.0, 0, -282.0), "r": 55.0, "col": Color(0.15, 0.85, 0.3)},
		"p": {"name": "Gangue Rosa", "c": hq["p"].c if hq.has("p") else Vector3(city._center(5), 0, city._center(6)), "r": 52.0, "col": Color(1.0, 0.35, 0.72)},
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
## repovoa (início e depois de morrer/ser preso): guardas dentro do bunker, no pátio, no portão
## e no telhado; dois carros da gangue no pátio
func populate() -> void:
	if not _phys_ok:
		_pending_pop = true
		return
	_pending_pop = false
	clear()
	for g in T:
		var hq: Dictionary = main.city.gang_hq.get(g, {})
		if hq.is_empty():
			continue
		for p in _posts(g):
			_spawn_member(g, p + Vector3(0, 0.3, 0), "pistol", true)
		for cs in hq.cars:
			var pc = main._spawn_car(cs[0], cs[1], T[g].col.darkened(0.1), false, ["sedan", "suv", "pickup"][rng.randi() % 3])
			pc.parked = true
			pc.set_meta("gang", g)
	skulls = 0
	hunter = ""
	wave_n = 0

## postos dos guardas: 3 dentro do bunker, 5 no pátio/portão, 1 no telhado
func _posts(g: String) -> Array:
	var hq: Dictionary = main.city.gang_hq[g]
	var out: Array = []
	out.append_array(hq.inside.slice(0, 3))
	out.append_array(hq.yard.slice(0, 5))
	out.append(hq.roof)
	return out

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
	wave_n = 0

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
	q.shot_player.connect(func(_d, _f): if main.incidents: main.incidents.on_gang_shot(q))
	q.hurt.connect(_on_hurt)
	q.died.connect(_on_died)
	members[g].append(q)
	return q

# ---------------------------------------------------------------- cofre, drogas, armas e senha
## O cofre fica no bunker (sala dos fundos) e nunca some: abre com a senha (bilhete escondido em
## algum canto da área) ou com explosivo (granada plantada, granada/foguete perto). O dinheiro
## volta em 10 min, com a porta fechada e senha nova escondida em outro lugar.
var safes := {}      # g -> {node, door, cash_node, open, cash, cd, charge, code, known, note}
func _build_loot() -> void:
	for g in T:
		var hq: Dictionary = main.city.gang_hq.get(g, {})
		if hq.is_empty():
			continue
		var fwd: Vector3 = hq.fwd
		var yaw: float = hq.yaw
		# --- cofre (fixo)
		var sn := StaticBody3D.new()
		main.add_child(sn)
		sn.global_position = hq.safe
		sn.rotation.y = yaw
		var steel := M.plain(Color(0.2, 0.21, 0.23), 0.35, 0.8)
		_mesh(sn, Vector3(1.6, 2.0, 1.2), Vector3(0, 1.0, 0), steel)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(1.6, 2.0, 1.2)
		cs.shape = sh
		cs.position = Vector3(0, 1.0, 0)
		sn.add_child(cs)
		_mesh(sn, Vector3(1.3, 1.7, 0.05), Vector3(0, 1.0, 0.58), M.plain(Color(0.05, 0.05, 0.05), 0.9))
		var cash := Node3D.new()
		sn.add_child(cash)
		for k in 6:
			_mesh(cash, Vector3(0.34, 0.16, 0.5), Vector3(-0.35 + (k % 3) * 0.35, 0.5 + float(k / 3) * 0.55, 0.25), M.plain(Color(0.25, 0.55, 0.25), 0.8))
		var door := Node3D.new()        # dobradiça no canto esquerdo da frente
		sn.add_child(door)
		door.position = Vector3(-0.8, 0, 0.62)
		_mesh(door, Vector3(1.6, 2.0, 0.12), Vector3(0.8, 1.0, 0), steel)
		var dial := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = 0.18
		cy.bottom_radius = 0.18
		cy.height = 0.06
		dial.mesh = cy
		dial.material_override = M.plain(Color(0.8, 0.8, 0.82), 0.3, 0.9)
		dial.rotation.x = PI * 0.5
		dial.position = Vector3(0.8, 1.1, 0.09)
		door.add_child(dial)
		_mesh(door, Vector3(0.36, 0.26, 0.04), Vector3(1.25, 1.55, 0.08), M.emissive(Color(0.2, 0.9, 0.35), 0.8))
		_mesh(door, Vector3(0.08, 0.5, 0.08), Vector3(1.3, 1.0, 0.12), M.plain(Color(0.8, 0.8, 0.82), 0.3, 0.9))
		var lb := _label(sn, "COFRE", T[g].col, 2.45)
		var st := {"node": sn, "door": door, "cash_node": cash, "label": lb, "open": false, "open_k": 0.0, "cash": 0, "cd": 0.0, "charge": -1.0, "code": "", "known": false, "note": null}
		safes[g] = st
		_refill(g)
		loots.append({"gang": g, "kind": "safe", "pos": hq.safe + fwd * 1.25, "node": sn, "cd": 0.0})
		# --- drogas (na mesa) e armas (caixas) dentro do bunker
		var dn := Node3D.new()
		main.add_child(dn)
		dn.global_position = hq.drugs
		dn.rotation.y = yaw
		for k in 8:
			_mesh(dn, Vector3(0.3, 0.12, 0.2), Vector3(-0.9 + (k % 4) * 0.6, 0.06 + float(k / 4) * 0.12, -0.2 + float(k % 2) * 0.35), M.plain(Color(0.93, 0.92, 0.88) if k % 3 else Color(0.55, 0.4, 0.22), 0.8))
		_label(dn, "DROGAS", T[g].col, 0.6)
		loots.append({"gang": g, "kind": "drugs", "pos": hq.drugs, "node": dn, "cd": 0.0})
		var gn := StaticBody3D.new()
		main.add_child(gn)
		gn.global_position = hq.guns
		gn.rotation.y = yaw
		for k in 2:
			_mesh(gn, Vector3(1.4, 0.55, 0.6), Vector3(0, 0.28 + k * 0.56, 0), M.plain(Color(0.28, 0.33, 0.2), 0.7))
		var gs := CollisionShape3D.new()
		var gsh := BoxShape3D.new()
		gsh.size = Vector3(1.4, 1.1, 0.6)
		gs.shape = gsh
		gs.position.y = 0.55
		gn.add_child(gs)
		_label(gn, "ARMAS", T[g].col, 1.55)
		loots.append({"gang": g, "kind": "guns", "pos": hq.guns, "node": gn, "cd": 0.0})
		# --- bilhete com a senha, escondido num dos cantos da área
		var nt := Node3D.new()
		main.add_child(nt)
		_mesh(nt, Vector3(0.26, 0.02, 0.18), Vector3(0, 0.03, 0), M.emissive(Color(0.95, 0.93, 0.8), 0.35))
		_mesh(nt, Vector3(0.18, 0.025, 0.02), Vector3(0, 0.04, -0.03), M.plain(Color(0.1, 0.1, 0.4), 0.6))
		var nl := {"gang": g, "kind": "note", "pos": Vector3.ZERO, "node": nt, "cd": 0.0}
		st.note = nl
		loots.append(nl)
		_place_note(g)

func _mesh(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _label(parent: Node3D, txt: String, col: Color, y: float) -> Label3D:
	var lb := Label3D.new()
	lb.text = txt
	lb.font_size = 48
	lb.pixel_size = 0.005
	lb.modulate = col
	lb.outline_size = 8
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.position.y = y
	lb.visibility_range_end = 22.0
	parent.add_child(lb)
	return lb

## cofre fecha, enche de novo e ganha senha nova, escondida em outro canto
func _refill(g: String) -> void:
	var st: Dictionary = safes[g]
	st.open = false
	st.cash = rng.randi_range(2500, 6000)
	st.code = "%04d" % rng.randi_range(0, 9999)
	st.known = false
	st.charge = -1.0
	if st.note != null:
		_place_note(g)

func _place_note(g: String) -> void:
	var st: Dictionary = safes[g]
	var spots: Array = main.city.gang_hq[g].notes
	var p: Vector3 = spots[rng.randi() % spots.size()]
	st.note.pos = p
	st.note.cd = 0.0
	st.note.node.global_position = p
	st.note.node.rotation.y = rng.randf() * TAU
	st.note.node.visible = true

func loot_near(pp: Vector3):
	for l in loots:
		if l.cd <= 0.0 and Vector2(l.pos.x - pp.x, l.pos.z - pp.z).length() < (1.9 if l.kind != "note" else 1.5) and absf(l.pos.y - pp.y) < 1.7:
			if l.kind == "note" and safes[l.gang].known:
				continue
			return l
	return null

## texto do botão e da dica para o que está perto
func loot_label(l: Dictionary) -> String:
	if l.kind != "safe":
		return "PEGAR"
	var st: Dictionary = safes[l.gang]
	if st.open:
		return "PEGAR" if st.cash > 0 else ""
	if st.charge >= 0.0:
		return ""
	if st.known:
		return "SENHA"
	if _explosives() > 0:
		return "EXPLODIR"
	return ""

func loot_hint(l: Dictionary) -> String:
	var g: String = l.gang
	match l.kind:
		"drugs": return "Drogas da gangue · toque em PEGAR"
		"guns": return "Armas da gangue · toque em PEGAR"
		"note": return "Um bilhete escondido... · toque em PEGAR"
	var st: Dictionary = safes[g]
	if st.open:
		return ("Cofre aberto: $%d · toque em PEGAR" % st.cash) if st.cash > 0 else "Cofre vazio · enche de novo em %d min" % ceili(st.cd / 60.0)
	if st.charge >= 0.0:
		return "Explosivo armado! Afaste-se!"
	if st.known:
		return "Cofre trancado · você sabe a senha (%s) · toque em SENHA" % st.code
	if _explosives() > 0:
		return "Cofre trancado · ache a senha escondida na área ou EXPLODA (gasta 1 granada)"
	return "Cofre trancado · ache a senha escondida na área ou traga explosivo (granada/bazuca)"

func _explosives() -> int:
	var c = main.combat
	return c.ammo.get("grenade", 0) if c.owned.get("grenade", false) else 0

## pega o que estava guardado: dinheiro, drogas (vendidas na hora), armas/munição ou a senha
func take_loot(l: Dictionary) -> void:
	var g: String = l.gang
	var c = main.combat
	match l.kind:
		"safe":
			var st: Dictionary = safes[g]
			if st.open:
				if st.cash <= 0:
					return
				main.money += st.cash
				main._msg("Cofre da %s: +$%d (o cofre fica; enche de novo em 10 min)" % [T[g].name, st.cash])
				st.cash = 0
				st.cd = 600.0
				main.audio.play("cash", null, 0.0)
			elif st.known:
				_open_safe(g, "Senha %s digitada: o cofre abriu!" % st.code)
				main.audio.play("click", null, 0.0)
			elif _explosives() > 0 and st.charge < 0.0:
				c.ammo["grenade"] -= 1
				st.charge = 4.0
				main._msg("Explosivo plantado no cofre! Afaste-se (4 s)")
				main.audio.play("click", null, 0.0)
			else:
				main._msg("Cofre trancado: ache a senha escondida na área ou use explosivo")
				return
			_hostile(g, maxi(skulls if hunter == g else 0, 2))
			return
		"note":
			safes[g].known = true
			l.node.visible = false
			l.cd = 1e9
			main._msg("Bilhete achado! Senha do cofre da %s: %s" % [T[g].name, safes[g].code], true)
			main.audio.play("click", null, 0.0)
			return
		"drugs":
			l.cd = 600.0
			l.node.visible = false
			var v2 := rng.randi_range(400, 900)
			main.money += v2
			main._msg("Drogas vendidas: +$%d" % v2)
		"guns":
			l.cd = 600.0
			l.node.visible = false
			for w in ["smg", "shotgun", "pistol"]:
				c.owned[w] = true
				c.add_ammo(w, 60 if w != "shotgun" else 16)
			c.owned["grenade"] = true
			c.add_ammo("grenade", 2)
			main._msg("Caixa de armas: submetralhadora, escopeta, granadas e munição")
	main.audio.play("cash", null, 0.0)
	# roubar a gangue = guerra (eles defendem o esconderijo em ondas)
	_hostile(g, maxi(skulls if hunter == g else 0, 2))

func _open_safe(g: String, msg: String) -> void:
	var st: Dictionary = safes[g]
	st.open = true
	st.charge = -1.0
	st.known = true
	if st.note != null:
		st.note.node.visible = false
		st.note.cd = 1e9
	main._msg(msg)

## explosão (granada, foguete, carga plantada) perto do cofre: a porta estoura
func on_explosion(pos: Vector3) -> void:
	for g in safes:
		var st: Dictionary = safes[g]
		if not st.open and is_instance_valid(st.node) and pos.distance_to(st.node.global_position + Vector3(0, 1.0, 0)) < 4.5:
			_open_safe(g, "A explosão arrombou o cofre da %s!" % T[g].name)
			_hostile(g, maxi(skulls if hunter == g else 0, 3))

func _safes_tick(dt: float) -> void:
	for g in safes:
		var st: Dictionary = safes[g]
		if not is_instance_valid(st.node):
			continue
		if st.charge >= 0.0:
			st.charge -= dt
			if int(st.charge * 2.0) != int((st.charge + dt) * 2.0):
				main.audio.play("click", st.node.global_position, -4.0)
			if st.charge < 0.0:
				var fp: Vector3 = st.node.global_position + st.node.global_transform.basis.z * 0.9 + Vector3(0, 1.0, 0)
				main.explode_at(fp, 3.5, 45.0)
				_open_safe(g, "BUM! O cofre da %s foi arrombado!" % T[g].name)
		if st.cash <= 0 and st.cd > 0.0:
			st.cd -= dt
			if st.cd <= 0.0 and main.player.global_position.distance_to(st.node.global_position) > 40.0:
				_refill(g)
			elif st.cd <= 0.0:
				st.cd = 5.0
		st.open_k = move_toward(st.open_k, 1.0 if st.open else 0.0, dt * 1.2)
		st.door.rotation.y = -st.open_k * 1.9
		st.cash_node.visible = st.cash > 0 and st.open_k > 0.05

# ---------------------------------------------------------------- comportamento
func tick(dt: float) -> void:
	for l in loots:
		if l.cd > 0.0 and l.kind in ["drugs", "guns"]:
			l.cd -= dt
			if l.cd <= 0.0 and is_instance_valid(l.node):
				l.node.visible = true
	_safes_tick(dt)
	for fg in friendly_t.keys():
		friendly_t[fg] = maxf(0.0, friendly_t[fg] - dt)
	_restock_t -= dt
	if _restock_t <= 0.0:
		_restock_t = 4.0
		_restock()
		_arrivals()
	if main.combat.dead or main.interior != "":
		return
	var pp: Vector3 = main.player.global_position
	for g in members:
		members[g] = members[g].filter(func(q): return is_instance_valid(q))
	if skulls == 0:
		_warn_tick(dt, pp)
	else:
		_hunt_tick(dt, pp)
		_wave_tick(dt, pp)
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
	_see_t -= dt
	_seen_t -= dt
	var check := _see_t <= 0.0
	if check:
		_see_t = 0.3
	for g in T:
		var d: float = Vector2(pp.x - T[g].c.x, pp.z - T[g].c.z).length()
		if d > T[g].r + 10.0 or friendly_t.get(g, 0.0) > 0.0 or main.missions.near_gang_job(g, pp):
			continue
		# só é "descoberto" se algum membro realmente te enxergar (perto e sem parede no meio);
		# depois de visto, continua marcado por 3 s mesmo atrás de uma parede
		if check and _seen_by(g, pp):
			_seen_t = 3.0
			_seen_g = g
		if _seen_t > 0.0 and _seen_g == g:
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
	if warn_t > 8.0:
		_hostile(inside, 1)

var _see_t := 0.0
var _seen_t := 0.0
var _seen_by_cached := false
var _seen_g := ""
var friendly_t := {}           # gangue -> segundos de trégua (depois de trabalhar para ela)
## algum membro da gangue enxerga o jogador? (até 30 m, raio sem parede no meio)
func _seen_by(g: String, pp: Vector3) -> bool:
	_seen_by_cached = false
	var ss = main.get_world_3d().direct_space_state
	for q in members[g]:
		if not is_instance_valid(q) or q.down:
			continue
		var d: float = q.global_position.distance_to(pp)
		if d > 30.0:
			continue
		var qr := PhysicsRayQueryParameters3D.create(q.global_position + Vector3(0, 1.6, 0), pp + Vector3(0, 1.3, 0), 1)
		qr.exclude = [q.get_rid(), main.player.get_rid()]
		if main.player.vehicle:
			qr.exclude.append(main.player.vehicle.get_rid())
		if ss.intersect_ray(qr).is_empty():
			_seen_by_cached = true
			return true
	return false

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
		var sp: Vector3 = _street_spot(g) + Vector3(0, 0.3, 0)      # chegam pela rua
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
	for g in T:
		out.append({"pos": T[g].c, "col": T[g].col, "icon": "loot"})
	return out


# ---------------------------------------------------------------- defesa do esconderijo em ondas
## Em guerra e com o jogador dentro do território: quando o bando de defesa quase acaba, chega a
## próxima onda pelo portão (cada uma maior; a partir da 3ª também de carro). Só para quando
## você sai da área e a gangue desiste.
var wave_n := 0
var _wave_t := 0.0
func _wave_tick(dt: float, pp: Vector3) -> void:
	var g := hunter
	if g == "" or not main.city.gang_hq.has(g):
		return
	var c: Vector3 = T[g].c
	if Vector2(pp.x - c.x, pp.z - c.z).length() > T[g].r + 15.0:
		_wave_t = minf(_wave_t, 6.0)
		return
	var defenders := 0
	for q in members[g]:
		if is_instance_valid(q) and not q.down and q.global_position.distance_to(c) < T[g].r + 40.0:
			defenders += 1
	if defenders > 1:
		_wave_t = maxf(_wave_t, 5.0)
		return
	_wave_t -= dt
	if _wave_t > 0.0:
		return
	wave_n += 1
	_wave_t = 9.0
	if wave_n >= 2 and skulls < 4:
		skulls = mini(4, skulls + 1)
	var n := mini(3 + wave_n, 8)
	var hq: Dictionary = main.city.gang_hq[g]
	var gate: Vector3 = hq.gate_out
	var side: Vector3 = hq.fwd.cross(Vector3.UP)
	for k in n:
		var sp: Vector3 = gate + side * ((k % 4) - 1.5) * 1.6 + hq.fwd * float(k / 4) * 1.6 + Vector3(0, 0.3, 0)
		var q = _spawn_member(g, sp, _weapon_for(k), false)
		q.accuracy = 0.28 + skulls * 0.05
	if wave_n >= 3 and hunters.size() < 2:
		_spawn_hunter(g, "car", pp)
	_arm_all()
	main._msg("%s: onda %d de reforços chegando para defender o esconderijo!" % [T[g].name, wave_n])

## ponto na rua em frente ao esconderijo (de onde chegam os reforços), longe do jogador e
## de preferência fora da tela
func _street_spot(g: String) -> Vector3:
	var hq: Dictionary = main.city.gang_hq[g]
	var side: Vector3 = hq.fwd.cross(Vector3.UP)
	var cam: Camera3D = main.cam
	var best: Vector3 = hq.gate_out + hq.fwd * 14.0
	var bs := -1e9
	for k in 8:
		var cand: Vector3 = hq.gate_out + hq.fwd * rng.randf_range(10.0, 22.0) + side * rng.randf_range(-40.0, 40.0)
		var sc: float = cand.distance_to(main.player.global_position)
		if cam and (cand - cam.global_position).normalized().dot(-cam.global_transform.basis.z) > 0.5:
			sc -= 60.0          # na frente da câmera: evita surgir à vista
		if sc > bs:
			bs = sc
			best = cand
	return Vector3(best.x, 0.15, best.z)

## guarda que chegou ao posto: fica rondando ali
func _arrivals() -> void:
	for g in members:
		for q in members[g]:
			if is_instance_valid(q) and not q.down and q.has_meta("post") and q.target == null:
				var post: Vector3 = q.get_meta("post")
				# longe de tudo (ninguém vê) o NPC não processa: completa o caminho até o posto
				if q.global_position.distance_to(main.player.global_position) > 75.0:
					q.global_position = post + Vector3(0, 0.3, 0)
				if Vector2(q.global_position.x - post.x, q.global_position.z - post.z).length() < 1.6:
					q.remove_meta("post")
					q.patrol = [post + Vector3(1.2, 0, 0), post + Vector3(0, 0, 1.2), post + Vector3(-1.2, 0, 0), post + Vector3(0, 0, -1.2)] if rng.randf() < 0.4 else []

## em paz e com o jogador longe: a gangue repõe os guardas mortos (um a cada 4 s)
var _restock_t := 6.0
func _restock() -> void:
	if skulls > 0:
		return
	var pp: Vector3 = main.player.global_position
	for g in T:
		if not main.city.gang_hq.has(g) or pp.distance_to(T[g].c) < 110.0:
			continue
		var posts := _posts(g)
		var alive_n := 0
		for q in members[g]:
			if is_instance_valid(q) and not q.down:
				alive_n += 1
		if alive_n >= posts.size():
			continue
		# posto vago: o mais longe de qualquer membro vivo
		var best: Vector3 = posts[0]
		var bd := -1.0
		for p in posts:
			var dmin := 1e9
			for q in members[g]:
				if is_instance_valid(q) and not q.down:
					dmin = minf(dmin, q.global_position.distance_to(p))
			if dmin > bd:
				bd = dmin
				best = p
		# o guarda novo chega a pé pela rua, entra pelo portão e vai até o posto
		var hq: Dictionary = main.city.gang_hq[g]
		var q = _spawn_member(g, _street_spot(g) + Vector3(0, 0.3, 0), "pistol", true)
		q.patrol = [hq.gate_out, hq.gate_out - hq.fwd * 13.0, best]
		q.set_meta("post", best)
		wave_n = 0

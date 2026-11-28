extends Node
## Trânsito com regras: grade de cruzamentos, mão dupla (faixa a 2,6 m do eixo), semáforos sincronizados
## (eixo N-S / L-O), linha de parada antes da faixa de pedestres, distância do carro da frente, freia para
## pedestres e para o jogador, curvas nos cruzamentos, recuo quando trava, motoristas visíveis.
## Também navega a polícia pelas ruas (rota por cruzamentos até perto do jogador).

const Humanoid := preload("res://scripts/humanoid.gd")

const CYCLE := 24.0          # 0-10 N-S verde, 10-12 amarelo, 12-22 L-O verde, 22-24 amarelo
static var clock := 0.0

var main: Node3D
var city: Node3D
var N := 5
var agents: Array = []       # {car, n: Vector2i, d: Vector2i, st, wps, vlim, stuck, back, drv, bus, stop_cd, stop_t}
var lights_mm := {}          # "ns_r" ... -> MultiMeshInstance3D (materiais trocam de energia)
var _lmat := {}
var rng := RandomNumberGenerator.new()

## true se o eixo ("ns" = carros andando em z, "ew" = andando em x) está liberado
static func green(axis: String) -> bool:
	var t := fmod(clock, CYCLE)
	return t < 10.0 if axis == "ns" else (t >= 12.0 and t < 22.0)

static func yellow(axis: String) -> bool:
	var t := fmod(clock, CYCLE)
	return (t >= 10.0 and t < 12.0) if axis == "ns" else t >= 22.0

func R(k: int) -> float:
	return (k - N * 0.5) * city.CELL

func node_pos(n: Vector2i) -> Vector3:
	return Vector3(R(n.x), 0, R(n.y))

func _off(d: Vector2i) -> Vector3:
	return Vector3(-d.y * 2.6, 0, d.x * 2.6)     # mão direita (Brasil): faixa à direita do sentido

func _d3(d: Vector2i) -> Vector3:
	return Vector3(d.x, 0, d.y)

func _valid(n: Vector2i) -> bool:
	return n.x >= 0 and n.y >= 0 and n.x <= N and n.y <= N

func setup(m: Node3D) -> void:
	main = m
	city = m.city
	N = city.N
	rng.seed = 555
	_build_lights()

# ---------------------------------------------------------------- semáforos (visual)
func _build_lights() -> void:
	var M := preload("res://scripts/mats.gd")
	var poles := []
	var boxes := []
	var lamp := {"ns_r": [], "ns_y": [], "ns_g": [], "ew_r": [], "ew_y": [], "ew_g": []}
	for i in N + 1:
		for j in N + 1:
			var c := node_pos(Vector2i(i, j))
			for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var n2: Vector2i = Vector2i(i, j) - d
				if not _valid(n2):
					continue
				# poste na esquina à direita de quem chega, lâmpadas viradas para o carro
				var p: Vector3 = c - _d3(d) * 8.4 + _off(d) * (8.0 / 2.6)
				var yaw: float = atan2(-d.x, -d.y)
				poles.append(Transform3D(Basis(), p + Vector3(0, 2.0, 0)))
				var bx := Basis(Vector3.UP, yaw)
				boxes.append(Transform3D(bx, p + Vector3(0, 4.3, 0)))
				var ax: String = "ns" if d.x == 0 else "ew"
				for k in 3:
					var key: String = ax + ["_r", "_y", "_g"][k]
					lamp[key].append(Transform3D(bx, p + Vector3(0, 4.68 - k * 0.38, 0) + bx * Vector3(0, 0, 0.16)))
	var pole := CylinderMesh.new()
	pole.top_radius = 0.07
	pole.bottom_radius = 0.09
	pole.height = 4.0
	pole.radial_segments = 6
	_mm(pole, M.plain(Color(0.2, 0.21, 0.22), 0.5, 0.6), poles)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.36, 1.2, 0.26)
	_mm(bm, M.plain(Color(0.08, 0.08, 0.08), 0.6), boxes)
	var lm := BoxMesh.new()          # lâmpada do semáforo: caixa (12 triângulos) em vez de esfera
	lm.size = Vector3(0.22, 0.22, 0.06)
	var cols := {"_r": Color(1, 0.08, 0.05), "_y": Color(1, 0.7, 0.05), "_g": Color(0.1, 1, 0.3)}
	for key in lamp:
		var mat := StandardMaterial3D.new()
		var c: Color = cols[key.substr(2)]
		mat.albedo_color = c * 0.3
		mat.emission_enabled = true
		mat.emission = c
		mat.emission_energy_multiplier = 0.0
		_lmat[key] = mat
		_mm(lm, mat, lamp[key])

func _mm(mesh: Mesh, mat: Material, xf: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for k in xf.size():
		mm.set_instance_transform(k, xf[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

var _lamp_key := -1
func _update_lamps() -> void:
	var key := (1 if green("ns") else 0) + (2 if yellow("ns") else 0) + (4 if green("ew") else 0) + (8 if yellow("ew") else 0)
	if key == _lamp_key:
		return            # só muda o material quando o semáforo troca
	_lamp_key = key
	for ax in ["ns", "ew"]:
		var g := green(ax)
		var y := yellow(ax)
		_lmat[ax + "_g"].emission_energy_multiplier = 3.0 if g else 0.0
		_lmat[ax + "_y"].emission_energy_multiplier = 3.0 if y else 0.0
		_lmat[ax + "_r"].emission_energy_multiplier = 3.0 if not g and not y else 0.0

# ---------------------------------------------------------------- criação dos agentes
## coloca o carro no meio de um trecho de rua, na faixa certa
func add_agent(car, n: Vector2i, d: Vector2i, bus := false) -> void:
	var a := {"car": car, "n": n, "d": d, "st": "road", "wps": [], "vlim": 11.0 if not bus else 8.5, "stuck": 0.0, "back": 0.0, "bus": bus, "stop_cd": 0.0, "stop_t": 0.0, "nd": Vector2i.ZERO, "drv": null, "pd": d, "unstuck": 0}
	var prev: Vector3 = node_pos(n - d)
	var p: Vector3 = prev.lerp(node_pos(n), rng.randf_range(0.35, 0.6)) + _off(d) + Vector3(0, 0.7 if car.kind != "bus" else 0.9, 0)
	car.global_position = p
	car.rotation.y = atan2(d.x, d.y)
	car.ai_target = null
	car.max_engine = car.max_engine * (0.8 if car.kind != "bus" else 0.7)
	_driver(a)
	agents.append(a)

func _driver(a: Dictionary) -> void:
	var c = a.car
	var h := Humanoid.new()
	var shirts := [Color(0.7, 0.2, 0.2), Color(0.2, 0.35, 0.65), Color(0.85, 0.75, 0.3), Color(0.9, 0.9, 0.88), Color(0.2, 0.2, 0.22), Color(0.45, 0.6, 0.35)]
	var ex := {}
	if c.kind == "moto":
		ex = {"hat": 2, "hat_c": [Color(0.1, 0.1, 0.1), Color(0.8, 0.1, 0.1), Color(0.9, 0.9, 0.9)][rng.randi() % 3]}   # capacete
	var cols := [shirts[rng.randi() % shirts.size()], Color(0.12, 0.14, 0.2), [Color(0.92, 0.75, 0.6), Color(0.55, 0.36, 0.22), Color(0.78, 0.56, 0.38)][rng.randi() % 3], Color(0.08, 0.06, 0.05)]
	if c.get("police") == true:
		cols[0] = Color(0.12, 0.2, 0.42)       # policial (farda azul)
		cols[1] = Color(0.08, 0.1, 0.2)
		if c.kind != "moto":
			ex = {"hat": 1, "hat_c": Color(0.08, 0.1, 0.22)}
	a.cols = cols
	h.build(cols[0], cols[1], cols[2], cols[3], ex)
	h.sitting = true
	h.moto_pose = c.kind == "moto"
	h.scale = Vector3.ONE * 0.85
	h.position = main.seat_pos(c)
	if c.lean:
		c.lean.add_child(h)
	else:
		c.add_child(h)
	h.animate(0, 0)
	h.set_far(45.0)
	a.drv = h
	c.set_meta("drv_node", h)

## jogador vai pegar o carro: o carro para e devolve o motorista (a animação o tira do banco)
## {drv: Humanoid ou null, cols, dead}
func release(car) -> Dictionary:
	for a in agents.duplicate():
		if a.car == car:
			agents.erase(a)
			car.throttle = 0.0
			car.brake_in = 1.0
			return {"drv": a.drv, "cols": a.cols, "dead": false}
	for d in drifting.duplicate():
		if d.car == car:
			drifting.erase(d)
			return {"drv": d.drv, "cols": d.cols, "dead": true}
	return {}

func driver_of(car):
	for a in agents:
		if a.car == car:
			return a.drv
	return null

var drifting: Array = []     # carros com motorista morto, desgovernados
## tiro no motorista: carro sai de controle (moto: piloto cai e a moto tomba)
func kill_driver(car) -> void:
	for a in agents.duplicate():
		if a.car == car:
			agents.erase(a)
			if car.kind == "moto":
				eject_rider_agent(a, true)
			else:
				a.drv.slumped = true
				a.drv.animate(0, 0)
				drifting.append({"car": car, "t": 0.0, "st": rng.randf_range(-0.7, 0.7), "drv": a.drv, "cols": a.cols})
			return

## moto atingida/atropelada: piloto vira ragdoll (levanta se não morreu) e a moto tomba
func eject_rider(car, dead: bool) -> void:
	for a in agents.duplicate():
		if a.car == car:
			agents.erase(a)
			eject_rider_agent(a, dead)
			return

func eject_rider_agent(a: Dictionary, dead: bool) -> void:
	var c = a.car
	var h: Node3D = a.drv
	var pos: Vector3 = h.global_position if is_instance_valid(h) else c.global_position
	# moto da polícia: o policial cai, levanta e reage (só quando foi o jogador)
	if c.get("police") == true and not dead and main.player.global_position.distance_to(c.global_position) < 12.0:
		main.police.angry_cop(pos, c.linear_velocity + Vector3(0, 2.5, 0))
		if is_instance_valid(h):
			h.queue_free()
		c.fall_over()
		return
	var Ped := preload("res://scripts/ped.gd")
	var p = Ped.new()
	main.add_child(p)
	p.setup([pos, pos, pos, pos], 0, rng)
	p._cols = a.cols.duplicate()
	p.body.queue_free()
	p._make_body()
	p.global_position = pos
	p.died.connect(main._on_ped_died)
	main.peds.append(p)
	var vel: Vector3 = c.linear_velocity + Vector3(0, 2.5, 0)
	if dead:
		p.hit(null, vel, main.gore)
	else:
		p.knock(vel, 30.0)
	if is_instance_valid(h):
		h.queue_free()
	c.fall_over()

func is_agent(car) -> bool:
	for a in agents:
		if a.car == car:
			return true
	return false

# ---------------------------------------------------------------- direção
## grade espacial (24 m) de carros e pessoas, refeita 1× por passo: cada carro do trânsito só
## olha os vizinhos (antes percorria todos os carros e pedestres a cada decisão)
const GCELL := 24.0
var _g_cars := {}
var _g_bodies := {}
func _grid_build() -> void:
	_g_cars.clear()
	_g_bodies.clear()
	for o in main.cars:
		if is_instance_valid(o):
			var k := Vector2i(floori(o.global_position.x / GCELL), floori(o.global_position.z / GCELL))
			if not _g_cars.has(k):
				_g_cars[k] = []
			_g_cars[k].append(o)
	var bl: Array = main.peds.duplicate()
	if main.player.vehicle == null:
		bl.append(main.player)
	for p in bl:
		if is_instance_valid(p) and not p.get("down"):
			var k2 := Vector2i(floori(p.global_position.x / GCELL), floori(p.global_position.z / GCELL))
			if not _g_bodies.has(k2):
				_g_bodies[k2] = []
			_g_bodies[k2].append(p)

func _near(g: Dictionary, pos: Vector3) -> Array:
	var out := []
	var cx := floori(pos.x / GCELL)
	var cz := floori(pos.z / GCELL)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var a = g.get(Vector2i(cx + dx, cz + dz))
			if a:
				out.append_array(a)
	return out

func _physics_process(dt: float) -> void:
	clock += dt
	_grid_build()
	_update_lamps()
	for d in drifting.duplicate():
		var dc = d.car
		if not is_instance_valid(dc) or dc == main.player.vehicle:
			drifting.erase(d)
			continue
		d.t += dt
		d.st = clampf(d.st + rng.randf_range(-1.5, 1.5) * dt, -0.9, 0.9)
		dc.steer_in = d.st
		dc.throttle = 0.35 if d.t < 2.5 else 0.0
		dc.brake_in = 0.0 if d.t < 4.0 else 0.4
	# otimização: cada motorista decide a cada 2 quadros de física (metade num, metade no outro)
	_tick += 1
	var i := 0
	for a in agents.duplicate():
		i += 1
		var c = a.car
		if not is_instance_valid(c) or c.dead:
			agents.erase(a)
			continue
		if c == main.player.vehicle:
			continue
		var fast: bool = a.get("mode", "") in ["ram", "chase", "flee"]
		if (i + _tick) % 2 == 0 or fast:
			_drive(a, dt if fast else dt * 2.0)

func _drive(a: Dictionary, dt: float) -> void:
	var c = a.car
	var pos: Vector3 = c.global_position
	# reação à arma apontada: avança para atropelar / para e o motorista se rende
	var md: String = a.get("mode", "")
	if md == "ram":
		a.mode_t -= dt
		var pp: Vector3 = main.player.global_position
		if a.mode_t <= 0.0 or main.player.vehicle != null:
			a.mode = ""
		else:
			c.ai_target = null
			var loc: Vector3 = c.global_transform.affine_inverse() * pp
			c.steer_in = clampf(atan2(loc.x, loc.z) * 2.0, -1.0, 1.0)
			c.throttle = 1.0
			c.brake_in = 0.0
			return
	elif md == "stop":
		c.throttle = 0.0
		c.brake_in = 1.0
		return
	elif md == "chase" or md == "flee":
		# batida: o motorista persegue (tenta bater de volta) ou foge a toda
		a.mode_t -= dt
		var tgt: Vector3 = main.player.vehicle.global_position if main.player.vehicle else main.player.global_position
		if a.mode_t <= 0.0 or pos.distance_to(tgt) > (90.0 if md == "chase" else 140.0):
			a.mode = ""
			c.max_engine = a.get("eng0", c.max_engine)
		else:
			c.ai_target = null
			var loc: Vector3 = c.global_transform.affine_inverse() * tgt
			var ang := atan2(loc.x, loc.z)
			if md == "flee":
				ang = atan2(-loc.x, -loc.z)
			c.steer_in = clampf(ang * 1.6, -1.0, 1.0)
			c.throttle = 1.0 if absf(ang) < 2.2 or c.forward_speed() > 4.0 else -0.6
			c.brake_in = 0.0
			# buzina de vez em quando (antes tocava em todo quadro por meio segundo = zumbido)
			a.horn_t = a.get("horn_t", 0.0) - get_physics_process_delta_time()
			if md == "chase" and a.horn_t <= 0.0:
				a.horn_t = rng.randf_range(2.2, 4.0)
				main.audio.play("horn", pos, 0.0)
			return
	# vigia: carro que não sai do lugar por muito tempo
	a.wd_t = a.get("wd_t", 0.0) + dt
	if a.wd_t > 10.0:
		var moved: float = pos.distance_to(a.get("wd_p", pos + Vector3(99, 0, 0)))
		a.wd_t = 0.0
		a.wd_p = pos
		if moved < 3.0:
			a.wd_n = a.get("wd_n", 0) + 1
			if a.wd_n >= 2 and (pos.distance_to(main.player.global_position) > 55.0 or not _in_view(pos)):
				_respawn(a)
				a.wd_n = 0
				return
			# à vista: anda ignorando os outros carros e dá ré se preciso
			a.ghost = 3.0
			a.back = 1.0
		else:
			a.wd_n = 0
	var d: Vector2i = a.d
	var dir := _d3(d)
	var center := node_pos(a.n)
	var along := (center - pos).dot(dir)        # distância até o centro do cruzamento
	var vt: float = a.vlim
	var carrot: Vector3
	var axis := "ns" if d.x == 0 else "ew"
	if a.st == "road":
		# ultrapassagem: usa a faixa oposta por alguns segundos para desviar de carro parado/abandonado
		var lane_k := 1.0
		if a.get("ovt", 0.0) > 0.0:
			a.ovt -= dt
			lane_k = -1.0
		var lane_pt: Vector3 = center + _off(d) * lane_k - dir * along
		carrot = lane_pt + dir * minf(9.0, maxf(along - 4.0, 2.0))
		var big: bool = c.body_size.z > 6.0
		# semáforo: começa a frear com antecedência (distância de frenagem ~3,5 m/s²) e para na linha
		var stop_d := along - 11.0
		var red: bool = not green(axis) and stop_d > -0.5 and not (yellow(axis) and stop_d < 6.0)
		if red and along < 40.0:
			vt = minf(vt, sqrt(2.0 * 3.5 * maxf(0.0, stop_d - 0.5)))
			if stop_d < 1.0:
				vt = 0.0
		if along < 13.0:
			if a.nd == Vector2i.ZERO:
				a.nd = _choose(a)
			if not red and along < (11.5 if big else 9.5):
				_begin_turn(a)
		elif along < -2.0:
			_begin_turn(a)
		# ponto de ônibus
		if a.bus:
			a.stop_cd -= dt
			for bs in city.bus_route:
				if bs.stop and a.stop_cd <= 0.0 and Vector2(bs.p.x - pos.x, bs.p.z - pos.z).length() < 5.0:
					a.stop_t = 4.0
					a.stop_cd = 12.0
			if a.stop_t > 0.0:
				a.stop_t -= dt
				vt = 0.0
	else:
		# curva/travessia do cruzamento: segue a lista de pontos
		if a.wps.is_empty():
			a.st = "road"
			return
		carrot = a.wps[0]
		var bigv: bool = c.body_size.z > 6.0
		vt = (4.5 if bigv else 6.0) if a.d != a.pd else a.vlim
		if Vector2(carrot.x - pos.x, carrot.z - pos.z).length() < (4.5 if bigv else 3.2):
			a.wps.pop_front()
			if a.wps.is_empty():
				a.st = "road"
	# carro / pessoa à frente
	last_block = null
	a.ghost = a.get("ghost", 0.0) - dt
	var lim := _ahead_limit(c, pos, a.ghost > 0.0, a.get("ign"))
	if a.ghost > 0.0:
		lim = maxf(lim, 3.0)
	vt = minf(vt, lim)
	var blk = last_block
	if lim < 0.6 and blk != null:
		a.blk_t = a.get("blk_t", 0.0) + dt
		# carro parado/abandonado na faixa: ultrapassa pela faixa oposta
		var blk_stuck: bool = not is_agent(blk) or _agent_of(blk).get("blk_t", 0.0) > 1.5 or _agent_of(blk).get("mode", "") == "stop" or blk.get("dead") == true
		if blk == main.player.vehicle and a.blk_t > 1.5 and fmod(a.blk_t, 2.5) < dt:
			main.audio.play("horn", pos, -4.0)
		if a.st == "road" and along > 7.0 and blk_stuck and a.blk_t > 1.2 and blk.linear_velocity.length() < 0.5:
			a.blk_t = 0.0
			a.ovt = 4.0
			a.ign = blk
		# impasse entre carros do trânsito (cruzamento): avança devagar ignorando os outros
		elif a.blk_t > 6.0:
			a.blk_t = 0.0
			a.ghost = 2.5
	else:
		a.blk_t = 0.0
	if a.get("ovt", 0.0) <= 0.0 and a.ghost <= 0.0:
		a.ign = null
	_control(c, carrot, vt, a, dt)

func _choose(a: Dictionary) -> Vector2i:
	var d: Vector2i = a.d
	var opts := []
	for nd in [d, Vector2i(-d.y, d.x), Vector2i(d.y, -d.x)]:
		if _valid(a.n + nd):
			opts.append(nd)
	if a.bus:
		# ônibus: mantém o retângulo das quadras 1..3 (cruzamentos 1..4)
		var keep := []
		for nd in opts:
			var q: Vector2i = a.n + nd
			if q.x >= 1 and q.x <= 4 and q.y >= 1 and q.y <= 4 and (q.x == 1 or q.x == 4 or q.y == 1 or q.y == 4):
				keep.append(nd)
		if keep.has(d):
			return d
		if not keep.is_empty():
			return keep[0]
	if opts.is_empty():
		return -d
	if opts.has(d) and rng.randf() < 0.5:
		return d
	return opts[rng.randi() % opts.size()]

func _begin_turn(a: Dictionary) -> void:
	var d: Vector2i = a.d
	var nd: Vector2i = a.nd if a.nd != Vector2i.ZERO else _choose(a)
	var c := node_pos(a.n)
	var wps := []
	if nd == d:
		wps.append(c + _off(d) + _d3(d) * 10.0)
	elif nd == -d:
		wps.append(c + _off(d) + _d3(d) * 3.0)
		wps.append(c + _off(nd) - _d3(nd) * 2.0)
	else:
		# ônibus/caminhão: curva mais aberta (antes cortavam a esquina e batiam nos prédios)
		var big: bool = a.car.body_size.z > 6.0
		var a0 := c + _off(d) - _d3(d) * (9.0 if big else 7.0)
		var a2 := c + _off(nd) + _d3(nd) * (11.0 if big else 8.0)
		var corner := c + _off(d) + _off(nd)
		for t in [0.35, 0.7, 1.0]:
			var p := a0.lerp(corner, t).lerp(corner.lerp(a2, t), t)
			wps.append(p)
	a.pd = d
	a.d = nd
	a.n = a.n + nd
	a.nd = Vector2i.ZERO
	a.wps = wps
	a.st = "turn"
	if not _valid(a.n):
		a.n = a.n - nd
		a.d = -nd

## limite de velocidade por obstáculo à frente (carros, jogador, pedestres, policiais)
var last_block = null
var _tick := 0
func _ahead_limit(c, pos: Vector3, no_cars := false, ign = null) -> float:
	last_block = null
	var f: Vector3 = c.global_transform.basis.z
	var lim := 99.0
	var reach: float = 16.0 + c.body_size.z * 0.5
	for o in _near(_g_cars, pos):
		if o == c or o == ign or not is_instance_valid(o):
			continue
		if no_cars and is_agent(o):
			continue
		var rel: Vector3 = o.global_position - pos
		var fwd := rel.dot(f)
		if fwd < 0.5 or fwd > reach:
			continue
		var lat := (rel - f * fwd).length()
		if lat < 1.9 + o.body_size.x * 0.3:
			last_block = o
			lim = minf(lim, maxf(0.0, fwd - c.body_size.z * 0.5 - o.body_size.z * 0.5 - 2.5) * 0.8)
	for p in _near(_g_bodies, pos):
		var rel2: Vector3 = p.global_position - pos
		var fwd2 := rel2.dot(f)
		if fwd2 < 0.5 or fwd2 > 12.0:
			continue
		if (rel2 - f * fwd2).length() < 1.8:
			lim = minf(lim, maxf(0.0, fwd2 - c.body_size.z * 0.5 - 1.5) * 0.7)
	return lim

func _control(c, carrot: Vector3, vt: float, a: Dictionary, dt: float) -> void:
	var local: Vector3 = c.global_transform.affine_inverse() * carrot
	var ang := atan2(local.x, local.z)
	var fs: float = c.forward_speed()
	if a.back > 0.0:
		a.back -= dt
		c.throttle = -0.6
		c.brake_in = 0.0
		c.steer_in = -clampf(ang * 1.8, -1.0, 1.0)
		return
	c.steer_in = clampf(ang * 1.8, -1.0, 1.0)
	if fs < vt - 0.4:
		c.throttle = clampf((vt - fs) * 0.25, 0.15, 0.85)
		c.brake_in = 0.0
	else:
		c.throttle = 0.0
		c.brake_in = clampf((fs - vt) * 0.35, 0.0, 1.0) if fs > vt + 0.6 or vt < 0.3 else 0.0
		if vt < 0.3 and fs < 0.6:
			c.brake_in = 1.0
	# travado (quer andar mas não anda): dá ré e tenta de novo; muito tempo longe da vista: reaparece
	if vt > 2.0 and absf(fs) < 0.4:
		a.stuck += dt
		if a.stuck > 3.5:
			a.stuck = 0.0
			a.back = 1.4
			a.unstuck = a.get("unstuck", 0) + 1
			if a.unstuck >= 4 and c.global_position.distance_to(main.player.global_position) > 70.0:
				_respawn(a)
	else:
		a.stuck = maxf(0.0, a.stuck - dt)
		if fs > 3.0:
			a.unstuck = 0

func _respawn(a: Dictionary) -> void:
	var pp: Vector3 = main.player.global_position
	for k in 20:
		var n := Vector2i(rng.randi_range(0, N), rng.randi_range(0, N))
		var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		var d: Vector2i = dirs[rng.randi() % 4]
		if not _valid(n - d):
			continue
		var p := node_pos(n)
		if p.distance_to(pp) < 90.0:
			continue
		var c = a.car
		c.linear_velocity = Vector3.ZERO
		c.angular_velocity = Vector3.ZERO
		var prev: Vector3 = node_pos(n - d)
		c.global_position = prev.lerp(p, 0.5) + _off(d) + Vector3(0, 0.7, 0)
		c.rotation = Vector3(0, atan2(d.x, d.y), 0)
		a.n = n
		a.d = d
		a.st = "road"
		a.wps = []
		a.nd = Vector2i.ZERO
		a.unstuck = 0
		return

# ---------------------------------------------------------------- navegação (polícia)
func nearest_node(p: Vector3) -> Vector2i:
	var i := clampi(roundi(p.x / city.CELL + N * 0.5), 0, N)
	var j := clampi(roundi(p.z / city.CELL + N * 0.5), 0, N)
	return Vector2i(i, j)

## pontos (centros de cruzamento) do carro até perto do alvo; caminho em "L" pela grade
func route(from: Vector3, to: Vector3) -> Array:
	var a := nearest_node(from)
	var b := nearest_node(to)
	var pts := []
	var cur := a
	pts.append(node_pos(cur))
	# anda primeiro no eixo de maior diferença
	var first_x: bool = absf(to.x - from.x) > absf(to.z - from.z)
	for pass_ in 2:
		var on_x := first_x if pass_ == 0 else not first_x
		while (cur.x != b.x if on_x else cur.y != b.y):
			if on_x:
				cur.x += signi(b.x - cur.x)
			else:
				cur.y += signi(b.y - cur.y)
			pts.append(node_pos(cur))
	return pts

## dirige um carro (polícia) até 'goal' pelas ruas; estado guardado em 'st' (Dictionary do chamador)
func chase(c, goal: Vector3, lead_goal: Vector3, st: Dictionary, dt: float, vmax := 26.0) -> void:
	var pos: Vector3 = c.global_position
	st.t = st.get("t", 0.0) - dt
	var d_goal := Vector2(goal.x - pos.x, goal.z - pos.z).length()
	var target := lead_goal
	if d_goal > 34.0:
		if st.t <= 0.0 or not st.has("pts"):
			st.t = 1.5
			# a rota começa no cruzamento À FRENTE da viatura (senão ela volta e fica rodando)
			var ahead: Vector3 = pos + c.global_transform.basis.z * 22.0
			st.pts = route(ahead, goal)
			while st.pts.size() > 1:
				var lp: Vector3 = c.global_transform.affine_inverse() * st.pts[0]
				if lp.z < 2.0 or Vector2(st.pts[0].x - pos.x, st.pts[0].z - pos.z).length() < 10.0:
					st.pts.pop_front()
				else:
					break
		var pts: Array = st.pts
		if pts.size() > 0:
			target = pts[0]
			if Vector2(target.x - pos.x, target.z - pos.z).length() < 9.0:
				if pts.size() > 1:
					pts.pop_front()
					target = pts[0]
				else:
					target = lead_goal       # chegou no último cruzamento: vai direto (antes ficava rodando nele)
	var local: Vector3 = c.global_transform.affine_inverse() * target
	var ang := atan2(local.x, local.z)
	var fs: float = c.forward_speed()
	if st.get("back", 0.0) > 0.0:
		st.back -= dt
		c.throttle = -0.8
		c.brake_in = 0.0
		c.steer_in = -clampf(ang * 2.0, -1, 1)
		return
	c.steer_in = clampf(ang * 2.0, -1.0, 1.0)
	var turn_slow := clampf(1.0 - absf(ang) * 0.7, 0.35, 1.0)
	var vt := vmax * turn_slow
	if local.z < -3.0 and d_goal < 14.0:
		# alvo atrás: ré manobrando
		c.throttle = -0.7
		c.steer_in = -c.steer_in
		c.brake_in = 0.0
		return
	c.throttle = 1.0 if fs < vt else 0.2
	c.brake_in = 0.6 if fs > vt + 4.0 else 0.0
	if absf(fs) < 0.6 and c.throttle > 0.5:
		st.stuck = st.get("stuck", 0.0) + dt
		if st.stuck > 1.6:
			st.stuck = 0.0
			st.back = 1.2
	else:
		st.stuck = 0.0

func _agent_of(car) -> Dictionary:
	for a in agents:
		if a.car == car:
			return a
	return {}

func _in_view(p: Vector3) -> bool:
	var cam: Camera3D = main.cam
	return not cam.is_position_behind(p) and p.distance_to(cam.global_position) < 120.0

## arma apontada para o motorista: 50% acelera para atropelar, 50% para e sai com as mãos para cima
## reação a uma batida do jogador: "chase" persegue, "flee" foge com o carro
func crash_mode(car, md: String, t: float) -> bool:
	var a := _agent_of(car)
	if a.is_empty() or a.bus:
		return false
	a.mode = md
	a.mode_t = t
	a.eng0 = car.max_engine
	car.max_engine *= 1.35
	return true

func aim_reaction(car) -> String:
	var a := _agent_of(car)
	if a.is_empty() or a.get("reacted", false) or a.bus:
		return ""
	a.reacted = true
	if rng.randf() < 0.5:
		a.mode = "ram"
		a.mode_t = 3.5
		main.audio.play("horn", car.global_position, 2.0)
		return "ram"
	a.mode = "stop"
	return "stop"

extends Node
## Missões e trabalhos (marcadores na cidade; entra-se a pé no marcador):
##   ENTREGA QUENTE: roube o esportivo marcado e leve à garagem antes do tempo (alarme: 2 estrelas).
##   ACERTO DE CONTAS: elimine o alvo protegido por capangas armados.
##   CORRIDA DE RUA: a pé; paga o aluguel de um carro só para a corrida e disputa contra pilotos NPC,
##     2 voltas, trajeto diferente a cada corrida. O carro some no fim.
##   TRANSPORTADORA: caminhão da empresa, 3 entregas pela cidade.
##   ENTREGAS DE MOTO: moto com baú, 4 pedidos com tempo (gorjeta pela pressa).
##   SERVIÇOS DAS GANGUES (Verde e Rosa, ao lado do portão do esconderijo): eliminar um alvo ou
##     espalhar a droga em 3 pontos. Trabalhando para a gangue, ela não te ataca na área dela.
## Táxi e Uber: o serviço só começa no botão SERVIÇO (táxi) ou pelo celular (Uber).
## Uber como passageiro: pedido pelo celular; o carro vem, você entra atrás e ele leva ao destino.

const Ped := preload("res://scripts/ped.gd")
const Cop := preload("res://scripts/cop.gd")
const W2 := preload("res://scripts/world2.gd")

var main: Node3D
var active := ""
var givers: Array = []         # {id, name, pos, node, label, car_pos, car_yaw}
var obj_node: MeshInstance3D
var obj_pos := Vector3.INF
var timer := -1.0
var reward := 0
var target_car = null
var target_ped = null
var thugs: Array = []
var checkpoints: Array = []
var cp_i := 0
var garage := Vector3.ZERO
var taxi_state := ""
var passenger = null
var fare_from := Vector3.ZERO
var rng := RandomNumberGenerator.new()
var text := ""
var done := {}
var job_car = null             # veículo do trabalho/aluguel (some no fim)
var drops: Array = []
var drop_i := 0
var job_gang := ""
var near_giver := {}          # marcador de missão em que o jogador está (botão INICIAR)
var rent_i := -1              # carro alugado no racha (-1 = veículo próprio)

const INFO := {
	"delivery": {"name": "ROUBO DE CARRO", "reward": 900, "icon": "m_steal", "desc": "Roube o esportivo vermelho estacionado e leve até a garagem antes do tempo. O alarme chama a polícia."},
	"hit": {"name": "ACERTO DE CONTAS", "reward": 1200, "icon": "m_hit", "desc": "Elimine o alvo protegido por capangas armados."},
	"race": {"name": "RACHA", "reward": 1000, "icon": "m_race", "desc": "Corrida de 2 voltas contra 3 pilotos. Prêmio: 1º $1.000 · 2º $450 · 3º $150."},
	"truck": {"name": "TRANSPORTADORA", "reward": 0, "icon": "m_truck", "desc": "Leve a carga do caminhão da empresa a 3 endereços. $380 por entrega + $400 no fim."},
	"motojob": {"name": "ENTREGAS DE MOTO", "reward": 0, "icon": "m_moto", "desc": "4 pedidos com tempo. Quanto mais rápido, maior a gorjeta; atrasou, o cliente cancela."},
	"gang_g": {"name": "SERVIÇO DA GANGUE VERDE", "reward": 1100, "icon": "m_gang", "desc": "A gangue tem um serviço: eliminar alguém, roubar um carro ou espalhar a droga."},
	"gang_p": {"name": "SERVIÇO DA GANGUE ROSA", "reward": 1100, "icon": "m_gang", "desc": "A gangue tem um serviço: eliminar alguém, roubar um carro ou espalhar a droga."},
}
## carros para alugar no racha: cada um mais rápido, mas nenhum mais rápido que os adversários
const RENT := [
	{"name": "Hatch preparado", "kind": "hatch", "price": 100, "eng": 1.25, "vmax": 1.0, "mods": {"wheels": 2, "sticker": 1, "spoiler": 1}},
	{"name": "Sedã envenenado", "kind": "sedan", "price": 220, "eng": 1.35, "vmax": 1.05, "mods": {"wheels": 1, "sticker": 4, "spoiler": 2, "fbumper": 1}},
	{"name": "Esportivo", "kind": "sport", "price": 400, "eng": 1.3, "vmax": 1.03, "mods": {"wheels": 3, "sticker": 1, "spoiler": 2, "fbumper": 1, "rbumper": 1}},
	{"name": "Supercarro", "kind": "super", "price": 750, "eng": 1.0, "vmax": 0.95, "mods": {"wheels": 5, "sticker": 3, "spoiler": 3}},
]
const RACE_FEE := 150
const RACE_LAPS := 2
## trajetos da corrida: cruzamentos da grade (índice da rua 0..7), em laço fechado
const ROUTES := [
	[[1, 1], [6, 1], [6, 4], [3, 4], [3, 6], [1, 6]],
	[[1, 2], [4, 2], [4, 1], [6, 1], [6, 5], [4, 5], [4, 6], [1, 6]],
	[[2, 1], [5, 1], [5, 3], [2, 3], [2, 5], [6, 5], [6, 6], [1, 6], [1, 1]],
	[[1, 3], [3, 3], [3, 1], [6, 1], [6, 6], [2, 6], [2, 4], [1, 4]],
]

func setup(m: Node3D) -> void:
	main = m
	rng.randomize()
	var c = main.city
	var sw: float = c.BLOCK * 0.5 - 1.6        # calçada (a partir do centro da quadra)
	var half: float = c.CELL * 0.5
	var spots := {
		"delivery": [Vector3(c._center(0) + sw, 0.15, c._center(0)), Vector3.INF, 0.0],
		"hit": [Vector3(c._center(4) - sw, 0.15, c._center(1)), Vector3.INF, 0.0],
		"race": [c.race_lot.giver, c.race_lot.rent, PI * 0.5],
		"truck": [Vector3(c._center(3), 0.15, c._center(0) + sw), Vector3(c._center(3) + 6.0, 0.9, c._center(0) + half - 2.6), PI * 0.5],
		"motojob": [Vector3(c._center(1) + 8.0, 0.15, c._center(3) + sw), Vector3(c._center(1) + 12.0, 0.8, c._center(3) + half - 2.6), PI * 0.5],
	}
	var hq: Dictionary = c.gang_hq
	for g in ["g", "p"]:
		if hq.has(g):
			var gp: Vector3 = hq[g].alley          # viela ao lado do esconderijo
			spots["gang_" + g] = [Vector3(gp.x, 0.15, gp.z), Vector3.INF, 0.0]
	for id in spots:
		var pos: Vector3 = spots[id][0]
		var col := Color(1.0, 0.8, 0.1)
		if id == "gang_g":
			col = Color(0.2, 0.9, 0.35)
		elif id == "gang_p":
			col = Color(1.0, 0.4, 0.75)
		var mk := W2.marker(main, pos, col, 0.9)
		# placa flutuante com o símbolo da missão (bandeira, carro com cadeado, mira, caminhão...)
		var lb := Sprite3D.new()
		lb.texture = icon_tex(INFO[id].icon, col)
		lb.pixel_size = 0.016
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.shaded = false
		lb.no_depth_test = false
		main.add_child(lb)
		lb.global_position = pos + Vector3(0, 3.0, 0)
		givers.append({"id": id, "pos": pos, "node": mk, "label": lb, "car_pos": spots[id][1], "car_yaw": spots[id][2], "col": col, "icon": INFO[id].icon})
	garage = Vector3(c._center(4) + c.CELL * 0.5 + 2.6, 0.15, c._center(4))

## símbolo de cada missão (placa flutuante): desenhado em uma Image 64×64
static var _icons := {}
static func icon_tex(kind: String, col: Color) -> Texture2D:
	var key := kind + col.to_html()
	if _icons.has(key):
		return _icons[key]
	var n := 64
	var im := Image.create(n, n, false, Image.FORMAT_RGBA8)
	im.fill(Color(0, 0, 0, 0))
	var bg := Color(0.06, 0.06, 0.08, 0.92)
	var w := Color(1, 1, 1)
	for y in n:
		for x in n:
			var d := Vector2(x - 31.5, y - 31.5).length()
			if d < 30.5:
				im.set_pixel(x, y, col if d > 27.0 else bg)
	var R := func(x0: int, y0: int, x1: int, y1: int, c: Color):
		for yy in range(y0, y1):
			for xx in range(x0, x1):
				im.set_pixel(xx, yy, c)
	match kind:
		"m_race":   # bandeira quadriculada
			R.call(16, 14, 19, 50, w)
			for yy in 4:
				for xx in 6:
					R.call(19 + xx * 5, 14 + yy * 5, 24 + xx * 5, 19 + yy * 5, w if (xx + yy) % 2 == 0 else Color(0.1, 0.1, 0.1))
		"m_steal":  # carro + cadeado
			R.call(12, 30, 46, 40, w); R.call(18, 23, 38, 31, w)
			R.call(15, 39, 21, 45, Color(0.2, 0.2, 0.2)); R.call(37, 39, 43, 45, Color(0.2, 0.2, 0.2))
			R.call(40, 36, 54, 48, col); R.call(43, 30, 45, 37, col); R.call(49, 30, 51, 37, col); R.call(43, 29, 51, 31, col)
		"m_hit":    # mira
			for yy in n:
				for xx in n:
					var d := Vector2(xx - 31.5, yy - 31.5).length()
					if absf(d - 15.0) < 1.8 or d < 2.5:
						im.set_pixel(xx, yy, Color(1, 0.3, 0.3))
			R.call(31, 10, 33, 24, w); R.call(31, 40, 33, 54, w); R.call(10, 31, 24, 33, w); R.call(40, 31, 54, 33, w)
		"m_truck":  # caminhão
			R.call(10, 20, 36, 40, w); R.call(36, 27, 50, 40, w); R.call(40, 29, 47, 34, bg)
			R.call(14, 39, 21, 46, Color(0.3, 0.3, 0.3)); R.call(40, 39, 47, 46, Color(0.3, 0.3, 0.3))
		"m_moto":   # moto + caixa de entrega
			R.call(14, 36, 22, 44, w); R.call(40, 36, 48, 44, w); R.call(20, 32, 44, 36, w); R.call(36, 24, 39, 33, w)
			R.call(18, 20, 30, 31, Color(1, 0.6, 0.1))
		"m_gang":   # caveira
			for yy in n:
				for xx in n:
					if Vector2(xx - 31.5, (yy - 27.0) * 1.1).length() < 13.0:
						im.set_pixel(xx, yy, w)
			R.call(24, 36, 40, 46, w)
			R.call(24, 23, 30, 30, bg); R.call(34, 23, 40, 30, bg); R.call(30, 31, 34, 35, bg)
			R.call(28, 40, 30, 46, bg); R.call(34, 40, 36, 46, bg)
		_:
			R.call(28, 14, 36, 40, w); R.call(28, 44, 36, 50, w)
	var t := ImageTexture.create_from_image(im)
	_icons[key] = t
	return t

func hostiles() -> Array:
	thugs = thugs.filter(func(t): return is_instance_valid(t))
	if main.gangs:
		return thugs + main.gangs.alive()
	return thugs

## o jogador está fazendo serviço para a gangue (ou está no marcador dela)? Então ela não ataca.
func near_gang_job(g: String, pp: Vector3) -> bool:
	if active == "gang_" + g:
		return true
	for gv in givers:
		if gv.id == "gang_" + g and Vector2(pp.x - gv.pos.x, pp.z - gv.pos.z).length() < 14.0:
			return true
	return false

## pontos para o minimapa: [{pos, col}]
func blips() -> Array:
	var b := []
	if active == "":
		for g in givers:
			b.append({"pos": g.pos, "col": g.col, "icon": g.icon})
	if active == "race" and not checkpoints.is_empty():
		var n := checkpoints.size()
		b.append({"pos": checkpoints[cp_i % n], "col": Color(0.2, 0.8, 1.0), "icon": "cp", "next": checkpoints[(cp_i + 1) % n]})
		for r in racers:
			if is_instance_valid(r.car):
				b.append({"pos": r.car.global_position, "col": Color(1, 0.55, 0.1)})
	elif obj_pos != Vector3.INF:
		b.append({"pos": obj_pos, "col": Color(1, 0.95, 0.2)})
	for t in hostiles():
		if not t.down and (t in thugs):
			b.append({"pos": t.global_position, "col": Color(1, 0.2, 0.2)})
	return b

func _set_obj(pos: Vector3, col := Color(1, 0.9, 0.1), r := 2.5) -> void:
	_clear_obj()
	obj_pos = pos
	obj_node = W2.marker(main, pos, col, r)

func _clear_obj() -> void:
	if obj_node and is_instance_valid(obj_node):
		obj_node.queue_free()
	obj_node = null
	obj_pos = Vector3.INF

func tick(dt: float) -> void:
	var p = main.player
	var veh = p.vehicle
	for g in givers:
		g.node.visible = active == ""
		g.label.visible = active == ""
	_ride_tick(dt)
	if timer > 0.0:
		timer -= dt
		if timer <= 0.0:
			if active in ["taxi", "uber"]:
				_end_fare()
			elif active == "motojob":
				_moto_late()
			else:
				fail("Tempo esgotado")
				return
	if active in ["taxi", "uber"]:
		if veh == null or (active == "taxi" and veh.get("kind") != "taxi"):
			_taxi_end()
		else:
			_taxi_tick(dt, veh)
		_text()
		return
	if active == "":
		# perto do marcador só aparece o botão INICIAR (não começa sozinho)
		near_giver = {}
		var pp: Vector3 = veh.global_position if veh else p.global_position
		for g in givers:
			var r := 6.5 if (veh != null and g.id == "race") else 2.8
			if Vector2(pp.x - g.pos.x, pp.z - g.pos.z).length() < r and not main.combat.dead and (veh == null or g.id == "race"):
				near_giver = g
		text = ""
		_text()
		return
	near_giver = {}
	match active:
		"delivery": _delivery_tick(veh)
		"hit": _hit_tick()
		"race": _race_tick(dt, veh)
		"truck", "motojob": _drops_tick(dt, veh)
		"gang_g", "gang_p": _gang_tick(dt, veh)
	_text()

func _text() -> void:
	main.hud.mission_text = text
	main.hud.mission_timer = timer

func _giver(id: String) -> Dictionary:
	for g in givers:
		if g.id == id:
			return g
	return {}

## carro do trabalho/aluguel na rua ao lado do marcador; o jogador já entra nele
func _job_vehicle(id: String, kind: String, col: Color):
	var g := _giver(id)
	var c = main._spawn_car(g.car_pos, g.car_yaw, col, false, kind)
	c.unlocked = true
	c.set_meta("job", true)
	job_car = c
	return c

## opções da tela da missão: [[texto, habilitado, Callable], ...]
func offer_options(g: Dictionary) -> Array:
	var id: String = g.id
	var out := []
	if id == "race":
		var veh = main.player.vehicle
		if veh != null:
			out.append(["Certeza que quer iniciar com esse veículo? SIM", true, func(): rent_i = -1; _start("race")])
		for i in RENT.size():
			var it: Dictionary = RENT[i]
			var ii := i
			out.append(["Alugar %s · $%d" % [it.name, it.price], main.money >= it.price, func(): rent_i = ii; _start("race")])
	else:
		out.append(["INICIAR", true, func(): _start(id)])
	return out

func _start(id: String) -> void:
	var p = main.player
	var c = main.city
	if id == "race" and rent_i >= 0:
		var it: Dictionary = RENT[rent_i]
		if main.money < it.price:
			main._msg("Dinheiro insuficiente para o aluguel", true)
			return
		main.money -= it.price
	active = id
	reward = INFO[id].reward
	main.hud.banner(INFO[id].name, Color(1, 0.85, 0.1))
	main.audio.play("cash")
	match id:
		"delivery":
			var road: float = c._center(0) - c.CELL * 0.5
			target_car = main._spawn_car(Vector3(road + 5.9, 0.7, c._center(3)), 0.0, Color(0.85, 0.05, 0.05), false, "sport")
			text = "Roube o esportivo vermelho"
			timer = -1.0
		"hit":
			var base := Vector3(c._center(3), 0.2, c._center(4))
			_spawn_target(base, 3)
			text = "Elimine o alvo (marcado em vermelho)"
			timer = 180.0
		"race":
			_race_start()
		"truck":
			var tk = _job_vehicle("truck", "truck", Color(0.9, 0.9, 0.9))
			_make_drops(3, 140.0, 360.0)
			text = "Entre no caminhão da transportadora"
			obj_pos = tk.global_position
		"motojob":
			_job_vehicle("motojob", "moto", Color(0.85, 0.1, 0.1))
			_make_drops(4, 80.0, 240.0)
			text = "Pegue a moto de entregas"
		"gang_g", "gang_p":
			job_gang = id.substr(5)
			var kind: String = ["kill", "steal", "drugs"][int(done.get(id, 0)) % 3]
			set_meta("gang_kind", kind)
			if kind == "kill":
				var spot := _far_sidewalk(p.global_position, 150.0, 320.0)
				_spawn_target(spot, 2)
				text = "Gangue: elimine o alvo (vermelho no mapa)"
				timer = 240.0
			elif kind == "steal":
				var spot := _far_sidewalk(p.global_position, 160.0, 330.0)
				target_car = main._spawn_car(spot + Vector3(0, 0.5, 0), rng.randf() * TAU, [Color(0.9, 0.9, 0.92), Color(0.05, 0.05, 0.06), Color(0.6, 0.0, 0.05)][rng.randi() % 3], false, ["super", "sport", "suv"][rng.randi() % 3])
				target_car.parked = true
				target_car.unlocked = false
				text = "Gangue: roube o carro marcado e traga para a viela"
				timer = 300.0
			else:
				_make_drops(3, 90.0, 300.0)
				drop_i = 0
				_set_obj(drops[0], Color(0.6, 1.0, 0.3), 2.5)
				text = "Gangue: entregue a droga nos 3 pontos (1/3)"
				timer = 300.0

func _spawn_target(base: Vector3, guards: int) -> void:
	target_ped = Cop.new()
	main.add_child(target_ped)
	target_ped.setup(rng.randi(), "thug")
	target_ped.global_position = base + Vector3(0, 0.2, 0)
	target_ped.hp = 140.0
	thugs = [target_ped]
	for k in guards:
		var t := Cop.new()
		main.add_child(t)
		t.setup(rng.randi(), "thug")
		t.global_position = base + Vector3(cos(k * 2.1) * 3.0, 0.2, sin(k * 2.1) * 3.0)
		thugs.append(t)
	for t in thugs:
		t.shot_player.connect(main.combat._on_cop_shot)
		t.pref = rng.randf_range(6.0, 12.0)

## ponto de calçada entre rmin e rmax do jogador
func _far_sidewalk(from: Vector3, rmin: float, rmax: float) -> Vector3:
	var c = main.city
	for k in 40:
		var loop: Array = c.walk_loops[rng.randi() % c.walk_loops.size()]
		var k0 := rng.randi() % loop.size()
		var pt: Vector3 = loop[k0].lerp(loop[(k0 + 1) % loop.size()], rng.randf())     # na calçada (antes cortava a quadra na diagonal = dentro dos prédios)
		var d := pt.distance_to(from)
		if d > rmin and d < rmax:
			return pt
	return c.hospital_pos

func _make_drops(n: int, rmin: float, rmax: float) -> void:
	drops = []
	var from: Vector3 = main.player.global_position
	for k in n:
		var d := _far_sidewalk(from, rmin * 0.6, rmax)
		drops.append(d)
		from = d
	drop_i = 0

# ---------------------------------------------------------------- entregas (caminhão / moto)
func _drops_tick(dt: float, veh) -> void:
	if job_car == null or not is_instance_valid(job_car) or job_car.get("dead"):
		fail("O veículo do trabalho foi destruído")
		return
	var nm := "caminhão" if active == "truck" else "moto"
	if veh != job_car:
		obj_pos = job_car.global_position
		if obj_node:
			_clear_obj()
			obj_pos = job_car.global_position
		text = "Volte para a %s" % nm if active == "motojob" else "Volte para o caminhão"
		if drop_i == 0 and timer < 0.0:
			text = "Entre no caminhão da transportadora" if active == "truck" else "Pegue a moto de entregas"
		return
	if obj_node == null:
		_set_obj(drops[drop_i], Color(0.2, 1.0, 0.3), 3.5)
		if active == "motojob":
			timer = job_car.global_position.distance_to(drops[drop_i]) / 9.0 + 25.0
	var total := drops.size()
	text = ("Entrega %d/%d · leve a carga ao ponto verde" if active == "truck" else "Pedido %d/%d · entregue antes do tempo") % [drop_i + 1, total]
	if Vector2(veh.global_position.x - drops[drop_i].x, veh.global_position.z - drops[drop_i].z).length() < 11.0 and veh.linear_velocity.length() < 2.5:
		var pay := 0
		if active == "truck":
			pay = 380
		else:
			pay = 110 + int(maxf(timer, 0.0) * 4.0)       # gorjeta pela pressa
		main.money += pay
		main.audio.play("cash")
		main.hud.banner("ENTREGA FEITA  +$%d" % pay, Color(0.4, 1.0, 0.4), 2.0)
		drop_i += 1
		_clear_obj()
		timer = -1.0
		if drop_i >= total:
			if active == "truck":
				main.money += 400
				main.hud.banner("TRANSPORTADORA: SERVIÇO COMPLETO  +$400 de bônus", Color(1, 0.85, 0.1))
			reward = 0
			_success()

func _moto_late() -> void:
	# pedido atrasado: o cliente cancela; segue para o próximo
	main.hud.banner("PEDIDO ATRASADO — CANCELADO", Color(1, 0.4, 0.2), 2.0)
	drop_i += 1
	_clear_obj()
	timer = -1.0
	if drop_i >= drops.size():
		reward = 0
		_success()

# ---------------------------------------------------------------- serviços das gangues
func _gang_tick(dt: float, veh) -> void:
	var kind: String = get_meta("gang_kind", "kill")
	if kind == "kill":
		_hit_tick()
		return
	if kind == "steal":
		if target_car == null or not is_instance_valid(target_car) or target_car.dead:
			fail("O carro foi destruído")
			return
		var drop: Vector3 = main.city.gang_hq[job_gang].get("alley", main.city.gang_hq[job_gang].gate_out)
		if veh != target_car:
			if obj_node:
				_clear_obj()
			obj_pos = target_car.global_position
			text = "Gangue: roube o carro marcado e traga para a viela"
			return
		if obj_node == null:
			_set_obj(drop, Color(0.6, 1.0, 0.3), 5.0)
		text = "Gangue: leve o carro até a viela"
		if Vector2(veh.global_position.x - drop.x, veh.global_position.z - drop.z).length() < 8.0 and veh.linear_velocity.length() < 3.0:
			main.eject_player(Vector3.ZERO)
			main.cars.erase(target_car)
			var tc = target_car
			target_car = null
			tc.get_tree().create_timer(4.0).timeout.connect(func(): if is_instance_valid(tc) and main.player.vehicle != tc: tc.queue_free())
			_clear_obj()
			_success()
		return
	var p = main.player
	var pp: Vector3 = veh.global_position if veh else p.global_position
	text = "Gangue: entregue a droga nos 3 pontos (%d/3)" % (drop_i + 1)
	if Vector2(pp.x - drops[drop_i].x, pp.z - drops[drop_i].z).length() < 4.5:
		main.audio.play("cash", null, -4.0)
		if main.police.seen_by_cop(pp):
			main._raise_wanted(1)       # um policial viu a entrega
		drop_i += 1
		if drop_i >= drops.size():
			_clear_obj()
			_success()
			return
		_set_obj(drops[drop_i], Color(0.6, 1.0, 0.3), 2.5)

# ---------------------------------------------------------------- missões antigas
func _delivery_tick(veh) -> void:
	if target_car == null or not is_instance_valid(target_car) or target_car.dead:
		fail("O carro foi destruído")
		return
	if veh != target_car:
		obj_pos = target_car.global_position
		text = "Roube o esportivo vermelho" if timer < 0.0 else "Volte para o carro!"
		return
	if timer < 0.0:
		timer = 100.0
		main._add_wanted(2)
		_set_obj(garage, Color(0.2, 1.0, 0.3), 4.0)
	text = "Leve o carro à garagem (verde)"
	if veh.global_position.distance_to(garage) < 6.0 and veh.linear_velocity.length() < 3.0:
		main.eject_player(Vector3.ZERO)
		main.cars.erase(target_car)
		target_car.queue_free()
		target_car = null
		_success()

func _hit_tick() -> void:
	var p = main.player
	for t in thugs:
		if is_instance_valid(t) and not t.down:
			t.target = main.player.vehicle if main.player.vehicle else p
			if t.global_position.distance_to(p.global_position) > 28.0 and t != target_ped:
				t.target = null
	if target_ped == null or not is_instance_valid(target_ped) or target_ped.down:
		_success()
		return
	obj_pos = target_ped.global_position
	if target_ped.global_position.distance_to(p.global_position) > 28.0:
		target_ped.target = null

func on_kill(t) -> void:
	if (active == "hit" or active.begins_with("gang_")) and t == target_ped:
		_success()

# ---------------------------------------------------------------- corrida de rua
var route_i := 0
var laps := 0
var racers: Array = []       # [{car, cp, lap, done, skill, drv}]
var race_t := 0.0
var finish_order: Array = []

func _node(q: Array) -> Vector3:
	return Vector3((q[0] - 3.5) * main.city.CELL, 0.4, (q[1] - 3.5) * main.city.CELL)

var grid: Array = []          # posições de largada [pos, yaw]
var race_kind := "sport"      # modelo do carro do jogador (para trocar se explodir)
var race_mods := {}
var race_top := 40.0          # velocidade máxima do carro do jogador (m/s)
var _pdead_t := 0.0
var _gas_prev := false
var _gas_taps: Array = []
var _nitro_used := false

func _race_start() -> void:
	var route: Array = ROUTES[route_i % ROUTES.size()]
	route_i += 1
	checkpoints = []
	for q in route:
		checkpoints.append(_node(q))
	checkpoints.append(checkpoints[0])       # volta fecha no ponto de partida
	checkpoints.remove_at(0)
	# grade de largada: no 1º trecho, saindo do ponto de partida em direção ao 1º ponto
	var a: Vector3 = _node(route[0])
	var b: Vector3 = checkpoints[0]
	var dir: Vector3 = (b - a).normalized()
	var side: Vector3 = dir.cross(Vector3.UP)
	var yaw := atan2(dir.x, dir.z)
	grid = []
	for k in 4:
		grid.append([a + dir * (16.0 - float(k / 2) * 7.0) + side * (2.4 if k % 2 == 0 else -2.4) + Vector3(0, 0.4, 0), yaw])
	# tela de cinema: do ponto de encontro para a largada
	main.ui.cinematic("RACHA", "indo para a largada...", _race_setup)

func _race_setup() -> void:
	var own = main.player.vehicle
	var pc
	if rent_i < 0 and own != null and is_instance_valid(own):
		pc = own                               # corre com o próprio veículo
		race_kind = own.get("variant") if own.get("variant") else own.kind
		race_mods = own.get("mods") if own.get("mods") is Dictionary else {}
	else:
		if own != null:
			main.eject_player(Vector3.ZERO)
		var it: Dictionary = RENT[maxi(rent_i, 0)]
		race_kind = it.kind
		race_mods = it.mods.duplicate()
		race_mods["paint"] = Color(0.95, 0.75, 0.05).to_html()
		pc = _rent_car(grid[0][0], grid[0][1])
	job_car = pc
	_place(pc, grid[0][0], grid[0][1])
	if main.player.vehicle != pc:
		main.player.global_position = pc.global_position + Vector3(2.5, 0, 0)
		main.finish_enter(pc)
	race_top = main.Car.VMAX.get(pc.get("variant"), main.Car.VMAX.get(pc.kind, 160.0)) / 3.6 * float(pc.get("vmax_mult") if pc.get("vmax_mult") else 1.0)
	racers = []
	var kinds := ["super", "sport", "super"]
	var cols := [Color(0.1, 0.3, 0.9), Color(0.85, 0.1, 0.1), Color(0.1, 0.1, 0.1)]
	for k in 3:
		var r := {"cp": 0, "lap": 0, "done": false, "kind": kinds[k], "col": cols[k],
			"skill": rng.randf_range(1.02, 1.07), "dead_t": 0.0}
		r.car = _racer_car(r, grid[k + 1][0], grid[k + 1][1])
		racers.append(r)
	cp_i = 0
	laps = 0
	finish_order = []
	_pdead_t = 0.0
	_nitro_used = false
	race_t = -3.0        # contagem regressiva
	main.hud.banner("3", Color(1, 1, 1), 1.0)
	_set_obj(checkpoints[0], Color(0.2, 0.8, 1.0), 6.0)

## carro alugado do jogador (tunado, mais forte conforme o preço)
func _rent_car(pos: Vector3, yaw: float):
	var pc = main._spawn_car(pos, yaw, Color(0.95, 0.75, 0.05), false, race_kind)
	pc.unlocked = true
	pc.set_meta("job", true)
	main.TUNING.apply(pc, race_mods)
	if rent_i >= 0:
		pc.eng_mult = RENT[rent_i].eng
		pc.vmax_mult = RENT[rent_i].vmax
	return pc

## carro de um adversário: nunca mais lento que o do jogador (velocidade quase igual)
func _racer_car(r: Dictionary, pos: Vector3, yaw: float):
	var rc = main._spawn_car(pos, yaw, r.col, false, r.kind)
	rc.set_meta("job", true)
	rc.unlocked = false
	main.TUNING.apply(rc, {"wheels": 1 + rng.randi() % 5, "sticker": 1 + rng.randi() % 5, "spoiler": 1 + rng.randi() % 3, "fbumper": 1, "paint": r.col.to_html()})
	var base: float = main.Car.VMAX.get(r.kind, 230.0) / 3.6
	rc.vmax_mult = maxf(1.0, race_top * r.skill * 1.06 / base)
	rc.eng_mult = 1.3
	main.seat_npc(rc)
	_place(rc, pos, yaw)
	return rc

func _place(c, pos: Vector3, yaw: float) -> void:
	c.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0, 0.5, 0))
	c.linear_velocity = Vector3.ZERO
	c.angular_velocity = Vector3.ZERO
	c.throttle = 0.0
	c.brake_in = 1.0

## ponto de reposição: último ponto alcançado, virado para o próximo
func _cp_spot(cp: int, lap: int, lane: float) -> Array:
	var n := checkpoints.size()
	if cp == 0 and lap == 0:
		return grid[0]
	var prv: Vector3 = checkpoints[(cp - 1 + n) % n]
	var nx: Vector3 = checkpoints[cp % n]
	var dir: Vector3 = (nx - prv).normalized()
	return [prv + dir * 8.0 + dir.cross(Vector3.UP) * lane + Vector3(0, 0.4, 0), atan2(dir.x, dir.z)]

## menu do racha: voltar ao último ponto (troca o carro se explodiu)
func race_to_checkpoint() -> void:
	if active != "race":
		return
	var sp := _cp_spot(cp_i, laps, 0.0)
	main.ui.cinematic("RACHA", "voltando ao último ponto...", func():
		if job_car == null or not is_instance_valid(job_car) or job_car.dead:
			if main.player.vehicle != null:
				main.eject_player(Vector3.ZERO)
			job_car = _rent_car(sp[0], sp[1])
		elif main.player.vehicle != job_car and main.player.vehicle != null:
			main.eject_player(Vector3.ZERO)
		if job_car.has_method("repair") and job_car.get("hp") != null and job_car.hp < 30.0:
			job_car.repair()
		_place(job_car, sp[0], sp[1])
		if main.player.vehicle != job_car:
			main.player.global_position = job_car.global_position + Vector3(2.5, 0, 0)
			main.finish_enter(job_car)
		_pdead_t = 0.0)

## recomeça do início: todos de volta à largada, nova contagem
func race_restart() -> void:
	if active != "race":
		return
	main.ui.cinematic("RACHA", "recomeçando...", func():
		if job_car == null or not is_instance_valid(job_car) or job_car.dead:
			if main.player.vehicle != null:
				main.eject_player(Vector3.ZERO)
			job_car = _rent_car(grid[0][0], grid[0][1])
		elif main.player.vehicle != job_car and main.player.vehicle != null:
			main.eject_player(Vector3.ZERO)
		if job_car.has_method("repair"):
			job_car.repair()
		_place(job_car, grid[0][0], grid[0][1])
		if main.player.vehicle != job_car:
			main.player.global_position = job_car.global_position + Vector3(2.5, 0, 0)
			main.finish_enter(job_car)
		for k in racers.size():
			var r: Dictionary = racers[k]
			if not is_instance_valid(r.car) or r.car.dead:
				r.car = _racer_car(r, grid[k + 1][0], grid[k + 1][1])
			else:
				if r.car.has_method("repair"):
					r.car.repair()
				_place(r.car, grid[k + 1][0], grid[k + 1][1])
			r.cp = 0
			r.lap = 0
			r.done = false
			r.dead_t = 0.0
		cp_i = 0
		laps = 0
		finish_order = []
		_pdead_t = 0.0
		_nitro_used = false
		race_t = -3.0
		main.hud.banner("3", Color(1, 1, 1), 1.0)
		_set_obj(checkpoints[0], Color(0.2, 0.8, 1.0), 6.0))

## vácuo: atrás de outro carro da corrida (3–22 m, alinhado) ganha força e velocidade
func _draft_tick(dt: float) -> void:
	var rcs: Array = []
	if job_car and is_instance_valid(job_car) and not job_car.dead:
		rcs.append(job_car)
	for r in racers:
		if is_instance_valid(r.car) and not r.car.dead:
			rcs.append(r.car)
	var mine := 0.0
	for c in rcs:
		var best := 0.0
		var fwd: Vector3 = c.global_transform.basis.z
		var sp: float = c.linear_velocity.length()
		if sp > 8.0:
			for o in rcs:
				if o == c:
					continue
				var d: Vector3 = o.global_position - c.global_position
				var ahead := d.dot(fwd)
				if ahead < 3.0 or ahead > 22.0:
					continue
				if absf(d.dot(fwd.cross(Vector3.UP))) > 1.8:
					continue
				if o.linear_velocity.dot(fwd) < 6.0:
					continue
				best = maxf(best, 1.0 - (ahead - 3.0) / 19.0 * 0.6)
		# saiu do vácuo: o embalo dura ~2,5 s (dá para ultrapassar) e depois cai devagar
		if best > 0.05:
			c.set_meta("dr_hold", 2.5)
			c.draft = move_toward(c.draft, best, dt * 2.5)
		else:
			var hold: float = c.get_meta("dr_hold", 0.0) - dt
			c.set_meta("dr_hold", hold)
			if hold <= 0.0:
				c.draft = move_toward(c.draft, 0.0, dt * 0.35)
		_draft_fx(c, best)
		if c == job_car:
			mine = c.draft
	in_draft = mine > 0.2

var in_draft := false

## rastro branco do vácuo: 2 faixas translúcidas saindo da traseira enquanto pega o vácuo
static var _trail_mat: StandardMaterial3D
func _draft_fx(c, cur: float) -> void:
	var tr: Node3D = c.get_meta("dr_fx", null)
	if tr == null or not is_instance_valid(tr):
		if _trail_mat == null:
			_trail_mat = StandardMaterial3D.new()
			_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_trail_mat.albedo_color = Color(1, 1, 1, 0.45)
			_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		tr = Node3D.new()
		c.add_child(tr)
		var hz: float = c.body_size.z * 0.5 if c.get("body_size") != null else 2.2
		var hx: float = c.body_size.x * 0.35 if c.get("body_size") != null else 0.7
		for sx in [-hx, hx]:
			var m := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.12, 0.05, 1.0)
			m.mesh = bm
			m.material_override = _trail_mat
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			m.position = Vector3(sx, 0.55, -hz - 0.5)
			tr.add_child(m)
		c.set_meta("dr_fx", tr)
	var on: bool = cur > 0.05 or c.get_meta("dr_hold", 0.0) > 0.0
	tr.visible = on and c.linear_velocity.length() > 8.0
	if tr.visible:
		var ln: float = clampf(c.linear_velocity.length() * 0.12, 1.0, 6.0) * clampf(c.draft + 0.2, 0.3, 1.0)
		var hz2: float = c.body_size.z * 0.5 if c.get("body_size") != null else 2.2
		for m in tr.get_children():
			m.scale = Vector3(1, 1, ln)
			m.position.z = -hz2 - ln * 0.5


## desvia de carros da rua à frente: desloca o alvo para o lado livre
func _dodge(rc, tgt: Vector3) -> Vector3:
	var b: Basis = rc.global_transform.basis
	var fwd: Vector3 = b.z
	fwd.y = 0
	fwd = fwd.normalized()
	var rt := fwd.cross(Vector3.UP)
	var best := 99.0
	var lat := 0.0
	var v: float = maxf(rc.linear_velocity.length(), 8.0)
	var look := clampf(v * 1.1, 14.0, 38.0)
	for o in main.cars:
		if o == rc or not is_instance_valid(o) or o.get("dead"):
			continue
		var d: Vector3 = o.global_position - rc.global_position
		var ahead := d.dot(fwd)
		if ahead < 2.0 or ahead > look:
			continue
		var side := d.dot(rt)
		if absf(side) > 2.6:
			continue
		# carro à frente mais lento que nós
		if o.linear_velocity.dot(fwd) > v * 0.8:
			continue
		if ahead < best:
			best = ahead
			lat = side
	if best > 90.0:
		return tgt
	var push := -signf(lat) if absf(lat) > 0.3 else 1.0
	return rc.global_position + fwd * best + rt * push * 3.4

func _race_progress(lap: int, cp: int, pos: Vector3) -> float:
	var n := checkpoints.size()
	var d := pos.distance_to(checkpoints[cp % n])
	return lap * n + cp - d / 500.0

func _race_tick(dt: float, veh) -> void:
	if main.ui._cine:
		return
	if job_car == null or not is_instance_valid(job_car) or job_car.dead:
		# o carro do jogador explodiu: volta no último ponto com um carro igual
		_pdead_t += dt
		text = "Carro destruído! Voltando ao último ponto..."
		if _pdead_t > 2.5 and not main.combat.dead:
			race_to_checkpoint()
		return
	var prev_t := race_t
	race_t += dt
	# contagem regressiva: todos parados
	if race_t < 0.0:
		for r in racers:
			if is_instance_valid(r.car):
				r.car.brake_in = 1.0
				r.car.throttle = 0.0
				r.car.hold = true
		if veh:
			veh.hold = true          # acelerar antes do VAI! não sai do lugar
		_gas_prev = veh != null and veh.throttle > 0.5
		_gas_taps = []
		if int(ceil(prev_t)) != int(ceil(race_t)) and race_t < -0.01:
			main.hud.banner(str(int(ceil(-race_t))), Color(1, 1, 1), 1.0)
		text = "Prepare-se..."
		return
	if prev_t < 0.0:
		main.hud.banner("VAI!", Color(0.3, 1.0, 0.3), 1.0)
		main.audio.play("horn", job_car.global_position, 0.0)
		job_car.hold = false
		job_car.brake_in = 0.0
		for r in racers:
			if is_instance_valid(r.car):
				r.car.hold = false
				# adversários também usam nitro na largada (às vezes)
				if rng.randf() < 0.6:
					r.car.nitro_t = rng.randf_range(1.5, 2.6)
	# nitro: tocar 2× no acelerador logo depois da largada (até 3 s)
	if veh == job_car and race_t < 3.0 and not _nitro_used:
		var gas: bool = veh.throttle > 0.5
		if gas and not _gas_prev:
			_gas_taps.append(race_t)
			if _gas_taps.size() >= 2 and _gas_taps[-1] - _gas_taps[-2] < 0.6:
				_nitro_used = true
				veh.nitro_t = 2.6
				main.hud.banner("NITRO!", Color(0.3, 0.8, 1.0), 1.2)
				main.audio.play("whoosh", veh.global_position, 4.0)
		_gas_prev = gas
	_draft_tick(dt)
	var n := checkpoints.size()
	# pilotos NPC
	for r in racers:
		var rc = r.car
		if not r.done and (not is_instance_valid(rc) or rc.dead):
			# adversário bateu/explodiu: renasce no último ponto que alcançou (fica a carcaça)
			r.dead_t += dt
			if r.dead_t > 3.0:
				r.dead_t = 0.0
				if is_instance_valid(rc):
					rc.remove_meta("job")
				var sp := _cp_spot(r.cp, r.lap, rng.randf_range(-2.5, 2.5))
				r.car = _racer_car(r, sp[0], sp[1])
			continue
		if r.done:
			if is_instance_valid(rc):
				rc.throttle = 0.0
				rc.brake_in = 0.6
			continue
		var tgt: Vector3 = checkpoints[r.cp % n]
		var nxt: Vector3 = checkpoints[(r.cp + 1) % n]
		# travado (bateu, trânsito na frente): ré girando; muito tempo preso e fora da vista = volta
		# para a pista no último ponto
		if rc.linear_velocity.length() < 1.2:
			r.st = r.get("st", 0.0) + dt
		else:
			r.st = 0.0
		if r.st > 6.0:
			# travado (poste, parede, outro carro): volta no último ponto com o carro inteiro
			r.st = 0.0
			var sp := _cp_spot(r.cp, r.lap, rng.randf_range(-2.5, 2.5))
			main.cars.erase(rc)
			rc.queue_free()
			r.car = _racer_car(r, sp[0], sp[1])
			r.car.hold = false
			continue
		drive_to(rc, _dodge(rc, tgt), nxt, race_top * r.skill)
		if Vector2(rc.global_position.x - tgt.x, rc.global_position.z - tgt.z).length() < 9.0:
			r.cp += 1
			if r.cp % n == 0:
				r.lap += 1
				if r.lap >= RACE_LAPS:
					r.done = true
					finish_order.append(rc)
	if veh != job_car:
		text = "Volte para o carro da corrida!"
		return
	var cp: Vector3 = checkpoints[cp_i % n]
	if Vector2(veh.global_position.x - cp.x, veh.global_position.z - cp.z).length() < 9.0:
		cp_i += 1
		main.audio.play("click")
		if cp_i % n == 0:
			laps += 1
			if laps >= RACE_LAPS:
				finish_order.append(veh)
				_race_finish()
				return
			main.hud.banner("VOLTA %d/%d" % [laps + 1, RACE_LAPS], Color(0.3, 0.8, 1.0), 1.5)
		_set_obj(checkpoints[cp_i % n], Color(0.2, 0.8, 1.0), 6.0)
	# posição
	var mine := _race_progress(laps, cp_i, veh.global_position)
	var place := 1 + finish_order.size()
	for r in racers:
		if is_instance_valid(r.car) and not r.done and _race_progress(r.lap, r.cp, r.car.global_position) > mine:
			place += 1
	text = "Volta %d/%d · %dº lugar · ponto %d/%d" % [mini(laps + 1, RACE_LAPS), RACE_LAPS, place, cp_i % n + 1, n] 

func _race_finish() -> void:
	var place: int = finish_order.find(job_car) + 1
	var prize: int = [0, 1000, 450, 150, 0][clampi(place, 0, 4)]
	reward = prize
	main.hud.banner("%dº LUGAR!" % place, Color(1, 0.85, 0.1) if place == 1 else Color(0.9, 0.9, 0.9), 3.0)
	_success()

## piloto NPC: mira no ponto (antecipando a curva) e reduz antes das esquinas
func drive_to(c, tgt: Vector3, nxt: Vector3, vmax: float) -> void:
	var dt := get_physics_process_delta_time()
	# travado (calçada, poste, outro carro): ré com o volante virado por 1,3 s
	var rv: float = c.get_meta("dt_rv", 0.0)
	if rv > 0.0:
		c.set_meta("dt_rv", rv - dt)
		c.throttle = -0.8
		c.brake_in = 0.0
		c.steer_in = c.get_meta("dt_rs", 1.0)
		return
	var st: float = c.get_meta("dt_st", 0.0)
	if c.linear_velocity.length() < 0.8 and absf(c.throttle) > 0.3:
		st += dt
	else:
		st = 0.0
	c.set_meta("dt_st", st)
	if st > 2.0:
		c.set_meta("dt_st", 0.0)
		c.set_meta("dt_rv", 1.3)
		var lp0: Vector3 = c.global_transform.basis.inverse() * (tgt - c.global_position)
		c.set_meta("dt_rs", -signf(lp0.x) if absf(lp0.x) > 0.5 else 1.0)
		return
	var to: Vector3 = tgt - c.global_position
	to.y = 0
	var dist := to.length()
	var aim := tgt
	if dist < 12.0:
		aim = tgt.lerp(nxt, clampf((12.0 - dist) / 12.0, 0.0, 0.35))
	var local: Vector3 = c.global_transform.basis.inverse() * (aim - c.global_position)
	var ang := atan2(local.x, local.z)
	c.steer_in = clampf(ang * 1.8, -1.0, 1.0)
	var turn: float = absf((nxt - tgt).normalized().signed_angle_to(to.normalized(), Vector3.UP)) if dist > 0.5 else 0.0
	var want: float = vmax
	if turn > 0.6:
		# velocidade que ainda dá para frear até a curva (≈7 m/s² de freio)
		var vc := lerpf(13.0, 8.0, clampf((turn - 0.6) / 1.2, 0.0, 1.0))
		want = minf(vmax, sqrt(vc * vc + 2.0 * 7.0 * maxf(0.0, dist - 9.0)))
	var fs: float = c.forward_speed()
	if local.z < -1.0 and fs < 2.0:
		c.throttle = -0.7          # ponto atrás: ré e gira
		c.steer_in = -c.steer_in
		c.brake_in = 0.0
	elif fs > want + 1.5:
		c.throttle = 0.0
		c.brake_in = clampf((fs - want) * 0.15, 0.2, 1.0)
	else:
		c.throttle = 1.0 if absf(ang) < 0.9 else 0.55
		c.brake_in = 0.0

# ---------------------------------------------------------------- fim
func _success() -> void:
	var r := reward
	main.money += r
	main.audio.play("cash")
	if r > 0 and active != "race":
		main.hud.banner("MISSÃO CUMPRIDA!  +$%d" % r, Color(1, 0.85, 0.1))
	elif active == "race" and r > 0:
		main.hud.banner("PRÊMIO DA CORRIDA  +$%d" % r, Color(1, 0.85, 0.1))
	done[active] = int(done.get(active, 0)) + 1
	if active.begins_with("gang_") and main.gangs:
		main.gangs.friendly_t[job_gang] = 600.0      # trégua com a gangue
	_cleanup()
	main.ui.save_game()

func fail(why: String) -> void:
	if active == "":
		return
	if active in ["taxi", "uber"]:
		_taxi_end()
		return
	main.hud.banner("MISSÃO FRACASSADA: " + why, Color(1, 0.25, 0.2))
	# morreu/preso no racha: os carros ficam onde estão até o renascer (o reinício do mundo apaga tudo)
	if active == "race" and main.combat.dead:
		for r in racers:
			if is_instance_valid(r.car):
				r.car.throttle = 0.0
				r.car.brake_in = 0.4
				r.car.draft = 0.0
		racers = []
		job_car = null
		_clear_obj()
		checkpoints = []
		active = ""
		text = ""
		timer = -1.0
		_text()
		return
	_cleanup()

func _cleanup() -> void:
	_clear_obj()
	timer = -1.0
	text = ""
	_text()
	if target_car and is_instance_valid(target_car) and target_car != main.player.vehicle:
		main.cars.erase(target_car)
		target_car.queue_free()
	target_car = null
	for t in thugs:
		if is_instance_valid(t) and not t.down:
			t.target = null
			t.get_tree().create_timer(10.0).timeout.connect(t.queue_free)
	thugs = []
	target_ped = null
	if job_car and is_instance_valid(job_car) and job_car.get("hold") != null:
		job_car.hold = false
		job_car.draft = 0.0
		job_car.nitro_t = 0.0
		var fx = job_car.get_meta("dr_fx", null)
		if fx and is_instance_valid(fx):
			fx.queue_free()
		job_car.remove_meta("dr_fx")
	in_draft = false
	# carro alugado/do trabalho e pilotos somem (o jogador desce antes)
	if job_car and is_instance_valid(job_car) and job_car.has_meta("job"):
		if main.player.vehicle == job_car:
			main.eject_player(Vector3.ZERO)
		main.cars.erase(job_car)
		job_car.queue_free()
	job_car = null
	for r in racers:
		if is_instance_valid(r.car):
			main.cars.erase(r.car)
			r.car.queue_free()
	racers = []
	checkpoints = []
	drops = []
	job_gang = ""
	active = ""

# ---------------------------------------------------------------- táxi / Uber (trabalhando)
## botão SERVIÇO no táxi, ou "Trabalhar de Uber" no celular (qualquer carro)
func start_fares(mode: String) -> void:
	if active != "" or main.player.vehicle == null:
		return
	active = mode
	taxi_state = ""
	main.hud.banner("CORRIDAS DE TÁXI" if mode == "taxi" else "UBER: AGUARDANDO PASSAGEIROS", Color(1, 0.85, 0.1))

func _taxi_tick(dt: float, veh) -> void:
	if active == "uber":
		_uber_tick(dt, veh)
		return
	var c = main.city
	var vp: Vector3 = veh.global_position
	if taxi_state == "":
		var best := _far_sidewalk(vp, 60.0, 180.0)
		passenger = Ped.new()
		main.add_child(passenger)
		passenger.setup([best, best + Vector3(0.01, 0, 0), best, best], 0, rng)
		passenger.speed = 0.0
		_set_obj(best, Color(1, 0.9, 0.1), 3.0)
		taxi_state = "pickup"
		timer = -1.0
		text = "Busque o passageiro (amarelo)"
		return
	if taxi_state == "pickup":
		if passenger == null or not is_instance_valid(passenger) or passenger.down:
			taxi_state = ""
			_clear_obj()
			return
		if vp.distance_to(passenger.global_position) < 7.5 and veh.linear_velocity.length() < 2.0:
			passenger.queue_free()
			passenger = null
			main.audio.play("door", vp)
			var dest := _far_sidewalk(vp, 120.0, 320.0)
			fare_from = vp
			_set_obj(dest, Color(0.2, 1.0, 0.3), 3.5)
			timer = vp.distance_to(dest) / 8.0 + 18.0
			taxi_state = "ride"
			text = "Leve o passageiro ao destino (verde)"
		return
	if taxi_state == "ride":
		if vp.distance_to(obj_pos) < 8.0 and veh.linear_velocity.length() < 2.0:
			var pay := int(15.0 + fare_from.distance_to(obj_pos) * 0.22 + maxf(timer, 0.0) * 0.8)
			if active == "uber":
				pay = int(pay * 0.85)          # a plataforma fica com 15%
			main.money += pay
			main.audio.play("cash")
			main.hud.banner("CORRIDA PAGA  +$%d" % pay, Color(1, 0.85, 0.1))
			var p2 := Ped.new()
			main.add_child(p2)
			var loop: Array = c.walk_loops[0]
			for l in c.walk_loops:
				if l[0].distance_to(vp) < loop[0].distance_to(vp):
					loop = l
			p2.setup(loop, 0, rng)
			p2.position = vp + veh.global_transform.basis.x * 2.2
			main.peds.append(p2)
			_end_fare()

# ---------------------------------------------------------------- Uber (trabalhando)
## pedidos aparecem na calçada; alguns passageiros já esperam lá, outros só descem quando você
## manda mensagem pelo app. No fim: avaliação (estrela/sorriso/confuso/bravo) muda os pontos de
## Uber, o valor das corridas e quantas aparecem.
const U_NAMES := ["Carla", "Rafael", "Bianca", "Diego", "Juliana", "Thiago", "Fernanda", "Lucas", "Patrícia", "Bruno", "Camila", "Gustavo", "Larissa", "Felipe", "Renata", "Marcos", "Aline", "Vinícius", "Tatiane", "Eduardo"]
const U_QUOTES := ["Gosto de música baixa.", "Pode ir pelo caminho mais rápido.", "Tenho pressa!", "Primeira vez no app.", "Sempre dou gorjeta.", "Prefiro motorista calado.", "Cuidado com as curvas, por favor.", "Vou com mala."]
const MSG_WAITING := ["Já estou aqui.", "Ok, estou aguardando.", "blz mano, já tô aqui.", "pdp, tô aqui."]
const MSG_COMING := ["certo, estou descendo!", "MDS, tô indo!", "blz, indo.", "blz, descendo.", "ok estou indo!", "indo."]
var uber := {}          # pedido atual
var uber_wait := 4.0    # tempo até o próximo pedido
var uber_chat: Array = []

func _uber_mult() -> float:
	return clampf(1.0 + float(main.uber_pts) / 150.0, 0.6, 1.8)

func _uber_new_request(vp: Vector3) -> void:
	var pos := _far_sidewalk(vp, 60.0, 230.0)
	var waiting := rng.randf() < 0.55
	uber = {"name": U_NAMES[rng.randi() % U_NAMES.size()], "rating": snappedf(rng.randf_range(3.9, 5.0), 0.1), "rides": rng.randi_range(2, 340),
		"quote": U_QUOTES[rng.randi() % U_QUOTES.size()], "pos": pos, "waiting": waiting, "ped": null, "state": "pickup",
		"told": false, "come_t": -1.0, "msg_sent": false}
	uber_chat = []
	if waiting:
		_uber_spawn_ped()
	_set_obj(pos, Color(1, 0.9, 0.1), 3.0)
	main.audio.play("click")
	main.hud.banner("UBER: %s (★%.1f) · %d m" % [uber.name, uber.rating, int(vp.distance_to(pos))], Color(0.3, 1.0, 0.5), 3.0)
	text = "Busque %s (amarelo) · abra o Uber no celular para mandar mensagem" % uber.name

func _uber_spawn_ped() -> void:
	var pos: Vector3 = uber.pos
	var p := Ped.new()
	main.add_child(p)
	p.setup([pos, pos + Vector3(0.01, 0, 0), pos, pos], 0, rng)
	p.speed = 0.0
	p.mode = "clerk"
	p.body.arm_pose = "wave"
	uber.ped = p

## mensagens do app
func uber_msg(kind: String) -> void:
	if uber.is_empty() or uber.state != "pickup":
		return
	var mine := "Estou a caminho, pode descer." if kind == "coming" else "Cheguei! Pode descer."
	uber_chat.append(["eu", mine])
	var reply := ""
	if uber.waiting or (uber.ped != null and is_instance_valid(uber.ped)):
		reply = MSG_WAITING[rng.randi() % MSG_WAITING.size()]
	else:
		reply = MSG_COMING[rng.randi() % MSG_COMING.size()]
		if uber.come_t < 0.0:
			uber.come_t = rng.randf_range(5.0, 10.0)      # demora um pouco para descer
	uber_chat.append([uber.name, reply])
	uber.msg_sent = true
	main.get_tree().create_timer(1.2, true).timeout.connect(func():
		main.audio.play("click")
		main.hud.banner("%s: %s" % [uber.get("name", ""), reply], Color(0.85, 0.95, 1.0), 3.0))

func uber_cancel() -> void:
	if uber.is_empty():
		return
	if uber.ped != null and is_instance_valid(uber.ped):
		uber.ped.queue_free()
	_clear_obj()
	uber = {}
	uber_wait = rng.randf_range(2.0, 5.0)
	main.uber_pts = maxi(-60, main.uber_pts - 1)
	text = "Uber: procurando outra corrida..."

func _uber_tick(dt: float, veh) -> void:
	var vp: Vector3 = veh.global_position
	if uber.is_empty():
		uber_wait -= dt
		text = "Uber: aguardando pedidos... (pontos %d)" % main.uber_pts
		if uber_wait <= 0.0:
			_uber_new_request(vp)
		return
	if uber.state == "pickup":
		# passageiro que não estava esperando desce depois da mensagem
		if uber.come_t >= 0.0:
			uber.come_t -= dt
			if uber.come_t < 0.0 and (uber.ped == null or not is_instance_valid(uber.ped)):
				_uber_spawn_ped()
				uber.come_t = -1.0
		var p = uber.ped
		var near: bool = Vector2(vp.x - uber.pos.x, vp.z - uber.pos.z).length() < 9.0
		if near and (p == null or not is_instance_valid(p)) and uber.come_t < 0.0:
			text = "Chegou! Mande mensagem pelo Uber (celular) para %s descer" % uber.name
		if p != null and is_instance_valid(p) and p.down:
			uber_cancel()
			return
		if p != null and is_instance_valid(p) and vp.distance_to(p.global_position) < 7.5 and veh.linear_velocity.length() < 2.0:
			p.queue_free()
			uber.ped = null
			main.audio.play("door", vp)
			var dest := _far_sidewalk(vp, 120.0, 360.0)
			uber.dest = dest
			uber.from = vp
			uber.t = 0.0
			uber.exp_t = vp.distance_to(dest) / 9.0 + 20.0
			uber.hp0 = veh.get("hp") if veh.get("hp") != null else 100.0
			uber.hits = 0
			uber.crashes = 0
			uber.last_hp = uber.hp0
			uber.stars0 = main.wanted
			uber.state = "ride"
			_set_obj(dest, Color(0.2, 1.0, 0.3), 3.5)
			text = "Leve %s ao destino (verde)" % uber.name
		return
	if uber.state == "ride":
		uber.t += dt
		var hpn: float = veh.get("hp") if veh.get("hp") != null else 100.0
		if hpn < uber.last_hp - 1.5:
			uber.crashes += 1
		uber.last_hp = hpn
		text = "Leve %s ao destino (verde) · %d s" % [uber.name, int(uber.t)]
		if vp.distance_to(obj_pos) < 8.0 and veh.linear_velocity.length() < 2.0:
			_uber_finish(veh)

func _uber_finish(veh) -> void:
	var score := 100.0
	score -= uber.crashes * 12.0
	score -= maxf(0.0, uber.hp0 - (veh.get("hp") if veh.get("hp") != null else 100.0)) * 0.6
	score -= maxf(0.0, uber.t - uber.exp_t) * 1.2
	if main.wanted > uber.stars0:
		score -= 35.0
	var icon := "angry"
	var dpts := -10
	if score >= 88.0:
		icon = "star"
		dpts = 8
	elif score >= 65.0:
		icon = "smile"
		dpts = 5
	elif score >= 40.0:
		icon = "confused"
		dpts = -4
	main.uber_pts = clampi(main.uber_pts + dpts, -60, 300)
	var pay := int((15.0 + uber.from.distance_to(uber.dest) * 0.22) * 0.85 * _uber_mult())
	var tip := 0
	if icon == "star":
		tip = rng.randi_range(15, 110)
	main.money += pay + tip
	main.audio.play("cash")
	main.hud.rating_icon = icon
	main.hud.rating_t = 4.5
	main.hud.banner("CORRIDA PAGA  +$%d%s" % [pay, ("  · gorjeta +$%d" % tip) if tip > 0 else ""], Color(1, 0.85, 0.1))
	# passageiro desce na calçada
	var p2 := Ped.new()
	main.add_child(p2)
	var loop: Array = main.city.walk_loops[0]
	for l in main.city.walk_loops:
		if l[0].distance_to(veh.global_position) < loop[0].distance_to(veh.global_position):
			loop = l
	p2.setup(loop, 0, rng)
	p2.position = veh.global_position + veh.global_transform.basis.x * 2.2
	main.peds.append(p2)
	_clear_obj()
	uber = {}
	# avaliação ruim = menos pedidos (espera maior)
	uber_wait = rng.randf_range(3.0, 7.0) if main.uber_pts >= 0 else rng.randf_range(10.0, 25.0)
	main.ui.save_game()

func _end_fare() -> void:
	if not uber.is_empty():
		if uber.get("ped") != null and is_instance_valid(uber.ped):
			uber.ped.queue_free()
		uber = {}
	_clear_obj()
	timer = -1.0
	taxi_state = ""
	if passenger and is_instance_valid(passenger):
		passenger.queue_free()
	passenger = null

func _taxi_end() -> void:
	_end_fare()
	active = ""
	text = ""
	_text()

# ---------------------------------------------------------------- Uber como passageiro
var ride := {}        # {car, dest, path, i, state, fare}
func request_ride(dest: Vector3, name: String) -> void:
	if not ride.is_empty() or main.player.vehicle != null:
		return
	var pp: Vector3 = main.player.global_position
	# carro aparece numa rua a ~70 m e vem até você
	var path: PackedVector3Array = PackedVector3Array()
	var start := pp
	for k in 12:
		var cand: Vector3 = pp + Vector3(rng.randf_range(-90, 90), 0, rng.randf_range(-90, 90))
		var rp: PackedVector3Array = main.route_path(main.road_snap(cand), main.road_snap(pp))
		if rp.size() > 1 and rp[0].distance_to(pp) > 45.0:
			path = rp
			start = rp[0]
			break
	if path.size() < 2:
		path = main.route_path(main.road_snap(pp + Vector3(60, 0, 0)), main.road_snap(pp))
		start = path[0] if path.size() > 0 else pp + Vector3(60, 0, 0)
	var dir: Vector3 = (path[1] - path[0]).normalized() if path.size() > 1 else Vector3.FORWARD
	var car = main._spawn_car(start + Vector3(0, 0.8, 0), atan2(dir.x, dir.z), Color(0.12, 0.12, 0.13), false, "sedan")
	car.set_meta("uber", true)
	main.seat_npc(car)
	ride = {"car": car, "dest": dest, "name": name, "path": path, "i": 1, "state": "coming", "fare": 0}
	main.hud.banner("UBER A CAMINHO · destino: %s" % name, Color(0.9, 0.9, 0.9), 3.0)

func ride_car():
	return ride.get("car") if not ride.is_empty() else null

## o jogador tocou ENTRAR perto do carro do Uber
func board_ride() -> void:
	var car = ride.car
	main.enter_as_passenger(car)
	var path: PackedVector3Array = main.route_path(main.road_snap(car.global_position), main.road_snap(ride.dest))
	ride.path = path
	ride.i = 1
	ride.state = "riding"
	ride.from = car.global_position
	main.audio.play("door", car.global_position)

func end_ride(arrived: bool) -> void:
	if ride.is_empty():
		return
	var car = ride.car
	if is_instance_valid(car):
		var dist: float = ride.get("from", car.global_position).distance_to(car.global_position)
		if ride.state == "riding":
			var fare := int(10.0 + dist * 0.3)
			main.money = maxi(0, main.money - fare)
			main.hud.banner(("Você chegou: %s · Uber $%d" % [ride.name, fare]) if arrived else "Corrida encerrada · Uber $%d" % fare, Color(0.9, 0.9, 0.9), 3.0)
		if main.player.vehicle == car:
			main.leave_passenger()
		var cc = car
		get_tree().create_timer(12.0).timeout.connect(func(): if is_instance_valid(cc) and cc != main.player.vehicle: main.cars.erase(cc); cc.queue_free())
		car.throttle = 0.0
		car.brake_in = 1.0
	ride = {}

func _ride_tick(dt: float) -> void:
	if ride.is_empty():
		return
	var car = ride.car
	if not is_instance_valid(car) or car.dead:
		if main.player.vehicle == car:
			main.leave_passenger()
		ride = {}
		return
	var path: PackedVector3Array = ride.path
	var goal: Vector3 = main.road_snap(main.player.global_position if ride.state == "coming" else ride.dest)
	if ride.i >= path.size():
		var d: float = Vector2(car.global_position.x - goal.x, car.global_position.z - goal.z).length()
		if d > 6.0:
			drive_to(car, goal, goal, 8.0)
			return
		car.throttle = 0.0
		car.brake_in = 1.0
		if ride.state == "riding" and car.linear_velocity.length() < 1.0:
			end_ride(true)
		return
	var tgt: Vector3 = path[ride.i]
	var nxt: Vector3 = path[mini(ride.i + 1, path.size() - 1)]
	drive_to(car, tgt, nxt, 13.0)
	if Vector2(car.global_position.x - tgt.x, car.global_position.z - tgt.z).length() < 6.0:
		ride.i += 1

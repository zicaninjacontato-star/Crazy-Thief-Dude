extends Node
## Táxi e missões.
## - Táxi: dentro de um táxi, busque passageiros (marcador amarelo) e leve ao destino antes do tempo.
## - Missões (marcadores "M" amarelos na cidade):
##   ENTREGA QUENTE: roube o esportivo marcado e leve à garagem antes do tempo (alarme: 2 estrelas).
##   ACERTO DE CONTAS: elimine o alvo protegido por capangas armados.
##   CORRIDA DE RUA: passe por todos os pontos de controle com um veículo antes do tempo.

const Ped := preload("res://scripts/ped.gd")
const Cop := preload("res://scripts/cop.gd")
const W2 := preload("res://scripts/world2.gd")

var main: Node3D
var active := ""
var givers: Array = []         # {id, name, pos, node, label}
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

const INFO := {
	"delivery": {"name": "ENTREGA QUENTE", "reward": 900},
	"hit": {"name": "ACERTO DE CONTAS", "reward": 1200},
	"race": {"name": "CORRIDA DE RUA", "reward": 700},
}

func setup(m: Node3D) -> void:
	main = m
	rng.seed = 2024
	var c = main.city
	var spots := {"delivery": Vector3(c._center(0) + c.BLOCK * 0.5 - 1.6, 0.15, c._center(0)),
		"hit": Vector3(c._center(4) - c.BLOCK * 0.5 + 1.6, 0.15, c._center(1)),
		"race": Vector3(c._center(1), 0.15, c._center(4) - c.BLOCK * 0.5 + 1.6)}
	for id in spots:
		var pos: Vector3 = spots[id]
		var mk := W2.marker(main, pos, Color(1.0, 0.8, 0.1), 0.9)
		var lb := Label3D.new()
		lb.text = "M"
		lb.font_size = 160
		lb.pixel_size = 0.01
		lb.modulate = Color(1, 0.85, 0.2)
		lb.outline_size = 14
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.shaded = false
		main.add_child(lb)
		lb.global_position = pos + Vector3(0, 3.2, 0)
		givers.append({"id": id, "pos": pos, "node": mk, "label": lb})
	garage = Vector3(c._center(4) + c.CELL * 0.5 + 2.6, 0.15, c._center(4))

func hostiles() -> Array:
	thugs = thugs.filter(func(t): return is_instance_valid(t))
	return thugs

## pontos para o minimapa: [{pos, col}]
func blips() -> Array:
	var b := []
	if active == "":
		for g in givers:
			b.append({"pos": g.pos, "col": Color(1, 0.8, 0.1)})
	if obj_pos != Vector3.INF:
		b.append({"pos": obj_pos, "col": Color(1, 0.95, 0.2)})
	for t in hostiles():
		if not t.down:
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
	if timer > 0.0:
		timer -= dt
		if timer <= 0.0:
			if active == "taxi":
				main._msg("O passageiro desistiu da corrida")
				_end_fare()
			else:
				fail("Tempo esgotado")
				return
	# táxi: liga ao entrar num táxi, desliga ao sair
	if veh != null and veh.get("kind") == "taxi" and active == "":
		active = "taxi"
		taxi_state = ""
		main.hud.banner("CORRIDAS DE TÁXI", Color(1, 0.85, 0.1))
	if active == "taxi":
		if veh == null or veh.get("kind") != "taxi":
			_taxi_end()
		else:
			_taxi_tick(dt, veh)
		_text()
		return
	if active == "":
		for g in givers:
			if p.global_position.distance_to(g.pos) < 2.6 and not main.combat.dead:
				_start(g.id)
				_text()
				return
		text = ""
		return
	match active:
		"delivery": _delivery_tick(veh)
		"hit": _hit_tick()
		"race": _race_tick(veh)
	_text()

func _text() -> void:
	main.hud.mission_text = text
	main.hud.mission_timer = timer

func _start(id: String) -> void:
	var p = main.player
	if id == "race" and p.vehicle == null:
		main._msg("CORRIDA DE RUA: venha com um veículo")
		return
	active = id
	reward = INFO[id].reward
	main.hud.banner(INFO[id].name, Color(1, 0.85, 0.1))
	main.audio.play("cash")
	var c = main.city
	match id:
		"delivery":
			var road: float = c._center(0) - c.CELL * 0.5
			target_car = main._spawn_car(Vector3(road + 5.9, 0.7, c._center(3)), 0.0, Color(0.85, 0.05, 0.05), false, "sport")
			text = "Roube o esportivo vermelho"
			timer = -1.0
		"hit":
			var base := Vector3(c._center(3), 0.2, c._center(4))
			target_ped = Cop.new()
			main.add_child(target_ped)
			target_ped.setup(rng.randi(), "thug")
			target_ped.global_position = base
			target_ped.hp = 140.0
			thugs = [target_ped]
			for k in 3:
				var t := Cop.new()
				main.add_child(t)
				t.setup(rng.randi(), "thug")
				t.global_position = base + Vector3(cos(k * 2.1) * 3.0, 0, sin(k * 2.1) * 3.0)
				thugs.append(t)
			for t in thugs:
				t.shot_player.connect(main.combat._on_cop_shot)
				t.pref = rng.randf_range(6.0, 12.0)
			text = "Elimine o alvo (marcado em vermelho)"
			timer = 180.0
		"race":
			checkpoints = []
			for q in [[1, 4], [4, 4], [4, 0], [0, 0], [0, 3], [2, 3], [2, 1], [1, 1]]:
				var x: float = c._center(q[0]) - c.CELL * 0.5
				var z: float = c._center(q[1]) - c.CELL * 0.5
				checkpoints.append(Vector3(x, 0.1, z))
			cp_i = 0
			_set_obj(checkpoints[0], Color(0.2, 0.8, 1.0), 6.0)
			timer = 110.0
			text = "Ponto 1/%d" % checkpoints.size()

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
		main._msg("Alarme disparou! Leve o carro à garagem")
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
	for t in hostiles():
		if not t.down:
			t.target = main.player.vehicle if main.player.vehicle else p
			if t.global_position.distance_to(p.global_position) > 28.0 and t != target_ped:
				t.target = null
	if target_ped == null or not is_instance_valid(target_ped) or target_ped.down:
		_success()
		return
	obj_pos = target_ped.global_position
	text = "Elimine o alvo (vermelho no mapa)"
	if target_ped.global_position.distance_to(p.global_position) > 28.0:
		target_ped.target = null

func on_kill(t) -> void:
	if active == "hit" and t == target_ped:
		_success()

func _race_tick(veh) -> void:
	if veh == null:
		text = "Volte para o veículo!"
		return
	var cp: Vector3 = checkpoints[cp_i]
	if Vector2(veh.global_position.x - cp.x, veh.global_position.z - cp.z).length() < 7.0:
		cp_i += 1
		main.audio.play("cash")
		if cp_i >= checkpoints.size():
			_clear_obj()
			_success()
			return
		_set_obj(checkpoints[cp_i], Color(0.2, 0.8, 1.0), 6.0)
	text = "Ponto %d/%d" % [cp_i + 1, checkpoints.size()]

func _success() -> void:
	var r := reward
	main.money += r
	main.audio.play("cash")
	main.hud.banner("MISSÃO CUMPRIDA!  +$%d" % r, Color(1, 0.85, 0.1))
	done[active] = true
	_cleanup()
	main.ui.save_game()

func fail(why: String) -> void:
	if active == "" :
		return
	if active == "taxi":
		_taxi_end()
		return
	main.hud.banner("MISSÃO FRACASSADA: " + why, Color(1, 0.25, 0.2))
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
	for t in hostiles():
		if not t.down:
			t.target = null
			t.get_tree().create_timer(10.0).timeout.connect(t.queue_free)
	thugs = []
	target_ped = null
	active = ""

# ---------------------------------------------------------------- táxi
func _taxi_tick(dt: float, veh) -> void:
	var c = main.city
	var vp: Vector3 = veh.global_position
	if taxi_state == "":
		# novo passageiro numa calçada a 60-180 m
		var best := Vector3.ZERO
		for k in 20:
			var loop: Array = c.walk_loops[rng.randi() % c.walk_loops.size()]
			var pt: Vector3 = loop[rng.randi() % 4].lerp(loop[rng.randi() % 4], 0.5)
			var d := pt.distance_to(vp)
			if d > 60.0 and d < 180.0:
				best = pt
				break
		if best == Vector3.ZERO:
			return
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
			# destino a 120-320 m
			var dest := Vector3.ZERO
			for k in 30:
				var loop: Array = c.walk_loops[rng.randi() % c.walk_loops.size()]
				var pt: Vector3 = loop[rng.randi() % 4].lerp(loop[rng.randi() % 4], 0.5)
				var d := pt.distance_to(vp)
				if d > 120.0 and d < 320.0:
					dest = pt
					break
			if dest == Vector3.ZERO:
				dest = c.hospital_pos
			fare_from = vp
			_set_obj(dest, Color(0.2, 1.0, 0.3), 3.5)
			timer = vp.distance_to(dest) / 8.0 + 18.0
			taxi_state = "ride"
			text = "Leve o passageiro ao destino (verde)"
		return
	if taxi_state == "ride":
		if vp.distance_to(obj_pos) < 8.0 and veh.linear_velocity.length() < 2.0:
			var pay := int(15.0 + fare_from.distance_to(obj_pos) * 0.22 + maxf(timer, 0.0) * 0.8)
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

func _end_fare() -> void:
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

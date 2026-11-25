extends Node
## Animações de entrar e sair de TODOS os veículos.
## Carro/táxi/viatura/ônibus/picape: anda até a porta → porta abre → senta (o corpo desliza para o banco) → porta fecha.
## Moto: anda até o lado → pulo para o banco. Barco: pulo para dentro. Avião/helicóptero: sobe na cabine.
## Sair: o inverso. Os controles ficam travados durante a animação.

var main: Node3D
var state := ""            # "", "walk", "open", "in", "close", "x_open", "x_out", "x_close"
var car = null
var t := 0.0
var dur := 0.0
var seated: Node3D
var _from := Vector3.ZERO  # local do veículo
var _to := Vector3.ZERO
var _door_pt := Vector3.ZERO
var _walk_t := 0.0

func busy() -> bool:
	return state != ""

func _has_door(c) -> bool:
	return c.get("door_node") != null

func _kind(c) -> String:
	return str(c.get("kind"))

func _local_door(c) -> Vector3:
	return c.global_transform.affine_inverse() * c.door_world()

# ---------------------------------------------------------------- entrar
func start_enter(c) -> void:
	car = c
	state = "walk"
	t = 0.0
	_walk_t = 0.0
	_door_pt = c.door_world()
	main.player.velocity = Vector3.ZERO

func start_exit(c) -> void:
	car = c
	seated = main.seated
	t = 0.0
	state = "x_open"
	dur = 0.3 if _has_door(c) else 0.01

func tick(dt: float) -> void:
	if state == "":
		return
	if car == null or not is_instance_valid(car):
		state = ""
		return
	t += dt
	var p = main.player
	match state:
		"walk":
			var dp: Vector3 = car.door_world()
			var to: Vector3 = dp - p.global_position
			to.y = 0
			_walk_t += dt
			if to.length() < 0.35 or _walk_t > 2.2:
				_begin_in()
				return
			var v := to.normalized() * minf(4.5, to.length() * 6.0)
			p.velocity = Vector3(v.x, p.velocity.y - 18.0 * dt, v.z)
			p.move_and_slide()
			p.body.rotation.y = atan2(to.x, to.z)
			p.body.animate(v.length(), dt)
		"open":
			car.set_door(clampf(t / dur, 0.0, 1.0))
			if t >= dur:
				_go("in", 0.55 if _kind(car) not in ["plane", "heli"] else 0.8)
		"in":
			var k := clampf(t / dur, 0.0, 1.0)
			var e := k * k * (3.0 - 2.0 * k)
			var pos := _from.lerp(_to, e)
			var kind := _kind(car)
			if kind in ["moto", "boat"]:
				pos.y += sin(k * PI) * (0.55 if kind == "moto" else 0.9)
			seated.position = pos
			if k > 0.45 and not seated.sitting:
				seated.sitting = true
				seated.animate(0, 0)
			if t >= dur:
				seated.position = _to
				_go("close", 0.3 if _has_door(car) else 0.01)
		"close":
			car.set_door(1.0 - clampf(t / dur, 0.0, 1.0))
			if t >= dur:
				car.set_door(0.0)
				state = ""
				main.anim_done()
		"x_open":
			car.set_door(clampf(t / dur, 0.0, 1.0))
			if t >= dur:
				_from = seated.position
				_to = _local_door(car)
				if _kind(car) == "boat":
					_to.y = seated.position.y
				_go("x_out", 0.5 if _kind(car) not in ["plane", "heli"] else 0.75)
		"x_out":
			var k := clampf(t / dur, 0.0, 1.0)
			var e := k * k * (3.0 - 2.0 * k)
			var pos := _from.lerp(_to, e)
			if _kind(car) in ["moto", "boat"]:
				pos.y += sin(k * PI) * 0.5
			seated.position = pos
			if k > 0.4 and seated.sitting:
				seated.sitting = false
				seated.animate(0.1, 0.0)
			if t >= dur:
				main.finish_exit(car, car.door_world())
				_go("x_close", 0.3 if _has_door(car) else 0.01)
		"x_close":
			car.set_door(1.0 - clampf(t / dur, 0.0, 1.0))
			if t >= dur:
				car.set_door(0.0)
				state = ""

func _begin_in() -> void:
	var p = main.player
	seated = main.finish_enter(car)
	# começa de pé na porta (coordenadas locais do veículo) e desliza para o banco
	_from = _local_door(car)
	if _kind(car) == "boat":
		_from.y = 0.6
	_to = seated.position
	seated.position = _from
	seated.sitting = false
	seated.rotation.y = 0.0
	seated.animate(0, 0)
	if _has_door(car):
		_go("open", 0.3)
	else:
		_go("in", 0.45 if _kind(car) != "boat" else 0.6)
	main.audio.play("door", car.global_position)

func _go(s: String, d: float) -> void:
	state = s
	t = 0.0
	dur = d

## sai na hora (morte, derrubada, missão): sem animação
func cancel() -> void:
	state = ""
	if car and is_instance_valid(car):
		car.set_door(0.0)

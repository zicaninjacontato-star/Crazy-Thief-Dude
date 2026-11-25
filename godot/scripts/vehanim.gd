extends Node
## Animações de entrar e sair de TODOS os veículos.
## Entrar num carro: anda até a porta → (trancado e vazio: quebra o vidro com o cotovelo OU mixa na
## maçaneta, sorteado) → a porta de verdade (recortada da carroceria) abre → se houver motorista, o
## jogador o puxa para fora (ele cai/foge; morto vira corpo) → entra deslizando para o banco → fecha.
## Moto: derruba o piloto (se houver) e monta com um pulo. Barco: pula para dentro. Avião/heli: sobe.
## Sair: o inverso. Os controles ficam travados durante a animação.

const Ped := preload("res://scripts/ped.gd")
const FX := preload("res://scripts/fx.gd")

var main: Node3D
var state := ""
var car = null
var t := 0.0
var dur := 0.0
var seated: Node3D
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _walk_t := 0.0
var drv_info := {}         # motorista a ser retirado {drv, cols, dead}
var _drv_from := Vector3.ZERO
var _drv_to := Vector3.ZERO
var rng := RandomNumberGenerator.new()

func busy() -> bool:
	return state != ""

func _has_door(c) -> bool:
	return c.get("door_node") != null

func _kind(c) -> String:
	return str(c.get("kind"))

func _local_door(c) -> Vector3:
	return c.global_transform.affine_inverse() * c.door_world()

# ---------------------------------------------------------------- entrar
func start_enter(c, info := {}) -> void:
	car = c
	drv_info = info
	state = "walk"
	t = 0.0
	_walk_t = 0.0
	main.player.velocity = Vector3.ZERO

func start_exit(c) -> void:
	car = c
	seated = main.seated
	t = 0.0
	state = "x_open"
	dur = 0.3 if _has_door(c) else 0.01
	# carro afundado: chuta a porta ou quebra o vidro para sair nadando
	if c.has_meta("sink_t") and c.global_position.y + 0.8 < main.world2.WATER_Y:
		state = "x_kick"
		dur = 1.2
		seated.pose = "kick"

func _go(s: String, d: float) -> void:
	state = s
	t = 0.0
	dur = d

func tick(dt: float) -> void:
	if state == "":
		return
	if car == null or not is_instance_valid(car):
		state = ""
		if main.player.body:
			main.player.body.pose = ""
		return
	t += dt
	var p = main.player
	var k := clampf(t / maxf(dur, 0.001), 0.0, 1.0)
	match state:
		"walk":
			var dp: Vector3 = car.door_world()
			var to: Vector3 = dp - p.global_position
			to.y = 0
			_walk_t += dt
			if to.length() < 0.35 or _walk_t > 2.2:
				_at_door()
				return
			var v := to.normalized() * minf(4.5, to.length() * 6.0)
			p.velocity = Vector3(v.x, p.velocity.y - 18.0 * dt, v.z)
			p.move_and_slide()
			p.body.rotation.y = atan2(to.x, to.z)
			p.body.animate(v.length(), dt)
		"force":
			# quebrando o vidro (cotovelo) ou mixa na maçaneta
			p.body.pose_t = k
			p.body.animate(0, dt)
			if p.body.pose == "break" and t >= dur * 0.5 and not car.unlocked:
				car.unlocked = true
				FX.sparks(main, car.global_transform * Vector3(car.body_size.x * 0.5, 1.15, car.seat.z))
				main.audio.play("crash", car.global_position, -4.0)
				if main.police.seen_by_cop(car.global_position):
					main._add_wanted(1)
			if t >= dur:
				car.unlocked = true
				p.body.pose = ""
				_open_door()
		"open0":
			car.set_door(k)
			p.body.animate(0, dt)
			if t >= dur:
				if not drv_info.is_empty() and is_instance_valid(drv_info.get("drv")):
					_begin_pull()
				else:
					_begin_in()
		"pull":
			p.body.pose = "pull"
			p.body.pose_t = k
			p.body.animate(0, dt)
			var h: Node3D = drv_info.drv
			if is_instance_valid(h):
				h.global_position = _drv_from.lerp(_drv_to, k) + Vector3(0, sin(k * PI) * 0.25, 0)
				if k > 0.35 and h.sitting:
					h.sitting = false
					h.slumped = false
				h.animate(0.5 if k < 0.8 else 0.0, dt)
			if t >= dur:
				p.body.pose = ""
				_drop_driver()
				_begin_in()
		"in":
			var e := k * k * (3.0 - 2.0 * k)
			var pos := _from.lerp(_to, e)
			var kind := _kind(car)
			if kind in ["moto", "boat"]:
				pos.y += sin(k * PI) * (0.55 if kind == "moto" else 0.9)
			elif kind in ["plane", "heli"]:
				pos.y = lerpf(_from.y, _to.y, minf(1.0, k * 1.5))
			seated.position = pos
			if k > 0.45 and not seated.sitting:
				seated.sitting = true
				seated.animate(0, 0)
			if t >= dur:
				seated.position = _to
				_go("close", 0.3 if _has_door(car) else 0.01)
		"close":
			car.set_door(1.0 - k)
			if t >= dur:
				car.set_door(0.0)
				state = ""
				main.anim_done()
		"x_kick":
			seated.pose_t = k
			seated.animate(0, dt)
			if t >= dur:
				seated.pose = ""
				if _has_door(car) and rng.randf() < 0.6:
					car.set_door(1.0)
					main.audio.play("kick", car.global_position, 4.0)
				else:
					main.audio.play("glass", car.global_position, 2.0)
					FX.sparks(main, car.global_transform * Vector3(car.body_size.x * 0.5, 1.1, car.seat.z))
				FX.splash(main, car.global_position + Vector3(0, 1.2, 0), 0.6)
				main.finish_exit(car, car.door_world() + Vector3(0, 0.6, 0))
				state = ""
		"x_open":
			car.set_door(k)
			if t >= dur:
				_from = seated.position
				_to = _local_door(car)
				if _kind(car) == "boat":
					_to.y = seated.position.y
				_go("x_out", 0.5 if _kind(car) not in ["plane", "heli"] else 0.75)
		"x_out":
			var e2 := k * k * (3.0 - 2.0 * k)
			var pos2 := _from.lerp(_to, e2)
			if _kind(car) in ["moto", "boat"]:
				pos2.y += sin(k * PI) * 0.5
			seated.position = pos2
			if k > 0.4 and seated.sitting:
				seated.sitting = false
				seated.animate(0.1, 0.0)
			if t >= dur:
				main.finish_exit(car, car.door_world())
				_go("x_close", 0.3 if _has_door(car) else 0.01)
		"x_close":
			car.set_door(1.0 - k)
			if t >= dur:
				car.set_door(0.0)
				state = ""

## na porta: moto com piloto = derruba; carro vazio trancado = força a entrada; senão abre
func _at_door() -> void:
	var p = main.player
	p.velocity = Vector3.ZERO
	var dp: Vector3 = car.global_position - p.global_position
	p.body.rotation.y = atan2(dp.x, dp.z)
	var kind := _kind(car)
	if kind == "moto":
		if not drv_info.is_empty():
			var fake := {"car": car, "drv": drv_info.drv, "cols": drv_info.cols}
			main.traffic_sys.eject_rider_agent(fake, drv_info.dead)
			drv_info = {}
		if car.get("down"):
			car.down = false
			car.global_transform = Transform3D(Basis(Vector3.UP, car.rotation.y), car.global_position + Vector3(0, 0.4, 0))
		_begin_in()
		return
	if not _has_door(car):
		_begin_in()
		return
	if drv_info.is_empty() and not car.get("unlocked"):
		p.body.pose = "break" if rng.randf() < 0.5 else "lockpick"
		_go("force", 0.7 if p.body.pose == "break" else 1.3)
		return
	_open_door()

func _open_door() -> void:
	main.audio.play("door", car.global_position)
	_go("open0", 0.35)

func _begin_pull() -> void:
	var h: Node3D = drv_info.drv
	var gt := h.global_transform
	h.get_parent().remove_child(h)
	main.add_child(h)
	h.global_transform = gt
	_drv_from = h.global_position
	var out: Vector3 = car.global_transform.basis.x
	_drv_to = car.door_world() + out * 1.0 + car.global_transform.basis.z * 0.6
	_drv_to.y = main.player.global_position.y
	h.rotation.y = atan2(out.x, out.z)
	main.audio.play("scream", h.global_position, -4.0)
	_go("pull", 1.0)

## motorista retirado: cai no chão (vivo foge depois; morto vira corpo)
func _drop_driver() -> void:
	var h: Node3D = drv_info.get("drv")
	if not is_instance_valid(h):
		drv_info = {}
		return
	var pos := h.global_position
	var q = Ped.new()
	main.add_child(q)
	var loop: Array = main.city.walk_loops[0]
	for l in main.city.walk_loops:
		if l[0].distance_to(pos) < loop[0].distance_to(pos):
			loop = l
	q.setup(loop, 0, rng)
	q._cols = drv_info.cols.duplicate()
	q.body.queue_free()
	q._make_body()
	q.global_position = pos
	q.died.connect(main._on_ped_died)
	main.peds.append(q)
	var push: Vector3 = car.global_transform.basis.x * 2.5 + Vector3(0, 1.0, 0)
	if drv_info.dead:
		q.hit(null, push, false)
	else:
		q.knock(push, 5.0)
		q.flee = 12.0
	h.queue_free()
	drv_info = {}

func _begin_in() -> void:
	var p = main.player
	p.body.pose = ""
	seated = main.finish_enter(car)
	_from = _local_door(car)
	if _kind(car) == "boat":
		_from.y = 0.6
	_to = seated.position
	seated.position = _from
	seated.sitting = false
	seated.rotation.y = 0.0
	seated.animate(0, 0)
	if _has_door(car) and car.door_open < 0.5:
		car.set_door(1.0)
	_go("in", 0.55 if _kind(car) not in ["plane", "heli"] else 0.8)

## sai na hora (morte, derrubada, missão): sem animação
func cancel() -> void:
	state = ""
	if main.player.body:
		main.player.body.pose = ""
	if car and is_instance_valid(car):
		car.set_door(0.0)

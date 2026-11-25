extends VehicleBody3D
## Carro com física real do Godot (suspensão por roda, atrito, transferência de peso).
## Modelo gerado por código (carmodel.gd).

const M := preload("res://scripts/mats.gd")
const CarModel := preload("res://scripts/carmodel.gd")
const VehModel := preload("res://scripts/vehmodel.gd")
const FX := preload("res://scripts/fx.gd")

var throttle := 0.0     # -1..1 (negativo = ré)
var brake_in := 0.0     # 0..1
var steer_in := 0.0     # -1..1 (positivo = esquerda)
var handbrake := false
var max_engine := 5200.0
var max_brake := 60.0
var max_steer := 0.52
var police := false
var ai_target: Node3D = null
var driver: Node = null
var _lights: Array = []
var _t := 0.0
var wheels: Array = []
var body_size := Vector3(1.8, 1.4, 4.6)
var seat := Vector3(0.38, 0.5, 0.0)
var _flip_t := 0.0
var kind := "sedan"
var spin: Array = []        # rodas visuais que giram sozinhas (moto)
var fork: Node3D            # garfo da moto (esterça)
var lean: Node3D            # inclinação visual da moto
var wheel_r := 0.33
# dano / batidas / destruição
signal crashed(car, dv)
signal destroyed(car)
var hp := 100.0
var dead := false
var _lastv := Vector3.ZERO
var _crash_cd := 0.0
var _fire_t := -1.0
var model_root: Node3D
var _smoke: CPUParticles3D
var _fire: CPUParticles3D
var paint_c := Color.WHITE
# porta do motorista (abre na animação de entrar/sair)
var door_info := {}
var door_node: Node3D
var door_cover: MeshInstance3D
var door_open := 0.0
var parked := false

## kind: sedan, hatch, suv, pickup, sport ou police (modelo gerado por carmodel.gd).
func setup(kind: String, paint: Color) -> void:
	police = kind == "police"
	self.kind = kind
	var built: Dictionary = VehModel.build(kind, paint) if kind in ["moto", "bus"] else CarModel.build(kind, paint)
	var size: Vector3 = built.size
	mass = 1350.0 if size.z < 4.8 else 1700.0
	spin = built.get("spin", [])
	fork = built.get("fork")
	lean = built.get("lean")
	wheel_r = built.wr
	if kind == "moto":
		mass = 260.0
		max_engine = 1350.0
		max_brake = 14.0
		max_steer = 0.42
	elif kind == "bus":
		mass = 9000.0
		max_engine = 26000.0
		max_brake = 380.0
		max_steer = 0.5
	can_sleep = false
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	# centro de massa abaixo do eixo das rodas: o carro inclina mas não capota em curva normal
	center_of_mass = Vector3(0, 0.05, 0.05)
	angular_damp = 0.8
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(size.x - 0.1, 0.7, size.z - 0.1)
	cs.shape = bx
	cs.position = Vector3(0, 0.7, 0)
	add_child(cs)
	var cs2 := CollisionShape3D.new()
	var bx2 := BoxShape3D.new()
	bx2.size = Vector3(size.x * 0.78, maxf(0.3, size.y - 1.05), size.z * 0.42)
	cs2.shape = bx2
	cs2.position = Vector3(0, 1.05 + bx2.size.y * 0.5, -0.1)
	add_child(cs2)
	body_size = size
	seat = built.seat
	add_child(built.root)
	model_root = built.root
	paint_c = built.get("paint", paint)
	door_info = built.get("door", {})
	if not door_info.is_empty():
		_make_door()
	var wr: float = built.wr
	for wd in built.wheels:
		var w := VehicleWheel3D.new()
		var p: Vector3 = wd.pos
		w.position = Vector3(p.x, p.y + 0.14, p.z)
		w.wheel_radius = wr
		w.wheel_rest_length = 0.14
		w.suspension_travel = 0.2
		w.suspension_stiffness = 48.0
		w.suspension_max_force = 12000.0 * (mass / 1350.0) if mass > 1350.0 else 12000.0
		if kind == "bus":
			w.suspension_stiffness = 70.0
		elif kind == "moto":
			w.suspension_stiffness = 30.0
		w.damping_compression = 0.4
		w.damping_relaxation = 0.6
		w.wheel_friction_slip = 2.4
		w.wheel_roll_influence = 0.0
		w.use_as_steering = wd.front
		w.use_as_traction = not wd.front
		add_child(w)
		w.add_child(wd.node)
		wheels.append(w)
	if police:
		_light_bar()

func make_police() -> void:
	police = true
	_light_bar()

## viatura toda preta (3 estrelas ou mais)
func paint_black() -> void:
	var blk := M.car_paint(Color(0.03, 0.03, 0.035))
	for n in model_root.find_children("*", "MeshInstance3D", true, false):
		var m = n.material_override
		if m is StandardMaterial3D and m.albedo_color.r > 0.85 and m.albedo_color.g > 0.85 and not m.transparency:
			n.material_override = blk

func _light_bar() -> void:
	var size := body_size
	if true:
		for s in [-1.0, 1.0]:
			var b := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.5, 0.12, 0.24)
			b.mesh = bm
			b.position = Vector3(0.3 * s, size.y + 0.16, -0.1)
			b.material_override = M.emissive(Color(1, 0.1, 0.1) if s < 0 else Color(0.1, 0.3, 1), 3.0)
			add_child(b)
			_lights.append(b)

func _make_door() -> void:
	var d := door_info
	var h: float = d.y1 - d.y0
	var ln: float = d.zf - d.zb
	door_node = Node3D.new()
	door_node.position = Vector3(d.x + 0.015, d.y0, d.zf)
	model_root.add_child(door_node)
	var panel := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, h, ln)
	panel.mesh = bm
	panel.position = Vector3(0.03, h * 0.5, -ln * 0.5)
	panel.material_override = M.car_paint(Color(0.93, 0.93, 0.94) if police else paint_c)
	door_node.add_child(panel)
	var inner := MeshInstance3D.new()
	var im := BoxMesh.new()
	im.size = Vector3(0.02, h * 0.85, ln * 0.9)
	inner.mesh = im
	inner.position = Vector3(-0.02, h * 0.5, -ln * 0.5)
	inner.material_override = M.plain(Color(0.12, 0.12, 0.13), 0.8)
	door_node.add_child(inner)
	door_cover = MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.02, h * 0.98, ln * 0.98)
	door_cover.mesh = cm
	door_cover.position = Vector3(d.x + 0.02, d.y0 + h * 0.5, d.zf - ln * 0.5)
	door_cover.material_override = M.plain(Color(0.03, 0.03, 0.035), 0.9)
	model_root.add_child(door_cover)
	set_door(0.0)

## 0 = fechada, 1 = aberta (~70°)
func set_door(a: float) -> void:
	door_open = a
	if door_node == null:
		return
	door_node.visible = a > 0.02
	door_cover.visible = a > 0.02
	door_node.rotation.y = -a * 1.2

func door_world() -> Vector3:
	## ponto na calçada ao lado da porta do motorista
	if door_info.is_empty():
		return global_transform * Vector3(body_size.x * 0.5 + 0.7, 0, seat.z)
	return global_transform * Vector3(door_info.x + 0.75, 0, (door_info.zf + door_info.zb) * 0.5 - 0.3)

func take_damage(d: float) -> void:
	if dead or d <= 0.0:
		return
	hp -= d
	if hp < 45.0 and _smoke == null:
		_smoke = FX.smoke_emitter(model_root, Vector3(0, body_size.y * 0.6, body_size.z * 0.38))
	if hp < 18.0 and _fire == null:
		_fire = FX.fire_emitter(model_root, Vector3(0, body_size.y * 0.55, body_size.z * 0.38))
		_fire_t = 4.5
	if hp <= -25.0:
		explode()

func explode() -> void:
	if dead:
		return
	dead = true
	hp = 0.0
	throttle = 0.0
	ai_target = null
	engine_force = 0.0
	brake = 4.0
	var burnt := M.plain(Color(0.06, 0.055, 0.05), 0.95)
	for n in model_root.find_children("*", "MeshInstance3D", true, false):
		n.material_override = burnt
	for w in wheels:
		for n in w.find_children("*", "MeshInstance3D", true, false):
			n.material_override = burnt
	if _fire == null:
		_fire = FX.fire_emitter(model_root, Vector3(0, body_size.y * 0.55, 0))
	apply_central_impulse(Vector3(randf_range(-1, 1), 6.0, randf_range(-1, 1)) * mass)
	apply_torque_impulse(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * mass * 1.5)
	destroyed.emit(self)
	get_tree().create_timer(14.0).timeout.connect(func(): if is_instance_valid(_fire): _fire.emitting = false)

func _dent(dv: float) -> void:
	if model_root == null:
		return
	var k := clampf((dv - 6.0) * 0.004, 0.0, 0.05)
	model_root.scale.z = maxf(0.88, model_root.scale.z - k)
	model_root.scale.y = maxf(0.9, model_root.scale.y - k * 0.4)
	model_root.rotation.z = clampf(model_root.rotation.z + randf_range(-k, k), -0.05, 0.05)

func _paint(n: Node, name: String, mat: Material) -> void:
	var t := _find(n, name)
	if t is MeshInstance3D:
		t.material_override = mat

func _find(n: Node, name: String) -> Node:
	if n.name == name:
		return n
	for c in n.get_children():
		var r := _find(c, name)
		if r != null:
			return r
	return null

func speed_kmh() -> float:
	return linear_velocity.length() * 3.6

func forward_speed() -> float:
	return linear_velocity.dot(global_transform.basis.z)

func _physics_process(dt: float) -> void:
	_t += dt
	if police:
		for k in _lights.size():
			_lights[k].visible = int(_t * 6.0 + k) % 2 == 0
	# batida: variação brusca de velocidade
	var dvv := (linear_velocity - _lastv).length()
	_lastv = linear_velocity
	_crash_cd -= dt
	if dvv > 6.5 and _crash_cd <= 0.0 and _t > 1.0:
		_crash_cd = 0.3
		take_damage((dvv - 6.5) * (1.6 if kind == "bus" else 4.5))
		_dent(dvv)
		crashed.emit(self, dvv)
	if _fire_t > 0.0 and not dead:
		_fire_t -= dt
		if _fire_t <= 0.0:
			explode()
	if dead:
		engine_force = 0.0
		brake = 6.0
		steering = 0.0
		_anti_flip(dt)
		return
	if ai_target != null:
		_ai(dt)
	var fs := forward_speed()
	var eng := 0.0
	var brk := 0.0
	if throttle > 0.05:
		eng = throttle * max_engine * (1.0 - clampf(fs / 48.0, 0.0, 0.85))
	elif throttle < -0.05:
		if fs > 1.5:
			brk = -throttle * max_brake
		else:
			eng = throttle * max_engine * 0.45
	brk = maxf(brk, brake_in * max_brake)
	if handbrake:
		brk = max_brake * 0.6
	engine_force = eng
	brake = brk
	# esterço progressivo e menor em alta velocidade
	var lim := max_steer * lerpf(1.0, 0.18, clampf(absf(fs) / 28.0, 0.0, 1.0))
	steering = move_toward(steering, steer_in * lim, dt * 2.2)
	_anti_flip(dt)
	if spin.size() > 0:
		for n in spin:
			n.rotate_x(fs * dt / wheel_r)
		if fork:
			fork.rotation.y = steering * 1.1
		if lean:
			lean.rotation.z = lerpf(lean.rotation.z, -steering * clampf(absf(fs) / 12.0, 0.0, 1.0) * 0.9, minf(1.0, dt * 5.0))
	for w in wheels:
		if w.use_as_traction:
			w.wheel_friction_slip = 1.6 if handbrake else 2.6

func _ai(dt: float) -> void:
	var to := ai_target.global_position - global_position
	var local := global_transform.basis.inverse() * to
	var ang := atan2(local.x, local.z)
	var dist := to.length()
	steer_in = clampf(ang * 1.6, -1.0, 1.0)
	if local.z < -2.0 and dist < 14.0:
		throttle = -0.8
		steer_in = -steer_in
	elif dist > 9.0:
		throttle = 0.85 if absf(ang) < 1.2 else 0.45
	else:
		throttle = 0.0
		brake_in = 0.6
		return
	brake_in = 0.0

## Estabilidade estilo jogo de mundo aberto: torque que endireita o carro quando ele inclina demais
## e, se mesmo assim virar e ficar parado, ele é recolocado de pé depois de 2,5 s.
func _anti_flip(dt: float) -> void:
	var up := global_transform.basis.y
	var tilt := up.angle_to(Vector3.UP)
	if tilt > 0.25 and tilt < 2.0:
		var axis := up.cross(Vector3.UP).normalized()
		apply_torque(axis * tilt * mass * 9.0)
	if up.y < 0.35 and linear_velocity.length() < 3.0:
		_flip_t += dt
		if _flip_t > 2.5:
			_flip_t = 0.0
			var yaw := atan2(global_transform.basis.z.x, global_transform.basis.z.z)
			global_transform = Transform3D(Basis(Vector3.UP, yaw), global_position + Vector3(0, 1.2, 0))
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
	else:
		_flip_t = 0.0

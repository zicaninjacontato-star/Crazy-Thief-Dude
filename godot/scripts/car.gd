extends VehicleBody3D
## Carro com física real do Godot (suspensão por roda, atrito, transferência de peso).
## Modelo gerado por código (carmodel.gd).

const M := preload("res://scripts/mats.gd")
const CarModel := preload("res://scripts/carmodel.gd")

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

## kind: sedan, hatch, suv, pickup, sport ou police (modelo gerado por carmodel.gd).
func setup(kind: String, paint: Color) -> void:
	police = kind == "police"
	var built: Dictionary = CarModel.build(kind, paint)
	var size: Vector3 = built.size
	mass = 1350.0 if size.z < 4.8 else 1700.0
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
	var wr: float = built.wr
	for wd in built.wheels:
		var w := VehicleWheel3D.new()
		var p: Vector3 = wd.pos
		w.position = Vector3(p.x, p.y + 0.14, p.z)
		w.wheel_radius = wr
		w.wheel_rest_length = 0.14
		w.suspension_travel = 0.2
		w.suspension_stiffness = 48.0
		w.suspension_max_force = 12000.0
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
		for s in [-1.0, 1.0]:
			var b := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.5, 0.12, 0.24)
			b.mesh = bm
			b.position = Vector3(0.3 * s, size.y + 0.16, -0.1)
			b.material_override = M.emissive(Color(1, 0.1, 0.1) if s < 0 else Color(0.1, 0.3, 1), 3.0)
			add_child(b)
			_lights.append(b)

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

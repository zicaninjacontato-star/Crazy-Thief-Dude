extends VehicleBody3D
## Carro com física real do Godot (suspensão por roda, atrito, transferência de peso).
## Modelo: Car Concept (Khronos, CC-BY 4.0) — ver CREDITOS.md.

const M := preload("res://scripts/mats.gd")

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

## model: cena gerada a partir do GLB (nós st_p1, st_dark, st_glass, st_lights, wheel_fl/fr/rl/rr).
func setup(model: Node3D, paint: Color, is_police := false) -> void:
	police = is_police
	mass = 1350.0
	can_sleep = false
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.25, 0.05)
	angular_damp = 0.4
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(2.0, 0.75, 4.25)
	cs.shape = bx
	cs.position = Vector3(0, 0.72, 0)
	add_child(cs)
	add_child(model)
	model.position.z = -0.085   # centraliza o entre-eixos
	var paint_m := M.car_paint(paint)
	var dark := StandardMaterial3D.new()
	dark.vertex_color_use_as_albedo = true
	dark.roughness = 0.55
	dark.metallic = 0.25
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.04, 0.07, 0.09, 0.42)
	glass.roughness = 0.03
	glass.metallic = 0.7
	var lights := StandardMaterial3D.new()
	lights.vertex_color_use_as_albedo = true
	lights.emission_enabled = true
	lights.emission = Color(0.5, 0.5, 0.45)
	lights.emission_energy_multiplier = 0.6
	_paint(model, "st_p1", paint_m)
	_paint(model, "st_dark", dark)
	_paint(model, "st_glass", glass)
	_paint(model, "st_lights", lights)
	for k in ["fl", "fr", "rl", "rr"]:
		var wm := _find(model, "wheel_" + k)
		if wm == null:
			continue
		var w := VehicleWheel3D.new()
		var p: Vector3 = wm.position + model.position
		w.position = Vector3(p.x, p.y + 0.14, p.z)
		w.wheel_radius = 0.385
		w.wheel_rest_length = 0.14
		w.suspension_travel = 0.22
		w.suspension_stiffness = 42.0
		w.suspension_max_force = 9000.0
		w.damping_compression = 0.35
		w.damping_relaxation = 0.55
		w.wheel_friction_slip = 2.6
		w.wheel_roll_influence = 0.04
		w.use_as_steering = k.begins_with("f")
		w.use_as_traction = k.begins_with("r")
		add_child(w)
		wm.get_parent().remove_child(wm)
		w.add_child(wm)
		wm.position = Vector3.ZERO
		wm.material_override = dark
		wheels.append(w)
	if police:
		for s in [-1.0, 1.0]:
			var b := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.5, 0.12, 0.22)
			b.mesh = bm
			b.position = Vector3(0.28 * s, 1.33, -0.25)
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
	var lim := max_steer * lerpf(1.0, 0.22, clampf(absf(fs) / 30.0, 0.0, 1.0))
	steering = move_toward(steering, steer_in * lim, dt * 2.2)
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

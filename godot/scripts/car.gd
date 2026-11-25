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
var trunk_node: Node3D
var trunk_open := 0.0
var cargo := 0              # corpos no porta-malas
var unlocked := false       # vidro quebrado / tiro no vidro / carro próprio
var engine_hp := 100.0      # motor: batidas de frente estragam; 0 = motor morto
var burst: Array = []       # rodas com pneu estourado
var down := false           # moto caída (piloto derrubado)
signal engine_died(car)
var door_open := 0.0
var parked := false
var broken_wheels: Array = []
var lights_broken := false
const VMAX := {"hatch": 150.0, "sedan": 165.0, "suv": 155.0, "pickup": 150.0, "sport": 230.0, "police": 190.0, "taxi": 160.0, "moto": 175.0, "bus": 90.0}

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
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
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
	door_node = door_info.get("node")
	trunk_node = door_info.get("trunk")

## 0 = fechada, 1 = aberta (~70°). A porta é a peça recortada da própria carroceria.
func set_door(a: float) -> void:
	door_open = a
	if door_node:
		door_node.rotation.y = -a * 1.2

func set_trunk(a: float) -> void:
	trunk_open = a
	if trunk_node:
		trunk_node.rotation.x = a * 1.15

func trunk_world() -> Vector3:
	return global_transform * Vector3(0, 0, -body_size.z * 0.5 - 0.8)

func door_world() -> Vector3:
	## ponto na calçada ao lado da porta do motorista
	if door_info.is_empty():
		return global_transform * Vector3(body_size.x * 0.5 + 0.7, 0, seat.z)
	return global_transform * Vector3(door_info.x + 0.75, 0, (door_info.zf + door_info.zb) * 0.5 - 0.3)

func take_damage(d: float) -> void:
	if dead or d <= 0.0:
		return
	hp -= d
	if hp < 35.0 and _smoke == null:
		_smoke = FX.smoke_emitter(model_root, Vector3(0, body_size.y * 0.6, body_size.z * 0.38))
	if hp < 12.0 and _fire == null:
		_fire = FX.fire_emitter(model_root, Vector3(0, body_size.y * 0.55, body_size.z * 0.38))
		_fire_t = 6.0
	if hp <= -30.0:
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

var _lastv_prev := Vector3.INF
var _dv_local := Vector3.ZERO

## batida: amassa do lado do impacto, quebra faróis (frente) e, se forte, solta uma roda
func _impact(dv: float) -> void:
	_impact_at(Vector3(-_dv_local.x, 0, -_dv_local.z), dv * 0.9)
	var ld := _dv_local
	var front := ld.z < -absf(ld.x) * 0.6     # perdeu velocidade para a frente = bateu de frente
	var back := ld.z > absf(ld.x) * 0.6
	if model_root:
		var k := clampf((dv - 9.0) * 0.005, 0.0, 0.05)
		if front:
			model_root.position.z -= k * body_size.z * 0.5
		elif back:
			model_root.position.z += k * body_size.z * 0.5
		else:
			model_root.scale.x = maxf(0.9, model_root.scale.x - k)
	if front and dv > 11.0 and not lights_broken:
		lights_broken = true
		var lf := model_root.find_child("lights_front", true, false)
		if lf:
			lf.visible = false
		FX.sparks(get_tree().current_scene, global_transform * Vector3(0, 0.7, body_size.z * 0.5))
	if dv > 15.0 and randf() < 0.45 and wheels.size() >= 4 and broken_wheels.size() < 2:
		var side := -signf(ld.x) if absf(ld.x) > 2.0 else (1.0 if randf() < 0.5 else -1.0)
		var best: VehicleWheel3D = null
		for w in wheels:
			if w in broken_wheels:
				continue
			if signf(w.position.x) == side and ((w.position.z > 0.0) == (not back)):
				best = w
		if best:
			broken_wheels.append(best)
			for n in best.get_children():
				if n is Node3D:
					n.visible = false
			best.wheel_friction_slip = 0.45
			best.suspension_stiffness *= 0.35
			FX.debris(get_tree().current_scene, best.global_position, Color(0.06, 0.06, 0.06), linear_velocity * 0.6 + Vector3(side * 3.0, 4.0, 0), Vector3(0.24, wheel_r * 2.0, wheel_r * 2.0))

func _dent(dv: float) -> void:
	if model_root == null:
		return
	var k := clampf((dv - 6.0) * 0.004, 0.0, 0.05)
	model_root.scale.z = maxf(0.88, model_root.scale.z - k)
	model_root.scale.y = maxf(0.9, model_root.scale.y - k * 0.4)
	model_root.rotation.z = clampf(model_root.rotation.z + randf_range(-k, k), -0.05, 0.05)

## batida com outro veículo: os dois levam dano pela velocidade relativa (antes só quem freava bruscamente)
var _hit_cd := {}
func _on_body_entered(other: Node) -> void:
	if not (other is VehicleBody3D or other is CharacterBody3D) or not other.has_method("take_damage"):
		return
	var t := Time.get_ticks_msec()
	if _hit_cd.get(other.get_instance_id(), 0) > t:
		return
	_hit_cd[other.get_instance_id()] = t + 400
	var ov: Vector3 = other.linear_velocity if "linear_velocity" in other else Vector3.ZERO
	var rel := (linear_velocity - ov).length()
	if rel < 6.0:
		return
	var dir: Vector3 = (other.global_position - global_position)
	dir.y = 0
	var local := global_transform.basis.inverse() * dir.normalized()
	var my_share := 0.5 + 0.5 * clampf((ov.length() - linear_velocity.length()) / maxf(rel, 1.0), -1.0, 1.0)
	var sev := rel * (0.6 + my_share * 0.8)
	_impact_at(local, sev)
	take_damage(maxf(0.0, sev - 6.0) * 2.6)
	crashed.emit(self, sev)

## deforma a lataria de verdade: vértices perto do ponto de impacto afundam para dentro
func _impact_at(local_dir: Vector3, sev: float) -> void:
	if model_root == null or sev < 7.0:
		return
	var hx: float = body_size.x * 0.5
	var hz: float = body_size.z * 0.5
	var ld := Vector3(local_dir.x, 0, local_dir.z)
	if ld.length() < 0.01:
		ld = Vector3(0, 0, 1)
	ld = ld.normalized()
	var k := 1.0 / maxf(absf(ld.x) / hx, absf(ld.z) / hz)
	var pt := ld * k + Vector3(0, 0.75, 0)
	var depth := clampf((sev - 7.0) * 0.028, 0.03, 0.5)
	_deform(model_root, pt, ld, depth, 0.75 + depth)
	# batida de frente estraga o motor
	if ld.z > 0.6:
		engine_hp -= (sev - 7.0) * 5.5
		if engine_hp < 35.0 and _smoke == null:
			_smoke = FX.smoke_emitter(model_root, Vector3(0, body_size.y * 0.6, hz * 0.75))
		if engine_hp <= 0.0 and engine_hp + (sev - 7.0) * 5.5 > 0.0:
			engine_died.emit(self)
		if sev > 11.0 and not lights_broken:
			lights_broken = true
			var lf := model_root.find_child("lights_front", true, false)
			if lf:
				lf.visible = false
			FX.sparks(get_tree().current_scene, global_transform * Vector3(0, 0.7, hz))

func _deform(root: Node, pt: Vector3, dir: Vector3, depth: float, radius: float) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not (mi.mesh is ArrayMesh) or mi.get_parent() is VehicleWheel3D:
			continue
		var mesh := mi.mesh as ArrayMesh
		var xf: Transform3D = (model_root.global_transform.affine_inverse() * mi.global_transform)
		var inv := xf.affine_inverse()
		var lp: Vector3 = inv * pt
		var ldir: Vector3 = (inv.basis * dir).normalized()
		var out := ArrayMesh.new()
		var changed := false
		for si in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for vi in vs.size():
				var dd := vs[vi].distance_to(lp)
				if dd < radius:
					var f := 1.0 - dd / radius
					vs[vi] -= ldir * depth * f * f
					changed = true
			arr[Mesh.ARRAY_VERTEX] = vs
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			out.surface_set_material(si, mesh.surface_get_material(si))
		if changed:
			mi.mesh = out

## estoura o pneu de uma roda (tiro): perde aderência, o carro puxa; se estiver rápido, roda/derrapa
func burst_tire(w: VehicleWheel3D) -> void:
	if w in burst:
		return
	burst.append(w)
	w.wheel_friction_slip = 0.7
	w.suspension_stiffness *= 0.55
	for n in w.get_children():
		if n is Node3D:
			n.scale = Vector3(1.0, 0.82, 0.82)
	FX.sparks(get_tree().current_scene, w.global_position)
	var spd := linear_velocity.length()
	if spd > 8.0:
		apply_torque_impulse(Vector3.UP * mass * randf_range(-1.0, 1.0) * spd * 0.25)

## moto: piloto caiu → a moto tomba e desliza
func fall_over() -> void:
	if down:
		return
	down = true
	throttle = 0.0
	ai_target = null
	apply_torque_impulse(global_transform.basis.z * mass * (2.2 if randf() < 0.5 else -2.2))

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
	_dv_local = global_transform.basis.inverse() * (linear_velocity - _lastv)
	_lastv = linear_velocity
	_crash_cd -= dt
	if dvv > 9.0 and _crash_cd <= 0.0 and _t > 1.0:
		_crash_cd = 0.35
		take_damage((dvv - 9.0) * (0.9 if kind == "bus" else 2.3))
		_impact(dvv)
		crashed.emit(self, dvv)
	_lastv_prev = linear_velocity
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
	# limite de velocidade por modelo (e ré até 30 km/h)
	var vmax: float = VMAX.get(kind, 160.0) / 3.6
	if fs > vmax and eng > 0.0:
		eng = 0.0
		brk = maxf(brk, max_brake * 0.05)
	if fs < -8.0 and eng < 0.0:
		eng = 0.0
	if handbrake:
		brk = max_brake * 0.6
	if engine_hp <= 0.0:
		eng = 0.0
	elif engine_hp < 35.0:
		eng *= 0.5
	if down:
		eng = 0.0
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
		if w.use_as_traction and not (w in broken_wheels) and not (w in burst):
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
	if down:
		return
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

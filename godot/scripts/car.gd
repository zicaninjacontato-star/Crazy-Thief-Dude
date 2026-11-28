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
var siren_on := false      # sirene + giroflex (viaturas da polícia ligam; o jogador liga/desliga)
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
const VMAX := {"hatch": 150.0, "sedan": 165.0, "suv": 155.0, "pickup": 150.0, "sport": 230.0, "police": 190.0, "taxi": 160.0, "moto": 175.0, "bus": 90.0,
	"van": 140.0, "bike": 30.0, "sportbike": 215.0, "offroad": 150.0, "super": 265.0, "truck": 105.0}

## kind: sedan, hatch, suv, pickup, sport ou police (modelo gerado por carmodel.gd).
var stick := Vector2.ZERO    # joystick do jogador (moto: puxar para trás + acelerar = empinar)
var wheelie_key := false
var wheelie := 0.0            # ângulo do empinado (rad)
signal wheelie_fall(car)
var mods := {}             # oficina tuning (tuning.gd)
var eng_mult := 1.0
var hold := false          # largada do racha: preso até o "VAI!"
var nitro_t := 0.0         # nitro (s restantes)
var draft := 0.0           # vácuo atrás de outro carro (0..1)
var vmax_mult := 1.0
var dmg_mult := 1.0
var variant := ""          # modelo real (bike/sportbike usam o comportamento de "moto")
func setup(kind: String, paint: Color) -> void:
	police = kind == "police"
	variant = kind
	if kind in ["bike", "sportbike"]:
		kind = "moto"
	self.kind = kind
	var built: Dictionary = VehModel.build(variant, paint) if variant in ["moto", "bus", "truck", "bike", "sportbike"] else CarModel.build(kind, paint)
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
		if variant == "bike":
			mass = 95.0
			max_engine = 170.0       # pedalada: arranca devagar (antes 260 = parecia moto)
			max_brake = 6.0
		elif variant == "sportbike":
			max_engine = 1900.0
	elif kind == "truck":
		mass = 7200.0
		max_engine = 17000.0
		max_brake = 280.0
		max_steer = 0.48
	elif kind == "super":
		max_engine *= 1.45
	elif kind == "offroad":
		max_engine *= 1.15
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
	optimize_visuals(model_root)
	for w in wheels:
		for n in w.get_children():
			if n is MeshInstance3D:
				n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				n.visibility_range_end = 110.0
	_make_lod()

## peças pequenas não projetam sombra e somem de longe (vidro, faróis, detalhes); a carroceria fica
static func optimize_visuals(root: Node, far := 150.0) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if mi.visibility_range_end > 0.0:
			continue          # motorista/ocupante (já tem distância própria)
		var sz: Vector3 = mi.get_aabb().size
		var longest := maxf(sz.x, maxf(sz.y, sz.z))
		var mat = mi.material_override
		var glass: bool = mat is BaseMaterial3D and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		if glass or longest < 1.6 or (mat is BaseMaterial3D and mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if longest < 1.2:
			mi.visibility_range_end = 90.0
		elif far > 0.0:
			mi.visibility_range_end = far       # carroceria some longe (mapa grande = muitos carros)
			mi.visibility_range_end_margin = 10.0

## veículo visto de longe: o modelo detalhado some e aparece um modelo simples (caixas coloridas,
## ~100 triângulos, 1 malha) — antes cada carro desenhava milhares de triângulos em 15–20 malhas
var lod_proxy: MeshInstance3D
func _make_lod() -> void:
	if model_root == null:
		return
	if lod_proxy and is_instance_valid(lod_proxy):
		lod_proxy.queue_free()
	var d: float = M.lod_vehicle()
	var s := body_size
	var col: Color = paint_c if not police else Color(0.05, 0.05, 0.06)
	var dark := Color(0.06, 0.06, 0.07)
	var glass := Color(0.1, 0.13, 0.17)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if kind == "moto":
		CarModel._box(st, Vector3(0.36, 0.5, s.z * 0.75), Vector3(0, 0.7, 0), col)
		CarModel._box(st, Vector3(0.12, wheel_r * 2.0, wheel_r * 2.0), Vector3(0, wheel_r, s.z * 0.38), dark)
		CarModel._box(st, Vector3(0.12, wheel_r * 2.0, wheel_r * 2.0), Vector3(0, wheel_r, -s.z * 0.38), dark)
	elif s.y > 2.6:
		# ônibus/caminhão: caixa + faixa de janelas
		CarModel._box(st, Vector3(s.x, s.y - 0.45, s.z), Vector3(0, 0.45 + (s.y - 0.45) * 0.5, 0), col)
		CarModel._box(st, Vector3(s.x + 0.03, 0.9, s.z * 0.86), Vector3(0, s.y * 0.68, 0), glass)
	else:
		var low := s.y * 0.5
		CarModel._box(st, Vector3(s.x, low - 0.25, s.z), Vector3(0, 0.25 + (low - 0.25) * 0.5, 0), col)
		CarModel._box(st, Vector3(s.x * 0.86, s.y - low, s.z * 0.5), Vector3(0, low + (s.y - low) * 0.5, -0.1), glass)
		CarModel._box(st, Vector3(s.x * 0.8, 0.06, s.z * 0.46), Vector3(0, s.y, -0.1), col)
	if kind != "moto":
		for w in wheels:
			CarModel._box(st, Vector3(0.28, wheel_r * 2.0, wheel_r * 2.0), Vector3(w.position.x, wheel_r, w.position.z), dark)
	lod_proxy = MeshInstance3D.new()
	lod_proxy.name = "lod"
	lod_proxy.mesh = st.commit()
	lod_proxy.material_override = CarModel.vc_mat()
	lod_proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lod_proxy.visibility_range_begin = d
	lod_proxy.visibility_range_end = 170.0 * M.lod_k
	model_root.add_child(lod_proxy)
	# o detalhado só até a distância do LOD
	for mi in model_root.find_children("*", "MeshInstance3D", true, false):
		if mi == lod_proxy or mi.get_parent().get_parent() is Node3D and mi.get_parent().get_parent().has_method("set_far") or (mi.visibility_range_end > 0.0 and mi.visibility_range_end < d):
			continue
		mi.visibility_range_end = d
		mi.visibility_range_end_margin = 0.0
	for w in wheels:
		for n in w.get_children():
			if n is MeshInstance3D:
				n.visibility_range_end = d

func make_police() -> void:
	police = true
	_light_bar()

## oficina: nova pintura (troca o material da tinta da carroceria e da porta)
func repaint(c: Color) -> void:
	var old: Material = M.car_paint(paint_c)
	var nm: Material = M.car_paint(c)
	for n in model_root.find_children("*", "MeshInstance3D", true, false):
		if n.material_override == old:
			n.material_override = nm
	if door_node:
		for n in door_node.find_children("*", "MeshInstance3D", true, false):
			if n.material_override == old:
				n.material_override = nm
	paint_c = c
	_make_lod()

## tiro no vidro: 1º trinca (branco leitoso), 2º estilhaça (some) — devolve true se acertou vidro
var _glass_hits := 0
func break_glass() -> bool:
	var gl: Array = []
	for mi in model_root.find_children("*", "MeshInstance3D", true, false):
		var m = mi.material_override
		if m is StandardMaterial3D and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and not m.vertex_color_use_as_albedo and mi.visible and mi.name != "mods":
			gl.append(mi)
	if gl.is_empty():
		return false
	_glass_hits += 1
	unlocked = true
	var sc := get_tree().current_scene
	if _glass_hits == 1:
		var cr := StandardMaterial3D.new()
		cr.albedo_color = Color(0.82, 0.86, 0.88, 0.72)
		cr.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cr.roughness = 0.6
		for mi in gl:
			if not mi.has_meta("glass_orig"):
				mi.set_meta("glass_orig", mi.material_override)
			mi.material_override = cr
		sc.audio.play("glass" if sc.audio.sounds.has("glass") else "hit", global_position, -4.0)
	else:
		for mi in gl:
			mi.visible = false
		sc.audio.play("glass" if sc.audio.sounds.has("glass") else "hit", global_position, 2.0)
		FX.sparks(sc, global_position + Vector3(0, body_size.y * 0.75, 0))
	return true

## oficina: conserto (vida, motor, fumaça/fogo e pneus)
func repair() -> void:
	hp = 100.0
	_glass_hits = 0
	for mi in model_root.find_children("*", "MeshInstance3D", true, false):
		if mi.has_meta("glass_orig"):
			mi.material_override = mi.get_meta("glass_orig")
			mi.remove_meta("glass_orig")
			mi.visible = true
	engine_hp = 100.0
	if _smoke and is_instance_valid(_smoke):
		_smoke.queue_free()
	_smoke = null
	if _fire and is_instance_valid(_fire):
		_fire.queue_free()
	_fire = null
	for w in wheels:
		w.wheel_friction_slip = 2.4
		w.suspension_stiffness = maxf(w.suspension_stiffness, 30.0)
	unbend()

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
	hood_node = door_info.get("hood")
	bumpers = door_info.get("bumpers", {})
	for k in bumpers:
		_bump0[k] = bumpers[k].transform
	if hood_node:
		_hood0 = hood_node.transform

## 0 = fechada, 1 = aberta (~70°). A porta é a peça recortada da própria carroceria.
func set_door(a: float) -> void:
	door_open = a
	if door_node:
		door_node.rotation.y = -maxf(a * 1.2, door_ajar)

func set_trunk(a: float) -> void:
	trunk_open = a
	if trunk_node:
		trunk_node.rotation.x = maxf(a * 1.15, trunk_pop)

func trunk_world() -> Vector3:
	return global_transform * Vector3(0, 0, -body_size.z * 0.5 - 0.8)

func door_world() -> Vector3:
	## ponto na calçada ao lado da porta do motorista
	if door_info.is_empty():
		return global_transform * Vector3(body_size.x * 0.5 + 0.7, 0, seat.z)
	return global_transform * Vector3(door_info.x + 0.75, 0, (door_info.zf + door_info.zb) * 0.5 - 0.3)

func take_damage(d: float) -> void:
	freeze = false
	if dead or d <= 0.0:
		return
	d *= dmg_mult
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

## batida: amassa a peça do lado do impacto (para-choque, capô, porta, porta-malas, roda)
func _impact(dv: float) -> void:
	_impact_at(Vector3(-_dv_local.x, 0, -_dv_local.z), dv * 0.9)

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
	set_meta("last_crash", sev)
	crashed.emit(self, sev)

# ---------------------------------------------------------------- dano por peça
var hood_node: Node3D
var bumpers := {}             # 1.0 = dianteiro, -1.0 = traseiro (nós "pc_d"/"pc_t" do carmodel)
var _bump0 := {}
var _hood0 := Transform3D.IDENTITY
var part_dmg := {}            # peça -> dano acumulado
var door_ajar := 0.0          # porta entortada pela batida (fica entreaberta)
var trunk_pop := 0.0          # tampa do porta-malas estourada
var hood_pop := 0.0           # capô levantado/dobrado
var bent: Array = []          # rodas entortadas

## deforma a lataria de verdade: a peça atingida afunda, enruga, solta ou abre conforme a força
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
	var pt := ld * k + Vector3(0, 0.65, 0)
	var depth := clampf((sev - 7.0) * 0.028, 0.03, 0.5)
	var big: float = 1.7 if body_size.z > 6.5 else 1.0      # ônibus/caminhão: amassado maior
	# frente/trás: a batida enruga a largura toda; lateral: um trecho mais comprido da porta
	var stretch := Vector3(0.5, 1.0, 1.0) if absf(ld.z) > 0.6 else Vector3(1.0, 1.0, 0.7)
	_deform(model_root, pt, ld, depth * (1.3 if big > 1.0 else 1.0), (0.75 + depth) * big, stretch)
	var e := sev - 7.0
	var front := ld.z > 0.6
	var rear := ld.z < -0.6
	if front or rear:
		var bk: float = 1.0 if front else -1.0
		_bumper_hit(bk, e, ld)
		if front:
			_add_part("hood", e)
			if hood_node and part_dmg.hood > 6.0:
				hood_pop = minf(0.75, hood_pop + e * 0.02)
				hood_node.transform = _hood0 * Transform3D(Basis(Vector3.RIGHT, -hood_pop * (0.35 if part_dmg.hood < 22.0 else 1.0)), Vector3.ZERO)
			if part_dmg.hood > 16.0 and _glass_hits == 0:
				break_glass()          # para-brisa trinca
		else:
			_add_part("trunk", e)
			if trunk_node and part_dmg.trunk > 8.0:
				trunk_pop = minf(0.6, trunk_pop + e * 0.03)
				set_trunk(trunk_open)
	else:
		var side: float = signf(ld.x)
		_add_part("door_%d" % int(side), e)
		if side > 0.0 and door_node and part_dmg["door_1"] > 10.0:
			door_ajar = minf(0.13, door_ajar + e * 0.006)
			set_door(door_open)
	# roda perto do ponto de impacto: pneu murcha e a roda entorta (cambagem)
	if e > 6.0 and kind != "moto":
		for w in wheels:
			var wp: Vector3 = w.position
			if Vector2(wp.x - pt.x, wp.z - pt.z).length() < 1.35 and not (w in bent):
				bent.append(w)
				burst_tire(w)
				for n in w.get_children():
					if n is Node3D:
						n.rotation.z = signf(wp.x) * randf_range(0.12, 0.28)
				break
	# batida de frente estraga o motor e quebra os faróis
	if front:
		engine_hp -= e * 5.5
		if engine_hp < 35.0 and _smoke == null:
			_smoke = FX.smoke_emitter(model_root, Vector3(0, body_size.y * 0.6, hz * 0.75))
		if engine_hp <= 0.0 and engine_hp + e * 5.5 > 0.0:
			engine_died.emit(self)
		if sev > 11.0 and not lights_broken:
			lights_broken = true
			var lf := model_root.find_child("lights_front", true, false)
			if lf:
				lf.visible = false
			FX.sparks(get_tree().current_scene, global_transform * Vector3(0, 0.7, hz))
	# roda arrancada (batida muito forte)
	if sev > 17.0 and randf() < 0.4 and wheels.size() >= 4 and broken_wheels.size() < 2:
		var sd := signf(ld.x) if absf(ld.x) > 0.3 else (1.0 if randf() < 0.5 else -1.0)
		var best: VehicleWheel3D = null
		for w in wheels:
			if w in broken_wheels:
				continue
			if signf(w.position.x) == sd and ((w.position.z > 0.0) == (not rear)):
				best = w
		if best:
			broken_wheels.append(best)
			for n in best.get_children():
				if n is Node3D:
					n.visible = false
			best.wheel_friction_slip = 0.45
			best.suspension_stiffness *= 0.35
			FX.debris(get_tree().current_scene, best.global_position, Color(0.06, 0.06, 0.06), linear_velocity * 0.6 + Vector3(sd * 3.0, 4.0, 0), Vector3(0.24, wheel_r * 2.0, wheel_r * 2.0))

func _add_part(p: String, e: float) -> void:
	part_dmg[p] = part_dmg.get(p, 0.0) + e

## para-choque: afunda → fica pendurado de um lado → cai (vira destroço)
func _bumper_hit(bk: float, e: float, ld: Vector3) -> void:
	var key := "pc_d" if bk > 0.0 else "pc_t"
	_add_part(key, e)
	var bn = bumpers.get(bk)
	if bn == null or not is_instance_valid(bn) or not bn.visible:
		return
	var d: float = part_dmg[key]
	var t0: Transform3D = _bump0[bk]
	var push := minf(0.22, d * 0.008)
	var hang := 0.0 if d < 14.0 else minf(0.5, (d - 14.0) * 0.025)
	var sd := -1.0 if ld.x > 0.0 else 1.0
	bn.transform = t0 * Transform3D(Basis(Vector3.FORWARD, sd * hang) * Basis(Vector3.RIGHT, bk * hang * 0.4), Vector3(0, -hang * 0.25, -bk * push))
	if d > 30.0:
		# solta: o para-choque cai como destroço
		bn.visible = false
		FX.debris(get_tree().current_scene, bn.global_position, paint_c, linear_velocity * 0.5 + Vector3(randf_range(-2, 2), 2.5, 0), Vector3(body_size.x * 0.85, 0.24, 0.26))
		FX.sparks(get_tree().current_scene, bn.global_position)

func _deform(root: Node, pt: Vector3, dir: Vector3, depth: float, radius: float, stretch := Vector3.ONE) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not (mi.mesh is ArrayMesh) or mi.get_parent() is VehicleWheel3D or mi.name == "lod" or not mi.visible:
			continue
		# não amassa o motorista/piloto (moto: ele fica dentro do modelo)
		var anc: Node = mi.get_parent()
		var person := false
		while anc != null and anc != root:
			if anc.has_method("set_far"):
				person = true
				break
			anc = anc.get_parent()
		if person:
			continue
		var mesh := mi.mesh as ArrayMesh
		var xf: Transform3D = (model_root.global_transform.affine_inverse() * mi.global_transform)
		var inv := xf.affine_inverse()
		var lp: Vector3 = inv * pt
		var ldir: Vector3 = (inv.basis * dir).normalized()
		var pa: Vector3 = ldir.cross(Vector3.UP).normalized() if absf(ldir.y) < 0.9 else Vector3.RIGHT
		var pb: Vector3 = ldir.cross(pa).normalized()
		var aabb := mesh.get_aabb().grow(radius / minf(stretch.x, minf(stretch.y, stretch.z)))
		if not aabb.has_point(lp):
			continue
		var out := ArrayMesh.new()
		var changed := false
		var m0: ArrayMesh = mi.get_meta("mesh0") if mi.has_meta("mesh0") else mesh
		var maxd: float = 0.42 if body_size.z > 6.5 else 0.2      # amassado máximo por ponto
		for si in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var v0s: PackedVector3Array = m0.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] if m0 != mesh else vs.duplicate()
			var any := false
			for vi in vs.size():
				var v: Vector3 = vs[vi]
				var dd := ((v - lp) * stretch).length()
				if dd < radius:
					var f := 1.0 - dd / radius
					# afunda + vincos (enrugado) para a lataria não ficar "lisa" depois da batida
					# vinco calculado só nas coordenadas da superfície (perpendiculares à batida): a chapa e a
					# face interna amassam juntas (antes a face interna escura atravessava a porta)
					var crease := sin(v.dot(pa) * 21.0) * sin(v.dot(pb) * 17.0)
					var nv: Vector3 = v - ldir * (depth * f * f + crease * depth * 0.16 * f)
					var off: Vector3 = nv - v0s[vi]
					if off.length() > maxd:
						nv = v0s[vi] + off.normalized() * maxd
					vs[vi] = nv
					any = true
			if any:
				changed = true
				arr[Mesh.ARRAY_VERTEX] = vs
				arr[Mesh.ARRAY_NORMAL] = _normals(vs, arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array())
				if arr[Mesh.ARRAY_TANGENT] != null:
					arr[Mesh.ARRAY_TANGENT] = null
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			out.surface_set_material(si, mesh.surface_get_material(si))
		if false:
			print("DEF porta mesh=", mi.material_override.resource_name if mi.material_override else "-", " col=", mi.material_override.albedo_color if mi.material_override is StandardMaterial3D else "", " changed=", changed, " lp=", lp.snapped(Vector3.ONE * 0.01), " aabb=", mesh.get_aabb())
		if changed:
			if not mi.has_meta("mesh0"):
				mi.set_meta("mesh0", mesh)
			mi.mesh = out

## normais recalculadas depois de amassar (com as antigas o amassado quase não aparecia na luz)
static func _normals(vs: PackedVector3Array, ix: PackedInt32Array) -> PackedVector3Array:
	var ns := PackedVector3Array()
	ns.resize(vs.size())
	if ix.size() > 0:
		for t in range(0, ix.size() - 2, 3):
			var a := ix[t]
			var b := ix[t + 1]
			var c := ix[t + 2]
			var fn := (vs[c] - vs[a]).cross(vs[b] - vs[a])      # Godot: frente = sentido horário
			ns[a] += fn
			ns[b] += fn
			ns[c] += fn
	else:
		for t in range(0, vs.size() - 2, 3):
			var fn2 := (vs[t + 2] - vs[t]).cross(vs[t + 1] - vs[t])
			ns[t] = fn2
			ns[t + 1] = fn2
			ns[t + 2] = fn2
	for i in ns.size():
		ns[i] = ns[i].normalized() if ns[i].length_squared() > 1e-12 else Vector3.UP
	return ns

## conserto (oficina): desamassa a lataria e devolve capô, para-choques, porta, porta-malas e rodas
func unbend() -> void:
	for mi in model_root.find_children("*", "MeshInstance3D", true, false):
		if mi.has_meta("mesh0"):
			mi.mesh = mi.get_meta("mesh0")
			mi.remove_meta("mesh0")
	for kb in bumpers:
		if is_instance_valid(bumpers[kb]):
			bumpers[kb].transform = _bump0[kb]
			bumpers[kb].visible = true
	if hood_node:
		hood_node.transform = _hood0
	part_dmg.clear()
	hood_pop = 0.0
	door_ajar = 0.0
	trunk_pop = 0.0
	set_door(0.0)
	set_trunk(0.0)
	for w in wheels:
		for n in w.get_children():
			if n is Node3D:
				n.rotation.z = 0.0
				n.scale = Vector3.ONE
				if w in broken_wheels:
					n.visible = true
		w.wheel_friction_slip = 2.4
	bent.clear()
	burst.clear()
	broken_wheels.clear()
	lights_broken = false
	var lf := model_root.find_child("lights_front", true, false)
	if lf:
		lf.visible = true
	model_root.position = Vector3(0, model_root.position.y, 0)
	model_root.scale = Vector3.ONE
	model_root.rotation = Vector3.ZERO

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

var _idle_chk := 0.0
func _physics_process(dt: float) -> void:
	_t += dt
	if police:
		for k in _lights.size():
			_lights[k].visible = siren_on and int(_t * 6.0 + k) % 2 == 0
	# otimização: carro parado longe do jogador "dorme" (sem física) até alguém mexer nele
	if freeze and (absf(throttle) > 0.01 or driver != null):
		freeze = false
	_idle_chk -= dt
	if _idle_chk <= 0.0:
		_idle_chk = 0.5
		var pl = get_tree().current_scene.get("player")
		var far: bool = pl != null and global_position.distance_squared_to(pl.global_position) > 60.0 * 60.0
		if freeze and not far:
			freeze = false
		# a suspensão deixa um tremor de poucos cm/s: antes nenhum carro estacionado chegava a "dormir"
		elif not freeze and far and linear_velocity.length_squared() < 0.06 and absf(throttle) < 0.01 and driver == null and _t > 3.0 and ai_target == null:
			freeze = true
	if freeze:
		return
	if kind == "moto":
		_ride_height(dt)
	# batida: variação brusca de velocidade
	var dvv := (linear_velocity - _lastv).length()
	_dv_local = global_transform.basis.inverse() * (linear_velocity - _lastv)
	_lastv = linear_velocity
	_crash_cd -= dt
	if dvv > 9.0 and _crash_cd <= 0.0 and _t > 1.0:
		_crash_cd = 0.35
		take_damage((dvv - 9.0) * (0.9 if kind == "bus" else 2.3))
		_impact(dvv)
		set_meta("last_crash", dvv)
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
	var vmax: float = VMAX.get(variant, VMAX.get(kind, 160.0)) / 3.6 * vmax_mult
	eng *= eng_mult
	# vácuo e nitro (racha)
	if draft > 0.01:
		eng *= 1.0 + 0.45 * draft
		vmax *= 1.0 + 0.1 * draft
	if nitro_t > 0.0:
		nitro_t -= dt
		if throttle > 0.05:
			eng = maxf(eng, max_engine * eng_mult) * 1.6
			apply_central_force(global_transform.basis.z * mass * 2.5)
		vmax *= 1.3
	if hold:
		eng = 0.0
		brk = maxf(brk, max_brake)
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
		if variant == "bike" and lean:
			# pedala com a roda (relação ~2:1) e só enquanto acelera ou anda
			if throttle > 0.05 or absf(fs) > 0.5:
				pedal_phase += (fs / wheel_r * 0.5 + throttle * 2.5) * dt
			for h in lean.get_children():
				if h.get("moto_pose") != null:
					h.pedal = pedal_phase
		if fork:
			fork.rotation.y = steering * 1.1
		if lean:
			lean.rotation.z = lerpf(lean.rotation.z, -steering * clampf(absf(fs) / 12.0, 0.0, 1.0) * 0.9, minf(1.0, dt * 5.0))
			_wheelie_tick(dt, fs)
	_hop_cd -= dt
	for w in wheels:
		if w.use_as_traction and not (w in broken_wheels) and not (w in burst):
			w.wheel_friction_slip = 1.6 if handbrake else 2.6

## empinar: acelerando e puxando o joystick para trás a roda da frente sobe; passou do ponto = cai
## moto: as rodas visuais ficam no modelo (presas ao chassi) e a suspensão mole abaixa o chassi —
## as rodas atravessavam a rua. O modelo é apoiado no ponto real de contato das rodas físicas.
var _ride_y := 0.0
var _ride_t := 0.0
func _ride_height(dt: float) -> void:
	_ride_t -= dt
	if _ride_t > 0.0:
		return
	# longe da câmera ninguém vê: mede 4×/s em vez de todo passo
	var cam := get_viewport().get_camera_3d()
	var far: bool = cam != null and cam.global_position.distance_squared_to(global_position) > 3600.0
	_ride_t = 0.25 if far else 0.0
	# chão medido de verdade (raio de cada roda física até o asfalto), em coordenadas do chassi
	var ss := get_world_3d().direct_space_state
	var sum := 0.0
	var n := 0
	for i in range(0, wheels.size(), 2):
		var w: VehicleWheel3D = wheels[i]
		var top: Vector3 = w.global_position + global_transform.basis.y * 0.3
		var q := PhysicsRayQueryParameters3D.create(top, top - global_transform.basis.y * 1.6, 1)
		q.exclude = [get_rid()]
		var r := ss.intersect_ray(q)
		if not r.is_empty():
			sum += to_local(r.position).y
			n += 1
	var want := sum / n if n > 0 else 0.0
	_ride_y = lerpf(_ride_y, clampf(want, -0.1, 0.35), minf(1.0, maxf(dt, _ride_t) * 12.0))
	if model_root:
		model_root.position.y = _ride_y

var _lean_z := 0.0
var pedal_phase := 0.0
var _hop_cd := 0.0
## bicicleta: pulo (bunny hop) com o botão PULAR
func hop() -> void:
	if _hop_cd > 0.0 or down:
		return
	var on_ground := false
	for w in wheels:
		if w.is_in_contact():
			on_ground = true
	if not on_ground:
		return
	_hop_cd = 0.8
	apply_central_impulse(global_transform.basis.y * mass * 4.6 + global_transform.basis.z * mass * 0.6)
	apply_torque_impulse(global_transform.basis.x * -mass * 0.25)

func _wheelie_tick(dt: float, fs: float) -> void:
	var want := driver != null and throttle > 0.5 and fs > 3.0 and (stick.y < -0.35 or wheelie_key) and not down
	if want:
		# puxar um pouco = equilibra num ângulo; puxar tudo (ou segurar a tecla) = continua subindo e cai
		var pull := clampf((-stick.y - 0.35) / 0.5, 0.0, 1.0)
		var goal: float = 1.35 if (stick.y < -0.9 or wheelie_key) else lerpf(0.2, 0.75, pull)
		wheelie = move_toward(wheelie, goal, dt * 0.7)
	else:
		wheelie = maxf(0.0, wheelie - dt * 1.8)
		if wheelie > 0.0 and wheelie < 0.04:
			wheelie = 0.0
	# segurando o equilíbrio: perto de 0,85 rad ainda dá para voltar; passou de 1,15 = tomba para trás
	if wheelie > 1.15:
		wheelie = 0.0
		fall_over()
		apply_central_impulse(-global_transform.basis.z * mass * 1.5 + Vector3(0, mass * 2.0, 0))
		wheelie_fall.emit(self)
	# gira o conjunto (moto + piloto) em volta do eixo da roda traseira
	var zr := -body_size.z * 0.3
	var piv := Vector3(0, 0.05, zr)
	var rz: float = lean.rotation.z
	var b := Basis(Vector3.RIGHT, -wheelie) * Basis(Vector3.FORWARD, -rz)
	lean.transform = Transform3D(b, piv - b * piv)
	if wheelie > 0.05:
		engine_force *= 1.08

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
	# só endireita o ROLAMENTO (capotar de lado). Inclinação para frente/trás em morro, rampa ou
	# no ar é livre — antes o torque nivelava o carro e ele "grudava" no chão em vez de voar
	var roll := asin(clampf(global_transform.basis.x.y, -1.0, 1.0))
	var pitch := asin(clampf(global_transform.basis.z.y, -1.0, 1.0))
	if absf(roll) > 0.3 and tilt < 2.0:
		apply_torque(global_transform.basis.z * roll * mass * 9.0)
	if absf(pitch) > 1.0 and tilt < 2.0:
		apply_torque(-global_transform.basis.x * pitch * mass * 4.0)
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

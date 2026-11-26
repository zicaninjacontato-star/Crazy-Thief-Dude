extends CharacterBody3D
## Veículos "arcade" (sem rodas físicas): barco, avião e helicóptero.
## Mesma interface do car.gd (throttle, brake_in, steer_in, seat, body_size, take_damage, explode...),
## então entrar/sair, dano, explosão e câmera funcionam igual. 'stick' recebe o joystick (x = lado, y = frente).

const CM := preload("res://scripts/carmodel.gd")
const M := preload("res://scripts/mats.gd")
const FX := preload("res://scripts/fx.gd")

signal crashed(car, dv)
signal destroyed(car)

const WATER_Y := 0.9

var kind := "boat"          # boat, plane, heli
var throttle := 0.0
var brake_in := 0.0
var steer_in := 0.0
var handbrake := false
var stick := Vector2.ZERO
var max_engine := 1.0
var police := false
var ai_target: Node3D = null
var ai_mode := ""           # "" ou "follow" (helicóptero da polícia)
var ai_speed := 24.0
var _far_chk := 0.0
var _far := false        # velocidade máxima seguindo o alvo
var driver: Node = null
var wheels: Array = []
var lean: Node3D = null
var body_size := Vector3(2, 1.5, 6)
var seat := Vector3(0, 0.6, 0)
var model_root: Node3D
var hp := 100.0
var dead := false
var parked := false
var linear_velocity := Vector3.ZERO
var engine_on := false
var world2: Node = null      # para saber onde é água
var v := 0.0                 # velocidade escalar para a frente
var _rot_main: Node3D
var _rot_tail: Node3D
var _prop: Node3D
var _t := 0.0
var _fire: CPUParticles3D
var _smoke: CPUParticles3D
var _fall := false
var yaw := 0.0
var sinking := false
const MAX_ALT := 260.0
const MAX_DIST := 1600.0
var pitch := 0.0
var roll := 0.0
var vy := 0.0

var _spl_t := 0.0
var armed := false           # caça / helicóptero de ataque: metralhadora + mísseis
var subkind := ""           # boat / jetski / ship (todos usam a física de barco)
var ai_path: Array = []      # patrulha em volta da ilha (barcos com piloto NPC)
var ai_i := 0
var npc_drv: Node3D = null

func setup(k: String, paint: Color) -> void:
	subkind = k
	if k in ["jetski", "ship"]:
		k = "boat"
	elif k == "jet":
		k = "plane"
		armed = true
	elif k == "attack":
		k = "heli"
		armed = true
	kind = k
	collision_layer = 1
	collision_mask = 1
	model_root = Node3D.new()
	add_child(model_root)
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	match kind:
		"boat":
			if subkind == "jetski":
				_jetski(paint)
				body_size = Vector3(1.2, 1.1, 3.2)
				seat = Vector3(0, 0.75, -0.3)
				hp = 70.0
			elif subkind == "ship":
				_ship(paint)
				body_size = Vector3(9.0, 9.0, 42.0)
				seat = Vector3(0, 9.2, -12.5)
				hp = 900.0
			else:
				_boat(paint)
				body_size = Vector3(2.2, 1.4, 6.0)
				seat = Vector3(0.35, 1.08, -0.4)      # sobre o banco (antes afundava no piso)
				hp = 120.0
		"plane":
			if armed:
				_fighter(paint)
				body_size = Vector3(9.6, 3.0, 13.0)
				seat = Vector3(0, 1.25, 2.2)
				hp = 320.0
			else:
				_plane(paint)
				body_size = Vector3(10.5, 2.6, 8.4)
				seat = Vector3(0, 0.95, 0.6)
				hp = 140.0
		"heli":
			_heli(paint, police)
			body_size = Vector3(2.4, 2.8, 9.0)
			seat = Vector3(0.35, 0.65, 0.9)
			hp = 160.0
			if armed:
				_attack_kit()
				hp = 300.0
	bx.size = Vector3(minf(body_size.x, 2.4), 1.2, body_size.z * 0.8) if subkind != "ship" else Vector3(8.6, 4.0, 40.0)
	cs.shape = bx
	cs.position = Vector3(0, 0.8, 0)
	add_child(cs)
	preload("res://scripts/car.gd").optimize_visuals(model_root, 0.0)

func door_world() -> Vector3:
	return global_transform * Vector3(body_size.x * 0.5 + 0.9 if kind != "plane" else 1.6, 0, seat.z)

func set_door(_a: float) -> void:
	pass

func speed_kmh() -> float:
	return linear_velocity.length() * 3.6

func forward_speed() -> float:
	return v

func take_damage(d: float) -> void:
	if dead:
		return
	hp -= d
	if hp < 40.0 and _smoke == null:
		_smoke = FX.smoke_emitter(model_root, Vector3(0, 1.2, -0.5))
	if hp < 15.0 and _fire == null:
		_fire = FX.fire_emitter(model_root, Vector3(0, 1.0, -0.5))
		if kind != "boat" and global_position.y > 2.0:
			_fall = true     # motor falha: cai girando
	if hp <= 0.0:
		if kind == "boat":
			_sink()      # barco destruído no mar afunda (o jogador cai na água)
		else:
			explode()

func _sink() -> void:
	if sinking:
		return
	sinking = true
	dead = true
	engine_on = false
	FX.splash(get_tree().current_scene, global_position + Vector3(0, 0.8, 0), 2.0)
	destroyed_water.emit(self)
	FX.extinguish(self)
	get_tree().create_timer(40.0).timeout.connect(queue_free)

signal destroyed_water(car)

# ---------------------------------------------------------------- helicóptero da polícia: atiradores, piloto e hélices
var gunners: Array = []       # [{h: Humanoid, hp, side, cool}]
var pilot_hp := 110.0
var rotor_hp := 140.0
var crew_dead := false
func add_gunners() -> void:
	var Hum := preload("res://scripts/humanoid.gd")
	var Wp := preload("res://scripts/weapons.gd")
	for side in [-1.0, 1.0]:
		var h = Hum.new()
		h.build(Color(0.1, 0.1, 0.12), Color(0.08, 0.08, 0.1), Color(0.78, 0.56, 0.38), Color(0.05, 0.05, 0.06), {"hat": 2, "hat_c": Color(0.08, 0.08, 0.1), "glasses": true, "jacket": Color(0.12, 0.13, 0.15)})
		model_root.add_child(h)
		h.sitting = true
		h.scale = Vector3.ONE * 0.85
		h.position = Vector3(1.0 * side, 0.55 - 0.98 * 0.85 + 0.4, 0.2)
		h.rotation.y = PI * 0.5 * side         # virado para fora (porta aberta)
		h.give_gun(Wp.gun_mesh("rifle"))
		h.gun_kind = "rifle"
		h.aiming = true
		h.animate(0, 0)
		gunners.append({"h": h, "hp": 90.0, "side": side, "cool": randf_range(0.5, 1.5)})
	# hélice com colisão (tiro na hélice derruba)
	var rs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 4.6
	cyl.height = 0.35
	rs.shape = cyl
	rs.position = Vector3(0, 2.85, 0.2)
	add_child(rs)
	var cab := CollisionShape3D.new()
	var cb := BoxShape3D.new()
	cb.size = Vector3(2.2, 1.2, 3.0)
	cab.shape = cb
	cab.position = Vector3(0, 1.9, 0.6)
	add_child(cab)

## tiro acertou o helicóptero em pos: atirador da porta, piloto (pelo vidro) ou hélice
func hit_at(pos: Vector3, dmg: float) -> String:
	var lp: Vector3 = global_transform.affine_inverse() * pos
	for g in gunners:
		if g.hp > 0.0 and is_instance_valid(g.h) and lp.distance_to(g.h.position + Vector3(0, 0.95, 0)) < 0.75:
			g.hp -= dmg
			if g.hp <= 0.0:
				_gunner_down(g)
			return "gunner"
	if lp.y > 2.55 and kind == "heli":
		rotor_hp -= dmg
		if rotor_hp <= 0.0 and not _fall:
			_fall = true
			FX.sparks(get_tree().current_scene, pos)
		return "rotor"
	if kind == "heli" and driver == null and lp.z > 0.6 and lp.y > 1.0:
		pilot_hp -= dmg * 0.55
		if pilot_hp <= 0.0 and not _fall:
			_fall = true                 # piloto atingido: perde o controle, cai e explode
			ai_mode = ""
			FX.blood_burst(get_tree().current_scene, pos, Vector3.UP, 16)
		return "pilot"
	return ""

func _gunner_down(g: Dictionary) -> void:
	var h = g.h
	var gp: Vector3 = h.global_position
	var sc := get_tree().current_scene
	FX.blood_burst(sc, gp + Vector3(0, 1.0, 0), Vector3.UP, 18)
	sc.audio.play("scream", gp, 0.0)
	model_root.remove_child(h)
	sc.add_child(h)
	h.global_position = gp
	h.scale = Vector3.ONE
	h.sitting = false
	h.add_to_group("tmp")
	h.ragdoll(global_transform.basis.x * g.side * 4.0 + velocity, null, false)
	gunners.erase(g)
	if gunners.is_empty():
		crew_dead = true

func explode() -> void:
	if dead:
		return
	dead = true
	engine_on = false
	var burnt := M.plain(Color(0.06, 0.055, 0.05), 0.95)
	for n in model_root.find_children("*", "MeshInstance3D", true, false):
		n.material_override = burnt
	if _fire == null:
		_fire = FX.fire_emitter(model_root, Vector3(0, 1.0, 0))
	destroyed.emit(self)

var _inited := false
func _physics_process(dt: float) -> void:
	if not _inited:
		_inited = true
		yaw = rotation.y
	_t += dt
	if _rot_main:
		_rot_main.rotate_y(dt * (28.0 if engine_on or _fall else 0.0))
	if _rot_tail:
		_rot_tail.rotate_x(dt * (40.0 if engine_on else 0.0))
	if _prop:
		_prop.rotate_z(dt * (30.0 * clampf(v / 10.0 + (0.4 if engine_on else 0.0), 0.0, 1.5)))
	# otimização: veículo parado, sem piloto e longe do jogador não roda física
	if driver == null and ai_mode == "" and (npc_drv == null or ai_path.is_empty()) and not sinking and not _fall and absf(v) < 0.05 and velocity.length_squared() < 0.01 and absf(throttle) < 0.01:
		_far_chk -= dt
		if _far_chk <= 0.0:
			_far_chk = 0.5
			var pl = world2.main.player if world2 and world2.main else null
			_far = pl != null and global_position.distance_squared_to(pl.global_position) > 90.0 * 90.0
		if _far:
			return
	else:
		_far = false
	if sinking:
		velocity = velocity.lerp(Vector3(0, -1.4, 0), dt * 1.5)
		move_and_slide()
		model_root.rotation.x = lerpf(model_root.rotation.x, 0.5, dt * 0.3)
		return
	# limites: alto demais ou longe demais = o motor falha e a aeronave cai
	if kind in ["plane", "heli"] and not dead and not _fall and (global_position.y > MAX_ALT or Vector2(global_position.x, global_position.z).length() > MAX_DIST):
		_fall = true
		if _smoke == null:
			_smoke = FX.smoke_emitter(model_root, Vector3(0, 1.2, -0.5))
	# na água: afunda (avião/helicóptero que cai no mar, barco destruído)
	if world2 and world2.is_water(global_position.x, global_position.z) and global_position.y < world2.WATER_Y + (0.6 if kind != "boat" else -0.2) and (kind != "boat" or dead):
		_sink()
		return
	var before := velocity
	match kind:
		"boat": _boat_phys(dt)
		"plane": _plane_phys(dt)
		"heli": _heli_phys(dt)
	linear_velocity = velocity
	# barco/jet-ski andando: respingos na popa e nas laterais
	if kind == "boat" and not sinking and absf(v) > 4.0:
		_spl_t -= dt
		if _spl_t <= 0.0:
			_spl_t = 0.22 if subkind == "jetski" else 0.32
			var sc := get_tree().current_scene
			if sc.cam.global_position.distance_to(global_position) < 70.0:
				var back := -global_transform.basis.z * body_size.z * 0.45
				FX.splash(sc, Vector3(global_position.x, WATER_Y, global_position.z) + back, 0.2 + absf(v) / 70.0)
	# batida em parede/prédio
	if get_slide_collision_count() > 0:
		var dv := (before - velocity).length()
		if dv > 7.0:
			take_damage((dv - 7.0) * (6.0 if kind != "boat" else 3.0))
			crashed.emit(self, dv)
			if kind == "plane" and dv > 14.0:
				explode()

# ---------------------------------------------------------------- barco
func _boat_phys(dt: float) -> void:
	# piloto NPC: segue a rota de patrulha em volta da ilha
	if driver == null and npc_drv != null and not ai_path.is_empty() and not dead:
		var tp: Vector3 = ai_path[ai_i]
		var to := tp - global_position
		to.y = 0
		if to.length() < 25.0:
			ai_i = (ai_i + 1) % ai_path.size()
		var want := atan2(to.x, to.z)
		steer_in = clampf(wrapf(want - yaw, -PI, PI) * 1.5, -1.0, 1.0)
		throttle = 0.6
	var drive := not dead and (driver != null or ai_target != null or throttle != 0.0)
	engine_on = drive
	var vmax := 30.0 if subkind == "jetski" else (10.0 if subkind == "ship" else 26.0)
	var acc := throttle * (14.0 if subkind == "jetski" else (2.5 if subkind == "ship" else 11.0)) if drive else 0.0
	v += acc * dt
	v -= v * (0.35 if absf(throttle) > 0.05 else 0.9) * dt * (0.3 if subkind == "ship" else 1.0)
	v = clampf(v, -6.0, vmax)
	yaw += steer_in * (1.6 if subkind == "jetski" else (0.18 if subkind == "ship" else 1.1)) * clampf(absf(v) / 5.0, 0.0, 1.0) * signf(v + 0.01) * dt
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var next := global_position + fwd * v * dt
	if world2 and not world2.is_water(next.x, next.z):
		v = -v * 0.3
		if absf(v) > 4.0:
			take_damage(absf(v) * 2.0)
	velocity = fwd * v
	var float_y := WATER_Y - (0.55 if subkind != "ship" else 3.2)
	velocity.y = (float_y - global_position.y) * 6.0 if not dead else -0.6
	move_and_slide()
	if dead and global_position.y < -2.5:
		queue_free()
	# balanço nas ondas e empinar com a aceleração
	rotation = Vector3(0, yaw, 0)
	model_root.rotation.x = -clampf(v / 26.0, 0.0, 1.0) * 0.12 + sin(_t * 1.7) * 0.025
	model_root.rotation.z = sin(_t * 1.3) * 0.03 - steer_in * clampf(v / 20.0, 0.0, 1.0) * 0.12

# ---------------------------------------------------------------- avião
func _plane_phys(dt: float) -> void:
	var on_ground := global_position.y < 0.15
	engine_on = driver != null and not dead
	var thr := throttle if engine_on else 0.0
	v += (thr * ((26.0 if armed else 16.0) if thr > 0 else 22.0) - v * (0.1 if armed else 0.12)) * dt
	v = clampf(v, 0.0, 98.0 if armed else 62.0)
	if on_ground:
		yaw += steer_in * 0.8 * clampf(v / 8.0, 0.0, 1.0) * dt
		roll = lerpf(roll, 0.0, dt * 4.0)
		var want_pitch := 0.0
		if v > 24.0 and stick.y < -0.2:
			want_pitch = 0.25     # decolagem: puxe o manche (joystick para trás)
		pitch = lerpf(pitch, want_pitch, dt * 2.0)
		vy = 0.0
	else:
		roll = lerpf(roll, -stick.x * 0.95, dt * 2.5)
		pitch = clampf(pitch - stick.y * 1.1 * dt, -0.9, 0.9)
		yaw += roll * 0.9 * dt
	if _fall:
		roll += dt * 2.5
		pitch = lerpf(pitch, -0.7, dt)
	var fwd := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var vel := fwd * v
	# sustentação: abaixo de 20 m/s o avião afunda (estol)
	var lift := clampf((v - 14.0) / 10.0, 0.0, 1.0)
	if not on_ground or pitch > 0.05:
		vy = lerpf(vy, -9.0 * (1.0 - lift), dt * 1.5)
		vel.y += vy
	if _fall:
		vel.y -= 12.0
	velocity = vel
	move_and_slide()
	if global_position.y < 0.0:
		var impact := -vel.y
		global_position.y = 0.0
		if impact > 7.0 or pitch < -0.35 or _fall or absf(roll) > 0.8:
			explode()
			v = 0.0
		pitch = maxf(pitch, 0.0)
	rotation = Vector3(0, 0, 0)
	basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch) * Basis(Vector3.FORWARD, -roll)

# ---------------------------------------------------------------- helicóptero
func _heli_phys(dt: float) -> void:
	engine_on = (driver != null or ai_mode != "") and not dead
	var target_v := Vector3.ZERO
	var climb := 0.0
	if ai_mode == "follow" and ai_target and is_instance_valid(ai_target):
		# polícia: circula o alvo a 22 m de altura
		var c := ai_target.global_position + Vector3(cos(_t * 0.35) * 18.0, 0, sin(_t * 0.35) * 18.0)
		var to := c - global_position
		to.y = 0
		target_v = to.limit_length(ai_speed)
		climb = clampf((ai_target.global_position.y + 22.0 - global_position.y) * 0.8, -6.0, 6.0)
		var face := ai_target.global_position - global_position
		yaw = lerp_angle(yaw, atan2(face.x, face.z), dt * 1.5)
	elif ai_mode == "leave":
		target_v = Vector3(sin(yaw), 0, cos(yaw)) * 25.0
		climb = 4.0
	elif engine_on:
		yaw -= stick.x * 1.4 * dt
		var fwd := Vector3(sin(yaw), 0, cos(yaw))
		target_v = fwd * stick.y * (38.0 if armed else 30.0)
		climb = (throttle * 7.0) if absf(throttle) > 0.05 else 0.0
	var hv := Vector3(velocity.x, 0, velocity.z).lerp(target_v, dt * 1.2)
	var vyy := lerpf(velocity.y, climb, dt * 2.0)
	if not engine_on:
		vyy = velocity.y - 14.0 * dt
		hv = hv.lerp(Vector3.ZERO, dt * 0.5)
	if _fall:
		yaw += dt * 4.0
		vyy = velocity.y - 10.0 * dt
	velocity = Vector3(hv.x, vyy, hv.z)
	move_and_slide()
	if global_position.y < 0.0:
		if velocity.y < -9.0 or _fall:
			explode()
		global_position.y = 0.0
		velocity.y = 0.0
	# inclina para onde acelera
	var local := Basis(Vector3.UP, yaw).inverse() * hv
	pitch = lerpf(pitch, -clampf(local.z / 30.0, -1, 1) * 0.25, dt * 3.0)
	roll = lerpf(roll, clampf(local.x / 30.0, -1, 1) * 0.25, dt * 3.0)
	basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch) * Basis(Vector3.FORWARD, roll)
	v = hv.length()

# ---------------------------------------------------------------- modelos
func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

func _commit(st: SurfaceTool, parent: Node3D, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat if mat else CM.vc_mat()
	parent.add_child(mi)
	return mi

func _glass() -> StandardMaterial3D:
	var g := StandardMaterial3D.new()
	g.albedo_color = Color(0.1, 0.16, 0.22, 0.55)
	g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.metallic = 0.8
	g.roughness = 0.05
	return g

func _cyl(r: float, h: float, seg := 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c

func _boat(paint: Color) -> void:
	var st := _st()
	var white := Color(0.93, 0.93, 0.92)
	# casco: fatias que afinam na proa
	for i in 12:
		var z := lerpf(-2.9, 2.2, i / 11.0)
		var w := 2.1 * (1.0 - pow(clampf((z - 0.2) / 2.2, 0.0, 1.0), 1.6) * 0.85)
		CM._box(st, Vector3(w, 0.9, 0.46), Vector3(0, 0.45 + clampf((z - 0.8) * 0.15, 0, 0.25), z), white)
		CM._box(st, Vector3(w + 0.02, 0.22, 0.46), Vector3(0, 0.25, z), paint)
	CM._ell(st, Vector3(0, 0.62, 2.55), Vector3(0.55, 0.62, 1.2), white)
	CM._box(st, Vector3(1.7, 0.1, 3.6), Vector3(0, 0.88, -0.6), Color(0.55, 0.42, 0.28))    # piso
	CM._box(st, Vector3(0.6, 0.85, 0.6), Vector3(0.35, 1.2, 0.35), Color(0.85, 0.85, 0.84))  # console
	CM._box(st, Vector3(0.5, 0.15, 0.5), Vector3(0.35, 1.0, -0.4), Color(0.1, 0.1, 0.12))    # banco
	CM._box(st, Vector3(0.5, 0.55, 0.1), Vector3(0.35, 1.3, -0.62), Color(0.1, 0.1, 0.12))
	CM._box(st, Vector3(1.6, 0.4, 0.5), Vector3(0, 1.08, -2.3), Color(0.1, 0.1, 0.12))       # banco de trás
	CM._box(st, Vector3(0.45, 1.0, 0.45), Vector3(0, 0.9, -3.05), Color(0.12, 0.12, 0.13))   # motor de popa
	CM._box(st, Vector3(0.15, 0.7, 0.15), Vector3(0, 0.3, -3.1), Color(0.3, 0.3, 0.32))
	_commit(st, model_root)
	var g := _st()
	CM._box(g, Vector3(0.9, 0.45, 0.04), Vector3(0.35, 1.82, 0.7), Color(1, 1, 1))
	var gm := _commit(g, model_root, _glass())
	gm.rotation.x = -0.4

func _plane(paint: Color) -> void:
	var st := _st()
	var white := Color(0.93, 0.93, 0.92)
	CM._ell(st, Vector3(0, 1.3, 0.2), Vector3(1.3, 1.35, 7.6), white)                   # fuselagem
	CM._ell(st, Vector3(0, 1.32, 0.0), Vector3(1.32, 0.3, 7.4), paint)                  # faixa
	CM._box(st, Vector3(10.5, 0.14, 1.6), Vector3(0, 1.85, 0.6), white)                 # asa
	for s in [-1.0, 1.0]:
		CM._box(st, Vector3(0.6, 0.16, 1.62), Vector3(4.9 * s, 1.85, 0.6), paint)       # pontas
		CM._prim(st, _cyl(0.04, 1.3, 6), Transform3D(Basis(Vector3.FORWARD, 0.5 * s), Vector3(1.2 * s, 1.25, 0.6)), Color(0.3, 0.3, 0.32))
	CM._box(st, Vector3(3.6, 0.1, 0.9), Vector3(0, 1.5, -3.4), white)                  # estabilizador
	CM._box(st, Vector3(0.1, 1.4, 1.1), Vector3(0, 2.1, -3.45), paint)                 # leme
	# trem de pouso
	for p in [Vector3(1.2, 0.35, 0.9), Vector3(-1.2, 0.35, 0.9), Vector3(0, 0.3, 3.0)]:
		CM._prim(st, _cyl(0.32, 0.18, 12), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), p), Color(0.05, 0.05, 0.05))
		CM._box(st, Vector3(0.08, 0.7, 0.08), p + Vector3(0, 0.4, 0), Color(0.3, 0.3, 0.32))
	CM._box(st, Vector3(0.7, 0.1, 0.8), Vector3(0, 0.95, 0.6), Color(0.12, 0.12, 0.13))  # banco
	CM._box(st, Vector3(0.8, 0.35, 0.15), Vector3(0, 1.45, 1.55), Color(0.1, 0.1, 0.1)) # painel
	_commit(st, model_root)
	var g := _st()
	CM._ell(g, Vector3(0, 1.95, 1.0), Vector3(0.95, 0.7, 2.0), Color(1, 1, 1))
	_commit(g, model_root, _glass())
	_prop = Node3D.new()
	_prop.position = Vector3(0, 1.3, 4.0)
	model_root.add_child(_prop)
	var ps := _st()
	CM._box(ps, Vector3(0.18, 2.3, 0.06), Vector3.ZERO, Color(0.08, 0.08, 0.08))
	CM._ell(ps, Vector3(0, 0, 0.1), Vector3(0.35, 0.35, 0.4), paint)
	_commit(ps, _prop)

func _heli(paint: Color, pol: bool) -> void:
	var st := _st()
	var c2 := Color(0.12, 0.12, 0.14) if pol else Color(0.9, 0.9, 0.9)
	CM._ell(st, Vector3(0, 1.5, 0.4), Vector3(2.1, 1.9, 4.0), paint)
	CM._box(st, Vector3(0.35, 0.4, 4.6), Vector3(0, 1.75, -3.6), paint)
	CM._box(st, Vector3(0.12, 1.1, 0.7), Vector3(0, 2.3, -5.7), c2)
	CM._box(st, Vector3(1.4, 0.08, 0.5), Vector3(0, 1.8, -5.4), c2)
	CM._box(st, Vector3(0.6, 0.4, 0.8), Vector3(0, 2.55, 0.2), c2)                       # motor
	for s in [-1.0, 1.0]:
		CM._box(st, Vector3(0.1, 0.1, 3.4), Vector3(1.0 * s, 0.08, 0.3), Color(0.15, 0.15, 0.16))   # esquis
		CM._box(st, Vector3(0.08, 0.6, 0.08), Vector3(0.9 * s, 0.4, 1.0), Color(0.15, 0.15, 0.16))
		CM._box(st, Vector3(0.08, 0.6, 0.08), Vector3(0.9 * s, 0.4, -0.5), Color(0.15, 0.15, 0.16))
	CM._box(st, Vector3(1.4, 0.12, 0.6), Vector3(0, 0.75, 0.2), Color(0.1, 0.1, 0.12))
	if pol:
		CM._box(st, Vector3(2.12, 0.25, 2.0), Vector3(0, 1.4, 0.0), Color(0.95, 0.95, 0.95))
	_commit(st, model_root)
	var g := _st()
	CM._ell(g, Vector3(0, 1.7, 1.55), Vector3(1.8, 1.5, 1.8), Color(1, 1, 1))
	_commit(g, model_root, _glass())
	_rot_main = Node3D.new()
	_rot_main.position = Vector3(0, 2.85, 0.2)
	model_root.add_child(_rot_main)
	var rs := _st()
	for q in 2:
		CM._prim(rs, _blade(), Transform3D(Basis(Vector3.UP, q * PI * 0.5), Vector3.ZERO), Color(0.1, 0.1, 0.1))
	_commit(rs, _rot_main)
	_rot_tail = Node3D.new()
	_rot_tail.position = Vector3(0.25, 2.3, -5.7)
	model_root.add_child(_rot_tail)
	var ts := _st()
	CM._box(ts, Vector3(0.04, 1.3, 0.14), Vector3.ZERO, Color(0.1, 0.1, 0.1))
	CM._box(ts, Vector3(0.04, 0.14, 1.3), Vector3.ZERO, Color(0.1, 0.1, 0.1))
	_commit(ts, _rot_tail)

func _blade() -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(0.28, 0.04, 10.4)
	return b


func _jetski(paint: Color) -> void:
	var st := _st()
	CM._ell(st, Vector3(0, 0.45, 0.1), Vector3(1.1, 0.55, 3.2), paint)
	CM._ell(st, Vector3(0, 0.32, 0.0), Vector3(1.15, 0.3, 3.1), Color(0.95, 0.95, 0.95))
	CM._ell(st, Vector3(0, 0.82, -0.45), Vector3(0.45, 0.22, 1.2), Color(0.08, 0.08, 0.1))   # banco
	CM._box(st, Vector3(0.5, 0.35, 0.3), Vector3(0, 0.95, 0.55), paint.darkened(0.3))        # console
	CM._box(st, Vector3(0.75, 0.05, 0.05), Vector3(0, 1.15, 0.5), Color(0.1, 0.1, 0.1))      # guidão
	_commit(st, model_root)

## navio de carga: casco, ponte de comando na popa e contêineres no convés
func _ship(paint: Color) -> void:
	var st := _st()
	var hull := Color(0.15, 0.2, 0.3)
	for i in 21:
		var z := lerpf(-21.0, 21.0, i / 20.0)
		var w := 9.0 * (1.0 - pow(clampf((z - 10.0) / 11.0, 0.0, 1.0), 1.5) * 0.8)
		CM._box(st, Vector3(w, 5.0, 2.1), Vector3(0, 2.5, z), hull)
		CM._box(st, Vector3(w + 0.05, 1.0, 2.1), Vector3(0, 0.5, z), Color(0.6, 0.1, 0.08))
	CM._box(st, Vector3(8.6, 0.2, 40.0), Vector3(0, 5.1, 0), Color(0.45, 0.45, 0.42))
	CM._box(st, Vector3(8.0, 6.0, 6.0), Vector3(0, 8.0, -15.5), Color(0.92, 0.92, 0.9))     # ponte
	CM._box(st, Vector3(8.4, 0.3, 6.4), Vector3(0, 11.1, -15.5), Color(0.3, 0.3, 0.32))
	CM._box(st, Vector3(1.2, 4.0, 1.2), Vector3(0, 13.0, -17.0), Color(0.75, 0.12, 0.1))   # chaminé
	var cc := [Color(0.75, 0.2, 0.1), Color(0.1, 0.35, 0.6), Color(0.85, 0.6, 0.1), Color(0.2, 0.5, 0.3)]
	for r in 6:
		for c in 3:
			for h in 2:
				CM._box(st, Vector3(2.4, 2.5, 5.8), Vector3(-2.7 + c * 2.7, 6.45 + h * 2.55, -8.0 + r * 4.6 + 2.0), cc[(r + c + h) % 4])
	_commit(st, model_root)

# ---------------------------------------------------------------- caça (asa delta, cockpit, mísseis sob as asas)
func _fighter(paint: Color) -> void:
	var st := _st()
	var dark := paint.darkened(0.35)
	CM._ell(st, Vector3(0, 1.5, 0), Vector3(1.5, 1.35, 13.0), paint)                  # fuselagem
	CM._ell(st, Vector3(0, 1.5, 6.1), Vector3(0.5, 0.5, 1.6), Color(0.2, 0.2, 0.22))    # cone do nariz
	for s in [-1.0, 1.0]:
		# asa delta: triângulo grosso (quadriláteros em cima e embaixo)
		var a := Vector3(0.6 * s, 1.35, 2.0)
		var bb := Vector3(4.8 * s, 1.3, -3.2)
		var cc := Vector3(0.6 * s, 1.35, -4.4)
		# faces dos dois lados (cima e baixo), com cor e normal explícitas
		for y in [0.0, -0.14]:
			st.set_color(paint)
			st.set_normal(Vector3.UP if y == 0.0 else Vector3.DOWN)
			var p0: Vector3 = a + Vector3(0, y, 0)
			var p1: Vector3 = bb + Vector3(0, y, 0)
			var p2: Vector3 = cc + Vector3(0, y, 0)
			CM._tri(st, p0, p1, p2)
			CM._tri(st, p0, p2, p1)
		CM._box(st, Vector3(0.12, 0.2, 1.4), bb + Vector3(0, -0.05, 0.4), dark)
		CM._prim(st, _cyl(0.13, 2.0, 8), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(2.6 * s, 1.08, -1.0)), Color(0.85, 0.85, 0.82))
		CM._ell(st, Vector3(2.6 * s, 1.08, 0.05), Vector3(0.26, 0.26, 0.4), Color(0.75, 0.1, 0.1))
		CM._box(st, Vector3(1.8, 0.1, 1.2), Vector3(1.3 * s, 1.5, -5.6), paint)             # profundor
		CM._box(st, Vector3(0.12, 2.2, 1.7), Vector3(0.75 * s, 2.7, -5.2), dark)           # deriva dupla
		CM._ell(st, Vector3(0.95 * s, 1.15, 1.6), Vector3(0.55, 0.7, 2.4), dark)           # entradas de ar
		CM._prim(st, _cyl(0.22, 0.16, 10), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(1.2 * s, 0.25, -1.0)), Color(0.05, 0.05, 0.05))
		CM._box(st, Vector3(0.08, 0.9, 0.08), Vector3(1.2 * s, 0.7, -1.0), Color(0.3, 0.3, 0.32))
	CM._prim(st, _cyl(0.55, 0.6, 14), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.45, -6.4)), Color(0.12, 0.12, 0.12))
	CM._prim(st, _cyl(0.2, 0.16, 10), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 0.25, 4.0)), Color(0.05, 0.05, 0.05))
	CM._box(st, Vector3(0.08, 0.9, 0.08), Vector3(0, 0.7, 4.0), Color(0.3, 0.3, 0.32))
	CM._box(st, Vector3(0.62, 0.1, 0.8), Vector3(0, 1.25, 2.2), Color(0.1, 0.1, 0.1))     # banco
	CM._box(st, Vector3(0.7, 0.3, 0.2), Vector3(0, 1.75, 3.1), Color(0.08, 0.08, 0.09))    # painel
	_commit(st, model_root)
	var g := _st()
	CM._ell(g, Vector3(0, 2.15, 2.4), Vector3(0.95, 0.75, 2.8), Color(1, 1, 1))
	_commit(g, model_root, _glass())

## helicóptero de ataque: casulos de foguete e metralhadora no nariz
func _attack_kit() -> void:
	var st := _st()
	var dark := Color(0.12, 0.13, 0.12)
	for s in [-1.0, 1.0]:
		CM._box(st, Vector3(1.6, 0.12, 0.5), Vector3(1.4 * s, 1.15, 0.3), dark)
		CM._prim(st, _cyl(0.22, 1.4, 10), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(2.1 * s, 0.95, 0.4)), Color(0.25, 0.28, 0.22))
		CM._ell(st, Vector3(2.1 * s, 0.95, 1.12), Vector3(0.4, 0.4, 0.12), Color(0.06, 0.06, 0.06))
	CM._prim(st, _cyl(0.06, 1.2, 8), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.7, 2.6)), dark)
	CM._ell(st, Vector3(0, 0.75, 2.0), Vector3(0.45, 0.45, 0.45), dark)
	_commit(st, model_root)

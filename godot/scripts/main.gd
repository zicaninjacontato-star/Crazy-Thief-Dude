extends Node3D
## Fatia de teste: monta ambiente (céu, sol, sombras, tonemap), cidade, jogador, carros, pedestres e polícia.

const City := preload("res://scripts/city.gd")
const Player := preload("res://scripts/player.gd")
const Car := preload("res://scripts/car.gd")
const Ped := preload("res://scripts/ped.gd")
const Hud := preload("res://scripts/hud.gd")
const Humanoid := preload("res://scripts/humanoid.gd")
const Audio := preload("res://scripts/audio.gd")
const FX := preload("res://scripts/fx.gd")
const Combat := preload("res://scripts/combat.gd")

var city: Node3D
var player: CharacterBody3D
var hud: CanvasLayer
var cam: Camera3D
var cars: Array = []
var peds: Array = []
var traffic: Array = []
var police_car = null
var my_car = null
var seated: Node3D
var wanted := 0
var wanted_timer := 0.0
var bust_timer := 0.0
var cam_yaw := PI
var cam_pitch := -0.32
var cam_idle := 0.0
var rng := RandomNumberGenerator.new()
var fps_acc := 0.0
var fps_n := 0
var fps_show := 0.0
var shot := ""
var shot_view := ""
var shot_at := 240
var shot_ped = null
var frames := 0
var msg_t := 0.0
var build_id := "dev"
var audio: Node
var money := 600
var hp := 100.0
var gore := true
var _step_ph := 0.0
var _lastv := Vector3.ZERO
var combat: Node

func _ready() -> void:
	rng.seed = 7
	if FileAccess.file_exists("res://build.txt"):
		build_id = FileAccess.get_file_as_string("res://build.txt").strip_edges()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): shot = a.substr(7)
		if a.begins_with("--view="): shot_view = a.substr(7)
		if a.begins_with("--at="): shot_at = int(a.substr(5))
	_inputs()
	_environment()
	# desempenho no celular: 3D em 75% da resolução + FXAA (sem MSAA)
	if OS.has_feature("mobile"):
		get_viewport().scaling_3d_scale = 0.75
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	audio = Audio.new()
	add_child(audio)
	city = City.new()
	add_child(city)
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.far = 650.0
	add_child(cam)
	cam.make_current()
	player = Player.new()
	add_child(player)
	player.position = Vector3(city._center(2) - city.BLOCK * 0.5 + 1.5, 0.3, city._center(2))
	hud = Hud.new()
	add_child(hud)
	hud.enter_pressed.connect(_toggle_car)
	for k in city.N + 1:
		hud.map_roads.append((k - city.N * 0.5) * city.CELL)
	hud.map_roadw = city.ROADW
	hud.jump_pressed.connect(func(): player.jump())
	# carro do jogador estacionado ao lado
	var road_x: float = city._center(2) - city.CELL * 0.5
	my_car = _spawn_car(Vector3(road_x + 2.6, 0.6, city._center(2) + 4.0), 0.0, Color(0.06, 0.2, 0.55), false, "sport")
	var palette := [Color(0.55, 0.02, 0.03), Color(0.85, 0.85, 0.86), Color(0.05, 0.05, 0.06), Color(0.75, 0.45, 0.05), Color(0.2, 0.22, 0.25)]
	for k in 5:
		var rx: float = city._center(rng.randi_range(0, 4)) + city.CELL * 0.5 * (1 if rng.randf() < 0.5 else -1)
		_spawn_car(Vector3(rx + 5.6, 0.6, rng.randf_range(-120, 120)), 0.0 if rng.randf() < 0.5 else PI, palette[k % palette.size()])
	# trânsito: 3 carros rodando em volta da quadra central
	for k in 3:
		var c = _spawn_car(Vector3(0, 0.6, 0), 0.0, palette[(k + 2) % palette.size()])
		var loop := _block_loop(2, 2, k)
		c.position = loop[0]
		var mk := Marker3D.new()
		add_child(mk)
		c.ai_target = mk
		c.max_engine = 3000.0
		traffic.append({"car": c, "loop": loop, "i": 1, "mk": mk})
	# pedestres
	for k in 26:
		var p := Ped.new()
		add_child(p)
		var loopw: Array = city.walk_loops[rng.randi() % city.walk_loops.size()]
		p.setup(loopw, rng.randi_range(0, 3), rng)
		p.position = loopw[p.idx].lerp(loopw[(p.idx + 1) % 4], rng.randf())
		peds.append(p)
	for p in peds:
		p.died.connect(_on_ped_died)
	combat = Combat.new()
	add_child(combat)
	combat.setup(self)
	hud.weapon_pressed.connect(func(): combat.cycle())

func _on_ped_died(p) -> void:
	combat.drop_cash(p.global_position)

func _block_loop(i: int, j: int, k: int) -> Array:
	var cx: float = city._center(i)
	var cz: float = city._center(j)
	var r: float = city.CELL * 0.5 + 2.6
	var pts := [Vector3(cx - r, 0.6, cz - r), Vector3(cx - r, 0.6, cz + r), Vector3(cx + r, 0.6, cz + r), Vector3(cx + r, 0.6, cz - r)]
	var out := []
	for q in 4:
		out.append(pts[(q + k) % 4])
	return out

func _spawn_car(pos: Vector3, yaw: float, paint: Color, police := false, kind := ""):
	var c := Car.new()
	add_child(c)
	var kinds := ["sedan", "sedan", "hatch", "suv", "pickup", "sport"]
	c.setup("police" if police else (kind if kind != "" else kinds[rng.randi() % kinds.size()]), paint)
	c.global_position = pos
	c.rotation.y = yaw
	cars.append(c)
	return c

func _inputs() -> void:
	var map := {"move_f": [KEY_W, KEY_UP], "move_b": [KEY_S, KEY_DOWN], "move_l": [KEY_A, KEY_LEFT], "move_r": [KEY_D, KEY_RIGHT], "enter": [KEY_E, KEY_F], "jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "fire": [KEY_J, KEY_CTRL], "weapon": [KEY_Q, KEY_TAB]}
	for a in map:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		for k in map[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(a, ev)

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.2, 0.42, 0.78)
	sm.sky_horizon_color = Color(0.7, 0.78, 0.86)
	sm.ground_bottom_color = Color(0.18, 0.17, 0.16)
	sm.ground_horizon_color = Color(0.6, 0.64, 0.68)
	sm.sun_angle_max = 25.0
	sm.sun_curve = 0.08
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.ambient_light_sky_contribution = 0.45
	env.ambient_light_color = Color(0.56, 0.56, 0.58)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.75, 0.84)
	env.fog_density = 0.0022
	env.fog_sky_affect = 0.2
	env.fog_aerial_perspective = 0.4
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 35, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.55
	sun.shadow_enabled = true
	sun.shadow_blur = 1.3
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)

func _toggle_car() -> void:
	if player.vehicle != null:
		var c = player.vehicle
		c.throttle = 0
		c.brake_in = 1.0
		player.vehicle = null
		player.visible = true
		player.collision_layer = 1
		player.collision_mask = 1
		player.process_mode = Node.PROCESS_MODE_INHERIT
		var side: Vector3 = c.global_transform.basis.x * 1.9
		player.global_position = c.global_position + side + Vector3(0, 0.3, 0)
		player.velocity = Vector3.ZERO
		if seated:
			seated.queue_free()
			seated = null
		return
	var best = null
	var bd := 4.0
	for c in cars:
		if c.police or traffic.any(func(t): return t.car == c):
			continue
		var d: float = c.global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			best = c
	if best == null:
		return
	player.vehicle = best
	player.visible = false
	player.collision_layer = 0
	player.collision_mask = 0
	player.velocity = Vector3.ZERO
	seated = Humanoid.new()
	seated.build(Color(0.13, 0.42, 0.26), Color(0.12, 0.16, 0.27), Color(0.86, 0.66, 0.5), Color(0.16, 0.1, 0.06))
	seated.sitting = true
	seated.scale = Vector3.ONE * 0.85
	seated.position = Vector3(best.seat.x, best.seat.y + 0.07 - 0.98 * 0.85, best.seat.z)
	best.add_child(seated)
	seated.animate(0, 0)
	best.brake_in = 0
	cam_idle = 2.0

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("enter"): _toggle_car()
	if e.is_action_pressed("jump"): player.jump()
	if e.is_action_pressed("fire"): combat.fire_held = true
	if e.is_action_released("fire"): combat.fire_held = false
	if e.is_action_pressed("weapon"): combat.cycle()

func _physics_process(dt: float) -> void:
	var k := Vector2(Input.get_axis("move_l", "move_r"), Input.get_axis("move_b", "move_f"))
	var stick: Vector2 = hud.joy
	var mv := Vector2(stick.x, -stick.y) if stick.length() > 0.05 else k
	if player.vehicle == null:
		player.move_input = Vector2(mv.x, mv.y)
		player.cam_yaw = cam_yaw + PI
		player.sprint = hud.sprint or Input.is_action_pressed("sprint")
	elif shot_view != "drive":
		var c = player.vehicle
		var g := 1.0 if hud.gas else 0.0
		var b := 1.0 if hud.brk else 0.0
		if stick.length() < 0.05:
			g = maxf(g, maxf(0.0, k.y))
			b = maxf(b, maxf(0.0, -k.y))
		c.throttle = g - b
		c.steer_in = -mv.x
		c.handbrake = Input.is_action_pressed("jump")
	if player.vehicle:
		player.global_position = player.vehicle.global_position
	if player.vehicle:
		var v: Vector3 = player.vehicle.linear_velocity
		if _lastv.length() > 4.0 and _lastv.distance_to(v) > 5.0:
			var pv: Vector3 = player.vehicle.global_position
			audio.play("crash", pv, 3.0)
			FX.sparks(self, pv + player.vehicle.global_transform.basis.z * 2.0 + Vector3(0, 0.6, 0))
			hp = maxf(5.0, hp - _lastv.distance_to(v) * 0.8)
		_lastv = v
	else:
		_lastv = Vector3.ZERO
	if hud.fire:
		combat.fire_held = true
	elif not Input.is_action_pressed("fire"):
		combat.fire_held = false
	_traffic()
	_crimes(dt)
	_police(dt)

func _traffic() -> void:
	for t in traffic:
		var c = t.car
		var tgt: Vector3 = t.loop[t.i]
		if c.global_position.distance_to(tgt) < 9.0:
			t.i = (t.i + 1) % t.loop.size()
		t.mk.global_position = tgt
		# freia atrás de outros carros e do jogador
		var ahead: Vector3 = c.global_position + c.global_transform.basis.z * 7.0
		var block := player.global_position.distance_to(ahead) < 4.5
		for o in cars:
			if o != c and o.global_position.distance_to(ahead) < 4.0:
				block = true
		if block:
			c.ai_target = null
			c.throttle = 0
			c.brake_in = 1.0
		else:
			c.ai_target = t.mk
			c.brake_in = 0.0

func _crimes(dt: float) -> void:
	peds = peds.filter(func(q): return is_instance_valid(q))
	var vc = player.vehicle
	if vc != null and vc.linear_velocity.length() > 3.0:
		for p in peds:
			if p.down: continue
			var d: Vector3 = p.global_position - vc.global_position
			d.y = 0
			if d.length() < 2.2:
				p.hit(vc, vc.linear_velocity, gore)
				audio.play("hit", p.global_position, 4.0)
				audio.play("scream", p.global_position, -2.0)
				_add_wanted(1)
				for q in peds:
					if q != p and q.global_position.distance_to(p.global_position) < 18.0:
						q.scare()
	if wanted > 0:
		wanted_timer -= dt
		if wanted_timer <= 0 and (police_car == null or police_car.global_position.distance_to(player.global_position) > 80.0):
			wanted = 0
			combat.clear_police()
			if police_car:
				police_car.queue_free()
				cars.erase(police_car)
				police_car = null

func _add_wanted(n: int) -> void:
	wanted = mini(5, wanted + n)
	wanted_timer = 35.0

func _police(dt: float) -> void:
	if wanted > 0 and police_car == null:
		# nasce numa rua (linha da grade mais próxima), ~55 m antes/depois do jogador, virada para ele
		var pp: Vector3 = player.global_position
		var best_road := 0.0
		var bd := 1e9
		for k in city.N + 1:
			var road: float = (k - city.N * 0.5) * city.CELL
			if absf(road - pp.x) < bd:
				bd = absf(road - pp.x)
				best_road = road
		var ext: float = city.extent() - 8.0
		var z := pp.z - 55.0 if pp.z > 0 else pp.z + 55.0
		z = clampf(z, -ext, ext)
		var yaw := 0.0 if z < pp.z else PI
		police_car = _spawn_car(Vector3(best_road + (2.6 if yaw == 0.0 else -2.6), 0.8, z), yaw, Color(0.92, 0.92, 0.93), true)
		police_car.max_engine = 6200.0
	if police_car:
		police_car.ai_target = player.vehicle if player.vehicle else player
		var d: float = police_car.global_position.distance_to(player.global_position)
		var slow: bool = player.vehicle == null or player.vehicle.linear_velocity.length() < 2.0
		bust_timer = bust_timer + dt if (d < 6.0 and slow) else 0.0
		if bust_timer > 3.0:
			_msg("PRESO! (teste)")
			wanted = 0
			bust_timer = 0
			police_car.queue_free()
			cars.erase(police_car)
			police_car = null

func _msg(t: String) -> void:
	hud.hint.text = t
	msg_t = 3.0

func _process(dt: float) -> void:
	frames += 1
	# câmera em 3ª pessoa
	var drag: Vector2 = hud.take_cam_drag()
	if drag.length() > 0:
		cam_yaw -= drag.x * 0.006
		cam_pitch = clampf(cam_pitch - drag.y * 0.004, -1.0, 0.2)
		cam_idle = 2.0
	cam_idle -= dt
	var tgt: Node3D = player.vehicle if player.vehicle else player
	var dist := 7.5 if player.vehicle else 4.6
	var h := 1.6 if player.vehicle else 1.5
	if player.vehicle and cam_idle <= 0:
		var fwd: Vector3 = player.vehicle.global_transform.basis.z
		var want_yaw := atan2(fwd.x, fwd.z) + PI
		cam_yaw = lerp_angle(cam_yaw, want_yaw, minf(1.0, dt * 2.5))
	var off := Vector3(sin(cam_yaw) * cos(cam_pitch), -sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch)) * dist
	var focus := tgt.global_position + Vector3(0, h, 0)
	cam.global_position = cam.global_position.lerp(focus + off, minf(1.0, dt * 8.0)) if frames > 2 else focus + off
	cam.look_at(focus, Vector3.UP)
	# sons contínuos
	if player.vehicle:
		var v = player.vehicle
		var rpm := clampf(absf(v.forward_speed()) / 30.0, 0.0, 1.0) * 0.8 + absf(v.throttle) * 0.2
		audio.set_engine(true, rpm, absf(v.throttle))
	else:
		audio.set_engine(false, 0.0, 0.0)
		var hs := Vector2(player.velocity.x, player.velocity.z).length()
		if hs > 0.5 and player.is_on_floor():
			_step_ph += dt * (2.2 + hs * 1.65) / PI
			if _step_ph >= 1.0:
				_step_ph -= 1.0
				audio.play("step", null, -8.0)
	audio.set_siren(police_car != null, police_car.global_position.distance_to(player.global_position) if police_car else 999.0)
	# HUD
	fps_acc += dt
	fps_n += 1
	if fps_acc > 0.5:
		fps_show = fps_n / fps_acc
		fps_acc = 0
		fps_n = 0
	hud.driving = player.vehicle != null
	hud.info.text = "%d FPS · %s · b%s · Fatia de teste Godot" % [round(fps_show), RenderingServer.get_video_adapter_name(), build_id]
	hud.stars.text = "★".repeat(wanted) + "☆".repeat(5 - wanted)
	hud.money.text = "$%d,00" % money
	hud.weapon_text = combat.label()
	hud.hp = hp
	hud.map_player = player.global_position
	hud.map_yaw = cam_yaw + PI
	hud.map_police = police_car.global_position if police_car else Vector3.INF
	hud.speed.text = ("%d km/h" % round(player.vehicle.speed_kmh())) if player.vehicle else ""
	if msg_t > 0:
		msg_t -= dt
		if msg_t <= 0: hud.hint.text = ""
	elif player.vehicle == null and my_car and my_car.global_position.distance_to(player.global_position) < 4.0:
		hud.hint.text = "Toque em CARRO para entrar"
	else:
		hud.hint.text = ""
	if shot != "":
		_shot_tick()

## Modo de captura para testes automáticos: --shot=arquivo.png --view=nome
func _shot_tick() -> void:
	if frames == 5:
		match shot_view:
			"drive":
				_toggle_car()
	if shot_view == "combat":
		if frames == 4:
			player.global_position = my_car.global_position + Vector3(-5.0, 0, 12.0)
			shot_ped = Ped.new()
			add_child(shot_ped)
			var pp: Vector3 = player.global_position + Vector3(0, 0, 6.0)
			shot_ped.setup([pp, pp + Vector3(0, 0, 0.1), pp, pp], 0, rng)
			shot_ped.died.connect(_on_ped_died)
			peds.append(shot_ped)
			cam_yaw = -PI
			cam_pitch = -0.2
		if frames > 8 and frames < 40:
			combat.fire_held = true
		if frames % 60 == 0:
			print("CMB ", frames, " pedDown=", (shot_ped.down if is_instance_valid(shot_ped) else "removido"), " wanted=", wanted, " hp=", snappedf(hp, 1), " cops=", combat.cops.size(), " dead=", combat.dead, " money=", money, " cash=", combat.cash.size(), " pos=", player.global_position.snapped(Vector3.ONE), " pol=", police_car != null)
		if frames == 70:
			# vai até a nota de dinheiro
			if combat.cash.size() > 0:
				player.global_position = combat.cash[0].n.global_position
	if shot_view == "rag" and frames == 4:
		player.global_position = my_car.global_position + Vector3(-5.0, 0, 12.0)
		shot_ped = Ped.new()
		add_child(shot_ped)
		var pp: Vector3 = player.global_position + Vector3(0, 0, 5.5)
		shot_ped.setup([pp, pp + Vector3(0, 0, 0.1), pp, pp], 0, rng)
		peds.append(shot_ped)
		cam_yaw = -PI
		cam_pitch = -0.22
	if shot_view == "rag" and frames == 12:
		shot_ped.hit(my_car, Vector3(7, 0, 4), gore)
		audio.play("scream", shot_ped.global_position)
	if shot_view == "police" and frames == 6:
		_add_wanted(2)
		set_meta("pd0", 0.0)
	if shot_view == "police" and frames == 20 and police_car:
		set_meta("pd0", police_car.global_position.distance_to(player.global_position))
	if shot_view == "walk" and frames > 5:
		hud.joy = Vector2(0, -1)
		if frames == 6:
			set_meta("p0", player.global_position)
			set_meta("c0", cam.global_position)
	if shot_view == "drive" and frames > 5 and player.vehicle:
		player.vehicle.throttle = 0.5 if frames < 120 else 0.15
		player.vehicle.steer_in = 0.0 if frames < 150 else 0.6
		if frames % 15 == 0: print("DRV ", frames, " yaw=", snappedf(my_car.rotation.y, 0.01), " pos=", my_car.global_position.snapped(Vector3.ONE*0.1), " v=", snappedf(my_car.forward_speed(), 0.1), " steer=", snappedf(my_car.steering, 0.01))
	if frames == 4:
		match shot_view:
			"street":
				cam_yaw = PI * 0.75
			"car":
				player.global_position = my_car.global_position + Vector3(-3.5, 0, -2.5)
			"aerial":
				cam_pitch = -0.6
			"drive":
				player.global_position = my_car.global_position + Vector3(2.0, 0, 0)
			"cars", "cars2":
				var base: Vector3 = my_car.global_position + Vector3(0, 0, 14)
				var ks := ["sedan", "hatch", "suv", "pickup", "sport", "police"]
				var cols := [Color(0.6, 0.05, 0.05), Color(0.9, 0.9, 0.9), Color(0.1, 0.25, 0.15), Color(0.2, 0.22, 0.25), Color(0.95, 0.6, 0.05), Color.WHITE]
				for q in ks.size():
					var cc = _spawn_car(base + Vector3(0, 0.6, q * 6.5), PI * 0.5, cols[q], ks[q] == "police", ks[q])
				player.global_position = base + Vector3(-9.0, 0, 14)
				cam_yaw = -PI * 0.5 if shot_view == "cars" else -PI * 0.25
				cam_pitch = -0.15
	if frames == shot_at:
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot)
		var info := {"draws": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), "prims": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), "fps": fps_show, "car_z": my_car.global_position.z, "car_x": my_car.global_position.x, "car_speed": my_car.linear_velocity.length(), "yaw": my_car.rotation.y, "up": my_car.global_transform.basis.y.y, "wanted": wanted, "police_d0": get_meta("pd0", -1.0), "pol": ([police_car.global_position, police_car.linear_velocity.length(), police_car.throttle, police_car.engine_force, police_car.brake, police_car.wheels.map(func(w): return w.is_in_contact())] if police_car else []), "police_d": (police_car.global_position.distance_to(player.global_position) if police_car else -1.0), "walk": (player.global_position - get_meta("p0", player.global_position)), "camdir": (get_meta("p0", player.global_position) - get_meta("c0", cam.global_position))}
		print("SHOT ", JSON.stringify(info))
		get_tree().quit()

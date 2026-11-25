extends Node3D
## Fatia de teste: monta ambiente (céu, sol, sombras, tonemap), cidade, jogador, carros, pedestres e polícia.

const City := preload("res://scripts/city.gd")
const Player := preload("res://scripts/player.gd")
const Car := preload("res://scripts/car.gd")
const Ped := preload("res://scripts/ped.gd")
const Hud := preload("res://scripts/hud.gd")
const Humanoid := preload("res://scripts/humanoid.gd")

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
var frames := 0
var msg_t := 0.0
var build_id := "dev"

func _ready() -> void:
	rng.seed = 7
	if FileAccess.file_exists("res://build.txt"):
		build_id = FileAccess.get_file_as_string("res://build.txt").strip_edges()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): shot = a.substr(7)
		if a.begins_with("--view="): shot_view = a.substr(7)
	_inputs()
	_environment()
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
	hud.jump_pressed.connect(func(): player.jump())
	# carro do jogador estacionado ao lado
	var road_x: float = city._center(2) - city.CELL * 0.5
	my_car = _spawn_car(Vector3(road_x + 2.6, 0.6, city._center(2) + 4.0), 0.0, Color(0.06, 0.2, 0.55))
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

func _block_loop(i: int, j: int, k: int) -> Array:
	var cx: float = city._center(i)
	var cz: float = city._center(j)
	var r: float = city.CELL * 0.5 + 2.6
	var pts := [Vector3(cx - r, 0.6, cz - r), Vector3(cx - r, 0.6, cz + r), Vector3(cx + r, 0.6, cz + r), Vector3(cx + r, 0.6, cz - r)]
	var out := []
	for q in 4:
		out.append(pts[(q + k) % 4])
	return out

func _load_model() -> Node3D:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var bytes := FileAccess.get_file_as_bytes("res://assets/esportivo.bin")
	if bytes.is_empty() or doc.append_from_buffer(bytes, "", st) != OK:
		push_error("modelo do carro não carregou")
		return Node3D.new()
	return doc.generate_scene(st)

func _spawn_car(pos: Vector3, yaw: float, paint: Color, police := false):
	var c := Car.new()
	add_child(c)
	c.setup(_load_model(), paint, police)
	c.global_position = pos
	c.rotation.y = yaw
	cars.append(c)
	return c

func _inputs() -> void:
	var map := {"move_f": [KEY_W, KEY_UP], "move_b": [KEY_S, KEY_DOWN], "move_l": [KEY_A, KEY_LEFT], "move_r": [KEY_D, KEY_RIGHT], "enter": [KEY_E, KEY_F], "jump": [KEY_SPACE], "sprint": [KEY_SHIFT]}
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
	sun.directional_shadow_max_distance = 95.0
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
	seated.scale = Vector3.ONE * 0.9
	seated.position = Vector3(0, -0.62, 0.2)
	best.add_child(seated)
	seated.animate(0, 0)
	best.brake_in = 0
	cam_idle = 2.0

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("enter"): _toggle_car()
	if e.is_action_pressed("jump"): player.jump()

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
	var vc = player.vehicle
	if vc != null and vc.linear_velocity.length() > 3.0:
		for p in peds:
			if p.down: continue
			var d: Vector3 = p.global_position - vc.global_position
			d.y = 0
			if d.length() < 2.2:
				p.hit(vc.global_position, vc.linear_velocity.length())
				_add_wanted(1)
	if wanted > 0:
		wanted_timer -= dt
		if wanted_timer <= 0 and (police_car == null or police_car.global_position.distance_to(player.global_position) > 80.0):
			wanted = 0
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
	if frames == 240:
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot)
		var info := {"fps": fps_show, "car_z": my_car.global_position.z, "car_x": my_car.global_position.x, "car_speed": my_car.linear_velocity.length(), "yaw": my_car.rotation.y, "up": my_car.global_transform.basis.y.y, "wanted": wanted, "police_d0": get_meta("pd0", -1.0), "pol": ([police_car.global_position, police_car.linear_velocity.length(), police_car.throttle, police_car.engine_force, police_car.brake, police_car.wheels.map(func(w): return w.is_in_contact())] if police_car else []), "police_d": (police_car.global_position.distance_to(player.global_position) if police_car else -1.0), "walk": (player.global_position - get_meta("p0", player.global_position)), "camdir": (get_meta("p0", player.global_position) - get_meta("c0", cam.global_position))}
		print("SHOT ", JSON.stringify(info))
		get_tree().quit()

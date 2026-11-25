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
const UI := preload("res://scripts/ui.gd")
const DayNight := preload("res://scripts/daynight.gd")
const Police := preload("res://scripts/police.gd")
const Arcade := preload("res://scripts/arcade.gd")
const World2 := preload("res://scripts/world2.gd")
const Missions := preload("res://scripts/missions.gd")
const VehAnim := preload("res://scripts/vehanim.gd")
const Traffic := preload("res://scripts/traffic.gd")

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
var ui: CanvasLayer
var sun: DirectionalLight3D
var world_env: Environment
var armor := 0.0
var owned_cars: Array = []   # [{kind, color}] comprados na concessionária
var shop_near := ""
var autosave_t := 0.0
var tod := 10.0          # hora do dia (0-24)
var quality := 1
var daynight: Node
var police: Node
var world2: Node3D
var missions: Node
var vehanim: Node
var interior := ""         # tipo da loja em que o jogador está ("" = rua)
var _int_from := Vector3.ZERO
var shop_action := ""      # "enter" / "exit" / "buy"
var shark: Node3D
var traffic_sys: Node
var god := false           # código: vida infinita
var shark_t := 0.0

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
	world2 = World2.new()
	add_child(world2)
	world2.build(self)
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.far = 650.0
	add_child(cam)
	cam.make_current()
	player = Player.new()
	player.world2 = world2
	add_child(player)
	player.set_meta("player", true)
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
	my_car = _spawn_car(Vector3(road_x + 5.9, 0.6, city._center(2) + 4.0), 0.0, Color(0.06, 0.2, 0.55), false, "sport")
	var palette := [Color(0.55, 0.02, 0.03), Color(0.85, 0.85, 0.86), Color(0.05, 0.05, 0.06), Color(0.75, 0.45, 0.05), Color(0.2, 0.22, 0.25)]
	for k in 5:
		var rx: float = city._center(rng.randi_range(0, 4)) + city.CELL * 0.5 * (1 if rng.randf() < 0.5 else -1)
		_spawn_car(Vector3(rx + 5.9, 0.6, rng.randf_range(-120, 120)), 0.0 if rng.randf() < 0.5 else PI, palette[k % palette.size()])
	var mcols := [Color(0.05, 0.05, 0.06), Color(0.95, 0.6, 0.05), Color(0.1, 0.3, 0.75)]
	for k in 3:
		_spawn_car(my_car.global_position + Vector3(0.3, 0, -8.0 - k * 3.2), 0.0, mcols[k], false, "moto")
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
	police = Police.new()
	add_child(police)
	police.setup(self)
	missions = Missions.new()
	add_child(missions)
	vehanim = VehAnim.new()
	vehanim.main = self
	add_child(vehanim)
	combat = Combat.new()
	add_child(combat)
	combat.setup(self)
	missions.setup(self)
	_spawn_extras()
	hud.weapon_pressed.connect(func(): ui.show_wheel())
	hud.shop_pressed.connect(_shop_action)
	daynight = DayNight.new()
	add_child(daynight)
	daynight.setup(self)
	ui = UI.new()
	ui.main = self
	add_child(ui)
	ui.apply_now()
	if shot == "" or shot_view in ["menu", "shop", "cars_shop", "settings"]:
		ui.show_main_menu()
	if shot_view in ["menu", "shop", "cars_shop", "settings", "clothes"]:
		process_mode = Node.PROCESS_MODE_ALWAYS   # captura de teste com o menu aberto

## novo jogo: só soco, $600, sem carros comprados
func new_game() -> void:
	money = 600
	hp = 100.0
	armor = 0.0
	combat.owned = {"fist": true}
	combat.ammo = {}
	combat.weapon = "fist"
	tod = 10.0
	player.outfit = player.OUTFIT0.duplicate()
	player.rebuild_body()
	combat._equip()
	for c in _owned_nodes():
		cars.erase(c)
		c.queue_free()
	owned_cars = []
	ui.save_game()

func load_game() -> void:
	var d: Dictionary = ui.load_save()
	if d.is_empty():
		new_game()
		return
	money = int(d.get("money", 600))
	armor = float(d.get("armor", 0.0))
	var ow := {"fist": true}
	var od: Dictionary = d.get("owned", {})
	for k in od:
		if od[k]: ow[k] = true
	combat.owned = ow
	var am := {}
	var ad: Dictionary = d.get("ammo", {})
	for k in ad:
		am[k] = int(ad[k])
	combat.ammo = am
	var w: String = d.get("weapon", "fist")
	combat.weapon = w if ow.has(w) else "fist"
	tod = float(d.get("time", 10.0))
	var of: Dictionary = player.OUTFIT0.duplicate()
	var od2: Dictionary = d.get("outfit", {})
	for k in od2:
		if of.has(k): of[k] = od2[k]
	of.hat = int(of.hat)
	player.outfit = of
	player.rebuild_body()
	combat._equip()
	for c in _owned_nodes():
		cars.erase(c)
		c.queue_free()
	owned_cars = d.get("cars", [])
	for i in owned_cars.size():
		var oc: Dictionary = owned_cars[i]
		_place_owned(oc.get("kind", "sedan"), Color.html(oc.get("color", "#2244aa")), i)

func _owned_nodes() -> Array:
	return cars.filter(func(c): return is_instance_valid(c) and c.has_meta("owned"))

## carros comprados: na rua em frente à concessionária (compra) ou numa fila de vagas ao lado do carro inicial (save)
func spawn_owned_car(kind: String, col: Color, _near_shop: bool) -> void:
	var sp: Vector3 = city.shops[1].pos
	var n := _owned_nodes().size()
	var c = _spawn_car(Vector3(sp.x - 6.0 + (n % 3) * 6.0, 0.6, sp.z - 4.6), PI * 0.5, col, false, kind)
	c.set_meta("owned", true)

func _place_owned(kind: String, col: Color, i: int) -> void:
	var base: Vector3 = my_car.global_position
	var c = _spawn_car(base + Vector3(0, 0, 8.0 + i * 6.5), 0.0, col, false, kind)
	c.set_meta("owned", true)

## configurações do menu (sangue, gore, qualidade, contador)
func apply_settings(s: Dictionary) -> void:
	gore = s.gore
	FX.blood_on = s.blood
	var q: int = s.quality
	quality = q
	var mobile := OS.has_feature("mobile")
	get_viewport().scaling_3d_scale = ([0.6, 0.75, 1.0] if mobile else [0.75, 1.0, 1.0])[q]
	if sun:
		sun.shadow_enabled = q > 0
		sun.directional_shadow_max_distance = [0.0, 60.0, 90.0][q]
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if q == 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	if world_env:
		world_env.glow_enabled = q > 0
		world_env.fog_aerial_perspective = 0.4 if q > 0 else 0.0
	if hud:
		hud.info.visible = s.fps

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
	var kinds := ["sedan", "sedan", "hatch", "suv", "pickup", "sport", "taxi"]
	c.setup("police" if police else (kind if kind != "" else kinds[rng.randi() % kinds.size()]), paint)
	c.global_position = pos
	c.rotation.y = yaw
	c.crashed.connect(_on_crash)
	c.destroyed.connect(_on_vehicle_destroyed)
	cars.append(c)
	return c

func _spawn_arcade(kind: String, pos: Vector3, yaw: float, paint: Color):
	var a := Arcade.new()
	add_child(a)
	a.setup(kind, paint)
	a.world2 = world2
	a.global_position = pos
	a.rotation.y = yaw
	a.crashed.connect(_on_crash)
	a.destroyed.connect(_on_vehicle_destroyed)
	cars.append(a)
	return a

## táxis, barcos, aviões, helicóptero, viaturas da delegacia, banhistas
func _spawn_extras() -> void:
	var road_x: float = city._center(2) - city.CELL * 0.5
	_spawn_car(Vector3(road_x + 5.9, 0.7, city._center(2) + 14.0), 0.0, Color.YELLOW, false, "taxi")
	_spawn_car(Vector3(city._center(1) - city.CELL * 0.5 - 5.9, 0.7, city._center(3)), PI, Color.YELLOW, false, "taxi")
	# trânsito com regras (traffic.gd): carros, motos, táxis e 2 ônibus na linha
	traffic_sys = Traffic.new()
	add_child(traffic_sys)
	traffic_sys.setup(self)
	var palette := [Color(0.55, 0.02, 0.03), Color(0.85, 0.85, 0.86), Color(0.05, 0.05, 0.06), Color(0.75, 0.45, 0.05), Color(0.2, 0.22, 0.25), Color(0.1, 0.25, 0.55), Color(0.3, 0.4, 0.3)]
	var used := {str(Vector2i(1, 3)) + str(Vector2i(0, 1)): true, str(Vector2i(4, 2)) + str(Vector2i(0, -1)): true}
	var kinds := ["sedan", "hatch", "suv", "pickup", "sedan", "hatch", "taxi", "sport", "sedan", "suv", "moto", "moto", "moto", "hatch", "pickup", "taxi"]
	for k in kinds.size():
		var n := Vector2i(rng.randi_range(0, city.N), rng.randi_range(0, city.N))
		var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		var d: Vector2i = dirs[rng.randi() % 4]
		var tries := 0
		while (not traffic_sys._valid(n - d) or used.has(str(n) + str(d))) and tries < 40:
			n = Vector2i(rng.randi_range(0, city.N), rng.randi_range(0, city.N))
			d = dirs[rng.randi() % 4]
			tries += 1
		used[str(n) + str(d)] = true
		var c = _spawn_car(Vector3(0, 0.7, 0), 0.0, palette[k % palette.size()], false, kinds[k])
		traffic_sys.add_agent(c, n, d)
	for k in 2:
		var b = _spawn_car(Vector3(0, 0.9, 0), 0.0, [Color(0.1, 0.45, 0.2), Color(0.7, 0.12, 0.1)][k], false, "bus")
		traffic_sys.add_agent(b, Vector2i(1, 3) if k == 0 else Vector2i(4, 2), Vector2i(0, 1) if k == 0 else Vector2i(0, -1), true)
	var bcols := [Color(0.1, 0.3, 0.7), Color(0.75, 0.1, 0.1), Color(0.1, 0.5, 0.3)]
	for i in world2.boat_spots.size():
		var bs: Array = world2.boat_spots[i]
		_spawn_arcade("boat", bs[0], bs[1], bcols[i % 3])
	for i in world2.plane_spots.size():
		var ps: Array = world2.plane_spots[i]
		_spawn_arcade("plane", ps[0], ps[1], [Color(0.75, 0.1, 0.1), Color(0.1, 0.25, 0.6)][i % 2])
	for hs in world2.heli_spots:
		_spawn_arcade("heli", hs[0], hs[1], Color(0.85, 0.55, 0.05))
	for sc in world2.station_cars:
		var pc = _spawn_car(sc[0], sc[1], Color.WHITE, true)
		pc.parked = true
	for k in 6:
		var p := Ped.new()
		add_child(p)
		p.setup(world2.beach_loop, k % 4, rng)
		p.position = world2.beach_loop[k % 4].lerp(world2.beach_loop[(k + 1) % 4], rng.randf())
		p.died.connect(_on_ped_died)
		peds.append(p)

## batida de qualquer veículo
func _on_crash(c, dv: float) -> void:
	var pv: Vector3 = c.global_position
	if pv.distance_to(player.global_position) < 60.0:
		audio.play("crash", pv, clampf((dv - 6.0) * 0.5, -6.0, 6.0))
	if dv > 9.0:
		FX.sparks(self, pv + Vector3(0, 0.7, 0))
	if dv > 14.0 and c.get("paint_c") != null:
		FX.debris(self, pv + Vector3(0, 0.9, 0), c.paint_c, c.linear_velocity * 0.4 + Vector3(randf_range(-3, 3), 4, randf_range(-3, 3)))
	if c == player.vehicle:
		hp -= maxf(0.0, dv - 8.0) * (2.4 if c.kind == "moto" else 0.9)
		hud.flash = 0.2
		# moto: o piloto voa
		if c.kind == "moto" and dv > 7.5:
			var vel: Vector3 = c.linear_velocity + c.global_transform.basis.z * dv * 0.6
			eject_player(Vector3.ZERO)
			combat.knockdown(vel + Vector3(0, 3.0, 0), 3.0)

## explosão: efeito + dano em área + empurrão
func explode_at(pos: Vector3, radius: float, dmg: float) -> void:
	FX.explosion(self, pos, clampf(radius / 6.0, 0.7, 1.6))
	audio.play("explosion", pos, 6.0)
	for q in peds.duplicate():
		if is_instance_valid(q) and not q.down:
			var d: float = q.global_position.distance_to(pos)
			if d < radius:
				var dir: Vector3 = (q.global_position - pos + Vector3(0, 0.5, 0)).normalized()
				q.hit(null, dir * (16.0 - d), gore)
				combat.drop_cash(q.global_position)
			elif d < radius * 2.5:
				q.scare()
	for c in police.cops + missions.hostiles():
		if is_instance_valid(c) and not c.down and c.global_position.distance_to(pos) < radius:
			var dir2: Vector3 = (c.global_position - pos + Vector3(0, 0.5, 0)).normalized()
			c.hit(null, dir2 * (16.0 - c.global_position.distance_to(pos)), gore)
			missions.on_kill(c)
	for c in cars.duplicate():
		if not is_instance_valid(c) or c.get("dead"):
			continue
		var d: float = c.global_position.distance_to(pos)
		if d < radius * 1.4:
			var f := 1.0 - d / (radius * 1.4)
			c.take_damage(dmg * f)
			if c is RigidBody3D:
				c.apply_central_impulse(((c.global_position - pos).normalized() + Vector3(0, 0.8, 0)) * c.mass * 9.0 * f)
	var pd: float = player.global_position.distance_to(pos)
	if pd < radius and not combat.dead:
		hp -= dmg * (1.0 - pd / radius) * (0.4 if player.vehicle else 1.0)
		if player.vehicle == null:
			combat.knockdown(((player.global_position - pos).normalized() + Vector3(0, 0.9, 0)) * (14.0 - pd), 2.8)
	hud.flash = maxf(hud.flash, clampf(0.4 - pd / 100.0, 0.0, 0.4))
	if wanted == 0 and pos.distance_to(player.global_position) < 60.0:
		_add_wanted(1)

func splash_at(pos: Vector3) -> void:
	FX.splash(self, Vector3(pos.x, world2.WATER_Y, pos.z), 1.0)
	audio.play("splash", pos)

func _on_vehicle_destroyed(c) -> void:
	var pos: Vector3 = c.global_position + Vector3(0, 0.8, 0)
	call_deferred("explode_at", pos, 6.5, 140.0)
	if c == player.vehicle:
		var vel: Vector3 = c.linear_velocity
		eject_player(Vector3.ZERO)
		hp -= 60.0
		combat.knockdown(vel + Vector3(randf_range(-3, 3), 8.0, randf_range(-3, 3)), 3.0)

# ---------------------------------------------------------------- lojas com interior
func _shop_action() -> void:
	match shop_action:
		"enter":
			for sh in city.shops:
				if Vector2(sh.pos.x - player.global_position.x, sh.pos.z - player.global_position.z).length() < 3.2:
					enter_interior(sh.type)
					return
		"exit":
			leave_interior()
		"buy":
			ui.show_shop(interior)

func enter_interior(type: String) -> void:
	var it: Dictionary = world2.interiors[type]
	_int_from = player.global_position
	interior = type
	player.global_position = it.spawn
	player.velocity = Vector3.ZERO
	cam_yaw = PI
	cam_pitch = -0.25
	audio.play("door")

func leave_interior() -> void:
	if interior == "":
		return
	interior = ""
	player.global_position = _int_from + Vector3(0, 0.2, -2.2)
	player.velocity = Vector3.ZERO
	cam_yaw = 0.0
	audio.play("door")

# ---------------------------------------------------------------- mar: carros afundam, tubarão
func _water_tick(dt: float) -> void:
	for c in cars.duplicate():
		if not is_instance_valid(c) or not (c is VehicleBody3D):
			continue
		if world2.is_water(c.global_position.x - 11.0, 0) and not c.has_meta("sinking"):
			c.set_meta("sinking", true)
			FX.splash(self, c.global_position + Vector3(0, 0.8, 0), 1.6)
			audio.play("splash", c.global_position, 4.0)
			c.dead = true
			c.collision_mask = 0
			c.gravity_scale = 0.12
			c.linear_damp = 3.0
			if c == player.vehicle:
				eject_player(Vector3.ZERO)
				player.global_position.x = c.global_position.x
			var cc = c
			get_tree().create_timer(12.0).timeout.connect(func(): if is_instance_valid(cc): cars.erase(cc); cc.queue_free())
	# tubarão no fim do mar (a nado, longe da costa)
	var pp: Vector3 = player.global_position
	if player.swimming and pp.x > world2.SHORE_X + 280.0 and pp.x < 2600.0:
		if shark == null:
			shark = _make_shark()
			shark.global_position = pp + Vector3(40.0, 0, randf_range(-20, 20))
			_msg("Cuidado: tubarão!")
	if shark:
		var to: Vector3 = pp - shark.global_position
		to.y = 0
		shark_t += dt
		var spd := 7.5 if player.swimming else 3.0
		if player.swimming and to.length() < 1.6 and not combat.dead:
			hp = 0.0
			FX.blood_burst(self, pp + Vector3(0, 0.9, 0), Vector3.UP, 40)
			audio.play("scream", pp)
		if not player.swimming:
			to = -to
			if to.length() > 0.0 and shark.global_position.distance_to(pp) > 120.0:
				shark.queue_free()
				shark = null
				return
		var dir := to.normalized()
		shark.global_position += dir * spd * dt
		shark.global_position.y = world2.WATER_Y - 0.55 + sin(shark_t * 3.0) * 0.05
		shark.rotation.y = lerp_angle(shark.rotation.y, atan2(dir.x, dir.z), dt * 3.0)

func _make_shark() -> Node3D:
	var n := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var CM := preload("res://scripts/carmodel.gd")
	CM._ell(st, Vector3(0, 0, 0), Vector3(0.9, 0.8, 3.6), Color(0.35, 0.38, 0.42))
	CM._ell(st, Vector3(0, -0.15, 0.2), Vector3(0.75, 0.5, 3.0), Color(0.85, 0.85, 0.85))
	CM._box(st, Vector3(0.08, 0.9, 0.7), Vector3(0, 0.75, 0.1), Color(0.3, 0.33, 0.37))
	CM._box(st, Vector3(0.08, 0.8, 0.5), Vector3(0, 0.1, -1.9), Color(0.3, 0.33, 0.37))
	CM._box(st, Vector3(1.6, 0.06, 0.5), Vector3(0, -0.2, 0.6), Color(0.3, 0.33, 0.37))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = CM.vc_mat()
	n.add_child(mi)
	add_child(n)
	return n

func _inputs() -> void:
	var map := {"move_f": [KEY_W, KEY_UP], "move_b": [KEY_S, KEY_DOWN], "move_l": [KEY_A, KEY_LEFT], "move_r": [KEY_D, KEY_RIGHT], "enter": [KEY_E, KEY_F], "jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "fire": [KEY_J, KEY_CTRL], "weapon": [KEY_Q, KEY_TAB], "shop": [KEY_B], "pause": [KEY_ESCAPE, KEY_P], "aim": [KEY_R]}
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
	world_env = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 35, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.55
	sun.shadow_enabled = true
	sun.shadow_blur = 1.3
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)

## entrar/sair (com animação). Sair de carro rápido = se jogar para fora (ragdoll).
func _toggle_car() -> void:
	if vehanim.busy() or combat.dead or combat.down_t > 0.0 or interior != "":
		return
	if player.vehicle != null:
		var c = player.vehicle
		var spd: float = c.linear_velocity.length()
		var k: String = c.kind
		var air: bool = k in ["plane", "heli"] and c.global_position.y > 2.0
		if air or (k == "moto" and spd > 3.0) or (k not in ["boat", "plane", "heli", "moto"] and spd > 6.0):
			var vel: Vector3 = c.linear_velocity
			eject_player(Vector3.ZERO)
			if not air:
				combat.knockdown(vel * 0.7 + c.global_transform.basis.x * 3.0 + Vector3(0, 2.0, 0), 2.6)
			return
		c.throttle = 0
		c.brake_in = 1.0
		vehanim.start_exit(c)
		return
	var best = null
	var bd := 2.4
	for c in cars:
		if not is_instance_valid(c) or c.get("dead") or police.is_unit_car(c):
			continue
		# distância até a caixa do veículo (ônibus é comprido)
		var lp: Vector3 = c.global_transform.affine_inverse() * player.global_position
		var hs: Vector3 = c.body_size * 0.5
		var q := Vector3(clampf(lp.x, -hs.x, hs.x), 0, clampf(lp.z, -hs.z, hs.z))
		var d: float = Vector2(lp.x - q.x, lp.z - q.z).length()
		var lim := bd + (1.6 if c.kind == "boat" else 0.0)
		if d < lim:
			bd = d
			best = c
	if best == null:
		return
	best.throttle = 0.0
	best.brake_in = 1.0
	best.ai_target = null
	vehanim.start_enter(best)

## chamado pela animação quando o jogador chega à porta: ele passa a "estar" no veículo
func finish_enter(best) -> Node3D:
	player.vehicle = best
	player.visible = false
	player.collision_layer = 0
	player.collision_mask = 0
	player.velocity = Vector3.ZERO
	best.ai_target = null
	best.driver = player
	# roubo: tráfego, ônibus e viaturas
	if traffic_sys.release(best):
		_spawn_fleeing(best)
	if best.police:
		_add_wanted(1)
	seated = player.make_body()
	seated.sitting = true
	seated.scale = Vector3.ONE * 0.85
	seated.position = seat_pos(best)
	seated.moto_pose = best.kind == "moto"
	if best.lean:
		best.lean.add_child(seated)
	else:
		best.add_child(seated)
	seated.animate(0, 0)
	if combat.weapon != "fist":
		seated.give_gun(preload("res://scripts/weapons.gd").gun_mesh(combat.weapon))
	return seated

## posição dos pés do boneco sentado (escala 0,85) para o quadril ficar no banco
func seat_pos(c) -> Vector3:
	var s: Vector3 = c.seat
	if c.kind == "moto":
		return Vector3(0, 0.84 - 0.98 * 0.85 + 0.04, -0.22)
	return Vector3(s.x, s.y + 0.07 - 0.98 * 0.85, s.z)

func anim_done() -> void:
	if player.vehicle:
		player.vehicle.brake_in = 0
	cam_idle = 2.0

func _spawn_fleeing(c) -> void:
	var p := Ped.new()
	add_child(p)
	var loop: Array = city.walk_loops[0]
	for l in city.walk_loops:
		if l[0].distance_to(c.global_position) < loop[0].distance_to(c.global_position):
			loop = l
	p.setup(loop, 0, rng)
	p.position = c.door_world() + c.global_transform.basis.x * 0.8
	p.died.connect(_on_ped_died)
	p.scare()
	p.flee = 10.0
	peds.append(p)
	audio.play("scream", p.position, -6.0)

func finish_exit(c, pos: Vector3) -> void:
	c.throttle = 0
	c.brake_in = 1.0
	c.driver = null
	player.vehicle = null
	player.visible = true
	player.collision_layer = 2
	player.collision_mask = 1
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.global_position = pos + Vector3(0, 0.3, 0)
	player.velocity = Vector3.ZERO
	player.body.rotation.y = c.rotation.y
	if seated:
		seated.queue_free()
		seated = null
	combat._equip()

## sai na hora (sem animação): batida de moto, morte, derrubada, missão
func eject_player(_impulse: Vector3) -> void:
	vehanim.cancel()
	if player.vehicle != null:
		var c = player.vehicle
		finish_exit(c, c.global_position + Vector3(0, 0.6 if c.kind != "plane" else 2.5, 0) + c.global_transform.basis.x * (0.0 if c.kind in ["moto"] else c.body_size.x * 0.5 + 0.6))

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("enter"): _toggle_car()
	if e.is_action_pressed("jump"): player.jump()
	if e.is_action_pressed("fire"): combat.fire_held = true
	if e.is_action_released("fire"): combat.fire_held = false
	if e.is_action_pressed("weapon"): combat.cycle()
	if e.is_action_pressed("shop"): _shop_action()
	if e.is_action_pressed("pause"): ui.show_pause()
	if e.is_action_pressed("aim"): hud.aim = not hud.aim

func _physics_process(dt: float) -> void:
	var k := Vector2(Input.get_axis("move_l", "move_r"), Input.get_axis("move_b", "move_f"))
	var stick: Vector2 = hud.joy
	var mv := Vector2(stick.x, -stick.y) if stick.length() > 0.05 else k
	vehanim.tick(dt)
	if vehanim.busy() or combat.down_t > 0.0:
		player.move_input = Vector2.ZERO
	elif player.vehicle == null:
		player.move_input = Vector2(mv.x, mv.y)
		player.cam_yaw = cam_yaw + PI
		player.sprint = hud.sprint or Input.is_action_pressed("sprint")
	elif not shot_view in ["drive", "motoride", "planefly", "helifly", "boatride", "busride", "motocrash", "props"]:
		var c = player.vehicle
		var g := 1.0 if hud.gas else 0.0
		var b := 1.0 if hud.brk else 0.0
		if stick.length() < 0.05:
			g = maxf(g, maxf(0.0, k.y))
			b = maxf(b, maxf(0.0, -k.y))
		c.throttle = g - b
		c.steer_in = -mv.x
		c.handbrake = Input.is_action_pressed("jump")
		if "stick" in c:
			c.stick = mv
	if player.vehicle:
		player.global_position = player.vehicle.global_position
	if hud.fire:
		combat.fire_held = true
	elif not Input.is_action_pressed("fire"):
		combat.fire_held = false
	_crimes(dt)
	_props_tick()
	_car_vs_player()
	police.tick(dt)
	missions.tick(dt)
	_water_tick(dt)

## carros batendo em postes (fáceis) e árvores (precisam de mais velocidade)
func _props_tick() -> void:
	for c in cars:
		if not is_instance_valid(c) or not (c is VehicleBody3D):
			continue
		var v: Vector3 = c.linear_velocity
		var spd := Vector2(v.x, v.z).length()
		if spd < 5.0:
			continue
		var pos: Vector3 = c.global_position + v.normalized() * c.body_size.z * 0.45
		for i in city.props_near(pos):
			var pr: Dictionary = city.props[i]
			var dd := Vector2(pr.pos.x - pos.x, pr.pos.z - pos.z).length()
			if dd > c.body_size.x * 0.5 + 0.7 + spd * 0.03:
				continue
			var need := 5.5 if pr.type == "lamp" else 14.0
			if c.kind == "bus":
				need *= 0.6
			if spd >= need:
				city.break_prop(i, v)
				c.linear_velocity = v * (0.85 if pr.type == "lamp" else 0.6)
				c.take_damage(4.0 if pr.type == "lamp" else 10.0)
				audio.play("crash", pr.pos, 2.0)
				FX.sparks(self, pr.pos + Vector3(0, 0.8, 0))

## carro x jogador a pé (o jogador não tem colisão com carros para não "lançá-los"): empurra ou atropela
func _car_vs_player() -> void:
	if player.vehicle != null or combat.dead or combat.down_t > 0.0 or vehanim.busy():
		return
	for c in cars:
		if not is_instance_valid(c) or c.kind in ["plane", "heli", "boat"]:
			continue
		var lp: Vector3 = c.global_transform.affine_inverse() * player.global_position
		var hs: Vector3 = c.body_size * 0.5
		if absf(lp.x) > hs.x + 0.45 or absf(lp.z) > hs.z + 0.45 or lp.y > 2.0:
			continue
		var spd: float = c.linear_velocity.length()
		if spd > 3.5:
			hp -= spd * 2.2
			audio.play("hit", player.global_position, 4.0)
			combat.knockdown(c.linear_velocity * 1.1 + Vector3(0, 2.5 + spd * 0.15, 0), 2.6)
			c.linear_velocity *= 0.85
			return
		else:
			var away: Vector3 = (player.global_position - c.global_position)
			away.y = 0
			player.global_position += away.normalized() * 0.08

func _crimes(dt: float) -> void:
	peds = peds.filter(func(q): return is_instance_valid(q))
	var vc = player.vehicle
	if vc != null and vc.linear_velocity.length() > 3.0:
		for p in peds:
			if p.down: continue
			var d: Vector3 = p.global_position - vc.global_position
			d.y = 0
			if d.length() < 2.2:
				var spd: float = vc.linear_velocity.length()
				if spd < 8.0:
					p.knock(vc.linear_velocity * 1.1, 30.0)
				else:
					p.hit(vc, vc.linear_velocity, gore)
				audio.play("hit", p.global_position, 4.0)
				audio.play("scream", p.global_position, -2.0)
				_add_wanted(1)
				for q in peds:
					if q != p and q.global_position.distance_to(p.global_position) < 18.0:
						q.scare()
	# policiais e capangas também podem ser atropelados
	if vc != null and vc.linear_velocity.length() > 4.0:
		for c in police.cops + missions.hostiles():
			if is_instance_valid(c) and not c.down and c.global_position.distance_to(vc.global_position) < vc.body_size.x * 0.5 + 1.0:
				c.hit(vc, vc.linear_velocity, gore)
				audio.play("hit", c.global_position, 4.0)
				_add_wanted(2 if c in police.cops else 0)

func _add_wanted(n: int) -> void:
	if interior != "":
		return
	wanted = mini(5, wanted + n)
	police.on_crime()

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
	var dist := 4.6
	var h := 1.5
	if player.vehicle:
		dist = {"bus": 13.0, "plane": 15.0, "heli": 13.0, "boat": 9.0, "moto": 5.5}.get(player.vehicle.kind, 7.5)
		h = {"bus": 3.0, "plane": 3.0, "heli": 3.0}.get(player.vehicle.kind, 1.6)
	elif player.body and player.body.ragdolled and player.body.parts.size() > 0 and is_instance_valid(player.body.parts[0]):
		tgt = player.body.parts[0]
		h = 0.6
	if player.vehicle != null or combat.dead or player.swimming:
		hud.aim = false
	var aiming: bool = hud.aim and player.vehicle == null and not combat.dead and combat.down_t <= 0.0 and not player.swimming
	combat.aim = aiming
	if not aiming:
		player.aim_yaw = NAN
	hud.crosshair = aiming
	if interior != "":
		dist = 3.6
	if aiming:
		dist = 2.4
		h = 1.65
		player.aim_yaw = cam_yaw + PI
	var want_fov := 62.0
	if aiming:
		want_fov = 22.0 if combat.weapon == "sniper" else 48.0
	cam.fov = lerpf(cam.fov, want_fov, minf(1.0, dt * 10.0))
	if player.vehicle and cam_idle <= 0:
		var fwd: Vector3 = player.vehicle.global_transform.basis.z
		var want_yaw := atan2(fwd.x, fwd.z) + PI
		cam_yaw = lerp_angle(cam_yaw, want_yaw, minf(1.0, dt * 2.5))
	var off := Vector3(sin(cam_yaw) * cos(cam_pitch), -sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch)) * dist
	var focus := tgt.global_position + Vector3(0, h, 0)
	if aiming:
		focus += Vector3(cos(cam_yaw), 0, -sin(cam_yaw)) * 0.55     # sobre o ombro direito
	# câmera não atravessa paredes
	var want_pos := focus + off
	var cq := PhysicsRayQueryParameters3D.create(focus, want_pos, 1)
	var excl := [player.get_rid()]
	if player.vehicle:
		excl.append(player.vehicle.get_rid())
	cq.exclude = excl
	var ch := get_world_3d().direct_space_state.intersect_ray(cq)
	if not ch.is_empty():
		want_pos = ch.position + (focus - want_pos).normalized() * 0.3
	cam.global_position = cam.global_position.lerp(want_pos, minf(1.0, dt * (14.0 if aiming else 8.0))) if frames > 2 else want_pos
	cam.look_at(focus + (-off.normalized() * 6.0 if aiming else Vector3.ZERO), Vector3.UP)
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
	hud.armor = armor
	shop_near = ""
	shop_action = ""
	if player.vehicle == null and not combat.dead and not vehanim.busy():
		if interior != "":
			var it: Dictionary = world2.interiors[interior]
			shop_near = interior
			if player.global_position.distance_to(it.exit) < 2.2:
				shop_action = "exit"
			elif player.global_position.distance_to(it.counter) < 2.6:
				shop_action = "buy"
		else:
			for sh in city.shops:
				if Vector2(sh.pos.x - player.global_position.x, sh.pos.z - player.global_position.z).length() < 3.2:
					shop_near = sh.type
					shop_action = "enter"
	hud.shop_label = {"enter": "ENTRAR", "exit": "SAIR", "buy": "COMPRAR"}.get(shop_action, "")
	var pk: String = player.vehicle.kind if player.vehicle else ""
	hud.gas_name = "SUBIR" if pk == "heli" else "ACEL"
	hud.brk_name = "DESCER" if pk == "heli" else "FREIO"
	hud.stars_blink = wanted > 0 and not police.seen
	var bl: Array = missions.blips()
	for u in police.units:
		if is_instance_valid(u.car):
			bl.append({"pos": u.car.global_position, "col": Color(0.2, 0.45, 1.0) if int(Time.get_ticks_msec() / 250) % 2 == 0 else Color(1, 0.15, 0.15)})
	if police.heli and is_instance_valid(police.heli):
		bl.append({"pos": police.heli.global_position, "col": Color(0.2, 0.45, 1.0)})
	if interior == "":
		for sh in city.shops:
			bl.append({"pos": sh.pos, "col": {"guns": Color(1, 0.3, 0.2), "cars": Color(0.3, 0.8, 1), "clothes": Color(0.95, 0.45, 0.85)}[sh.type]})
	hud.map_blips = bl
	hud.clock.text = "%02d:%02d" % [int(tod), int(fmod(tod, 1.0) * 60.0)]
	autosave_t += dt
	if autosave_t > 60.0 and shot == "":
		autosave_t = 0.0
		ui.save_game()
	hud.map_player = player.global_position
	hud.map_yaw = cam_yaw + PI
	hud.map_police = Vector3.INF
	hud.speed.text = ("%d km/h" % round(player.vehicle.speed_kmh())) if player.vehicle else ""
	if player.vehicle and player.vehicle.kind in ["plane", "heli"]:
		hud.speed.text += "\nalt. %d m" % round(player.vehicle.global_position.y)
	if msg_t > 0:
		msg_t -= dt
		if msg_t <= 0: hud.hint.text = ""
	elif shop_action != "":
		hud.hint.text = {"guns": "AMMU★NATION", "cars": "Concessionária", "clothes": "Loja de roupas"}[shop_near] + " · toque em " + hud.shop_label
	elif player.swimming:
		hud.hint.text = "Nadando"
	else:
		hud.hint.text = ""
	if shot != "":
		_shot_tick()

func _near_kind(k: String):
	var best = null
	for c in cars:
		if is_instance_valid(c) and c.kind == k and (best == null or c.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position)):
			best = c
	return best

## cenas de teste do lote 7
func _test_views() -> void:
	var v := shot_view
	if v == "beach" and frames == 4:
		player.global_position = Vector3(world2.SHORE_X - 20.0, 1.3, 30.0)
		cam_yaw = -PI * 0.5 - 0.5
		cam_pitch = -0.12
	if v == "swim":
		if frames == 4:
			player.global_position = Vector3(world2.SHORE_X + 14.0, 0.5, 20.0)
			cam_yaw = -PI * 0.5
		if frames > 6:
			hud.joy = Vector2(0, -1)
		if frames % 30 == 0:
			print("SWIM ", frames, " swim=", player.swimming, " pos=", player.global_position.snapped(Vector3.ONE * 0.1))
	if v in ["airport", "planefly", "helifly"] and frames == 4:
		var k: String = "heli" if v == "helifly" else "plane"
		var pl = _near_kind(k) if false else null
		for c in cars:
			if c.kind == k:
				pl = c
				break
		player.global_position = pl.global_position + pl.global_transform.basis.x * (6.0 if k == "plane" else 2.4)
		cam_yaw = PI * 0.5 if v == "airport" else 0.0
	if v in ["planefly", "helifly"]:
		if frames == 6:
			_toggle_car()
		if player.vehicle and frames > 6:
			var c = player.vehicle
			if v == "planefly":
				c.throttle = 1.0
				c.stick = Vector2(0, -0.6 if frames > 130 else 0.0)
			else:
				c.throttle = 1.0 if frames < 120 else 0.0
				c.stick = Vector2(0.0, 0.6 if frames > 120 else 0.0)
		if frames % 30 == 0:
			print("FLY ", frames, " veh=", player.vehicle.kind if player.vehicle else "-", " anim=", vehanim.state, " pos=", (player.vehicle.global_position if player.vehicle else player.global_position).snapped(Vector3.ONE), " v=", snappedf(player.vehicle.v, 0.1) if player.vehicle else 0.0, " dead=", player.vehicle.dead if player.vehicle else false)
	if v == "boatride":
		if frames == 4:
			for c in cars:
				if c.kind == "boat":
					player.global_position = c.global_position + Vector3(0, 1.4, -3.0)
					player.global_position = Vector3(world2.SHORE_X + 50.0, 1.9, 40.0)
					break
		if frames == 8:
			_toggle_car()
		if player.vehicle and frames > 8:
			player.vehicle.throttle = 1.0
			player.vehicle.steer_in = 0.4 if frames > 100 else 0.0
		if frames % 30 == 0:
			print("BOAT ", frames, " veh=", player.vehicle.kind if player.vehicle else "-", " anim=", vehanim.state, " pos=", (player.vehicle.global_position if player.vehicle else player.global_position).snapped(Vector3.ONE * 0.1))
	if v == "enter":
		if frames == 4:
			player.global_position = my_car.global_position + Vector3(3.0, 0, 3.0)
			cam_yaw = 0.9
		if frames == 6:
			_toggle_car()
		if frames == 90:
			_toggle_car()
		if frames % 6 == 0 and frames < 150:
			print("ENT ", frames, " st=", vehanim.state, " veh=", player.vehicle != null, " door=", snappedf(my_car.door_open, 0.01), " seat=", (seated.position.snapped(Vector3.ONE * 0.01) if seated else Vector3.ZERO), " vis=", player.visible)
	if v == "interior":
		if frames == 4:
			player.global_position = city.shops[0].pos
		if frames == 8:
			_shop_action()
		if frames == 12:
			print("INT ", interior, " action=", shop_action, " pos=", player.global_position)
	if v == "interior2" and frames == 6:
		enter_interior("cars")
		cam_yaw = PI + 0.4
	if v == "explode":
		if frames == 4:
			player.global_position = my_car.global_position + Vector3(-9.0, 0, 6.0)
			cam_yaw = -2.2
		if frames == 30:
			my_car.take_damage(200.0)
		if frames % 20 == 0:
			print("EXP ", frames, " car_dead=", my_car.dead, " hp=", snappedf(hp, 1), " down=", snappedf(combat.down_t, 0.1))
	if v == "wanted":
		if frames == 4:
			_add_wanted(4)
			combat.weapon = "pistol"
			god = true
		if frames % 30 == 0:
			var dmin := 999.0
			for u in police.units:
				dmin = minf(dmin, u.car.global_position.distance_to(player.global_position))
			if police.units.size() > 0:
				var u0 = police.units[0]
				print("  U0 pos=", u0.car.global_position.snapped(Vector3.ONE), " v=", snappedf(u0.car.forward_speed(), 0.1), " thr=", u0.car.throttle, " str=", snappedf(u0.car.steer_in, 0.01), " brk=", u0.car.brake_in, " out=", u0.out, " nav=", u0.get("nav", {}).get("pts", []).size(), " back=", u0.get("nav", {}).get("back", 0.0), " eng=", u0.car.engine_force, " dead=", u0.car.dead)
			print("WNT ", frames, " nearest=", snappedf(dmin, 1), " stars=", wanted, " units=", police.units.size(), " cops=", police.cops.size(), " heli=", police.heli != null, " hp=", snappedf(hp, 1), " seen=", police.seen)
	if v == "aimshot":
		if frames == 4:
			player.global_position = my_car.global_position + Vector3(-5.0, 0, 12.0)
			cam_yaw = -PI
			cam_pitch = -0.05
			hud.aim = true
			combat.weapon = "rifle"
			combat.ammo["rifle"] = 50
			combat.owned["rifle"] = true
			combat._equip()
		if frames > 20 and frames < 30:
			combat.fire_held = true
	if v == "punch":
		if frames == 4:
			player.global_position = my_car.global_position + Vector3(-5.0, 0, 12.0)
			shot_ped = Ped.new()
			add_child(shot_ped)
			var pp: Vector3 = player.global_position + Vector3(0, 0, 1.6)
			shot_ped.setup([pp, pp + Vector3(0, 0, 0.1), pp, pp], 0, rng)
			peds.append(shot_ped)
			combat.weapon = "fist"
			combat._equip()
			cam_yaw = PI
		if frames > 10 and frames < 200 and frames % 3 == 0:
			combat.combo_t = 0.5
			combat.shoot()
			print("PUN ", frames, " combo=", combat.combo, " ped_hp=", shot_ped.hp if is_instance_valid(shot_ped) else -1, " down=", shot_ped.down if is_instance_valid(shot_ped) else true, " stars=", wanted)
	if v == "wheel" and frames == 20:
		combat.owned = {"fist": true, "pistol": true, "rifle": true, "rpg": true, "grenade": true}
		combat.ammo = {"pistol": 30, "rifle": 90, "rpg": 3, "grenade": 4}
		ui.show_wheel()
	if v == "rpg":
		if frames == 4:
			player.global_position = my_car.global_position + Vector3(-25.0, 0, 0.0)
			combat.owned["rpg"] = true
			combat.ammo["rpg"] = 3
			combat.weapon = "rpg"
			combat._equip()
			cam_yaw = PI * 0.5
			cam_pitch = -0.04
			hud.aim = true
		if frames == 20:
			cam_yaw = atan2(player.global_position.x - my_car.global_position.x, player.global_position.z - my_car.global_position.z)
		if frames == 40:
			combat.shoot()
		if frames % 20 == 0:
			print("RPG ", frames, " rockets=", combat.rockets.size(), " car_hp=", snappedf(my_car.hp, 1), " dead=", my_car.dead)
	if v == "taxi":
		if frames == 4:
			var tx = _near_kind("taxi")
			player.global_position = tx.door_world()
			set_meta("tx", tx)
		if frames == 6:
			vehanim.start_enter(get_meta("tx"))
		if frames % 30 == 0:
			print("TAXI ", frames, " veh=", player.vehicle.kind if player.vehicle else "-", " active=", missions.active, " st=", missions.taxi_state, " obj=", missions.obj_pos, " text=", missions.text)
	if v == "mission":
		if frames == 4:
			player.global_position = missions.givers[1].pos
		if frames % 30 == 0:
			print("MIS ", frames, " active=", missions.active, " text=", missions.text, " hostiles=", missions.hostiles().size(), " timer=", snappedf(missions.timer, 1))
	if v == "busride":
		if frames == 4:
			var b = null
			for a in traffic_sys.agents:
				if a.car.kind == "bus":
					b = a.car
			player.global_position = b.door_world()
		if frames == 6:
			_toggle_car()
		if player.vehicle and frames > 80:
			player.vehicle.throttle = 1.0
		if frames % 30 == 0:
			print("BUSR ", frames, " veh=", player.vehicle.kind if player.vehicle else "-", " anim=", vehanim.state, " v=", snappedf(player.vehicle.speed_kmh(), 1) if player.vehicle else 0.0)
	if v == "fall":
		if frames == 4:
			player.global_position = Vector3(city._center(2), 22.0, city._center(2) - city.BLOCK * 0.5 + 1.0)
		if frames % 15 == 0:
			print("FALL ", frames, " y=", snappedf(player.global_position.y, 0.1), " hp=", snappedf(hp, 1), " down=", snappedf(combat.down_t, 0.1), " rag=", player.body.ragdolled)
	if v == "traffic":
		if frames == 4:
			player.global_position = Vector3(city._center(2) - city.CELL * 0.5 + 9.0, 0.3, city._center(2) - city.CELL * 0.5 + 9.0)
			cam_yaw = PI * 0.25
			cam_pitch = -0.35
		if frames % 60 == 0:
			var mv := 0
			var st := 0
			for a in traffic_sys.agents:
				if a.car.linear_velocity.length() > 2.0: mv += 1
				if a.stuck > 1.0: st += 1
			if frames % 300 == 0:
				for a in traffic_sys.agents:
					if a.car.linear_velocity.length() < 1.0:
						var lim2: float = traffic_sys._ahead_limit(a.car, a.car.global_position)
						var bl = traffic_sys.last_block
						print("  STOP ", a.car.kind, " pos=", a.car.global_position.snapped(Vector3.ONE), " n=", a.n, " d=", a.d, " st=", a.st, " wps=", a.wps.size(), " lim=", snappedf(lim2, 0.1), " blk=", (bl.kind + str(bl.global_position.snapped(Vector3.ONE))) if bl and lim2 < 50 else "-", " thr=", snappedf(a.car.throttle, 0.01), " brk=", snappedf(a.car.brake_in, 0.01), " up=", snappedf(a.car.global_transform.basis.y.y, 0.01))
			print("TRF ", frames, " agents=", traffic_sys.agents.size(), " moving=", mv, " stuck=", st, " clock=", snappedf(Traffic.clock, 0.1), " ns_green=", Traffic.green("ns"))
	if v == "motoseat":
		if frames == 4:
			var mo = null
			for c in cars:
				if c.kind == "moto" and not traffic_sys.is_agent(c):
					mo = c
					break
			player.global_position = mo.door_world()
			set_meta("moto", mo)
		if frames == 6:
			_toggle_car()
		if frames == 40:
			cam_yaw = get_meta("moto").rotation.y + PI * 0.5
			cam_idle = 999.0
			cam_pitch = -0.1
	if v == "exitcar":
		if frames == 4:
			player.global_position = my_car.door_world()
		if frames == 6:
			_toggle_car()
		if frames == 60:
			_toggle_car()
		if frames % 10 == 0 and frames > 50:
			print("EXIT ", frames, " anim=", vehanim.state, " car_v=", snappedf(my_car.linear_velocity.length(), 0.01), " car_y=", snappedf(my_car.global_position.y, 0.01), " hp=", my_car.hp, " veh=", player.vehicle != null)
	if v == "bump":
		if frames == 4:
			player.global_position = my_car.global_position + Vector3(-5.0, 0, 12.0)
			shot_ped = Ped.new()
			add_child(shot_ped)
			var pp: Vector3 = player.global_position + Vector3(0, 0, 4.0)
			shot_ped.setup([pp, pp + Vector3(0, 0, 0.1), pp, pp], 0, rng)
			shot_ped.speed = 0.0
			peds.append(shot_ped)
			cam_yaw = PI
		if frames > 6 and frames < 40:
			hud.joy = Vector2(0, -1)
			hud.sprint = true
		if frames == 40:
			hud.joy = Vector2.ZERO
		if frames % 10 == 0:
			print("BMP ", frames, " knocked=", snappedf(shot_ped.knocked, 0.1), " hp=", shot_ped.hp, " down=", shot_ped.down, " rag=", shot_ped.body.ragdolled if is_instance_valid(shot_ped.body) else "-")
	if v == "props":
		if frames == 4:
			var pr: Dictionary = city.props[0]
			for q in city.props:
				if q.type == "lamp":
					pr = q
					break
			set_meta("pr", pr)
			var c = _spawn_car(pr.pos + Vector3(0, 0.6, -30.0), 0.0, Color.RED, false, "sedan")
			c.linear_velocity = Vector3(0, 0, 14.0)
			set_meta("pc", c)
			player.global_position = pr.pos + Vector3(-8.0, 0, 5.0)
			cam_yaw = -PI * 0.5
		if frames % 10 == 0 and frames > 4:
			var c2 = get_meta("pc")
			c2.throttle = 1.0
			c2.steer_in = 0.0
			print("PRP ", frames, " lamp_alive=", get_meta("pr").alive, " car_v=", snappedf(c2.linear_velocity.length(), 0.1), " hp=", snappedf(c2.hp, 1), " z=", snappedf(c2.global_position.z, 0.1))
	if v == "motocrash":
		if frames == 4:
			var mo = null
			for c in cars:
				if c.kind == "moto" and not traffic_sys.is_agent(c):
					mo = c
					break
			player.global_position = mo.door_world()
			set_meta("moto", mo)
		if frames == 6:
			_toggle_car()
		if player.vehicle and frames > 70:
			player.vehicle.throttle = 1.0
			player.vehicle.steer_in = -1.0 if frames > 120 else 0.0
		if frames % 15 == 0:
			var mo2 = get_meta("moto")
			print("MCR ", frames, " veh=", player.vehicle.kind if player.vehicle else "-", " anim=", vehanim.state, " hp=", snappedf(hp, 1), " down=", snappedf(combat.down_t, 0.1), " v=", snappedf(mo2.speed_kmh(), 1), " pos=", mo2.global_position.snapped(Vector3.ONE), " thr=", mo2.throttle)

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
	if frames == 30 and shot_view == "settings":
		ui.show_settings(ui.show_main_menu)
	if frames == 30 and shot_view in ["shop", "cars_shop"]:
		money = 2500
		ui.show_shop("guns" if shot_view == "shop" else "cars")
	if shot_view == "buy":
		if frames == 10:
			new_game()
			money = 20000
			ui._buy_gun(ui.GUNS[0])
			ui._buy_gun(ui.GUNS[6])
			ui.car_color = 0
			ui._buy_car(ui.CARS[2])
			print("BUY money=", money, " owned=", combat.owned, " ammo=", combat.ammo, " armor=", armor, " cars=", owned_cars, " nodes=", _owned_nodes().size())
			combat._on_cop_shot(20.0, player.global_position)
			print("HIT hp=", hp, " armor=", armor)
		if frames == 20:
			new_game()
			print("NEW outfit=", player.outfit, " tod=", tod, " money=", money, " owned=", combat.owned, " nodes=", _owned_nodes().size())
			ui.save_game()
		if frames == 21:
			ui._clothes_begin()
			ui._set_outfit("hat", 2)
			ui._set_outfit("shirt", "a3141a")
			print("CLOTH cost=", ui._outfit_cost())
			ui._clothes_buy()
			ui._clothes_exit()
			tod = 21.25
			ui.save_game()
			print("CLOTH money=", money, " outfit=", player.outfit)
		if frames == 22:
			money = 20000
			ui._buy_car(ui.CARS[0])
			player.outfit = player.OUTFIT0.duplicate()
			tod = 3.0
			load_game()
			print("LOAD outfit=", player.outfit, " tod=", snappedf(tod, 0.01), " money=", money, " owned=", combat.owned, " weapon=", combat.weapon, " cars=", owned_cars.size(), " nodes=", _owned_nodes().size())
	if shot_view in ["night", "dusk", "nightcar"] and frames == 3:
		tod = {"night": 22.5, "dusk": 17.6, "nightcar": 23.0}[shot_view]
		daynight.set_process(false)
		daynight.apply(0.0, true)
	if shot_view == "nightcar" and frames == 4:
		player.global_position = my_car.global_position + Vector3(2.0, 0, 0)
	if shot_view == "nightcar" and frames == 5:
		_toggle_car()
		daynight.apply(0.0, true)
		cam_yaw = 0.3
		cam_idle = 999.0
	if shot_view == "night" and frames == 4:
		cam_yaw = PI * 0.75
		cam_pitch = -0.12
	if shot_view == "clothes" and frames == 20:
		player.global_position = city.shops[2].pos + Vector3(0, 0, -1.0)
	if shot_view == "clothes" and frames == 30:
		money = 900
		ui.show_shop("clothes")
		ui._set_outfit("jacket", "5a3a22")
		ui._set_outfit("hat", 1)
		ui._set_outfit("glasses", true)
	_test_views()
	if shot_view == "warm" and frames % 5 == 0 and frames < 40:
		print("WARM ", frames, " w=", daynight._warm, " omni=", daynight.lamp_lights.filter(func(l): return l.visible).size(), " spot=", daynight.car_lights.filter(func(c): return c.l.visible).size())
	if shot_view == "bus" and frames == 4 or shot_view == "bus" and frames == shot_at - 2:
		var b = traffic_sys.agents.filter(func(a): return a.car.kind == "bus")[0].car
		var bx: Vector3 = b.global_transform.basis.x
		var bz: Vector3 = b.global_transform.basis.z
		player.global_position = b.global_position + bx * 6.5 + bz * 7.0
		var away: Vector3 = (bx * 1.0 + bz * 0.25).normalized()
		cam_yaw = atan2(away.x, away.z)
		cam_pitch = -0.12
	if shot_view == "bus" and frames % 30 == 0:
		for a in traffic_sys.agents:
			if a.car.kind == "bus":
				print("  BA n=", a.n, " d=", a.d, " st=", a.st, " thr=", a.car.throttle, " brk=", a.car.brake_in, " stop_t=", a.stop_t, " lim=", traffic_sys._ahead_limit(a.car, a.car.global_position), " back=", a.back, " blk=", (str(traffic_sys.last_block.kind) + str(traffic_sys.last_block.global_position.snapped(Vector3.ONE)) + " agent=" + str(traffic_sys.is_agent(traffic_sys.last_block))) if traffic_sys.last_block else "-")
		print("BUS ", frames, " ", traffic_sys.agents.filter(func(a): return a.car.kind == "bus").map(func(x): return [x.n, snappedf(x.stop_t, 0.1), x.car.global_position.snapped(Vector3.ONE), snappedf(x.car.speed_kmh(), 1)]))
	if shot_view in ["moto", "motoride"] and frames == 4:
		var mo = cars.filter(func(c): return c.kind == "moto" and not traffic_sys.is_agent(c))[0]
		player.global_position = mo.global_position + Vector3(-1.2, 0, 0)
		cam_yaw = -PI * 0.5 - 0.6
		cam_pitch = -0.15
	if shot_view == "motoride" and frames == 6:
		_toggle_car()
		print("RIDE veh=", player.vehicle.kind if player.vehicle else "none")
	if shot_view == "motoride" and frames > 8 and player.vehicle:
		player.vehicle.throttle = 0.7
		player.vehicle.steer_in = 0.0 if frames < 100 else 0.7
		if frames % 20 == 0: print("MOTO ", frames, " v=", snappedf(player.vehicle.speed_kmh(), 1), " up=", snappedf(player.vehicle.global_transform.basis.y.y, 0.01), " pos=", player.vehicle.global_position.snapped(Vector3.ONE))
	if shot_view == "shopsign" and frames == 4:
		var sh: Dictionary = city.shops[0]
		player.global_position = sh.pos + Vector3(-3, 0, -6)
		cam_yaw = PI + 0.4
		cam_pitch = -0.1
	if frames == shot_at:
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot)
		var info := {"draws": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), "prims": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), "fps": fps_show, "car_z": my_car.global_position.z, "car_x": my_car.global_position.x, "car_speed": my_car.linear_velocity.length(), "yaw": my_car.rotation.y, "up": my_car.global_transform.basis.y.y, "wanted": wanted, "police_d0": get_meta("pd0", -1.0), "pol": ([police_car.global_position, police_car.linear_velocity.length(), police_car.throttle, police_car.engine_force, police_car.brake, police_car.wheels.map(func(w): return w.is_in_contact())] if police_car else []), "police_d": (police_car.global_position.distance_to(player.global_position) if police_car else -1.0), "walk": (player.global_position - get_meta("p0", player.global_position)), "camdir": (get_meta("p0", player.global_position) - get_meta("c0", cam.global_position))}
		print("SHOT ", JSON.stringify(info))
		get_tree().quit()

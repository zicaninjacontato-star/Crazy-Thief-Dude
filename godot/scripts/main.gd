extends Node3D
## Fatia de teste: monta ambiente (céu, sol, sombras, tonemap), cidade, jogador, carros, pedestres e polícia.

const City := preload("res://scripts/city.gd")
const Player := preload("res://scripts/player.gd")
const Car := preload("res://scripts/car.gd")
const Ped := preload("res://scripts/ped.gd")
const Hud := preload("res://scripts/hud.gd")
const Humanoid := preload("res://scripts/humanoid.gd")
const M := preload("res://scripts/mats.gd")
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
const Sea := preload("res://scripts/sea.gd")

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
var sea: Node3D
var cine_cam := false      # câmera controlada por uma cena (lula gigante)
var _snd_t := {}
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
	_spawn_population()
	hud.weapon_pressed.connect(func(): ui.show_wheel())
	hud.shop_pressed.connect(_shop_action)
	hud.siren_pressed.connect(_toggle_siren)
	hud.rob_pressed.connect(func(): combat.rob_target())
	hud.hostage_pressed.connect(func(): combat.toggle_hostage())
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
	c.unlocked = true

func _place_owned(kind: String, col: Color, i: int) -> void:
	var base: Vector3 = my_car.global_position
	var c = _spawn_car(base + Vector3(0, 0, 8.0 + i * 6.5), 0.0, col, false, kind)
	c.set_meta("owned", true)
	c.unlocked = true

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
	c.engine_died.connect(func(cc): if cc == player.vehicle: _msg("Motor quebrado! O carro não anda mais"))
	c.unlocked = rng.randf() < 0.3 and not police
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
	a.destroyed_water.connect(func(cc): if cc == player.vehicle: eject_player(Vector3.ZERO); _msg("O barco afundou!" if cc.kind == "boat" else "A aeronave afundou!"))
	cars.append(a)
	return a

## táxis, barcos, aviões, helicóptero, viaturas da delegacia, banhistas
func _spawn_extras() -> void:
	# trânsito com regras (traffic.gd): carros, motos, táxis e 2 ônibus na linha
	traffic_sys = Traffic.new()
	add_child(traffic_sys)
	traffic_sys.setup(self)
	# pescadores nos deques do costão
	for fs in world2.fish_spots:
		var fh := Humanoid.new()
		fh.build(Color.from_hsv(rng.randf(), 0.4, 0.6), Color(0.25, 0.3, 0.2), Color(0.78, 0.56, 0.38), Color(0.15, 0.1, 0.06), {"hat": 1, "hat_c": Color(0.85, 0.8, 0.6)})
		add_child(fh)
		fh.global_position = fs[0] + Vector3(0, -0.2, 0)
		fh.rotation.y = fs[1]
		fh.sitting = rng.randf() < 0.5
		if fh.sitting:
			fh.global_position.y -= 0.45
		fh.animate(0, 0)
		var rod := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(0.03, 0.03, 3.2)
		rod.mesh = rb
		rod.material_override = M.plain(Color(0.15, 0.12, 0.1), 0.5)
		rod.position = Vector3(0, 1.25, 1.3)
		rod.rotation.x = -0.55
		fh.add_child(rod)
		var line := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.008, 3.6, 0.008)
		line.mesh = lb
		line.material_override = M.plain(Color(0.9, 0.9, 0.9), 0.5)
		line.position = Vector3(0, 0.7, 2.75)
		fh.add_child(line)
		fh.set_far(80.0)
	sea = Sea.new()
	add_child(sea)
	sea.setup(self)

## batida de qualquer veículo
func _on_crash(c, dv: float) -> void:
	var pv: Vector3 = c.global_position
	if pv.distance_to(player.global_position) < 60.0:
		audio.play("crash", pv, clampf((dv - 6.0) * 0.5, -6.0, 6.0))
	if dv > 9.0:
		FX.sparks(self, pv + Vector3(0, 0.7, 0))
	if dv > 14.0 and c.get("paint_c") != null:
		FX.debris(self, pv + Vector3(0, 0.9, 0), c.paint_c, c.linear_velocity * 0.4 + Vector3(randf_range(-3, 3), 4, randf_range(-3, 3)))
	if c.kind == "moto" and dv > 6.0 and traffic_sys.is_agent(c):
		traffic_sys.eject_rider(c, false)
	if c == player.vehicle:
		hp -= maxf(0.0, dv - 8.0) * (2.4 if c.kind == "moto" else 0.9)
		hud.flash = 0.2
		# moto: o piloto voa e a moto tomba
		if c.kind == "moto" and dv > 7.5:
			var vel: Vector3 = c.linear_velocity + c.global_transform.basis.z * dv * 0.6
			eject_player(Vector3.ZERO)
			combat.knockdown(vel + Vector3(0, 3.0, 0), 3.0)
			c.fall_over()

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
	for a in police.army:
		if is_instance_valid(a) and not a.dead and a.global_position.distance_to(pos) < radius * 1.4:
			a.take_damage(dmg * (1.0 - a.global_position.distance_to(pos) / (radius * 1.4)) * 0.9)
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
const SHOP_NAMES := {"guns": "AMMU★NATION", "cars": "CONCESSIONÁRIA", "clothes": "LOJA DE ROUPAS"}
var act_target = null      # corpo ou carro da ação atual
func _shop_action() -> void:
	match shop_action:
		"enter":
			for sh in city.shops:
				if Vector2(sh.pos.x - player.global_position.x, sh.pos.z - player.global_position.z).length() < 3.2:
					var tp: String = sh.type
					ui.cinematic(SHOP_NAMES[tp], "entrando...", func(): enter_interior(tp))
					return
		"exit":
			ui.cinematic(SHOP_NAMES.get(interior, ""), "saindo...", leave_interior)
		"buy":
			ui.show_shop(interior)
		"carry":
			combat.pick_body(act_target)
		"drop":
			combat.drop_body()
		"trunk":
			var c = act_target
			if c.get("trunk_node"):
				var tw := create_tween()
				tw.tween_method(c.set_trunk, 0.0, 1.0, 0.4)
				tw.tween_callback(func(): combat.trunk_action(c))
				tw.tween_interval(0.4)
				tw.tween_method(c.set_trunk, 1.0, 0.0, 0.4)
			else:
				combat.trunk_action(c)
			audio.play("door", c.global_position)

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
var breath := 100.0
var _route_t := 0.0
var _uw_fog := false
var shark_cd := 0.0
var shark_jump := -1.0
var _shark_from := Vector3.ZERO
func _water_tick(dt: float) -> void:
	for c in cars:
		if not is_instance_valid(c) or not (c is VehicleBody3D) or c.freeze:
			continue
		var cp: Vector3 = c.global_position
		if not c.has_meta("sink_t") and absf(cp.x) < 165.0 and absf(cp.z) < 175.0:
			continue          # no meio da cidade não precisa checar o mar
		if world2.sea_dist(c.global_position.x, c.global_position.z) > 11.0 and world2.is_water(c.global_position.x, c.global_position.z) and not c.has_meta("sinking"):
			# boia alguns segundos e vai afundando devagar (quem fica dentro se afoga)
			c.set_meta("sinking", true)
			c.set_meta("sink_t", 0.0)
			FX.splash(self, c.global_position + Vector3(0, 0.8, 0), 1.6)
			audio.play("splash", c.global_position, 4.0)
			c.dead = true
			c.gravity_scale = 0.0
			c.linear_damp = 1.8
			c.angular_damp = 2.0
			var cc = c
			get_tree().create_timer(90.0).timeout.connect(func(): if is_instance_valid(cc) and cc != player.vehicle: cars.erase(cc); cc.queue_free())
		elif c.has_meta("sink_t"):
			var st: float = c.get_meta("sink_t") + dt
			c.set_meta("sink_t", st)
			if st < 5.0:
				# flutuando, balançando
				var fy: float = world2.WATER_Y - 0.55 - st * 0.08
				c.linear_velocity.y = (fy - c.global_position.y) * 2.0
				c.apply_torque(Vector3(sin(st * 2.0), 0, cos(st * 1.7)) * c.mass * 0.6)
				if int(st * 4.0) != int((st - dt) * 4.0):
					FX.splash(self, c.global_position + Vector3(0, 0.6, 0), 0.4)
			else:
				c.gravity_scale = 0.12
	# mergulho, fôlego e afogamento
	player.diving = player.swimming and (hud.jump_held or Input.is_action_pressed("jump"))
	player.rising = player.swimming and (hud.rise_held or Input.is_key_pressed(KEY_Q))
	var pv = player.vehicle
	var in_sunk: bool = pv != null and pv.has_meta("sink_t") and pv.global_position.y + 1.1 < world2.WATER_Y
	if (player.underwater or in_sunk) and not combat.dead:
		breath = maxf(0.0, breath - dt * 8.0)
		if breath <= 0.0:
			hp -= dt * 14.0
			hud.flash = maxf(hud.flash, 0.15)
	else:
		breath = minf(100.0, breath + dt * 30.0)
	hud.breath = breath if (player.swimming and breath < 99.5) else -1.0
	var uw: bool = cam.global_position.y < world2.WATER_Y - 0.05 and world2.is_water(cam.global_position.x, cam.global_position.z)
	if uw != _uw_fog:
		_uw_fog = uw
		world_env.fog_density = 0.09 if uw else 0.0022
		world_env.fog_light_color = Color(0.05, 0.25, 0.32) if uw else world_env.fog_light_color
		if not uw:
			daynight.apply(0.0, true)
	_shark_tick(dt)

## tubarão no fim do mar: ataca o barco até destruir (ou pula nele e come o jogador); quem está nadando é mordido
func _shark_tick(dt: float) -> void:
	var pp: Vector3 = player.global_position
	var boat = player.vehicle if player.vehicle and player.vehicle.kind == "boat" else null
	var far: bool = world2.is_water(pp.x, pp.z) and world2.sea_dist(pp.x, pp.z) > 280.0
	if (player.swimming or boat) and far and shark == null and not combat.dead:
		shark = _make_shark()
		shark.global_position = pp + Vector3(45.0, 0, randf_range(-25, 25))
		_msg("Cuidado: tubarão!")
	if shark == null:
		return
	shark_t += dt
	shark_cd -= dt
	if shark_jump >= 0.0:
		# salto em cima do barco: arco sobre o jogador e mordida fatal
		shark_jump += dt
		var k := clampf(shark_jump / 0.9, 0.0, 1.0)
		shark.global_position = _shark_from.lerp(pp, k) + Vector3(0, sin(k * PI) * 3.5, 0)
		shark.rotation.x = lerpf(-0.6, 0.6, k)
		if k >= 1.0:
			shark_jump = -1.0
			shark.rotation.x = 0.0
			if not combat.dead:
				FX.blood_burst(self, pp + Vector3(0, 1.0, 0), Vector3.UP, 50)
				audio.play("scream", pp)
				if player.vehicle:
					player.vehicle.take_damage(60.0)
				combat.kill_now()
		return
	var target: Vector3 = boat.global_position if boat else pp
	var to: Vector3 = target - shark.global_position
	to.y = 0
	var hunting: bool = (player.swimming or boat != null) and not combat.dead
	if not hunting:
		to = -to
		if shark.global_position.distance_to(pp) > 120.0:
			shark.queue_free()
			shark = null
			return
	var d := to.length()
	if hunting and d < (3.2 if boat else 1.6) and shark_cd <= 0.0:
		if boat:
			if randf() < 0.25:
				shark_jump = 0.0
				_shark_from = shark.global_position
				audio.play("splash", shark.global_position, 4.0)
				return
			shark_cd = 2.2
			boat.take_damage(18.0)
			boat.model_root.rotation.z += randf_range(-0.25, 0.25)
			FX.splash(self, shark.global_position + Vector3(0, 0.9, 0), 1.2)
			audio.play("crash", boat.global_position, 2.0)
			hud.flash = 0.2
		else:
			shark_cd = 1.0
			FX.blood_burst(self, pp + Vector3(0, 0.9, 0), Vector3.UP, 40)
			audio.play("scream", pp)
			combat.kill_now()
	var dir := to.normalized() if d > 0.01 else Vector3.FORWARD
	shark.global_position += dir * (8.5 if hunting else 3.0) * dt
	shark.global_position.y = world2.WATER_Y - (0.55 if not player.underwater else 1.6) + sin(shark_t * 3.0) * 0.05
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
		if not air and k not in ["boat", "plane", "heli", "moto"] and spd > 6.0 and c.get("door_node") != null:
			c.throttle = 0.0
			c.brake_in = 0.0
			vehanim.start_jump(c)
			return
		if air or (k == "moto" and spd > 3.0) or (k not in ["boat", "plane", "heli", "moto"] and spd > 6.0):
			var vel: Vector3 = c.linear_velocity
			eject_player(Vector3.ZERO)
			if air:
				# pulou da aeronave: cai em ragdoll e o impacto no chão dá dano
				combat.knockdown(vel * 0.6 + Vector3(0, -2.0, 0), 3.0)
			else:
				combat.knockdown(vel * 0.7 + c.global_transform.basis.x * 3.0 + Vector3(0, 2.0, 0), 2.6)
			if k == "moto":
				c.fall_over()
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
	if best.get("npc_drv") != null:
		# piloto do barco/jet-ski/navio pula na água
		if is_instance_valid(best.npc_drv):
			FX.splash(self, best.npc_drv.global_position, 1.0)
			audio.play("splash", best.npc_drv.global_position)
			best.npc_drv.queue_free()
		best.npc_drv = null
	var info: Dictionary = traffic_sys.release(best)
	vehanim.start_enter(best, info)

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
		if not is_instance_valid(c) or c.global_position.distance_squared_to(player.global_position) > 64.0 or c.kind in ["plane", "heli", "boat"]:
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
	var vc = player.vehicle
	if vc != null and vc.linear_velocity.length() > 3.0:
		for p in peds:
			if not is_instance_valid(p) or p.down: continue
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
	_upkeep(dt)
	frames += 1
	# câmera em 3ª pessoa
	var drag: Vector2 = hud.take_cam_drag()
	if drag.length() > 0:
		cam_yaw -= drag.x * 0.006
		cam_pitch = clampf(cam_pitch - drag.y * 0.004, -1.0, 1.05 if hud.aim else 0.2)
		cam_idle = 2.0
	cam_idle -= dt
	var tgt: Node3D = player.vehicle if player.vehicle else player
	var dist := 4.6
	var h := 1.5
	if player.vehicle:
		dist = {"bus": 13.0, "plane": 15.0, "heli": 13.0, "boat": 9.0 if player.vehicle.get("subkind") != "ship" else 38.0, "moto": 5.5}.get(player.vehicle.kind, 7.5)
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
		cam_pitch = minf(cam_pitch, 0.2)
	if player.body:
		player.body.aim_pitch = clampf(cam_pitch + 0.25, -0.6, 1.2) if aiming else 0.0
	hud.swim_mode = player.swimming
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
	if not cine_cam:
		cam.global_position = cam.global_position.lerp(want_pos, minf(1.0, dt * (14.0 if aiming else 8.0))) if frames > 2 else want_pos
		cam.look_at(focus + (-off.normalized() * 6.0 if aiming else Vector3.ZERO), Vector3.UP)
	# ambiente: cidade x mar pela distância da água; braçadas; carros e barcos passando
	var sdist: float = world2.sea_dist(player.global_position.x, player.global_position.z)
	var amb_city := clampf((-sdist - 30.0) / 80.0, 0.0, 1.0) if interior == "" else 0.0
	var amb_sea := clampf((sdist + 90.0) / 100.0, 0.0, 1.0) if interior == "" else 0.0
	if player.underwater:
		amb_sea *= 0.25
		amb_city = 0.0
	audio.set_ambient(amb_city, amb_sea)
	if player.swimming and Vector2(player.velocity.x, player.velocity.z).length() > 0.6:
		_step_ph += dt * 1.3
		if _step_ph >= 1.0:
			_step_ph = 0.0
			audio.play("stroke", player.global_position, -4.0)
	if frames % 10 == 0:
		var nowt := Time.get_ticks_msec()
		for c in cars:
			if not is_instance_valid(c) or c == player.vehicle:
				continue
			var cd: float = c.global_position.distance_to(player.global_position)
			if cd < 9.0 and c.linear_velocity.length() > 8.0 and _snd_t.get(c.get_instance_id(), 0) < nowt:
				_snd_t[c.get_instance_id()] = nowt + 4000
				audio.play("whoosh", c.global_position, 0.0 if c.kind != "boat" else 3.0)
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
				audio.play("step_" + _surface(), null, -6.0 if hs < 4.0 else -3.0)
	# sirene: viatura da polícia mais próxima, ou a viatura que o jogador dirige com a sirene ligada
	var pv = player.vehicle
	var own_siren: bool = pv != null and pv.get("police") == true and pv.get("siren_on") == true
	hud.siren_avail = pv != null and pv.get("police") == true
	hud.siren_on = own_siren
	if own_siren:
		audio.set_siren(true, 0.0)
	else:
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
			# corpos e porta-malas
			if shop_action == "" and combat.down_t <= 0.0:
				act_target = null
				for c in cars:
					if is_instance_valid(c) and c is VehicleBody3D and not c.dead and (c.get("trunk_node") != null or c.kind == "pickup") and (combat.carrying != null or c.cargo > 0):
						if c.trunk_world().distance_to(player.global_position) < 1.8:
							shop_action = "trunk"
							act_target = c
				if shop_action == "" and combat.carrying != null:
					shop_action = "drop"
				elif shop_action == "":
					for q in peds:
						if is_instance_valid(q) and q.down and not q.body.parts.is_empty() and is_instance_valid(q.body.parts[0]) and q.body.parts[0].global_position.distance_to(player.global_position + Vector3(0, 0.4, 0)) < 1.6:
							shop_action = "carry"
							act_target = q
							break
	hud.action_kind = shop_action
	hud.weapon_kind = combat.weapon
	hud.heli = player.vehicle != null and player.vehicle.kind == "heli"
	# botão do carro só aparece com um veículo por perto
	var ce := false
	if player.vehicle == null and interior == "" and not combat.dead:
		for c in cars:
			if is_instance_valid(c) and not c.get("dead") and c.global_position.distance_to(player.global_position) < maxf(c.body_size.z, c.body_size.x) * 0.5 + 3.0 and not police.is_unit_car(c):
				ce = true
				break
	hud.can_enter = ce
	hud.shop_label = {"enter": "ENTRAR", "exit": "SAIR", "buy": "COMPRAR", "carry": "CARREGAR", "drop": "SOLTAR", "trunk": "PORTA-MALAS"}.get(shop_action, "")
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
	# rastro até o destino (missão/táxi tem prioridade sobre o ponto marcado no mapa)
	_route_t -= dt
	if _route_t <= 0.0:
		_route_t = 0.4
		var rtgt := Vector3.INF
		if missions.obj_pos != Vector3.INF:
			rtgt = missions.obj_pos
		elif hud.map_waypoint != Vector3.INF:
			rtgt = hud.map_waypoint
			if Vector2(rtgt.x - player.global_position.x, rtgt.z - player.global_position.z).length() < 12.0:
				hud.map_waypoint = Vector3.INF
				rtgt = Vector3.INF
				_msg("Você chegou ao ponto marcado")
		hud.map_route = route_path(player.global_position, rtgt) if rtgt != Vector3.INF and interior == "" else PackedVector3Array()
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
	elif shop_action in ["enter", "exit", "buy"]:
		hud.hint.text = {"guns": "AMMU★NATION", "cars": "Concessionária", "clothes": "Loja de roupas"}[shop_near] + " · toque em " + hud.shop_label
	elif player.swimming and player.underwater:
		hud.hint.text = "Debaixo d'água · segure ⬆ (SUBIR) para voltar"
	elif player.swimming:
		hud.hint.text = "Nadando"
	else:
		hud.hint.text = ""
	if shot != "":
		_shot_tick()

## cenas de teste do lote 9
func _test9(v: String) -> void:
	if v in ["swimpose", "gun1", "gun2", "gun3"]:
		if frames == 4:
			if v == "swimpose":
				player.global_position = Vector3(world2.SHORE_X + 40.0, 0.3, 30.0)
			else:
				player.global_position = my_car.global_position + Vector3(-6.0, 0, 14.0)
				combat.owned["rifle"] = true
				combat.ammo["rifle"] = 60
				combat.weapon = "pistol" if v != "gun3" else "rifle"
				combat._equip()
				hud.aim = v != "gun1"
		if frames > 6:
			cam_yaw = PI * 0.5
			cam_pitch = -0.05
			if v == "swimpose":
				hud.joy = Vector2(0, -1) if frames < 30 else Vector2.ZERO
			player.aim_yaw = 0.0 if v != "gun1" else NAN
			player.body.rotation.y = 0.0
			if frames % 5 == 0 and player.body.gun:
				print("GUN ", frames, " barrel=", (player.body.gun.global_basis * Vector3(0, -1, 0)).snapped(Vector3.ONE * 0.01), " aiming=", player.body.aiming)
	if v == "fullmap":
		if frames == 6:
			hud.map_waypoint = Vector3(120.0, 0, -100.0)
		if frames == 10:
			hud.open_map()
			print("MAP paused_on_open=", get_tree().paused)
			get_tree().paused = false     # o teste precisa continuar contando quadros
			hud.map_zoom = 1.0
		if frames == 14:
			print("MAP full=", hud.map_full, " paused=", get_tree().paused, " route=", hud.map_route.size())
	if v == "minimap":
		if frames == 6:
			hud.map_waypoint = Vector3(120.0, 0, -100.0)
		if frames % 10 == 0:
			print("MAP route=", hud.map_route.size())
	if v == "aimreact":
		if frames == 4:
			combat.weapon = "pistol"
			combat._equip()
			hud.aim = true
			var q = peds[0]
			for pq in peds:
				if pq.global_position.distance_to(player.global_position) < q.global_position.distance_to(player.global_position):
					q = pq
			set_meta("aq", q)
		if frames > 4:
			var q = get_meta("aq")
			if is_instance_valid(q):
				if frames < 8:
					player.global_position = q.global_position + Vector3(0, 0, -6.0)
				var to: Vector3 = q.global_position - player.global_position
				cam_yaw = atan2(to.x, to.z) + PI
				cam_pitch = -0.05
				if frames == 20 and q.mode != "handsup":
					q.reacted = false
					q.mode = ""
					q._rng.seed = 3
					while true:
						q.reacted = false
						q.react_aim()
						if q.mode == "handsup":
							break
						q._end_mode()
						q.flee = 0.0
				if frames % 5 == 0:
					print("AIM ", frames, " mode=", q.mode, " flee=", snappedf(q.flee, 0.1), " reacted=", q.reacted, " rob=", hud.rob_avail, " money=", money, " hostage=", combat.hostage != null)
				if frames == 30:
					player.global_position = q.global_position + (player.global_position - q.global_position).normalized() * 2.5
				if frames == 35:
					combat.toggle_hostage()
				if frames == 50:
					combat.toggle_hostage()
				if frames == 55:
					q.mode = "handsup"
					q.body.arm_pose = "handsup"
					q.robbed = false
				if frames == 60:
					combat.rob_target()
	if v == "brawl":
		if frames == 4:
			combat.weapon = "fist"
			combat._equip()
			var q = peds[0]
			for pq in peds:
				if pq.global_position.distance_to(player.global_position) < q.global_position.distance_to(player.global_position):
					q = pq
			set_meta("bq", q)
			player.global_position = q.global_position + Vector3(0, 0, -3.0)
			q.start_brawl()
		if frames > 4:
			var q = get_meta("bq")
			if is_instance_valid(q):
				var to: Vector3 = q.global_position - player.global_position
				cam_yaw = atan2(to.x, to.z) + PI - 0.6
				cam_pitch = -0.1
				if frames % 6 == 0 and frames > 20:
					combat.shoot()
				if frames % 5 == 0:
					print("BRW ", frames, " mode=", q.mode, " qhp=", snappedf(q.hp, 1), " down=", q.down, " knocked=", snappedf(q.knocked, 0.1), " php=", snappedf(hp, 1), " combo=", combat.combo)
	if v == "carjump":
		if frames == 4:
			player.global_position = my_car.door_world()
		if frames == 6:
			_toggle_car()
		if frames > 30 and frames < 60:
			my_car.throttle = 1.0
			my_car.linear_velocity = my_car.global_transform.basis.z * 14.0
		if frames == 60:
			_toggle_car()
		if frames % 3 == 0 and frames > 55:
			print("JMP ", frames, " st=", vehanim.state, " veh=", player.vehicle != null, " door=", snappedf(my_car.door_open, 0.01), " down=", snappedf(combat.down_t, 0.1), " spd=", snappedf(my_car.linear_velocity.length(), 0.1))
	if v == "army":
		if frames == 4:
			wanted = 5
			god = true
		if frames % 15 == 0:
			var tk = police.army.filter(func(a): return is_instance_valid(a) and a.kind == "tank")
			var jt = police.army.filter(func(a): return is_instance_valid(a) and a.kind == "jet")
			print("ARM ", frames, " tanks=", tk.size(), " jets=", jt.size(), " units=", police.units.size(), " kinds=", police.units.map(func(u): return u.kind), " cops=", police.cops.size(), " heavy=", police.cops.filter(func(c): return is_instance_valid(c) and c.hp > 200).size(), " heli_spd=", police.heli.ai_speed if police.heli and is_instance_valid(police.heli) else -1, " td=", snappedf(tk[0].global_position.distance_to(player.global_position), 1) if tk.size() > 0 else -1)
		if frames == 200:
			var tk2 = police.army.filter(func(a): return is_instance_valid(a) and a.kind == "tank")
			if tk2.size() > 0:
				cam_yaw = atan2(tk2[0].global_position.x - player.global_position.x, tk2[0].global_position.z - player.global_position.z) + PI
	if v == "freedive":
		if frames == 4:
			player.global_position = Vector3(world2.SHORE_X + 60.0, 0.3, 30.0)
		if frames > 6 and frames < 30:
			hud.jump_held = true
		if frames == 30:
			hud.jump_held = false
		if frames > 60 and frames < 75:
			hud.rise_held = true
		if frames == 75:
			hud.rise_held = false
		if frames % 6 == 0:
			print("FDV ", frames, " y=", snappedf(player.global_position.y, 0.1), " uw=", player.underwater, " btn=", hud.buttons.has("rise"))
	if v == "steps":
		for spot in [Vector3(0, 0.3, 30), Vector3(200, 1.3, 0), Vector3(-300, 0.3, 120), world2.fish_spots[0][0], Vector3(world2.SHORE_X + 30, 0.3, 40)]:
			if frames == 4:
				player.global_position = spot
				print("SURF ", spot, " ", _surface())
	if v == "siren":
		if frames == 4:
			var pc = _spawn_car(my_car.global_position + Vector3(0, 0, 10), 0.0, Color.WHITE, true)
			set_meta("pc", pc)
			player.global_position = pc.door_world()
		if frames == 6:
			_toggle_car()
		if frames == 40:
			_toggle_siren()
		if frames % 10 == 0:
			print("SIR ", frames, " veh=", player.vehicle != null, " avail=", hud.siren_avail, " on=", hud.siren_on, " tgt=", snappedf(audio.sir_target, 0.01), " btn=", hud.buttons.has("siren"))
	if v == "coast2":
		if frames > 3:
			player.global_position = Vector3(-100.0, 0.5, 208.0)
			cam_yaw = PI + 0.4
			cam_pitch = 0.35
	if v == "aimcar":
		if frames == 4:
			combat.weapon = "pistol"
			combat._equip()
			hud.aim = true
			var a = traffic_sys.agents.filter(func(x): return x.car.kind == "sedan" or x.car.kind == "hatch")[0]
			set_meta("ac", a.car)
			traffic_sys.rng.seed = 2
		if frames > 4 and frames < 40:
			var c = get_meta("ac")
			player.global_position = c.global_position + c.global_transform.basis.z * 9.0 + Vector3(0, 0.3, 0)
			var to: Vector3 = c.global_position - player.global_position
			cam_yaw = atan2(to.x, to.z) + PI
			cam_pitch = -0.05
		if frames % 5 == 0:
			var c2 = get_meta("ac")
			var ag: Dictionary = traffic_sys._agent_of(c2)
			print("ACR ", frames, " mode=", ag.get("mode", "-"), " agent=", not ag.is_empty(), " handsup=", peds.filter(func(q): return is_instance_valid(q) and q.mode == "handsup").size(), " spd=", snappedf(c2.linear_velocity.length(), 0.1))
	if v == "soak":
		if frames == 4:
			god = false
		if frames > 10 and frames < 330 and frames % 6 == 0:
			var ang := frames * 0.7
			var at: Vector3 = player.global_position + Vector3(cos(ang), 0, sin(ang)) * rng.randf_range(8.0, 30.0)
			var tgt = null
			for c in cars:
				if is_instance_valid(c) and not c.get("dead") and c != player.vehicle and c.global_position.distance_to(player.global_position) < 70.0:
					tgt = c
					break
			if tgt and frames % 12 == 0:
				at = tgt.global_position
			explode_at(at + Vector3(0, 0.5, 0), 6.0, 160.0)
			hp = 100.0
			for i in 3:
				var pi = rng.randi() % city.props.size()
				city.break_prop(pi, Vector3(4, 0, 0))
		if frames == 340:
			combat.kill_now()
		if frames == 5 or frames == 425:
			var hist := {}
			for n in find_children("*", "", true, false):
				var k2: String = n.get_class() + ("@root" if n.get_parent() == self else "")
				hist[k2] = hist.get(k2, 0) + 1
			if frames == 5:
				set_meta("h5", hist)
			else:
				var h5: Dictionary = get_meta("h5")
				for k3 in hist:
					if hist[k3] != h5.get(k3, 0):
						print("HDIFF ", k3, " ", h5.get(k3, 0), " -> ", hist[k3])
				for k3 in h5:
					if not hist.has(k3):
						print("HDIFF ", k3, " ", h5[k3], " -> 0")
		if frames in [5, 100, 200, 330, 345, 400] or (frames > 345 and frames % 25 == 0):
			var rb := 0
			for n in get_tree().get_nodes_in_group("tmp"):
				if n is RigidBody3D:
					rb += 1
			var parts := 0
			for n in find_children("*", "CPUParticles3D", true, false):
				if n.emitting:
					parts += 1
			print("SOAK ", frames, " nodes=", get_tree().get_node_count(), " tmp=", get_tree().get_nodes_in_group("tmp").size(), " rigid=", rb, " emit=", parts, " cars=", cars.filter(func(c): return is_instance_valid(c)).size(), " wrecks=", cars.filter(func(c): return is_instance_valid(c) and c.get("dead")).size(), " peds=", peds.filter(func(q): return is_instance_valid(q) and not q.down).size(), " agents=", traffic_sys.agents.size(), " props_down=", city.props.filter(func(x): return not x.alive).size(), " dc=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), " dead=", combat.dead, " wanted=", wanted)
	if v == "dcprof":
		var groups := {"peds": peds, "cars": cars}
		if frames == 20:
			set_meta("dc0", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			for q in peds: q.visible = false
		if frames == 24:
			print("DCP base=", get_meta("dc0"), " no_peds=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			for c in cars: c.visible = false
		if frames == 28:
			print("DCP no_peds_cars=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			sun.shadow_enabled = false
		if frames == 32:
			print("DCP +no_shadow=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			sun.shadow_enabled = true
			for q in peds: q.visible = true
			for c in cars: c.visible = true
		if frames == 36:
			sun.shadow_enabled = false
		if frames == 40:
			print("DCP all_no_shadow=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			sun.shadow_enabled = true
			var cnt := {}
			for n in find_children("*", "MeshInstance3D", true, false):
				if not n.is_visible_in_tree():
					continue
				var o: Node = n
				var cat := "other"
				while o != null and o != self:
					if o is Car or o.get_script() == Arcade:
						cat = "car"
						break
					if o.get_script() == Ped:
						cat = "ped"
						break
					if o is Humanoid:
						cat = "human"
					o = o.get_parent()
				cnt[cat] = cnt.get(cat, 0) + 1
			print("DCP meshes ", cnt, " nodes=", get_tree().get_node_count())
		if frames >= 41 and frames <= 60 and frames % 5 == 0:
			print("PERF proc_ms=", snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01), " phys_ms=", snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01), " active_bodies=", Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS), " pairs=", Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS), " objs=", Performance.get_monitor(Performance.OBJECT_COUNT))
	if v == "sinkcar":
		if frames == 4:
			player.global_position = my_car.door_world()
		if frames == 6:
			_toggle_car()
		if frames == 40:
			my_car.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(world2.SHORE_X + 30.0, 2.0, 20.0))
			my_car.linear_velocity = Vector3.ZERO
		if frames % 10 == 0 and frames > 6:
			print("SNK ", frames, " y=", snappedf(my_car.global_position.y, 0.01), " veh=", player.vehicle != null, " hp=", snappedf(hp, 0.1), " br=", snappedf(breath, 0.01), " st=", vehanim.state, " sink=", my_car.has_meta("sink_t"))
		if frames == 130 and player.vehicle:
			_toggle_car()
		if frames > 130 and frames < 170:
			cam_pitch = 0.3
	if v == "reload":
		if frames == 6:
			combat.weapon = "pistol"
			combat.ammo["pistol"] = 30
			combat._equip()
		if frames > 8 and frames < 120:
			combat.shoot()
			if frames % 6 == 0:
				print("RLD ", frames, " ", combat.label(), " rt=", snappedf(combat.reload_t, 0.01))
	if v == "whale" or v == "squid":
		if frames == 4:
			var bt = null
			for c in cars:
				if is_instance_valid(c) and c.kind == "boat" and c.get("subkind") == "boat" and c.get("npc_drv") == null:
					bt = c
					break
			set_meta("bt", bt)
			bt.global_position = Vector3(world2.SHORE_X + (400.0 if v == "whale" else 950.0), world2.WATER_Y, 0.0)
			player.global_position = bt.global_position + Vector3(2, 0, 0)
		if frames == 6:
			_toggle_car()
		if frames == 40 and v == "whale":
			sea.whale_cd = 0.0
			sea._rng.seed = 1
			for i in 200:
				if sea.whale: break
				sea._whale_tick(1.0, player.global_position, world2)
		if frames % 10 == 0:
			print("SEA ", frames, " veh=", player.vehicle != null, " whale=", sea.whale != null, " squid=", snappedf(sea.squid_t, 0.01), " dead=", combat.dead, " bhp=", snappedf(get_meta("bt").hp, 1) if is_instance_valid(get_meta("bt")) else -1)
	if v == "hudnear":
		if frames == 4:
			player.global_position = my_car.door_world() + Vector3(1.5, 0, 0)
		if frames % 20 == 0:
			print("HUD ", frames, " can_enter=", hud.can_enter, " btns=", hud.buttons.keys())
	if v == "coast":
		if frames > 3:
			player.global_position = Vector3(-640.0, 1.0, 0.0)
			cam_yaw = -PI * 0.5
			cam_pitch = 0.5
	if v == "steal":
		if frames == 10:
			var a = traffic_sys.agents.filter(func(x): return x.car.kind == "sedan" or x.car.kind == "hatch")[0]
			var c = a.car
			traffic_sys.agents.erase(a)
			traffic_sys.agents.append(a)
			c.linear_velocity = Vector3.ZERO
			set_meta("sc", c)
			player.global_position = c.door_world() + c.global_transform.basis.x * 1.5
		if frames == 12:
			_toggle_car()
		if frames % 5 == 0 and frames > 10 and frames < 80:
			print("STL ", frames, " st=", vehanim.state, " veh=", player.vehicle != null, " door=", snappedf(get_meta("sc").door_open, 0.01), " peds=", peds.size(), " pose=", player.body.pose)
	if v == "force":
		if frames == 4:
			var c = _spawn_car(my_car.global_position + Vector3(0, 0, 16.0), 0.0, Color(0.3, 0.5, 0.2), false, "sedan")
			c.unlocked = false
			set_meta("fc", c)
		if frames == 8:
			player.global_position = get_meta("fc").door_world()
		if frames == 10:
			_toggle_car()
		if frames % 4 == 0 and frames > 8 and frames < 60:
			print("FRC ", frames, " st=", vehanim.state, " pose=", player.body.pose, " unlocked=", get_meta("fc").unlocked, " door=", snappedf(get_meta("fc").door_open, 0.01))
	if v == "tire":
		if frames == 10:
			var c = my_car
			var w = c.wheels[0]
			var from: Vector3 = w.global_position + Vector3(6, 1.2, 0)
			var vh: Dictionary = combat._vehicle_parts(from, (w.global_position - from).normalized(), 20.0)
			print("TIRE part=", vh.get("kind", "-"))
			if not vh.is_empty():
				combat._hit_vehicle_part(vh, 40.0)
			print("TIRE burst=", c.burst.size(), " slip=", w.wheel_friction_slip)
	if v == "crash2":
		if frames == 6:
			var base: Vector3 = Vector3(city._center(2), 0.7, city._center(2) - city.CELL * 0.5 + 2.6)
			var a = _spawn_car(base + Vector3(-25, 0, 0), PI * 0.5, Color(0.8, 0.1, 0.1), false, "sedan")
			var b = _spawn_car(base + Vector3(25, 0, 0), -PI * 0.5, Color(0.1, 0.3, 0.8), false, "sedan")
			a.linear_velocity = Vector3(16, 0, 0)
			b.linear_velocity = Vector3(-16, 0, 0)
			set_meta("ca", a)
			set_meta("cb", b)
			player.global_position = base + Vector3(-6, 0, 12)
			cam_yaw = 0.3
		if frames > 6 and frames < 60:
			get_meta("ca").throttle = 1.0
			get_meta("cb").throttle = 1.0
		if frames % 10 == 0 and frames > 6:
			var a2 = get_meta("ca")
			var b2 = get_meta("cb")
			print("CR2 ", frames, " A hp=", snappedf(a2.hp, 1), " eng=", snappedf(a2.engine_hp, 1), " v=", snappedf(a2.linear_velocity.length(), 0.1), " | B hp=", snappedf(b2.hp, 1), " eng=", snappedf(b2.engine_hp, 1), " lights_broken=", a2.lights_broken)
	if v == "dive":
		if frames == 4:
			player.global_position = Vector3(world2.SHORE_X + 120.0, 0.5, 30.0)
		if frames > 10 and frames < 200:
			hud.jump_held = true
		if frames % 20 == 0:
			print("DIV ", frames, " swim=", player.swimming, " y=", snappedf(player.global_position.y, 0.1), " uw=", player.underwater, " breath=", snappedf(breath, 1), " hp=", snappedf(hp, 1))
	if v == "sharkboat":
		if frames == 4:
			var bt = null
			for c in cars:
				if c.kind == "boat":
					bt = c
					break
			bt.global_position = Vector3(world2.SHORE_X + 330.0, 0.4, 40.0)
			player.global_position = bt.global_position + Vector3(0, 1.4, 0)
			set_meta("bt", bt)
		if frames == 6:
			vehanim.start_enter(get_meta("bt"))
		if frames % 20 == 0:
			var bt2 = get_meta("bt")
			print("SHK ", frames, " veh=", player.vehicle.kind if player.vehicle else "-", " boat_hp=", snappedf(bt2.hp, 1) if is_instance_valid(bt2) else -1, " shark=", shark != null, " dead=", combat.dead, " hp=", snappedf(hp, 1), " swim=", player.swimming)
	if v == "airjump":
		if frames == 4:
			var h = _near_kind("heli")
			h.global_position = Vector3(-205, 60, 70)
			player.global_position = h.global_position
			vehanim.start_enter(h)
		if frames == 40:
			_toggle_car()
		if frames % 10 == 0:
			print("AIR ", frames, " veh=", player.vehicle != null, " rag=", player.body.ragdolled, " down=", snappedf(combat.down_t, 0.1), " hp=", snappedf(hp, 1), " y=", snappedf((player.body.parts[0].global_position.y if player.body.ragdolled else player.global_position.y), 0.1), " dead=", combat.dead)
	if v == "carry":
		if frames == 4:
			player.global_position = my_car.trunk_world() + Vector3(0, 0, -2.0)
			shot_ped = Ped.new()
			add_child(shot_ped)
			var pp: Vector3 = player.global_position + Vector3(1.0, 0, 0)
			shot_ped.setup([pp, pp, pp, pp], 0, rng)
			peds.append(shot_ped)
		if frames == 6:
			shot_ped.hit(null, Vector3(0, 1, 0), false)
		if frames == 40:
			print("CAR action=", shop_action)
			_shop_action()
		if frames == 42:
			player.global_position = my_car.trunk_world()
		if frames == 46:
			print("CAR action2=", shop_action, " carrying=", combat.carrying != null)
			_shop_action()
		if frames == 70:
			print("CAR cargo=", my_car.cargo, " carrying=", combat.carrying != null, " trunk=", snappedf(my_car.trunk_open, 0.01))
	if v == "arrest1":
		if frames == 4:
			combat.owned = {"fist": true}
			combat.weapon = "fist"
			combat._equip()
			_add_wanted(1)
		if frames % 20 == 0:
			for cp in police.cops:
				if is_instance_valid(cp):
					print("   cop d=", snappedf(cp.global_position.distance_to(player.global_position), 0.1), " arrest=", cp.arrest_only, " anim=", cp.anim, " target=", cp.target != null, " pose=", cp.body.pose, " v=", snappedf(cp.velocity.length(), 0.1))
			print("ARR ", frames, " stars=", wanted, " cops=", police.cops.size(), " arresting=", police.arresting, " busted_t=", snappedf(combat.busted_t, 0.1), " down=", snappedf(combat.down_t, 0.1), " wasted=", hud.wasted, " pos=", player.global_position.snapped(Vector3.ONE))
	if v == "cover":
		if frames == 4:
			_add_wanted(3)
			combat.weapon = "pistol"
			god = true
		if frames % 30 == 0:
			var cv := 0
			var crouch := 0
			for cp in police.cops:
				if is_instance_valid(cp) and cp.cover_pos != Vector3.INF: cv += 1
				if is_instance_valid(cp) and cp.body.pose == "cover": crouch += 1
			print("COV ", frames, " cops=", police.cops.size(), " with_cover=", cv, " crouched=", crouch)
		if frames == 200:
			for cp in police.cops:
				if is_instance_valid(cp) and not cp.down:
					cp.damage(500.0, Vector3.FORWARD, false)
					break
		if frames > 200 and frames % 10 == 0:
			var rs := 0
			for cp in police.cops:
				if is_instance_valid(cp) and cp.rescue_rb != null: rs += 1
			print("RSC ", frames, " rescuing=", rs)
	if v == "store" and frames == 4:
		var sh: Dictionary = city.shops[0]
		player.global_position = sh.pos + Vector3(-4, 0, -7)
		cam_yaw = PI + 0.3
		cam_pitch = -0.08
	if v == "store2" and frames == 4:
		var sh2: Dictionary = city.shops[1]
		player.global_position = sh2.pos + Vector3(3, 0, -6)
		cam_yaw = PI - 0.4
		cam_pitch = -0.05
	if v in ["parkour", "parkour2"]:
		if frames == 4:
			var base := Vector3(city._center(2), 0.15, city._center(2) - city.BLOCK * 0.5 + 2.0)
			var hh := 1.0 if v == "parkour" else 2.2
			var sb := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			bx.size = Vector3(4.0, hh, 0.5 if v == "parkour" else 3.0)
			cs.shape = bx
			sb.add_child(cs)
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = bx.size
			mi.mesh = bm
			sb.add_child(mi)
			add_child(sb)
			sb.global_position = base + Vector3(-12.0, hh * 0.5, 0)
			player.global_position = base + Vector3(-20.0, 0.1, 0)
			cam_yaw = -PI * 0.5
		if frames > 6 and frames < 80:
			hud.joy = Vector2(0, -1)
			hud.sprint = true
		if frames % 4 == 0 and frames < 90:
			print("PKR ", frames, " kind=", player.pk_kind, " t=", snappedf(player.pk_t, 0.01), " pos=", player.global_position.snapped(Vector3.ONE * 0.1))
	if v == "walkanim":
		if frames == 4:
			cam_yaw = PI * 0.5
			cam_pitch = -0.1
		if frames > 6:
			hud.joy = Vector2(-1, 0)
			hud.sprint = frames > 30
	if v == "beachpeds" and frames == 4:
		player.global_position = Vector3(world2.BEACH_X0 + 32.0, 1.3, -195.0)
		cam_yaw = PI * 0.5 + 0.4

func _near_kind(k: String):
	var best = null
	for c in cars:
		if is_instance_valid(c) and c.kind == k and (best == null or c.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position)):
			best = c
	return best

## cenas de teste do lote 7
func _test_views() -> void:
	var v := shot_view
	_test9(v)
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


## caminho pelas ruas da grade (para o rastro do minimapa): perna até a rua mais próxima,
## segue pelas ruas (no máximo 2 curvas) e sai na rua mais próxima do destino
func route_path(a: Vector3, b: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var ext: float = city.N * city.CELL * 0.5
	var roads: Array = hud.map_roads
	var near_r := func(v: float) -> float:
		var best: float = roads[0]
		for r in roads:
			if absf(r - v) < absf(best - v):
				best = r
		return best
	var ca := Vector3(clampf(a.x, -ext, ext), 0, clampf(a.z, -ext, ext))
	var cb := Vector3(clampf(b.x, -ext, ext), 0, clampf(b.z, -ext, ext))
	out.append(a)
	if ca.distance_to(a) > 1.0:
		out.append(ca)
	var rxa: float = near_r.call(ca.x)
	var rza: float = near_r.call(ca.z)
	var rxb: float = near_r.call(cb.x)
	var rzb: float = near_r.call(cb.z)
	var va := absf(ca.x - rxa) < absf(ca.z - rza)     # a está numa rua vertical (x fixo)
	var vb := absf(cb.x - rxb) < absf(cb.z - rzb)
	if va and vb:
		var rzm: float = near_r.call((ca.z + cb.z) * 0.5)
		out.append_array([Vector3(rxa, 0, ca.z), Vector3(rxa, 0, rzm), Vector3(rxb, 0, rzm), Vector3(rxb, 0, cb.z)])
	elif va and not vb:
		out.append_array([Vector3(rxa, 0, ca.z), Vector3(rxa, 0, rzb), Vector3(cb.x, 0, rzb)])
	elif not va and vb:
		out.append_array([Vector3(ca.x, 0, rza), Vector3(rxb, 0, rza), Vector3(rxb, 0, cb.z)])
	else:
		var rxm: float = near_r.call((ca.x + cb.x) * 0.5)
		out.append_array([Vector3(ca.x, 0, rza), Vector3(rxm, 0, rza), Vector3(rxm, 0, rzb), Vector3(cb.x, 0, rzb)])
	out.append(cb)
	if cb.distance_to(b) > 1.0:
		out.append(b)
	return out

func _toggle_siren() -> void:
	var pv = player.vehicle
	if pv and pv.get("police") == true:
		pv.siren_on = not pv.siren_on
		audio.play("click", null, -4.0)

## piso sob o jogador (som dos passos)
func _surface() -> String:
	var p: Vector3 = player.global_position
	if interior != "":
		return "road"
	if world2.is_water(p.x, p.z):
		return "water" if p.y < world2.WATER_Y - 0.1 else "wood"
	if p.y < world2.WATER_Y - 0.25 and world2.sea_dist(p.x, p.z) > -10.0:
		return "water"
	if p.x > world2.BEACH_X0:
		return "sand"
	var ext: float = city.N * city.CELL * 0.5 + 4.0
	if absf(p.x) < ext and absf(p.z) < ext:
		return "road"
	if p.x < -150.0 and absf(p.z) < 14.0:
		return "road"       # pista do aeroporto
	if world2.sea_dist(p.x, p.z) > -26.0:
		return "road"       # costão de pedra
	return "grass"

# ---------------------------------------------------------------- população do mundo (recriada ao morrer)
var _pop_agents := 0
var _pop_peds := 26
var _upkeep_t := 0.0

## carros estacionados, trânsito, ônibus, barcos, aviões, helicóptero, viaturas da delegacia e pedestres
func _spawn_population() -> void:
	rng.seed = 7
	# carro do jogador estacionado ao lado
	var road_x: float = city._center(2) - city.CELL * 0.5
	my_car = _spawn_car(Vector3(road_x + 5.9, 0.6, city._center(2) + 4.0), 0.0, Color(0.06, 0.2, 0.55), false, "sport")
	var palette := [Color(0.55, 0.02, 0.03), Color(0.85, 0.85, 0.86), Color(0.05, 0.05, 0.06), Color(0.75, 0.45, 0.05), Color(0.2, 0.22, 0.25)]
	for k in 5:
		var rx: float = city._center(rng.randi_range(0, 4)) + city.CELL * 0.5 * (1 if rng.randf() < 0.5 else -1)
		_spawn_car(Vector3(rx + 5.9, 0.6, rng.randf_range(-120, 120)), 0.0 if rng.randf() < 0.5 else PI, palette[k % palette.size()])
	my_car.unlocked = true
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
	_spawn_vehicles2()

func _spawn_vehicles2() -> void:
	var road_x: float = city._center(2) - city.CELL * 0.5
	_spawn_car(Vector3(road_x + 5.9, 0.7, city._center(2) + 14.0), 0.0, Color.YELLOW, false, "taxi")
	_spawn_car(Vector3(city._center(1) - city.CELL * 0.5 - 5.9, 0.7, city._center(3)), PI, Color.YELLOW, false, "taxi")
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
	# jet-ski no píer e embarcações com piloto dando a volta na ilha (dá para roubar)
	var js = world2.boat_spots[0]
	_spawn_arcade("jetski", js[0] + Vector3(0, 0, -11.0), js[1], Color(0.9, 0.85, 0.1))
	var specs := [["boat", 70.0, Color(0.8, 0.8, 0.82)], ["boat", 140.0, Color(0.1, 0.3, 0.6)], ["boat", 95.0, Color(0.7, 0.15, 0.1)], ["jetski", 45.0, Color(0.1, 0.7, 0.3)], ["jetski", 55.0, Color(0.9, 0.3, 0.6)], ["ship", 320.0, Color.WHITE]]
	for i in specs.size():
		var off: float = specs[i][1]
		var x0: float = world2.PEN_X0 - off
		var x1: float = world2.SHORE_X + off
		var z0: float = world2.ISL_Z0 - off
		var z1: float = world2.ISL_Z1 + off
		var path := [Vector3(x1, 0, z1), Vector3(x1, 0, z0), Vector3(x0, 0, z0), Vector3(x0, 0, z1)]
		if i % 2 == 1:
			path.reverse()
		var start: Vector3 = path[i % 4].lerp(path[(i + 1) % 4], 0.3 + 0.1 * i)
		var b = _spawn_arcade(specs[i][0], start + Vector3(0, 0.4, 0), 0.0, specs[i][2])
		b.ai_path = path
		b.ai_i = (i + 1) % 4
		var dh := Humanoid.new()
		dh.build(Color(0.9, 0.9, 0.88), Color(0.15, 0.2, 0.35), Color(0.78, 0.56, 0.38), Color(0.08, 0.06, 0.05))
		dh.sitting = true
		dh.scale = Vector3.ONE * 0.85
		dh.position = Vector3(b.seat.x, b.seat.y + 0.07 - 0.98 * 0.85, b.seat.z)
		b.model_root.add_child(dh)
		dh.animate(0, 0)
		dh.set_far(70.0)
		b.npc_drv = dh
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

	_pop_agents = traffic_sys.agents.size()
	for i in owned_cars.size():
		var oc: Dictionary = owned_cars[i]
		_place_owned(oc.get("kind", "sedan"), Color.html(oc.get("color", "#2244aa")), i)

## reinicia o mundo do zero (morte ou prisão): todos os veículos, carcaças, pedestres, corpos,
## destroços, sangue, marcas, postes/árvores derrubados, polícia, exército e missão em andamento
func reset_world() -> void:
	vehanim.cancel()
	combat.release_hostage()
	combat._surrender.clear()
	if missions.active != "":
		if missions.active == "taxi":
			missions._taxi_end()
		else:
			missions._cleanup()
	police.clear()
	for c in cars:
		if is_instance_valid(c):
			c.queue_free()
	cars.clear()
	traffic_sys.agents.clear()
	traffic_sys.drifting.clear()
	for q in peds:
		if is_instance_valid(q):
			q.queue_free()
	peds.clear()
	for n in get_tree().get_nodes_in_group("tmp"):
		n.queue_free()
	combat.cash.clear()
	combat.rockets.clear()
	combat.grenades.clear()
	combat.carrying = null
	city.restore_props()
	sea.reset()
	if shark and is_instance_valid(shark):
		shark.queue_free()
	shark = null
	police_car = null
	act_target = null
	wanted = 0
	breath = 100.0
	_spawn_population()

## manutenção (a cada 2 s): tira referências mortas, apaga o fogo e depois a carcaça dos veículos
## destruídos (longe e fora da tela) e repõe trânsito e pedestres que sumiram, sempre fora da vista
func _upkeep(dt: float) -> void:
	_upkeep_t -= dt
	if _upkeep_t > 0.0:
		return
	_upkeep_t = 2.0
	cars = cars.filter(func(c): return is_instance_valid(c))
	peds = peds.filter(func(q): return is_instance_valid(q))
	var pp: Vector3 = player.global_position
	for c in cars.duplicate():
		if not c.get("dead") or c == player.vehicle:
			continue
		var wt: float = c.get_meta("wreck_t", 0.0) + 2.0
		c.set_meta("wreck_t", wt)
		if wt > 20.0:
			for e in c.find_children("*", "CPUParticles3D", true, false):
				e.emitting = false
		if wt > 45.0 and c.global_position.distance_to(pp) > 60.0 and not _seen(c.global_position):
			cars.erase(c)
			c.queue_free()
	# corpos no chão: no máximo 10 (o mais antigo some antes dos 40 s normais)
	var dead_peds := peds.filter(func(q): return q.down)
	if dead_peds.size() > 10:
		dead_peds.sort_custom(func(a, b): return a._t > b._t)
		for q in dead_peds.slice(0, dead_peds.size() - 10):
			q._t = 39.9
	if interior != "" or combat.dead:
		return
	# trânsito: repõe carros que foram destruídos/roubados
	if traffic_sys.agents.size() < _pop_agents:
		var kinds := ["sedan", "hatch", "suv", "pickup", "taxi", "sport", "moto"]
		var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		for t in 12:
			var n := Vector2i(rng.randi_range(0, city.N), rng.randi_range(0, city.N))
			var d: Vector2i = dirs[rng.randi() % 4]
			if not traffic_sys._valid(n - d):
				continue
			var mid: Vector3 = traffic_sys.node_pos(n - d).lerp(traffic_sys.node_pos(n), 0.5)
			if mid.distance_to(pp) < 90.0 or (mid.distance_to(pp) < 160.0 and _seen(mid)):
				continue
			var c = _spawn_car(Vector3(0, 0.7, 0), 0.0, Color.from_hsv(rng.randf(), rng.randf_range(0.2, 0.8), rng.randf_range(0.15, 0.85)), false, kinds[rng.randi() % kinds.size()])
			traffic_sys.add_agent(c, n, d)
			break
	# pedestres da cidade
	var alive := 0
	for q in peds:
		if not q.down and not q.beach:
			alive += 1
	if alive < _pop_peds:
		for t in 8:
			var loopw: Array = city.walk_loops[rng.randi() % city.walk_loops.size()]
			var k := rng.randi_range(0, 3)
			var pos: Vector3 = loopw[k]
			if pos.distance_to(pp) < 55.0 or (pos.distance_to(pp) < 120.0 and _seen(pos)):
				continue
			var q := Ped.new()
			add_child(q)
			q.setup(loopw, k, rng)
			q.died.connect(_on_ped_died)
			peds.append(q)
			break

func _seen(p: Vector3) -> bool:
	return not cam.is_position_behind(p) and cam.global_position.distance_to(p) < 160.0

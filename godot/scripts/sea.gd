extends Node3D
## Vida no mar:
## - peixes pequenos (cardumes) perto da costa: não atacam, fogem quando você chega perto;
## - baleia em mar aberto (>320 m da ilha): bate no barco e afunda;
## - lula gigante muito longe (>900 m, de barco): cena cinematográfica, destrói o barco e mata.
## (o tubarão fica no main: ataca quem nada / barcos a >280 m)

const CM := preload("res://scripts/carmodel.gd")
const FX := preload("res://scripts/fx.gd")

var main: Node3D
var fish_mm: MultiMeshInstance3D
var fish: Array = []          # {p: Vector3, v: Vector3, t}
var whale: Node3D
var whale_t := 0.0
var whale_cd := 0.0
var squid: Node3D
var squid_t := -1.0
var tentacles: Array = []
var _rng := RandomNumberGenerator.new()

func setup(m: Node3D) -> void:
	main = m
	_rng.seed = 909
	# peixes: 1 MultiMesh (1 draw call)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	CM._ell(st, Vector3.ZERO, Vector3(0.12, 0.16, 0.42), Color(0.75, 0.62, 0.25))
	CM._box(st, Vector3(0.02, 0.18, 0.12), Vector3(0, 0, -0.24), Color(0.7, 0.5, 0.2))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = st.commit()
	mm.instance_count = 60
	fish_mm = MultiMeshInstance3D.new()
	fish_mm.multimesh = mm
	var mat := CM.vc_mat().duplicate()
	mat.vertex_color_use_as_albedo = true
	fish_mm.material_override = mat
	fish_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fish_mm)
	for i in 60:
		fish.append({"p": Vector3(0, -100, 0), "v": Vector3.ZERO, "t": 0.0, "c": Color.from_hsv(_rng.randf_range(0.05, 0.6), 0.6, 0.9)})
		mm.set_instance_color(i, fish[i].c)

func _physics_process(dt: float) -> void:
	if main == null or main.player == null:
		return
	var pp: Vector3 = main.player.global_position
	var w2 = main.world2
	var near_sea: bool = w2.sea_dist(pp.x, pp.z) > -40.0
	fish_mm.visible = near_sea
	if near_sea:
		_fish_tick(dt, pp, w2)
	_whale_tick(dt, pp, w2)
	_squid_tick(dt, pp, w2)

func _fish_tick(dt: float, pp: Vector3, w2) -> void:
	var mm := fish_mm.multimesh
	for i in fish.size():
		var f: Dictionary = fish[i]
		var p: Vector3 = f.p
		# reposiciona perto do jogador, só na água rasa (até 120 m da costa)
		if p.distance_to(pp) > 70.0:
			var school := i / 8
			var ang := _rng.randf() * TAU
			var rr := _rng.randf_range(12.0, 55.0)
			var c := pp + Vector3(cos(ang + school), 0, sin(ang + school)) * rr
			var sd: float = w2.sea_dist(c.x, c.z)
			if sd < 6.0 or sd > 120.0:
				mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3(0, -50, 0)))
				continue
			p = c + Vector3(_rng.randf_range(-2, 2), _rng.randf_range(-5.0, -0.8), _rng.randf_range(-2, 2))
			f.v = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * 1.2
		var to := p - pp
		var d := to.length()
		var want: Vector3 = f.v
		if d < 6.0:
			want = to.normalized() * 6.5          # foge
			want.y = clampf(want.y, -2.0, 1.0)
		else:
			f.t += dt
			if f.t > 2.0:
				f.t = 0.0
				want = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.2, 0.2), _rng.randf_range(-1, 1)).normalized() * 1.3
		f.v = f.v.lerp(want, minf(1.0, dt * 3.0))
		p += f.v * dt
		p.y = clampf(p.y, main.world2.SEA_FLOOR + 0.5, main.world2.WATER_Y - 0.5)
		f.p = p
		var dir: Vector3 = f.v.normalized() if f.v.length() > 0.05 else Vector3.FORWARD
		var b := Basis.looking_at(-dir, Vector3.UP) if absf(dir.y) < 0.95 else Basis()
		mm.set_instance_transform(i, Transform3D(b, p))

# ---------------------------------------------------------------- baleia
func _whale_tick(dt: float, pp: Vector3, w2) -> void:
	var veh = main.player.vehicle
	var boat = veh if veh and veh.kind == "boat" else null
	var sd: float = w2.sea_dist(pp.x, pp.z)
	whale_cd -= dt
	if whale == null:
		if boat and sd > 320.0 and sd < 880.0 and whale_cd <= 0.0 and _rng.randf() < dt * 0.08:
			whale = _make_whale()
			var a := _rng.randf() * TAU
			whale.global_position = pp + Vector3(cos(a), 0, sin(a)) * 60.0 + Vector3(0, -6, 0)
			whale_t = 0.0
			main.audio.play("whale", whale.global_position, 6.0)
			main._msg("Uma baleia está vindo!")
		return
	whale_t += dt
	var tgt: Vector3 = boat.global_position if boat else whale.global_position + whale.global_transform.basis.z * 10.0
	var to := tgt - whale.global_position
	to.y = 0
	var dir := to.normalized() if to.length() > 0.1 else Vector3.FORWARD
	whale.rotation.y = lerp_angle(whale.rotation.y, atan2(dir.x, dir.z), dt * 0.8)
	var spd := 9.0 if boat else 4.0
	whale.global_position += whale.global_transform.basis.z * spd * dt
	# sobe para o ataque, depois mergulha
	var y_goal := -0.8 if to.length() < 25.0 else -4.0
	whale.global_position.y = lerpf(whale.global_position.y, y_goal, dt * 1.2)
	if boat and to.length() < 7.0:
		boat.take_damage(45.0)
		boat.model_root.rotation.z += 0.6
		FX.splash(main, boat.global_position + Vector3(0, 1, 0), 2.5)
		main.audio.play("crash", boat.global_position, 6.0)
		main.hud.flash = 0.3
		whale_cd = 25.0
		whale.queue_free()
		whale = null
		return
	if whale_t > 40.0 or not boat:
		whale.queue_free()
		whale = null
		whale_cd = 20.0

func _make_whale() -> Node3D:
	var n := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grey := Color(0.22, 0.26, 0.32)
	CM._ell(st, Vector3(0, 0, 0), Vector3(4.2, 3.6, 16.0), grey)
	CM._ell(st, Vector3(0, -0.6, 1.0), Vector3(3.6, 2.4, 13.0), Color(0.75, 0.75, 0.72))
	CM._ell(st, Vector3(0, 0.2, -8.5), Vector3(1.4, 0.9, 4.0), grey)
	CM._box(st, Vector3(6.0, 0.3, 1.8), Vector3(0, 0.3, -10.6), grey)
	CM._box(st, Vector3(3.0, 0.25, 1.2), Vector3(2.4, -1.0, 2.5), grey)
	CM._box(st, Vector3(3.0, 0.25, 1.2), Vector3(-2.4, -1.0, 2.5), grey)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = CM.vc_mat()
	n.add_child(mi)
	main.add_child(n)
	return n

# ---------------------------------------------------------------- lula gigante (cena cinematográfica)
func _squid_tick(dt: float, pp: Vector3, w2) -> void:
	var veh = main.player.vehicle
	var boat = veh if veh and veh.kind == "boat" else null
	if squid_t < 0.0:
		if boat and w2.sea_dist(pp.x, pp.z) > 900.0 and not main.combat.dead:
			_squid_start(boat)
		return
	squid_t += dt
	var bp: Vector3 = squid.global_position
	# tentáculos sobem em volta do barco, se curvam por cima e esmagam
	for i in tentacles.size():
		var t: Node3D = tentacles[i]
		var a: float = i * TAU / tentacles.size()
		var rise := clampf(squid_t / 1.6, 0.0, 1.0)
		var curl := clampf((squid_t - 1.4) / 1.4, 0.0, 1.0)
		t.position = Vector3(cos(a) * 6.5, lerpf(-14.0, -1.0, rise), sin(a) * 6.5)
		t.rotation = Vector3(0, -a + PI * 0.5, 0)
		for j in t.get_child_count():
			var seg: Node3D = t.get_child(j)
			seg.rotation.z = curl * 0.32 + sin(squid_t * 3.0 + j + i) * 0.08
	main.cam.global_position = bp + Vector3(cos(squid_t * 0.4) * 22.0, 9.0, sin(squid_t * 0.4) * 22.0)
	main.cam.look_at(bp + Vector3(0, 2, 0), Vector3.UP)
	main.cine_cam = true
	if squid_t > 2.8 and squid_t - dt <= 2.8:
		main.audio.play("squid", bp, 8.0)
		if is_instance_valid(main.player.vehicle):
			var b = main.player.vehicle
			b.take_damage(9999.0)
			FX.splash(main, bp + Vector3(0, 1, 0), 3.0)
		main.combat.kill_now()
	if squid_t > 5.0:
		squid.queue_free()
		squid = null
		tentacles.clear()
		squid_t = -1.0
		main.cine_cam = false
		main.ui.letterbox(false)

func _squid_start(boat) -> void:
	squid_t = 0.0
	squid = Node3D.new()
	main.add_child(squid)
	squid.global_position = Vector3(boat.global_position.x, main.world2.WATER_Y - 1.0, boat.global_position.z)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.18, 0.22)
	mat.roughness = 0.4
	for i in 8:
		var t := Node3D.new()
		squid.add_child(t)
		var prev: Node3D = t
		for j in 9:
			var seg := Node3D.new()
			seg.position = Vector3(0, 1.6 if j > 0 else 0.0, 0)
			prev.add_child(seg)
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.6 - j * 0.06
			cm.bottom_radius = 0.7 - j * 0.06
			cm.height = 1.7
			cm.radial_segments = 8
			mi.mesh = cm
			mi.position = Vector3(0, 0.8, 0)
			mi.material_override = mat
			seg.add_child(mi)
			prev = seg
		tentacles.append(t)
	main.ui.letterbox(true, "???")
	main.audio.play("whale", squid.global_position, 8.0)

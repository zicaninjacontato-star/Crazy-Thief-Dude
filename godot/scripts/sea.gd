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

## reinício do mundo: tira a baleia (a cena do tubarão gigante termina sozinha)
func reset() -> void:
	if whale and is_instance_valid(whale):
		whale.queue_free()
	whale = null
	whale_cd = 20.0

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

# ---------------------------------------------------------------- tubarão gigante (cena cinematográfica)
## Longe demais da ilha (>900 m) de barco: o motor morre, a água começa a tremer e um tubarão
## gigantesco sobe por baixo com a boca aberta e engole o veículo com o jogador.
var _gs_veh = null
var _jaw_up: Node3D
var _jaw_lo: Node3D
var _ripples: Array = []

func _squid_tick(dt: float, pp: Vector3, w2) -> void:
	var veh = main.player.vehicle
	if squid_t < 0.0:
		if veh and not main.combat.dead and w2.sea_dist(pp.x, pp.z) > 900.0 and (veh.kind == "boat" or (veh.kind in ["plane", "heli"] and veh.global_position.y < 25.0)):
			_squid_start(veh)
		return
	squid_t += dt
	var c: Vector3 = squid.global_position
	var v = _gs_veh
	# 0–2,6 s: motor morre e o veículo para; a água treme
	if is_instance_valid(v):
		v.throttle = 0.0
		v.engine_on = false
		if squid_t < 3.9:
			v.velocity = v.velocity.lerp(Vector3.ZERO, minf(1.0, dt * 2.5))
			if v.kind in ["plane", "heli"]:
				v.velocity.y = -3.0
		v.model_root.rotation.z = sin(squid_t * 11.0) * 0.05 * clampf(squid_t / 2.0, 0.0, 1.0)
	var shake := clampf(squid_t / 2.4, 0.0, 1.0) * (1.0 if squid_t < 4.2 else 0.3)
	for i in _ripples.size():
		var r: MeshInstance3D = _ripples[i]
		var k := fmod(squid_t * 0.8 + i * 0.25, 1.0)
		r.scale = Vector3.ONE * (2.0 + k * 22.0)
		r.transparency = k
		r.visible = squid_t > 0.6
	if squid_t > 1.0 and fmod(squid_t, 0.35) < dt:
		FX.splash(main, c + Vector3(_rng.randf_range(-10, 10), main.world2.WATER_Y + 0.2, _rng.randf_range(-10, 10)), 0.8)
	# 2,6–4 s: sobe por baixo, boca escancarada; 4 s: fecha e afunda
	var rise := clampf((squid_t - 2.6) / 1.1, 0.0, 1.0)
	var e := rise * rise * (3.0 - 2.0 * rise)
	var bite := clampf((squid_t - 3.75) / 0.25, 0.0, 1.0)
	var sink := clampf((squid_t - 4.6) / 1.4, 0.0, 1.0)
	var shark: Node3D = squid.get_child(0)
	shark.position = Vector3(0, lerpf(-45.0, 2.5, e) - sink * 34.0, 0)
	_jaw_up.rotation.x = lerpf(0.6, 0.02, bite)
	_jaw_lo.rotation.x = lerpf(-0.6, -0.02, bite)
	if squid_t > 3.95 and squid_t - dt <= 3.95:
		main.audio.play("squid", c, 8.0)
		FX.splash(main, c + Vector3(0, 1.5, 0), 4.0)
		main.hud.flash = 0.5
		if is_instance_valid(v):
			v.visible = false
			v.set_physics_process(false)
		main.combat.kill_now()
	if squid_t > 4.0:
		# o corpo vai junto para dentro da boca
		var body = main.player.body
		if body and body.ragdolled:
			for part in body.parts:
				if is_instance_valid(part) and part.visible:
					part.freeze = true
					part.visible = false
	# câmera: baixa, perto da água, olhando para o veículo; treme
	var ang := 0.6 + squid_t * 0.12
	var dist := 30.0 - e * 2.0
	var sh := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * shake * 0.35
	main.cam.global_position = c + Vector3(cos(ang) * dist, 3.0 + e * 2.5, sin(ang) * dist) + sh
	main.cam.look_at(c + Vector3(0, 1.0 + e * 6.0, 0), Vector3.UP)
	main.cine_cam = true
	if squid_t > 6.2:
		if is_instance_valid(v):
			v.queue_free()
		squid.queue_free()
		squid = null
		_ripples.clear()
		squid_t = -1.0
		main.cine_cam = false
		main.ui.letterbox(false)

func _squid_start(veh) -> void:
	squid_t = 0.0
	_gs_veh = veh
	squid = Node3D.new()
	main.add_child(squid)
	squid.global_position = Vector3(veh.global_position.x, main.world2.WATER_Y, veh.global_position.z)
	squid.add_child(_make_giant_shark())
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.85, 0.95, 1.0, 0.35)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in 4:
		var r := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.965
		tm.outer_radius = 1.0
		tm.rings = 24
		tm.ring_segments = 4
		r.mesh = tm
		r.material_override = rm
		r.position = Vector3(0, 0.08, 0)
		r.scale = Vector3(1, 0.05, 1)
		r.visible = false
		squid.add_child(r)
		_ripples.append(r)
	main.ui.letterbox(true, "")
	main.audio.play("whale", squid.global_position, 4.0)
	main._msg("O motor morreu...")

## tubarão colossal apontado para cima: corpo, nadadeiras e duas mandíbulas que abrem
func _make_giant_shark() -> Node3D:
	var root := Node3D.new()
	var grey := Color(0.32, 0.37, 0.42)
	var belly := Color(0.86, 0.86, 0.84)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	CM._ell(st, Vector3(0, -17.0, 0), Vector3(8.5, 19.0, 8.5), grey)
	CM._ell(st, Vector3(0, -15.0, -2.5), Vector3(6.5, 15.0, 6.6), belly)
	for s3 in [-1.0, 1.0]:
		CM._ell(st, Vector3(7.6 * s3, -0.5, 1.5), Vector3(0.6, 0.9, 0.9), Color(0.02, 0.02, 0.02))
	CM._box(st, Vector3(0.8, 9.0, 7.0), Vector3(0, -24.0, 7.5), grey)
	CM._box(st, Vector3(26.0, 5.0, 0.8), Vector3(0, -26.0, -1.0), grey)
	CM._box(st, Vector3(1.0, 12.0, 8.0), Vector3(0, -42.0, 0), grey)
	for g in 5:
		CM._box(st, Vector3(0.3, 3.0, 0.3), Vector3(7.8, -6.0 - g * 1.5, -1.0), Color(0.2, 0.22, 0.25))
		CM._box(st, Vector3(0.3, 3.0, 0.3), Vector3(-7.8, -6.0 - g * 1.5, -1.0), Color(0.2, 0.22, 0.25))
	var mat := CM.vc_mat()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	root.add_child(mi)
	# mandíbulas (pivô na base da boca): por dentro vermelho, fileiras de dentes
	for k in 2:
		var jaw := Node3D.new()
		jaw.position = Vector3(0, 0.0, 0)
		root.add_child(jaw)
		var sj := SurfaceTool.new()
		sj.begin(Mesh.PRIMITIVE_TRIANGLES)
		var sg := 1.0 if k == 0 else -1.0
		CM._ell(sj, Vector3(0, 4.0, sg * 2.2), Vector3(8.2, 7.0, 3.4), grey if k == 0 else belly)
		CM._ell(sj, Vector3(0, 4.0, sg * 0.6), Vector3(7.0, 6.0, 1.8), Color(0.5, 0.06, 0.09))
		for t in 16:
			var a := -PI * 0.5 + t * PI / 15.0
			var tp := Vector3(sin(a) * 6.6, 4.0 + cos(a) * 6.0, sg * 0.3)
			CM._box(sj, Vector3(0.55, 1.9, 0.5), tp - Vector3(sin(a), cos(a), 0) * 0.6, Color(0.96, 0.95, 0.9))
		var mj := MeshInstance3D.new()
		mj.mesh = sj.commit()
		mj.material_override = mat
		jaw.add_child(mj)
		if k == 0:
			_jaw_up = jaw
		else:
			_jaw_lo = jaw
	return root

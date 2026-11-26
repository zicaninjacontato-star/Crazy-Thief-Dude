extends Node
## Ciclo de dia e noite: sol/lua, cores do céu e da neblina, luz ambiente, janelas acesas,
## postes que acendem (pool de luzes reais perto do jogador) e faróis dos carros próximos.
## 1 dia do jogo = DAY_LEN segundos reais.

const M := preload("res://scripts/mats.gd")
const DAY_LEN := 1800.0     # 1 dia = 30 min (antes 12 min)

var main: Node3D
var sky: ProceduralSkyMaterial
var env: Environment
var sun: DirectionalLight3D
var lamp_lights: Array = []
var car_lights: Array = []
var _t := 0.0
var night := 0.0
var _lamp_cars: Array = []

func setup(m: Node3D) -> void:
	main = m
	process_mode = Node.PROCESS_MODE_ALWAYS
	env = m.world_env
	sky = env.sky.sky_material
	env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky.radiance_size = Sky.RADIANCE_SIZE_64
	sun = m.sun
	for i in 8:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.82, 0.55)
		l.omni_range = 16.0
		l.omni_attenuation = 1.2
		l.shadow_enabled = false
		l.visible = false
		m.add_child(l)
		lamp_lights.append(l)
	for i in 4:
		var s := SpotLight3D.new()
		s.light_color = Color(1.0, 0.95, 0.85)
		s.spot_range = 30.0
		s.spot_angle = 32.0
		s.spot_attenuation = 1.1
		s.light_energy = 0.0
		s.shadow_enabled = false
		s.visible = false
		m.add_child(s)
		car_lights.append({"l": s, "car": null})
	if main.shot != "" and main.shot_view != "warm":
		_warm = -1
	apply(0.0, true)

func _process(dt: float) -> void:
	if _warm >= 0:
		_warmup()
		return
	if get_tree().paused:
		return
	main.tod = fmod(main.tod + dt * 24.0 / DAY_LEN, 24.0)
	apply(dt)

## Aquecimento: no Godot 4.3 a 1ª vez que uma malha é desenhada com luz pontual/spot o shader
## é compilado na hora (engasgo forte ao anoitecer). Durante o menu inicial ligamos todas as luzes
## em volta do jogador por alguns quadros (combinações: omni+spot, só omni, só spot) para compilar antes.
var _warm := 0
func _warmup() -> void:
	_warm += 1
	var pp: Vector3 = main.player.global_position
	var phase := _warm / 6
	for i in lamp_lights.size():
		var l: OmniLight3D = lamp_lights[i]
		l.visible = phase != 2
		l.light_energy = 0.05
		l.global_position = pp + Vector3(cos(i * 0.8) * 9.0, 3.0, sin(i * 0.8) * 9.0)
	for i in car_lights.size():
		var s: SpotLight3D = car_lights[i].l
		s.visible = phase != 1
		s.light_energy = 0.05
		s.spot_range = 60.0
		s.global_transform = Transform3D(Basis(Vector3.UP, i * PI * 0.5) * Basis(Vector3.RIGHT, -0.6), pp + Vector3(0, 6.0, 0))
	if _warm > 18:
		_warm = -1
		for l in lamp_lights:
			l.visible = false
		for cl in car_lights:
			cl.l.visible = false
			cl.l.spot_range = 30.0
		apply(0.0, true)

## e = altura do sol (-1..1); day = 0 de noite, 1 de dia
## O céu (ProceduralSky) é re-renderizado pelo Godot sempre que suas cores ou a direção do sol mudam;
## por isso céu, ambiente e direção do sol mudam em degraus pequenos (não a cada quadro).
var _sky_key := ""
var _night_q := -1.0
func apply(dt: float, force := false) -> void:
	var tod: float = main.tod
	var e := sin((tod - 6.0) / 12.0 * PI)
	var day := smoothstep(-0.12, 0.25, e)
	night = 1.0 - day
	var dusk := clampf(1.0 - absf(e) / 0.32, 0.0, 1.0)
	var key := "%d_%d_%d" % [roundi(day * 30.0), roundi(dusk * 15.0), roundi(tod * 2.0)]
	if key != _sky_key or force:
		_sky_key = key
		var tq := roundf(tod * 2.0) / 2.0
		var eq := sin((tq - 6.0) / 12.0 * PI)
		var yaw := 35.0 + (tq - 12.0) * 12.0
		if e > -0.06:
			sun.rotation_degrees = Vector3(-maxf(asin(clampf(eq, 0.0, 1.0)) * 57.3 * 0.95, 5.0), yaw, 0)
			sun.light_color = Color(1.0, 0.95, 0.86).lerp(Color(1.0, 0.62, 0.38), dusk)
			sun.light_energy = lerpf(0.3, 1.55, day) * lerpf(1.0, 0.75, dusk * day)
		else:
			sun.rotation_degrees = Vector3(-42.0, yaw + 180.0, 0)
			sun.light_color = Color(0.7, 0.78, 1.0)
			sun.light_energy = 0.3
		var top_d := Color(0.2, 0.42, 0.78)
		var hor_d := Color(0.7, 0.78, 0.86)
		var top_n := Color(0.03, 0.05, 0.12)
		var hor_n := Color(0.13, 0.17, 0.27)
		sky.sky_top_color = top_n.lerp(top_d, day)
		sky.sky_horizon_color = hor_n.lerp(hor_d, day).lerp(Color(0.95, 0.55, 0.32), dusk * 0.75)
		sky.ground_horizon_color = Color(0.1, 0.12, 0.16).lerp(Color(0.6, 0.64, 0.68), day)
		sky.ground_bottom_color = Color(0.04, 0.04, 0.05).lerp(Color(0.18, 0.17, 0.16), day)
		sky.sun_angle_max = 25.0 if e > 0 else 8.0
		env.ambient_light_energy = lerpf(0.55, 0.8, day)
		env.ambient_light_color = Color(0.34, 0.39, 0.52).lerp(Color(0.56, 0.56, 0.58), day)
		env.fog_light_color = Color(0.09, 0.11, 0.18).lerp(Color(0.68, 0.75, 0.84), day).lerp(Color(0.85, 0.6, 0.45), dusk * 0.5)
		env.tonemap_exposure = lerpf(1.3, 0.95, day)
	# janelas e postes: só mexe nos materiais quando a noite muda de verdade (cada mudança
	# de material reenvia os parâmetros para a GPU; fazer isso todo quadro custava caro)
	var nq := roundf(night * 60.0) / 60.0
	if nq != _night_q or force:
		_night_q = nq
		M.set_night(nq)
		if main.city.lamp_mat:
			main.city.lamp_mat.emission_energy_multiplier = lerpf(0.3, 5.0, nq)
	_t -= dt
	if _t <= 0.0 or force:
		_t = 0.4
		_assign()
	var lamp_e := 4.5 * smoothstep(0.3, 0.75, night)
	for l in lamp_lights:
		l.light_energy = lamp_e
	var head_e := 6.0 * smoothstep(0.3, 0.75, night)
	for cl in car_lights:
		var s: SpotLight3D = cl.l
		var c = cl.car
		if c == null or not is_instance_valid(c) or head_e <= 0.0:
			s.visible = false
			continue
		s.visible = true
		s.light_energy = head_e
		var front: float = c.body_size.z * 0.5 if "body_size" in c else 2.2
		var xf: Transform3D = c.global_transform
		s.global_transform = Transform3D(xf.basis * Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, -0.12), xf * Vector3(0, 0.75, front))

## liga as luzes reais só nos postes e carros mais próximos do jogador
func _assign() -> void:
	var lit := night > 0.25
	var q: int = main.quality if "quality" in main else 1
	var n_lamp: int = [3, 6, 8][q]
	var n_car: int = [1, 3, 4][q]
	var pp: Vector3 = main.player.global_position
	var lamps: Array = main.city._lamps.duplicate()
	lamps.sort_custom(func(a, b): return a.distance_squared_to(pp) < b.distance_squared_to(pp))
	for i in lamp_lights.size():
		var l: OmniLight3D = lamp_lights[i]
		l.visible = lit and i < n_lamp and i < lamps.size()
		if l.visible:
			l.global_position = lamps[i] + Vector3(0, 6.6, 0)
	var cars: Array = main.cars.filter(func(c): return is_instance_valid(c) and c.global_position.distance_to(pp) < 70.0)
	cars.sort_custom(func(a, b): return a.global_position.distance_squared_to(pp) < b.global_position.distance_squared_to(pp))
	if main.player.vehicle and main.player.vehicle in cars:
		cars.erase(main.player.vehicle)
		cars.push_front(main.player.vehicle)
	for i in car_lights.size():
		car_lights[i].car = cars[i] if (lit and i < n_car and i < cars.size()) else null

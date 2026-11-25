extends Node
## Ciclo de dia e noite: sol/lua, cores do céu e da neblina, luz ambiente, janelas acesas,
## postes que acendem (pool de luzes reais perto do jogador) e faróis dos carros próximos.
## 1 dia do jogo = DAY_LEN segundos reais.

const M := preload("res://scripts/mats.gd")
const DAY_LEN := 720.0

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
	env = m.world_env
	sky = env.sky.sky_material
	sun = m.sun
	for i in 8:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.82, 0.55)
		l.omni_range = 14.0
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
	apply(0.0)

func _process(dt: float) -> void:
	main.tod = fmod(main.tod + dt * 24.0 / DAY_LEN, 24.0)
	apply(dt)

## e = altura do sol (-1..1); day = 0 de noite, 1 de dia
func apply(dt: float, force := false) -> void:
	var tod: float = main.tod
	var e := sin((tod - 6.0) / 12.0 * PI)
	var day := smoothstep(-0.12, 0.25, e)
	night = 1.0 - day
	var dusk := clampf(1.0 - absf(e) / 0.32, 0.0, 1.0)
	# sol ou lua
	var yaw := 35.0 + (tod - 12.0) * 12.0
	if e > -0.06:
		sun.rotation_degrees = Vector3(-maxf(asin(clampf(e, 0.0, 1.0)) * 57.3 * 0.95, 5.0), yaw, 0)
		sun.light_color = Color(1.0, 0.95, 0.86).lerp(Color(1.0, 0.62, 0.38), dusk)
		sun.light_energy = lerpf(0.1, 1.55, day) * lerpf(1.0, 0.75, dusk * day)
	else:
		sun.rotation_degrees = Vector3(-42.0, yaw + 180.0, 0)
		sun.light_color = Color(0.66, 0.74, 1.0)
		sun.light_energy = 0.1
	# céu
	var top_d := Color(0.2, 0.42, 0.78)
	var hor_d := Color(0.7, 0.78, 0.86)
	var top_n := Color(0.012, 0.02, 0.05)
	var hor_n := Color(0.06, 0.08, 0.14)
	sky.sky_top_color = top_n.lerp(top_d, day)
	sky.sky_horizon_color = hor_n.lerp(hor_d, day).lerp(Color(0.95, 0.55, 0.32), dusk * 0.75)
	sky.ground_horizon_color = Color(0.05, 0.06, 0.08).lerp(Color(0.6, 0.64, 0.68), day)
	sky.ground_bottom_color = Color(0.02, 0.02, 0.03).lerp(Color(0.18, 0.17, 0.16), day)
	sky.sun_angle_max = 25.0 if e > 0 else 8.0
	env.ambient_light_energy = lerpf(0.2, 0.8, day)
	env.ambient_light_color = Color(0.22, 0.26, 0.36).lerp(Color(0.56, 0.56, 0.58), day)
	env.fog_light_color = Color(0.05, 0.065, 0.11).lerp(Color(0.68, 0.75, 0.84), day).lerp(Color(0.85, 0.6, 0.45), dusk * 0.5)
	env.tonemap_exposure = lerpf(1.05, 0.95, day)
	# janelas e postes
	M.set_night(night)
	if main.city.lamp_mat:
		main.city.lamp_mat.emission_energy_multiplier = lerpf(0.3, 5.0, night)
	_t -= dt
	if _t <= 0.0 or force:
		_t = 0.4
		_assign()
	var lamp_e := 3.2 * smoothstep(0.35, 0.8, night)
	for l in lamp_lights:
		l.light_energy = lamp_e
	var head_e := 6.0 * smoothstep(0.35, 0.8, night)
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
	var lit := night > 0.3
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

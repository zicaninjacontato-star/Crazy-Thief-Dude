extends RefCounted
## Materiais PBR procedurais: as texturas são geradas no carregamento (nenhum arquivo de imagem externo).
## Tudo usa mapeamento triplanar em coordenadas do mundo, então a escala da textura é sempre em metros.

static var _cache := {}
static var _facades: Array = []   # materiais de fachada (emissão das janelas à noite)

static func set_night(n: float) -> void:
	for m in _facades:
		m.emission_energy_multiplier = n * 1.1

static func _noise(freq: float, seed: int, ntype: int, octaves := 5) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = ntype
	n.frequency = freq
	n.seed = seed
	n.fractal_octaves = octaves
	return n

static func noise_tex(freq: float, seed: int, ntype: int, size := 512, normal := false, bump := 4.0, ramp: Gradient = null) -> NoiseTexture2D:
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.generate_mipmaps = true
	t.noise = _noise(freq, seed, ntype)
	if normal:
		t.as_normal_map = true
		t.bump_strength = bump
	if ramp:
		t.color_ramp = ramp
	return t

static func ramp(a: Color, b: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	return g

static func _world(m: StandardMaterial3D, meters: float) -> void:
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / meters

static func asphalt() -> StandardMaterial3D:
	if _cache.has("asphalt"): return _cache["asphalt"]
	var m := StandardMaterial3D.new()
	m.albedo_texture = noise_tex(0.05, 3, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 512, false, 0, ramp(Color(0.075, 0.075, 0.08), Color(0.2, 0.2, 0.205)))
	m.normal_enabled = true
	m.normal_scale = 0.6
	m.normal_texture = noise_tex(0.35, 7, FastNoiseLite.TYPE_CELLULAR, 512, true, 2.5)
	m.roughness_texture = noise_tex(0.03, 11, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 256, false, 0, ramp(Color(0.62, 0.62, 0.62), Color(0.95, 0.95, 0.95)))
	m.roughness = 1.0
	_world(m, 9.0)
	_cache["asphalt"] = m
	return m

static func sidewalk() -> StandardMaterial3D:
	if _cache.has("sidewalk"): return _cache["sidewalk"]
	# placas de concreto de 1 m com rejunte
	var S := 256
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.62, 0.61, 0.58))
	var h := Image.create(S, S, false, Image.FORMAT_RGBA8)
	h.fill(Color(1, 1, 1))
	for i in 2:
		var p := i * S / 2
		img.fill_rect(Rect2i(p, 0, 3, S), Color(0.38, 0.37, 0.35))
		img.fill_rect(Rect2i(0, p, S, 3), Color(0.38, 0.37, 0.35))
		h.fill_rect(Rect2i(p, 0, 3, S), Color(0.25, 0.25, 0.25))
		h.fill_rect(Rect2i(0, p, S, 3), Color(0.25, 0.25, 0.25))
	h.bump_map_to_normal_map(6.0)
	img.generate_mipmaps()
	h.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.normal_enabled = true
	m.normal_texture = ImageTexture.create_from_image(h)
	m.roughness = 0.82
	m.detail_enabled = true
	m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	m.detail_albedo = noise_tex(0.08, 21, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 256, false, 0, ramp(Color(0.78, 0.78, 0.78), Color(1, 1, 1)))
	_world(m, 2.0)
	_cache["sidewalk"] = m
	return m

static func grass() -> StandardMaterial3D:
	if _cache.has("grass"): return _cache["grass"]
	var m := StandardMaterial3D.new()
	m.albedo_texture = noise_tex(0.09, 5, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 512, false, 0, ramp(Color(0.11, 0.2, 0.06), Color(0.27, 0.38, 0.12)))
	m.normal_enabled = true
	m.normal_texture = noise_tex(0.9, 6, FastNoiseLite.TYPE_SIMPLEX, 512, true, 3.0)
	m.roughness = 0.95
	_world(m, 6.0)
	_cache["grass"] = m
	return m

static func concrete(c := Color(0.5, 0.5, 0.5)) -> StandardMaterial3D:
	var key := "concrete" + c.to_html()
	if _cache.has(key): return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.albedo_texture = noise_tex(0.06, 31, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 256, false, 0, ramp(Color(0.8, 0.8, 0.8), Color(1, 1, 1)))
	m.normal_enabled = true
	m.normal_texture = noise_tex(0.5, 32, FastNoiseLite.TYPE_SIMPLEX, 256, true, 1.5)
	m.roughness = 0.9
	_world(m, 4.0)
	_cache[key] = m
	return m

## Fachadas: cada ladrilho da textura = 1 janela de 1 andar (3,2 m × 3,4 m).
## style: 0 concreto, 1 tijolo, 2 torre de vidro, 3 reboco claro, 4 granito escuro.
static func facade(style: int) -> StandardMaterial3D:
	var key := "facade%d" % style
	if _cache.has(key): return _cache[key]
	var S := 256
	var wall: Color
	var frame: Color
	var glass := Color(0.16, 0.22, 0.27)
	var win := Rect2i(int(S * 0.2), int(S * 0.2), int(S * 0.6), int(S * 0.58))
	match style:
		0: wall = Color(0.58, 0.56, 0.52); frame = Color(0.2, 0.2, 0.21)
		1: wall = Color(0.52, 0.27, 0.2); frame = Color(0.85, 0.83, 0.78)
		2: wall = Color(0.32, 0.36, 0.4); frame = Color(0.55, 0.58, 0.6); win = Rect2i(8, 8, S - 16, S - 30); glass = Color(0.2, 0.3, 0.36)
		3: wall = Color(0.84, 0.8, 0.7); frame = Color(0.35, 0.33, 0.3)
		_: wall = Color(0.24, 0.24, 0.26); frame = Color(0.7, 0.7, 0.72)
	var alb := Image.create(S, S, false, Image.FORMAT_RGBA8)
	var hgt := Image.create(S, S, false, Image.FORMAT_RGBA8)
	var rgh := Image.create(S, S, false, Image.FORMAT_RGBA8)
	var met := Image.create(S, S, false, Image.FORMAT_RGBA8)
	alb.fill(wall)
	hgt.fill(Color(0.8, 0.8, 0.8))
	rgh.fill(Color(0.9, 0.9, 0.9))
	met.fill(Color(0, 0, 0))
	if style == 1:
		# tijolos: fiadas de 8 px com junta deslocada
		var row := 0
		for y in range(0, S, 9):
			alb.fill_rect(Rect2i(0, y, S, 2), Color(0.66, 0.62, 0.56))
			hgt.fill_rect(Rect2i(0, y, S, 2), Color(0.55, 0.55, 0.55))
			var off := 0 if row % 2 == 0 else 12
			for x in range(off, S, 24):
				alb.fill_rect(Rect2i(x, y, 2, 9), Color(0.66, 0.62, 0.56))
				hgt.fill_rect(Rect2i(x, y, 2, 9), Color(0.55, 0.55, 0.55))
			row += 1
	if style != 2:
		# faixa de laje entre andares
		alb.fill_rect(Rect2i(0, S - 18, S, 18), wall.darkened(0.18))
		hgt.fill_rect(Rect2i(0, S - 18, S, 18), Color(1, 1, 1))
		# moldura e peitoril
		alb.fill_rect(win.grow(7), frame)
		hgt.fill_rect(win.grow(7), Color(0.6, 0.6, 0.6))
		alb.fill_rect(Rect2i(win.position.x - 14, win.end.y + 7, win.size.x + 28, 9), frame.lightened(0.15))
		hgt.fill_rect(Rect2i(win.position.x - 14, win.end.y + 7, win.size.x + 28, 9), Color(1, 1, 1))
	alb.fill_rect(win, glass)
	hgt.fill_rect(win, Color(0.15, 0.15, 0.15))
	rgh.fill_rect(win, Color(0.06, 0.06, 0.06))
	met.fill_rect(win, Color(0.75, 0.75, 0.75))
	# caixilho central
	var mul := Rect2i(win.position.x + win.size.x / 2 - 3, win.position.y, 6, win.size.y)
	alb.fill_rect(mul, frame)
	hgt.fill_rect(mul, Color(0.6, 0.6, 0.6))
	rgh.fill_rect(mul, Color(0.5, 0.5, 0.5))
	met.fill_rect(mul, Color(0.2, 0.2, 0.2))
	# bloco de 4x4 janelas (128 px cada) para variar quais janelas acendem à noite
	var T := 4
	var C := 128
	var tiles := []
	for im in [alb, hgt, rgh, met]:
		im.resize(C, C, Image.INTERPOLATE_BILINEAR)
		var big := Image.create(C * T, C * T, false, Image.FORMAT_RGBA8)
		for ty in T:
			for tx in T:
				big.blit_rect(im, Rect2i(0, 0, C, C), Vector2i(tx * C, ty * C))
		tiles.append(big)
	alb = tiles[0]; hgt = tiles[1]; rgh = tiles[2]; met = tiles[3]
	var emi := Image.create(C * T, C * T, false, Image.FORMAT_RGBA8)
	emi.fill(Color(0, 0, 0))
	var er := RandomNumberGenerator.new()
	er.seed = 300 + style
	var wr := Rect2i(win.position / 2, win.size / 2)
	var warm := [Color(1.0, 0.78, 0.45), Color(1.0, 0.88, 0.62), Color(0.75, 0.85, 1.0), Color(1.0, 0.7, 0.4)]
	for ty in T:
		for tx in T:
			if er.randf() < 0.42:
				var wc: Color = warm[er.randi() % warm.size()] * er.randf_range(0.55, 1.0)
				wc.a = 1.0
				emi.fill_rect(Rect2i(wr.position + Vector2i(tx * C, ty * C), wr.size), wc)
	hgt.bump_map_to_normal_map(5.0)
	for im in [alb, hgt, rgh, met, emi]:
		im.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.emission_enabled = true
	m.emission_texture = ImageTexture.create_from_image(emi)
	m.emission = Color(0, 0, 0)   # operador ADD: cor + textura (preto = só a máscara das janelas)
	m.emission_energy_multiplier = 0.0
	_facades.append(m)
	m.albedo_texture = ImageTexture.create_from_image(alb)
	m.normal_enabled = true
	m.normal_texture = ImageTexture.create_from_image(hgt)
	m.roughness_texture = ImageTexture.create_from_image(rgh)
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness = 1.0
	m.metallic_texture = ImageTexture.create_from_image(met)
	m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.metallic = 1.0
	m.metallic_specular = 0.6
	# sujeira/variação em escala maior (multiplica a cor)
	m.detail_enabled = true
	m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	m.detail_albedo = noise_tex(0.05, 40 + style, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 256, false, 0, ramp(Color(0.72, 0.72, 0.72), Color(1, 1, 1)))
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(1.0 / 12.8, 1.0 / 13.6, 1.0 / 12.8)
	_cache[key] = m
	return m

static func plain(c: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var key := "plain%s_%f_%f" % [c.to_html(), rough, metal]
	if _cache.has(key): return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	_cache[key] = m
	return m

static func emissive(c: Color, energy := 2.0) -> StandardMaterial3D:
	var key := "emi%s_%f" % [c.to_html(), energy]
	if _cache.has(key): return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	_cache[key] = m
	return m

static func leaves() -> StandardMaterial3D:
	if _cache.has("leaves"): return _cache["leaves"]
	var m := StandardMaterial3D.new()
	m.albedo_texture = noise_tex(0.6, 50, FastNoiseLite.TYPE_CELLULAR, 256, false, 0, ramp(Color(0.07, 0.17, 0.05), Color(0.25, 0.42, 0.12)))
	m.normal_enabled = true
	m.normal_texture = noise_tex(1.2, 51, FastNoiseLite.TYPE_CELLULAR, 256, true, 6.0)
	m.roughness = 0.85
	_world(m, 2.5)
	_cache["leaves"] = m
	return m

static func bark() -> StandardMaterial3D:
	if _cache.has("bark"): return _cache["bark"]
	var m := StandardMaterial3D.new()
	m.albedo_texture = noise_tex(0.4, 60, FastNoiseLite.TYPE_SIMPLEX, 128, false, 0, ramp(Color(0.16, 0.11, 0.07), Color(0.3, 0.22, 0.15)))
	m.roughness = 0.95
	_world(m, 1.0)
	_cache["bark"] = m
	return m

static func car_paint(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.55
	m.roughness = 0.28
	m.clearcoat_enabled = true
	m.clearcoat = 0.9
	m.clearcoat_roughness = 0.08
	return m

static func skin(c: Color) -> StandardMaterial3D:
	return plain(c, 0.6)

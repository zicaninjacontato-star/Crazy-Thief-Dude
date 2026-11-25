extends Node
## Sons sintetizados no próprio jogo (sem arquivos de áudio): motor contínuo, sirene da polícia,
## batida, impacto em pedestre, grito, passos e buzina.

const RATE := 22050.0

var engine_p: AudioStreamPlayer
var engine_pb: AudioStreamGeneratorPlayback
var siren_p: AudioStreamPlayer
var siren_pb: AudioStreamGeneratorPlayback
var eng_phase := 0.0
var eng_phase2 := 0.0
var eng_rpm := 0.0
var eng_vol := 0.0
var eng_target_rpm := 0.0
var eng_target_vol := 0.0
var sir_phase := 0.0
var sir_t := 0.0
var sir_vol := 0.0
var sir_target := 0.0
var sounds := {}
var amb_city: AudioStreamPlayer
var amb_sea: AudioStreamPlayer

## ambiente: 0..1 de cidade e de mar (o main calcula pela posição)
func set_ambient(city: float, sea: float) -> void:
	amb_city.volume_db = linear_to_db(maxf(0.0005, city * 0.55))
	amb_sea.volume_db = linear_to_db(maxf(0.0005, sea * 0.7))

func _loop_player(w: AudioStreamWAV) -> AudioStreamPlayer:
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = w.data.size() / 2
	var p := AudioStreamPlayer.new()
	p.stream = w
	p.volume_db = -60.0
	add_child(p)
	p.play()
	return p

func _ready() -> void:
	engine_p = _gen_player()
	siren_p = _gen_player()
	engine_pb = engine_p.get_stream_playback()
	siren_pb = siren_p.get_stream_playback()
	sounds["crash"] = _noise_burst(0.45, 0.06, 900.0, 0.9)
	sounds["hit"] = _noise_burst(0.22, 0.01, 300.0, 1.0)
	sounds["step"] = _noise_burst(0.07, 0.002, 1600.0, 0.35)
	sounds["scream"] = _scream()
	sounds["horn"] = _horn()
	sounds["shot"] = _shot()
	sounds["punch"] = _noise_burst(0.12, 0.002, 450.0, 1.0)
	sounds["cash"] = _chime()
	sounds["door"] = _noise_burst(0.18, 0.003, 260.0, 1.3)
	sounds["explosion"] = _boom()
	sounds["splash"] = _noise_burst(0.7, 0.02, 2500.0, 0.8)
	sounds["rocket"] = _noise_burst(0.9, 0.05, 1200.0, 0.6)
	sounds["swoosh"] = _noise_burst(0.15, 0.04, 2200.0, 0.4)
	sounds["kick"] = _noise_burst(0.14, 0.002, 380.0, 1.2)
	sounds["reload"] = _clicks([0.0, 0.35, 0.7], 0.95)
	sounds["click"] = _clicks([0.0], 0.15)
	sounds["stroke"] = _noise_burst(0.35, 0.05, 1800.0, 0.5)
	sounds["glass"] = _noise_burst(0.5, 0.001, 6000.0, 0.7)
	sounds["whale"] = _whale()
	sounds["whoosh"] = _whoosh()
	amb_city = _loop_player(_city_loop())
	amb_sea = _loop_player(_sea_loop())
	sounds["squid"] = _boom()

func _gen_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var g := AudioStreamGenerator.new()
	g.mix_rate = RATE
	g.buffer_length = 0.12
	p.stream = g
	p.volume_db = -6.0
	add_child(p)
	p.play()
	return p

## rpm 0..1, throttle 0..1, on = jogador está num carro
func set_engine(on: bool, rpm: float, throttle: float) -> void:
	eng_target_rpm = rpm
	eng_target_vol = (0.16 + throttle * 0.22) if on else 0.0

func set_siren(on: bool, dist: float) -> void:
	sir_target = clampf(1.0 - dist / 120.0, 0.0, 1.0) * 0.35 if on else 0.0

func _process(_dt: float) -> void:
	_fill_engine()
	_fill_siren()

func _fill_engine() -> void:
	var n := engine_pb.get_frames_available()
	for i in n:
		eng_rpm = lerpf(eng_rpm, eng_target_rpm, 0.0004)
		eng_vol = lerpf(eng_vol, eng_target_vol, 0.0008)
		var f := 38.0 + eng_rpm * 150.0
		eng_phase = fmod(eng_phase + f / RATE, 1.0)
		eng_phase2 = fmod(eng_phase2 + f * 0.5 / RATE, 1.0)
		# dente de serra + sub-harmônico + ruído: ronco de motor
		var s := (eng_phase * 2.0 - 1.0) * 0.55 + sin(eng_phase2 * TAU) * 0.45 + (randf() * 2.0 - 1.0) * 0.08
		s = clampf(s * 1.4, -1.0, 1.0) * eng_vol
		engine_pb.push_frame(Vector2(s, s))

func _fill_siren() -> void:
	var n := siren_pb.get_frames_available()
	for i in n:
		sir_vol = lerpf(sir_vol, sir_target, 0.0005)
		sir_t += 1.0 / RATE
		var sweep := (sin(sir_t * TAU * 0.33) * 0.5 + 0.5)
		var f := lerpf(620.0, 1350.0, sweep)
		sir_phase = fmod(sir_phase + f / RATE, 1.0)
		var tri := absf(sir_phase * 4.0 - 2.0) - 1.0
		var s := tri * sir_vol
		siren_pb.push_frame(Vector2(s, s))

func play(name: String, pos = null, vol_db := 0.0) -> void:
	if not sounds.has(name):
		return
	if pos == null:
		var p := AudioStreamPlayer.new()
		p.stream = sounds[name]
		p.volume_db = vol_db
		add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
	else:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = sounds[name]
		p3.volume_db = vol_db
		p3.unit_size = 8.0
		p3.max_distance = 90.0
		get_tree().current_scene.add_child(p3)
		p3.global_position = pos
		p3.play()
		p3.finished.connect(p3.queue_free)

func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = int(RATE)
	w.stereo = false
	w.data = data
	return w

func _noise_burst(dur: float, attack: float, lp_hz: float, gain: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var a := clampf(lp_hz / RATE * 6.28, 0.01, 1.0)
	var y := 0.0
	for i in n:
		var t := i / RATE
		var env := minf(1.0, t / maxf(attack, 0.0005)) * exp(-t * 6.0 / dur)
		y += a * ((randf() * 2.0 - 1.0) - y)
		out[i] = y * env * gain * 2.2
	return _wav(out)

func _scream() -> AudioStreamWAV:
	# voz: pulso glotal com vibrato filtrado por 3 formantes (ressonadores simples)
	var dur := 0.9
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var fm := [[850.0, 0.0, 0.0], [1350.0, 0.0, 0.0], [2900.0, 0.0, 0.0]]
	for i in n:
		var t := i / RATE
		var f0 := 520.0 + 90.0 * sin(t * 6.0) - t * 160.0
		ph = fmod(ph + f0 / RATE, 1.0)
		var src := (1.0 - ph) * (1.0 - ph) - 0.33 + (randf() - 0.5) * 0.15
		var s := 0.0
		for f in fm:
			var w: float = TAU * f[0] / RATE
			var r := 0.985
			var y: float = src + 2.0 * r * cos(w) * f[1] - r * r * f[2]
			f[2] = f[1]
			f[1] = y
			s += y
		var env := minf(1.0, t / 0.05) * minf(1.0, (dur - t) / 0.25)
		out[i] = s * 0.012 * env
	return _wav(out)

func _horn() -> AudioStreamWAV:
	var dur := 0.5
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := i / RATE
		var s := signf(sin(TAU * 410.0 * t)) * 0.3 + signf(sin(TAU * 520.0 * t)) * 0.3
		out[i] = s * minf(1.0, t / 0.01) * minf(1.0, (dur - t) / 0.03) * 0.5
	return _wav(out)

func _shot() -> AudioStreamWAV:
	var dur := 0.35
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := i / RATE
		y += 0.55 * ((randf() * 2.0 - 1.0) - y)
		var crack := y * exp(-t * 38.0) * 1.6
		var boom := sin(TAU * 70.0 * t * (1.0 - t)) * exp(-t * 12.0) * 0.8
		out[i] = clampf(crack + boom, -1.0, 1.0) * 0.9
	return _wav(out)

func _chime() -> AudioStreamWAV:
	var dur := 0.35
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := i / RATE
		var f := 1320.0 if t < 0.12 else 1760.0
		out[i] = sin(TAU * f * t) * exp(-t * 7.0) * 0.4
	return _wav(out)

func _boom() -> AudioStreamWAV:
	var dur := 1.6
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	var y2 := 0.0
	for i in n:
		var t := i / RATE
		y += 0.08 * ((randf() * 2.0 - 1.0) - y)
		y2 += 0.5 * ((randf() * 2.0 - 1.0) - y2)
		var low := sin(TAU * 45.0 * t * (1.0 - t * 0.3)) * exp(-t * 3.0)
		out[i] = clampf((y * 6.0 + low * 0.9) * exp(-t * 2.2) + y2 * exp(-t * 25.0) * 0.8, -1.0, 1.0)
	return _wav(out)

func _clicks(times: Array, dur: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for tt in times:
		var i0 := int(tt * RATE)
		for i in int(0.04 * RATE):
			if i0 + i < n:
				var t := i / RATE
				out[i0 + i] += (randf() * 2.0 - 1.0) * exp(-t * 120.0) * 0.9 + sin(TAU * 2400.0 * t) * exp(-t * 200.0) * 0.4
	return _wav(out)

func _whale() -> AudioStreamWAV:
	var dur := 2.5
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := i / RATE
		var f := 180.0 + sin(t * 1.3) * 60.0 + t * 30.0
		ph += f / RATE
		out[i] = sin(TAU * ph) * sin(PI * t / dur) * 0.5 + sin(TAU * ph * 2.01) * 0.12 * sin(PI * t / dur)
	return _wav(out)

## cidade (8 s em loop): ronco de trânsito, carros passando ao longe, vozes (formantes) e buzina distante
func _city_loop() -> AudioStreamWAV:
	var dur := 8.0
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	var y2 := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in n:
		var t := i / RATE
		y += 0.02 * ((rng.randf() * 2.0 - 1.0) - y)
		y2 += 0.12 * ((rng.randf() * 2.0 - 1.0) - y2)
		# carros passando: ondas lentas de ruído
		var pass_ := pow(maxf(0.0, sin(t * TAU / 8.0 * 3.0)), 6.0) + pow(maxf(0.0, sin(t * TAU / 8.0 * 2.0 + 1.3)), 8.0)
		# loop sem emenda: tudo periódico em 8 s
		out[i] = y * 5.0 * 0.35 + y2 * pass_ * 0.35
	# vozes: sílabas curtas filtradas
	for k in 26:
		var t0 := rng.randf_range(0.0, dur - 0.5)
		var f0 := rng.randf_range(140.0, 260.0)
		var syl := rng.randi_range(2, 5)
		var amp := rng.randf_range(0.03, 0.08)
		for sy in syl:
			var st := t0 + sy * 0.16
			var len_ := rng.randf_range(0.08, 0.14)
			var fm := rng.randf_range(500.0, 900.0)
			for i in int(len_ * RATE):
				var idx := int(st * RATE) + i
				if idx >= n:
					break
				var tt := i / RATE
				var env := sin(PI * tt / len_)
				out[idx] += (sin(TAU * f0 * tt) * 0.6 + sin(TAU * fm * tt) * 0.3) * env * amp
	# buzina distante
	var hb := int(5.3 * RATE)
	for i in int(0.35 * RATE):
		var tt := i / RATE
		out[hb + i] += (sin(TAU * 410.0 * tt) + sin(TAU * 520.0 * tt)) * 0.025 * minf(1.0, tt * 30.0) * minf(1.0, (0.35 - tt) * 20.0)
	return _wav(out)

## mar (8 s em loop): ondas batendo (ruído com envelope lento), vento e gaivotas
func _sea_loop() -> AudioStreamWAV:
	var dur := 8.0
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	var w := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for i in n:
		var t := i / RATE
		y += 0.09 * ((rng.randf() * 2.0 - 1.0) - y)
		w += 0.01 * ((rng.randf() * 2.0 - 1.0) - w)
		var wave := pow(0.5 + 0.5 * sin(t * TAU / 4.0 - 1.2), 3.0) * 0.8 + pow(0.5 + 0.5 * sin(t * TAU / 8.0 * 3.0), 4.0) * 0.4
		out[i] = y * wave * 0.9 + w * 2.5 * 0.25
	for k in 3:
		var t0 := rng.randf_range(0.5, dur - 1.0)
		for i in int(0.5 * RATE):
			var idx := int(t0 * RATE) + i
			var tt := i / RATE
			var f := 1800.0 - tt * 1400.0 + sin(tt * 60.0) * 120.0
			out[idx] += sin(TAU * f * tt) * sin(PI * tt / 0.5) * 0.05
	return _wav(out)

func _whoosh() -> AudioStreamWAV:
	var dur := 1.2
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := i / RATE
		y += 0.15 * ((randf() * 2.0 - 1.0) - y)
		out[i] = y * pow(sin(PI * t / dur), 2.0) * 1.6
	return _wav(out)

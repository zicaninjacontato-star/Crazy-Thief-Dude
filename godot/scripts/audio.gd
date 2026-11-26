extends Node
## Sons sintetizados no próprio jogo (sem arquivos de áudio): motor contínuo, sirene da polícia,
## batida, impacto em pedestre, grito, passos e buzina.

const RATE := 22050.0
const GEN := 16000.0     # motor e sirene (gerados em tempo real): taxa menor = menos trabalho por quadro

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
	amb_city.volume_db = linear_to_db(maxf(0.0005, city * 0.8))
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

var _pending: Array = []     # [nome, Callable]: sons gerados aos poucos depois de carregar

func _ready() -> void:
	engine_p = _gen_player()
	siren_p = _gen_player()
	engine_pb = engine_p.get_stream_playback()
	siren_pb = siren_p.get_stream_playback()
	sounds["crash"] = _noise_burst(0.45, 0.06, 900.0, 0.9)
	sounds["hit"] = [_thud(1), _thud(2), _thud(3)]
	sounds["punch"] = [_punch(1), _punch(2), _punch(3)]
	sounds["horn"] = _horn()
	sounds["cash"] = _chime()
	sounds["door"] = _noise_burst(0.18, 0.003, 260.0, 1.3)
	sounds["explosion"] = _boom()
	sounds["splash"] = _noise_burst(0.7, 0.02, 2500.0, 0.8)
	sounds["bones"] = _bones()
	sounds["rocket"] = _noise_burst(0.9, 0.05, 1200.0, 0.6)
	sounds["swoosh"] = _noise_burst(0.15, 0.04, 2200.0, 0.4)
	sounds["kick"] = [_punch(4), _punch(5)]
	sounds["reload"] = _clicks([0.0, 0.35, 0.7], 0.95)
	sounds["click"] = _clicks([0.0], 0.15)
	sounds["stroke"] = _noise_burst(0.35, 0.05, 1800.0, 0.5)
	sounds["glass"] = _noise_burst(0.5, 0.001, 6000.0, 0.7)
	sounds["whoosh"] = _whoosh()
	for surf in ["road", "grass", "sand", "wood", "water"]:
		var arr := []
		for v in 4:
			arr.append(_step(surf, v))
		sounds["step_" + surf] = arr
	sounds["step"] = sounds["step_road"]
	sounds["shot"] = _gun("pistol", 0)
	for w in ["pistol", "smg", "shotgun", "rifle", "sniper"]:
		sounds["shot_" + w] = [_gun(w, 0), _gun(w, 1)]
	amb_city = _loop_player(_city_loop())
	amb_sea = _loop_player(_sea_loop())
	# vozes, baleia, tanque e caça: gerados aos poucos (não atrasam o carregamento)
	var specs := _voice_specs()
	sounds["scream"] = []
	for i in specs.size():
		_pending.append(["scream", _voice.bind(specs[i], 100 + i)])
	_pending.append(["whale", _whale])
	_pending.append(["squid", _monster])
	_pending.append(["tank", _tank_shot])
	_pending.append(["jet", _jet])
	_pending.append(["jet_loop", _jet_loop])

func _gen_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var g := AudioStreamGenerator.new()
	g.mix_rate = GEN
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
	if not _pending.is_empty():
		var job: Array = _pending.pop_front()
		var w = job[1].call()
		if sounds.get(job[0]) is Array:
			sounds[job[0]].append(w)
		else:
			sounds[job[0]] = w

func _fill_engine() -> void:
	# otimização: sem som de motor (a pé) não gera amostras
	if eng_vol < 0.0005 and eng_target_vol <= 0.0:
		return
	var n := engine_pb.get_frames_available()
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		eng_rpm = lerpf(eng_rpm, eng_target_rpm, 0.0004)
		eng_vol = lerpf(eng_vol, eng_target_vol, 0.0008)
		var f := 38.0 + eng_rpm * 150.0
		eng_phase = fmod(eng_phase + f / GEN, 1.0)
		eng_phase2 = fmod(eng_phase2 + f * 0.5 / GEN, 1.0)
		# dente de serra + sub-harmônico + ruído: ronco de motor
		var s := (eng_phase * 2.0 - 1.0) * 0.55 + sin(eng_phase2 * TAU) * 0.45 + (randf() * 2.0 - 1.0) * 0.08
		s = clampf(s * 1.4, -1.0, 1.0) * eng_vol
		buf[i] = Vector2(s, s)
	engine_pb.push_buffer(buf)

func _fill_siren() -> void:
	if sir_vol < 0.0005 and sir_target <= 0.0:
		return
	var n := siren_pb.get_frames_available()
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		sir_vol = lerpf(sir_vol, sir_target, 0.0005)
		sir_t += 1.0 / GEN
		var sweep := (sin(sir_t * TAU * 0.33) * 0.5 + 0.5)
		var f := lerpf(620.0, 1350.0, sweep)
		sir_phase = fmod(sir_phase + f / GEN, 1.0)
		var tri := absf(sir_phase * 4.0 - 2.0) - 1.0
		var s := tri * sir_vol
		buf[i] = Vector2(s, s)
	siren_pb.push_buffer(buf)

func play(name: String, pos = null, vol_db := 0.0) -> void:
	if not sounds.has(name):
		return
	var st = sounds[name]
	if st is Array:
		if st.is_empty():
			return
		st = st[randi() % st.size()]
	var pitch := randf_range(0.93, 1.07)
	if pos == null:
		var p := AudioStreamPlayer.new()
		p.stream = st
		p.volume_db = vol_db
		p.pitch_scale = pitch
		add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
	else:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = st
		p3.volume_db = vol_db
		p3.pitch_scale = pitch
		p3.unit_size = 8.0
		p3.max_distance = 140.0
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

## ossos quebrando: estalos secos em sequência + baque surdo
func _bones() -> AudioStreamWAV:
	var n := int(0.55 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var cracks := [0.0, 0.05, 0.09, 0.16, 0.2, 0.31]
	for c in cracks:
		var i0 := int(c * RATE)
		var amp := randf_range(0.6, 1.0)
		for i in int(0.018 * RATE):
			if i0 + i < n:
				var e := exp(-i / (0.0035 * RATE))
				out[i0 + i] += (randf() * 2.0 - 1.0) * amp * e
	var y := 0.0
	for i in int(0.25 * RATE):
		y += 0.04 * ((randf() * 2.0 - 1.0) - y)
		out[i] += y * 3.0 * exp(-i / (0.07 * RATE))
	return _wav(out)

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

## cidade (12 s em loop): ronco grave de motores (harmônicos, não ruído), carros passando com
## efeito Doppler, burburinho de gente conversando, passos, pássaros e buzina distante
func _city_loop() -> AudioStreamWAV:
	var dur := 12.0
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	# trânsito parado/andando ao longe: soma de motores em marcha lenta (periódico em 12 s)
	for e in 5:
		var f := rng.randf_range(28.0, 46.0)
		f = roundf(f * dur) / dur
		var amp := rng.randf_range(0.012, 0.022)
		var ph := rng.randf() * TAU
		for i in n:
			var t := i / RATE
			var s := sin(TAU * f * t + ph) + 0.5 * sin(TAU * f * 2.0 * t + ph) + 0.25 * sin(TAU * f * 3.0 * t)
			out[i] += s * amp * (0.7 + 0.3 * sin(TAU * t / dur * (e + 1)))
	# carros passando (Doppler): motor + pneu num envelope curto
	var y := 0.0
	for k in 7:
		var t0 := rng.randf_range(0.0, dur)
		var len_ := rng.randf_range(2.2, 3.6)
		var f0 := rng.randf_range(55.0, 95.0)
		var amp := rng.randf_range(0.05, 0.1)
		var ph := 0.0
		for i in int(len_ * RATE):
			var idx := (int(t0 * RATE) + i) % n
			var tt := i / RATE
			var u := tt / len_ * 2.0 - 1.0          # -1..1, passa no meio
			var env := 1.0 / (1.0 + u * u * 18.0)
			var fd := f0 * (1.0 - 0.12 * clampf(u * 3.0, -1.0, 1.0))
			ph += fd / RATE
			y += 0.35 * ((rng.randf() * 2.0 - 1.0) - y)
			var eng := sin(TAU * ph) * 0.6 + sin(TAU * ph * 2.0) * 0.3 + sin(TAU * ph * 3.0) * 0.12
			out[idx] += (eng * 0.7 + y * 0.35) * env * amp
	# burburinho: muitas sílabas sobrepostas com vogais diferentes
	var vow := [[800.0, 1150.0], [500.0, 1700.0], [450.0, 800.0], [300.0, 2200.0], [650.0, 1100.0]]
	for k in 90:
		var t0 := rng.randf_range(0.0, dur)
		var f0 := rng.randf_range(110.0, 150.0) if rng.randf() < 0.5 else rng.randf_range(190.0, 260.0)
		var syl := rng.randi_range(2, 6)
		var amp := rng.randf_range(0.006, 0.016)
		var st := t0
		for sy in syl:
			var len_ := rng.randf_range(0.09, 0.2)
			var fm: Array = vow[rng.randi() % vow.size()]
			var ph := 0.0
			for i in int(len_ * RATE):
				var idx := (int(st * RATE) + i) % n
				var tt := i / RATE
				var env := sin(PI * tt / len_)
				var fx := f0 * (1.0 + 0.08 * sin(tt * 9.0 + k))
				ph += fx / RATE
				var g := fmod(ph, 1.0)
				var src := (1.0 - g) * (1.0 - g) - 0.33
				out[idx] += (src * 0.5 + sin(TAU * fm[0] * tt) * 0.25 * src + sin(TAU * fm[1] * tt) * 0.12 * src) * env * amp
			st += len_ + rng.randf_range(0.02, 0.08)
	# pássaros
	for k in 6:
		var t0 := rng.randf_range(0.0, dur - 0.4)
		for c2 in rng.randi_range(2, 4):
			var ts := t0 + c2 * 0.13
			var f := rng.randf_range(2800.0, 4200.0)
			for i in int(0.07 * RATE):
				var idx := (int(ts * RATE) + i) % n
				var tt := i / RATE
				out[idx] += sin(TAU * (f + tt * 9000.0) * tt) * sin(PI * tt / 0.07) * 0.025
	# buzinas distantes
	for hb0 in [3.1, 8.7]:
		var hb := int(hb0 * RATE)
		for i in int(0.4 * RATE):
			var tt := i / RATE
			out[(hb + i) % n] += (sin(TAU * 410.0 * tt) + sin(TAU * 520.0 * tt)) * 0.018 * minf(1.0, tt * 30.0) * minf(1.0, (0.4 - tt) * 20.0)
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

# ---------------------------------------------------------------- impactos
## pancada no corpo (dano): baque grave curto, sem chiado
func _thud(seed: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 31
	var dur := 0.22
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var f := rng.randf_range(70.0, 110.0)
	var y := 0.0
	for i in n:
		var t := i / RATE
		y += 0.12 * ((rng.randf() * 2.0 - 1.0) - y)
		out[i] = (sin(TAU * f * t * (1.0 - t * 1.5)) * exp(-t * 28.0) * 0.9 + y * exp(-t * 45.0) * 1.6) * 0.8
	return _wav(out)

## soco/chute: estalo seco + corpo
func _punch(seed: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 57
	var dur := 0.2
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	var f := rng.randf_range(90.0, 140.0) * (0.8 if seed > 3 else 1.0)
	for i in n:
		var t := i / RATE
		y += 0.5 * ((rng.randf() * 2.0 - 1.0) - y)
		out[i] = clampf(y * exp(-t * 90.0) * 1.4 + sin(TAU * f * t) * exp(-t * 30.0) * 0.9, -1.0, 1.0) * 0.85
	return _wav(out)

## passos por piso (4 variações cada)
func _step(surf: String, v: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(surf) + v * 13
	var dur: float = {"road": 0.09, "grass": 0.16, "sand": 0.2, "wood": 0.14, "water": 0.3}[surf]
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	var y2 := 0.0
	var f := rng.randf_range(0.9, 1.15)
	for i in n:
		var t := i / RATE
		var w := rng.randf() * 2.0 - 1.0
		match surf:
			"road":
				# calcanhar no asfalto: estalo agudo + leve arrasto
				y += 0.6 * (w - y)
				out[i] = (y - y2) * exp(-t * 70.0) * 0.9 + sin(TAU * 180.0 * f * t) * exp(-t * 60.0) * 0.25
				y2 = y
			"grass":
				# folhas amassando: estalinhos espalhados, abafados
				y += 0.25 * (w - y)
				var crackle := 1.0 if rng.randf() < 0.05 else 0.25
				out[i] = y * crackle * sin(PI * t / dur) * 0.9
			"sand":
				# areia: chiado granular grave
				y += 0.12 * (w - y)
				out[i] = y * (0.5 + 0.5 * absf(sin(t * 260.0 * f))) * sin(PI * t / dur) * 1.6
			"wood":
				# madeira oca: ressonância
				y += 0.4 * (w - y)
				out[i] = (sin(TAU * 140.0 * f * t) * 0.6 + sin(TAU * 310.0 * f * t) * 0.3) * exp(-t * 26.0) + y * exp(-t * 80.0) * 0.5
			"water":
				y += 0.3 * (w - y)
				out[i] = y * sin(PI * t / dur) * 0.8 + sin(TAU * (500.0 + t * 1800.0) * t) * exp(-t * 20.0) * 0.12
	return _wav(out)

# ---------------------------------------------------------------- armas
## cada arma tem estampido, corpo e cauda (eco) próprios
func _gun(w: String, v: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(w) + v * 7
	var P: Array = {
		"pistol": [0.45, 55.0, 160.0, 0.55, 0.25],
		"smg": [0.3, 75.0, 190.0, 0.45, 0.18],
		"shotgun": [0.9, 22.0, 85.0, 1.0, 0.45],
		"rifle": [0.75, 40.0, 120.0, 0.8, 0.4],
		"sniper": [1.4, 26.0, 95.0, 1.0, 0.6]}[w]
	var dur: float = P[0]
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	var yl := 0.0
	for i in n:
		var t := i / RATE
		var wv := rng.randf() * 2.0 - 1.0
		y += 0.7 * (wv - y)
		yl += 0.06 * (wv - yl)
		var crack: float = y * exp(-t * P[1] * 3.0) * 1.3
		var body: float = (sin(TAU * P[2] * t * (1.0 - t)) * 0.7 + yl * 4.0) * exp(-t * P[1] * 0.6) * P[3]
		var tail: float = yl * 3.0 * exp(-t * 6.0 / dur) * P[4] * (1.0 - exp(-t * 40.0))
		out[i] = clampf(crack + body + tail, -1.0, 1.0) * 0.85
	# eco (prédios): cópia atrasada e abafada
	var dl := int(rng.randf_range(0.09, 0.14) * RATE)
	for i in range(n - 1, dl, -1):
		out[i] += out[i - dl] * 0.28
	return _wav(out)

func _tank_shot() -> AudioStreamWAV:
	var w := _boom()
	return w

func _jet() -> AudioStreamWAV:
	var dur := 4.0
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	var y2 := 0.0
	for i in n:
		var t := i / RATE
		var w := randf() * 2.0 - 1.0
		y += 0.25 * (w - y)
		y2 += 0.03 * (w - y2)
		var u := t / dur * 2.0 - 1.0
		var env := 1.0 / (1.0 + u * u * 6.0)
		out[i] = (y * 0.7 + y2 * 4.0) * env * 0.8
	return _wav(out)

## turbina contínua (loop sem emenda) para os caças do exército
func _jet_loop() -> AudioStreamWAV:
	var dur := 2.0
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	var y2 := 0.0
	for i in n:
		var t := i / RATE
		var w := randf() * 2.0 - 1.0
		y += 0.3 * (w - y)
		y2 += 0.025 * (w - y2)
		var whine := sin(TAU * 1850.0 * t) * 0.05 + sin(TAU * 2770.0 * t) * 0.03
		out[i] = y * 0.55 + y2 * 3.6 + whine
	# emenda suave: o fim cruza com o começo
	var fade := int(0.1 * RATE)
	for i in fade:
		var k := float(i) / fade
		out[n - fade + i] = out[n - fade + i] * (1.0 - k) + out[i] * k
	var w := _wav(out)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = fade
	w.loop_end = n
	return w

## som contínuo preso a um nó (turbina, motor): devolve o player para ajustar volume/tom
func attach_loop(node: Node3D, name: String, vol_db := 0.0, max_d := 600.0) -> AudioStreamPlayer3D:
	if not sounds.has(name):
		return null
	var p3 := AudioStreamPlayer3D.new()
	p3.stream = sounds[name]
	p3.volume_db = vol_db
	p3.unit_size = 45.0
	p3.max_distance = max_d
	p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	node.add_child(p3)
	p3.play()
	return p3

## rugido grave do tubarão gigante
func _monster() -> AudioStreamWAV:
	var dur := 2.2
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	var ph := 0.0
	for i in n:
		var t := i / RATE
		y += 0.05 * ((randf() * 2.0 - 1.0) - y)
		ph += (48.0 + sin(t * 7.0) * 6.0 - t * 8.0) / RATE
		var g := fmod(ph, 1.0)
		out[i] = clampf(((1.0 - g) * 1.4 - 0.5 + y * 5.0) * sin(PI * minf(1.0, t / dur * 1.3)) * 0.7, -1.0, 1.0)
	return _wav(out)

# ---------------------------------------------------------------- vozes (gritos de dor / morte)
## cada NPC sorteia uma: homem/mulher, "aaah" caindo, "ugh" curto, "ai-ai", "nããão", gemido
func _voice_specs() -> Array:
	return [
		{"f0": 150.0, "f1": 95.0, "dur": 0.75, "v": ["a", "a", "o"], "vib": 5.0, "br": 0.25},
		{"f0": 120.0, "f1": 85.0, "dur": 0.28, "v": ["u", "o"], "vib": 0.0, "br": 0.4},
		{"f0": 330.0, "f1": 230.0, "dur": 0.85, "v": ["a", "a", "a"], "vib": 6.5, "br": 0.2},
		{"f0": 280.0, "f1": 260.0, "dur": 0.55, "v": ["a", "i", "a", "i"], "vib": 3.0, "br": 0.15, "gap": true},
		{"f0": 170.0, "f1": 110.0, "dur": 0.9, "v": ["o", "a", "u"], "vib": 4.0, "br": 0.3},
		{"f0": 260.0, "f1": 170.0, "dur": 0.4, "v": ["e", "a"], "vib": 2.0, "br": 0.35},
		{"f0": 105.0, "f1": 80.0, "dur": 0.6, "v": ["a", "u"], "vib": 1.5, "br": 0.45},
		{"f0": 380.0, "f1": 300.0, "dur": 0.7, "v": ["i", "a", "a"], "vib": 7.0, "br": 0.2}]

func _voice(sp: Dictionary, seed: int) -> AudioStreamWAV:
	var V := {"a": [[800.0, 80.0], [1200.0, 90.0], [2700.0, 140.0]], "o": [[480.0, 70.0], [850.0, 90.0], [2600.0, 140.0]],
		"u": [[340.0, 60.0], [750.0, 80.0], [2500.0, 150.0]], "e": [[520.0, 70.0], [1750.0, 100.0], [2600.0, 140.0]], "i": [[310.0, 60.0], [2250.0, 110.0], [3000.0, 160.0]]}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var dur: float = sp.dur
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var fem: bool = sp.f0 > 220.0
	var fs := 1.12 if fem else 1.0
	var st := [[0.0, 0.0], [0.0, 0.0], [0.0, 0.0]]
	var ph := 0.0
	var nb := 0.0
	var vs: Array = sp.v
	for i in n:
		var t := i / RATE
		var k := t / dur
		var f0: float = lerpf(sp.f0, sp.f1, k * k) * (1.0 + 0.04 * sin(t * TAU * sp.vib)) * (1.0 + (rng.randf() - 0.5) * 0.02)
		ph += f0 / RATE
		var g := fmod(ph, 1.0)
		# pulso glotal (Rosenberg) + ruído de respiração
		var src := (0.5 - 0.5 * cos(PI * g / 0.6)) if g < 0.6 else cos(PI * (g - 0.6) / 0.8)
		src = src * 2.0 - 0.6
		nb += 0.5 * ((rng.randf() * 2.0 - 1.0) - nb)
		src += nb * sp.br * (0.6 + k)
		# vogal atual (interpola entre as vogais da lista)
		var pos := k * (vs.size() - 1)
		var ia := mini(int(pos), vs.size() - 1)
		var ib := mini(ia + 1, vs.size() - 1)
		var fr := pos - ia
		var s := 0.0
		for j in 3:
			var fa: float = lerpf(V[vs[ia]][j][0], V[vs[ib]][j][0], fr) * fs
			var bw: float = V[vs[ia]][j][1] * (1.3 if fem else 1.0)
			var r := exp(-PI * bw / RATE)
			var w := TAU * fa / RATE
			var yv: float = (1.0 - r) * src + 2.0 * r * cos(w) * st[j][0] - r * r * st[j][1]
			st[j][1] = st[j][0]
			st[j][0] = yv
			s += yv * [1.0, 0.6, 0.25][j]
		var env := minf(1.0, t / 0.03) * minf(1.0, (dur - t) / (dur * 0.35))
		if sp.get("gap", false):
			env *= 0.25 + 0.75 * clampf(sin(k * PI * 2.0) * 3.0, 0.0, 1.0)
		out[i] = s * env
	# normaliza
	var mx := 0.001
	for v in out:
		mx = maxf(mx, absf(v))
	for i in n:
		out[i] = out[i] / mx * 0.7
	return _wav(out)

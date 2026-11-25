extends CanvasLayer
## HUD e controles de toque (multitoque): joystick à esquerda, botões à direita, arrastar no meio gira a câmera.

signal enter_pressed
signal jump_pressed
signal weapon_pressed
signal shop_pressed

var joy := Vector2.ZERO
var gas := false
var brk := false
var sprint := false
var fire := false
var flash := 0.0
var wasted := ""
var weapon_text := ""
var big: Label
var cam_drag := Vector2.ZERO

var _joy_id := -1
var _joy_center := Vector2.ZERO
var _cam_id := -1
var _cam_last := Vector2.ZERO
var _btn_ids := {}
var root: Control
var info: Label
var stars: Label
var speed: Label
var hint: Label
var buttons := {}   # nome -> Rect2 (em pixels de tela)
var driving := false
var money: Label
var clock: Label
var hp := 100.0
var armor := 0.0
var shop_label := ""   # texto do botão de loja (vazio = escondido)
var aim := false
var jump_held := false
var breath := -1.0
var swim_mode := false
var can_enter := false       # há veículo perto (mostra o botão do carro)
var weapon_kind := "fist"
var action_kind := ""        # enter / exit / buy / carry / drop / trunk
var heli := false
var _fire_last := Vector2.ZERO
var crosshair := false
var input_block := false
var map_blips: Array = []      # [{pos, col}]
var mission_text := ""
var mission_timer := -1.0
var gas_name := "ACEL"
var brk_name := "FREIO"
var stars_blink := false
var mlabel: Label
var _banner: Label
var _banner_t := 0.0
var map_player := Vector3.ZERO
var map_yaw := 0.0
var map_police := Vector3.INF
var map_roads: Array = []      # posições das ruas da grade (x e z)
var map_ext := 160.0
var map_roadw := 14.0
const R := 70.0

func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.draw.connect(_draw_controls)
	info = _label(Vector2(16, 10), 16)
	stars = _label(Vector2(0, 10), 34)
	stars.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stars.position = Vector2(-220, 98)
	stars.add_theme_color_override("font_color", Color(1, 0.82, 0.2))
	speed = _label(Vector2(16, 290), 26)
	clock = _label(Vector2(88, 232), 24)
	money = _label(Vector2(0, 0), 40)
	money.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	money.position = Vector2(-300, 44)
	money.size = Vector2(280, 50)
	money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money.add_theme_color_override("font_color", Color(0.35, 0.95, 0.35))
	info.position = Vector2(230, 10)
	big = _label(Vector2.ZERO, 84)
	big.size = Vector2(600, 110)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.add_theme_color_override("font_color", Color(0.85, 0.1, 0.1))
	hint = _label(Vector2(0, 0), 22)
	hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hint.position = Vector2(-200, 70)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.size = Vector2(400, 30)
	mlabel = _label(Vector2(0, 0), 22)
	mlabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mlabel.size = Vector2(700, 60)
	mlabel.add_theme_color_override("font_color", Color(1, 0.9, 0.35))
	_banner = _label(Vector2(0, 0), 44)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.size = Vector2(1000, 60)

func _label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return l

func _layout() -> void:
	var s := root.get_viewport_rect().size
	buttons.clear()
	var b := 92.0
	if can_enter or driving:
		buttons["enter"] = Rect2(s.x - b - 24, s.y * 0.38, b, b)
	if driving:
		buttons["gas"] = Rect2(s.x - b - 24, s.y - b - 30, b, b * 1.15)
		buttons["brake"] = Rect2(s.x - b * 2 - 44, s.y - b - 30, b, b * 1.15)
	else:
		buttons["fire"] = Rect2(s.x - b * 1.2 - 24, s.y - b * 1.2 - 30, b * 1.2, b * 1.2)
		buttons["jump"] = Rect2(s.x - b * 2.2 - 44, s.y - b - 30, b, b)
		buttons["sprint"] = Rect2(s.x - b * 1.2 - 24, s.y - b * 2.3 - 50, b * 1.2, b * 0.8)
		buttons["aim"] = Rect2(s.x - b * 2.2 - 44, s.y - b * 2.2 - 46, b, b)
	buttons["weapon"] = Rect2(s.x - 170, 122, 150, 78)
	if shop_label != "" and not driving:
		buttons["shop"] = Rect2(s.x - b - 24, s.y * 0.38 - b - 16, b, b)

func banner(text: String, col: Color, secs := 3.5) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", col)
	_banner_t = secs

func _input(e: InputEvent) -> void:
	if input_block:
		return
	_layout()
	if e is InputEventScreenTouch:
		var p: Vector2 = e.position
		if e.pressed:
			for k in buttons:
				if buttons[k].has_point(p):
					_btn_ids[e.index] = k
					_press(k, true)
					return
			if p.x < root.get_viewport_rect().size.x * 0.4 and _joy_id < 0:
				_joy_id = e.index
				_joy_center = p
				joy = Vector2.ZERO
			elif _cam_id < 0:
				_cam_id = e.index
				_cam_last = p
		else:
			if _btn_ids.has(e.index):
				_press(_btn_ids[e.index], false)
				_btn_ids.erase(e.index)
			if e.index == _joy_id:
				_joy_id = -1
				joy = Vector2.ZERO
			if e.index == _cam_id:
				_cam_id = -1
		root.queue_redraw()
	elif e is InputEventScreenDrag:
		# arrastar o dedo que está no ATIRAR também gira a câmera (atirar e mirar com um dedo só)
		if _btn_ids.get(e.index, "") in ["fire", "aim"]:
			cam_drag += e.relative
			root.queue_redraw()
			return
		if e.index == _joy_id:
			var d: Vector2 = (e.position - _joy_center) / R
			joy = d.limit_length(1.0)
		elif e.index == _cam_id:
			cam_drag += e.position - _cam_last
			_cam_last = e.position
		root.queue_redraw()

func _press(k: String, on: bool) -> void:
	match k:
		"enter":
			if on: enter_pressed.emit()
		"jump":
			jump_held = on
			if on: jump_pressed.emit()
		"gas": gas = on
		"brake": brk = on
		"sprint": sprint = on
		"fire": fire = on
		"aim":
			if on: aim = not aim
		"weapon":
			if on: weapon_pressed.emit()
		"shop":
			if on: shop_pressed.emit()

func _draw_controls() -> void:
	_layout()
	var s := root.get_viewport_rect().size
	var c := _joy_center if _joy_id >= 0 else Vector2(150, s.y - 150)
	root.draw_circle(c, R, Color(0, 0, 0, 0.28))
	root.draw_arc(c, R, 0, TAU, 48, Color(1, 1, 1, 0.5), 3.0)
	root.draw_circle(c + joy * R, 32, Color(1, 1, 1, 0.75))
	if flash > 0.0:
		root.draw_rect(Rect2(Vector2.ZERO, s), Color(0.8, 0, 0, flash))
	_draw_minimap()
	_draw_bars(s)
	if crosshair:
		var cc := s * 0.5
		for v in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			root.draw_line(cc + v * 6.0, cc + v * 16.0, Color(1, 1, 1, 0.9), 2.5)
		root.draw_circle(cc, 2.0, Color(1, 0.2, 0.2))
	var font := ThemeDB.fallback_font
	for k in buttons:
		var r: Rect2 = buttons[k]
		var on: bool = k in _btn_ids.values() or (k == "aim" and aim)
		var c2 := r.get_center()
		var rad := minf(r.size.x, r.size.y) * 0.5
		var white := Color(1, 1, 1, 0.92)
		if k == "weapon":
			var rr := Rect2(r.position, r.size)
			root.draw_rect(rr, Color(0, 0, 0, 0.4))
			root.draw_rect(rr, Color(1, 1, 1, 0.55), false, 2.0)
			_icon("w_" + weapon_kind, c2 + Vector2(0, -10), 30.0, white)
			var am := weapon_text.substr(weapon_text.find("  ") + 2) if weapon_text.find("  ") >= 0 else ""
			root.draw_string(font, r.position + Vector2(0, r.size.y - 8), am, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 18, white)
			continue
		root.draw_circle(c2, rad, Color(0, 0, 0, 0.32 if not on else 0.5))
		root.draw_arc(c2, rad, 0, TAU, 40, Color(1, 0.85, 0.3, 0.95) if on else Color(1, 1, 1, 0.6), 2.5)
		var ik: String = k
		match k:
			"enter": ik = "exit" if driving else "car"
			"jump": ik = "dive" if swim_mode else "jump"
			"sprint": ik = "run"
			"gas": ik = "up" if heli else "gas"
			"brake": ik = "down" if heli else "brake"
			"shop": ik = "a_" + action_kind
		_icon(ik, c2, rad * 0.62, white)

## ícones vetoriais dos botões
func _icon(kind: String, c: Vector2, r: float, col: Color) -> void:
	var w := maxf(2.0, r * 0.13)
	match kind:
		"run":
			_figure(c, r, col, w, [Vector2(-0.35, -0.2), Vector2(0.4, -0.45)], [Vector2(0.45, 0.85), Vector2(-0.5, 0.65)], 0.18)
		"jump":
			_figure(c, r, col, w, [Vector2(-0.5, -0.85), Vector2(0.5, -0.85)], [Vector2(-0.3, 0.45), Vector2(0.35, 0.4)], 0.0)
		"dive":
			_figure(c + Vector2(0, -r * 0.2), r * 0.75, col, w, [Vector2(-0.3, 0.6), Vector2(0.3, 0.6)], [Vector2(-0.2, -0.9), Vector2(0.2, -0.9)], 0.0)
			for i in 3:
				var y := c.y + r * (0.55 + i * 0.0)
				root.draw_line(Vector2(c.x - r * 0.8 + i * r * 0.55, y), Vector2(c.x - r * 0.55 + i * r * 0.55, y - r * 0.15), col, w * 0.7)
		"aim":
			root.draw_arc(c, r * 0.7, 0, TAU, 32, col, w)
			for v in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				root.draw_line(c + v * r * 0.35, c + v * r * 1.0, col, w)
			root.draw_circle(c, w * 0.8, Color(1, 0.3, 0.3))
		"fire":
			var pts := PackedVector2Array([c + Vector2(-0.25, 0.75) * r, c + Vector2(-0.25, -0.2) * r, c + Vector2(0, -0.8) * r, c + Vector2(0.25, -0.2) * r, c + Vector2(0.25, 0.75) * r])
			root.draw_colored_polygon(pts, Color(0.95, 0.75, 0.3))
			root.draw_line(c + Vector2(-0.3, 0.55) * r, c + Vector2(0.3, 0.55) * r, Color(0.5, 0.35, 0.1), w)
		"car":
			_car_icon(c, r, col, false)
		"exit":
			root.draw_rect(Rect2(c + Vector2(-0.7, -0.8) * r, Vector2(0.8, 1.6) * r), col, false, w)
			root.draw_line(c + Vector2(-0.1, 0) * r, c + Vector2(0.9, 0) * r, col, w)
			root.draw_colored_polygon(PackedVector2Array([c + Vector2(0.95, 0) * r, c + Vector2(0.6, -0.3) * r, c + Vector2(0.6, 0.3) * r]), col)
		"gas", "up":
			root.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -0.8) * r, c + Vector2(0.7, 0.1) * r, c + Vector2(0.25, 0.1) * r, c + Vector2(0.25, 0.8) * r, c + Vector2(-0.25, 0.8) * r, c + Vector2(-0.25, 0.1) * r, c + Vector2(-0.7, 0.1) * r]), col)
		"brake", "down":
			root.draw_colored_polygon(PackedVector2Array([c + Vector2(0, 0.8) * r, c + Vector2(0.7, -0.1) * r, c + Vector2(0.25, -0.1) * r, c + Vector2(0.25, -0.8) * r, c + Vector2(-0.25, -0.8) * r, c + Vector2(-0.25, -0.1) * r, c + Vector2(-0.7, -0.1) * r]), Color(1, 0.45, 0.4) if kind == "brake" else col)
		"a_enter", "a_exit":
			root.draw_rect(Rect2(c + Vector2(-0.5, -0.85) * r, Vector2(1.0, 1.7) * r), col, false, w)
			root.draw_circle(c + Vector2(0.28, 0.05) * r, w, col)
		"a_buy":
			root.draw_rect(Rect2(c + Vector2(-0.6, -0.3) * r, Vector2(1.2, 1.1) * r), col)
			root.draw_arc(c + Vector2(0, -0.3) * r, r * 0.35, PI, TAU, 16, col, w)
			root.draw_string(ThemeDB.fallback_font, c + Vector2(-0.3, 0.55) * r, "$", HORIZONTAL_ALIGNMENT_LEFT, -1, int(r * 0.8), Color(0.1, 0.5, 0.15))
		"a_carry", "a_drop":
			root.draw_circle(c + Vector2(0, 0.2) * r, r * 0.45, col)
			for i in 4:
				root.draw_line(c + Vector2(-0.35 + i * 0.23, -0.05) * r, c + Vector2(-0.35 + i * 0.23, -0.75) * r, col, w * 1.3)
			if kind == "a_drop":
				root.draw_line(c + Vector2(0.7, -0.6) * r, c + Vector2(0.7, 0.7) * r, Color(1, 0.4, 0.4), w)
		"a_trunk":
			_car_icon(c + Vector2(0, 0.15) * r, r * 0.9, col, true)
		"w_fist":
			root.draw_circle(c + Vector2(0, 0.1) * r, r * 0.55, col)
			for i in 4:
				root.draw_circle(c + Vector2(-0.4 + i * 0.27, -0.45) * r, r * 0.17, col)
		"w_pistol":
			_poly(c, r, [[-0.8, -0.35], [0.8, -0.35], [0.8, 0.0], [-0.1, 0.0], [-0.25, 0.75], [-0.65, 0.75], [-0.5, 0.0], [-0.8, 0.0]], col)
		"w_smg":
			_poly(c, r, [[-1.0, -0.3], [0.9, -0.3], [0.9, 0.05], [0.1, 0.05], [0.1, 0.8], [-0.15, 0.8], [-0.2, 0.05], [-0.5, 0.05], [-0.6, 0.55], [-0.85, 0.55], [-0.75, 0.05], [-1.0, 0.05]], col)
		"w_shotgun":
			_poly(c, r, [[-1.3, -0.1], [1.3, -0.25], [1.3, 0.0], [-0.5, 0.1], [-0.9, 0.45], [-1.3, 0.35]], col)
		"w_rifle":
			_poly(c, r, [[-1.3, -0.2], [1.3, -0.2], [1.3, 0.02], [0.2, 0.02], [0.3, 0.6], [0.05, 0.62], [-0.1, 0.05], [-0.55, 0.05], [-1.3, 0.4]], col)
		"w_sniper":
			_poly(c, r, [[-1.4, -0.1], [1.4, -0.1], [1.4, 0.05], [-0.5, 0.08], [-1.4, 0.4]], col)
			root.draw_rect(Rect2(c + Vector2(-0.4, -0.45) * r, Vector2(0.9, 0.25) * r), col)
		"w_rpg":
			root.draw_rect(Rect2(c + Vector2(-1.3, -0.18) * r, Vector2(2.1, 0.36) * r), col)
			_poly(c, r, [[0.8, -0.35], [1.4, 0.0], [0.8, 0.35]], col)
			root.draw_rect(Rect2(c + Vector2(-0.2, 0.15) * r, Vector2(0.2, 0.5) * r), col)
		"w_grenade":
			root.draw_circle(c + Vector2(0, 0.15) * r, r * 0.55, col)
			root.draw_rect(Rect2(c + Vector2(-0.2, -0.65) * r, Vector2(0.4, 0.3) * r), col)
			root.draw_arc(c + Vector2(0.35, -0.6) * r, r * 0.2, 0, TAU, 12, col, w * 0.6)

func _poly(c: Vector2, r: float, pts: Array, col: Color) -> void:
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + Vector2(p[0], p[1]) * r * 0.75)
	root.draw_colored_polygon(out, col)

func _figure(c: Vector2, r: float, col: Color, w: float, hands: Array, feet: Array, lean: float) -> void:
	var head := c + Vector2(lean, -0.75) * r
	var neck := c + Vector2(lean * 0.8, -0.5) * r
	var hip := c + Vector2(0, 0.15) * r
	root.draw_circle(head, r * 0.2, col)
	root.draw_line(neck, hip, col, w * 1.3)
	for h in hands:
		var hp: Vector2 = c + Vector2(h.x, h.y) * r
		var el := (neck + hp) * 0.5 + Vector2(0, r * 0.1)
		root.draw_line(neck, el, col, w)
		root.draw_line(el, hp, col, w)
	for f in feet:
		var fp: Vector2 = c + Vector2(f.x, f.y) * r
		var kn := (hip + fp) * 0.5 + Vector2(r * 0.12 * signf(f.x), -r * 0.05)
		root.draw_line(hip, kn, col, w * 1.1)
		root.draw_line(kn, fp, col, w * 1.1)

func _car_icon(c: Vector2, r: float, col: Color, open_trunk: bool) -> void:
	var pts := PackedVector2Array([c + Vector2(-1.0, 0.3) * r, c + Vector2(-0.95, -0.05) * r, c + Vector2(-0.5, -0.12) * r, c + Vector2(-0.25, -0.55) * r, c + Vector2(0.35, -0.55) * r, c + Vector2(0.6, -0.12) * r, c + Vector2(1.0, -0.05) * r, c + Vector2(1.0, 0.3) * r])
	root.draw_colored_polygon(pts, col)
	root.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.18, -0.45) * r, c + Vector2(0.28, -0.45) * r, c + Vector2(0.45, -0.15) * r, c + Vector2(-0.35, -0.15) * r]), Color(0.2, 0.25, 0.3, 0.9))
	for x in [-0.55, 0.55]:
		root.draw_circle(c + Vector2(x, 0.32) * r, r * 0.22, Color(0.1, 0.1, 0.1))
		root.draw_circle(c + Vector2(x, 0.32) * r, r * 0.1, col)
	if open_trunk:
		root.draw_line(c + Vector2(-0.95, -0.05) * r, c + Vector2(-1.3, -0.6) * r, Color(1, 0.85, 0.3), maxf(2.0, r * 0.12))

func _process(_dt: float) -> void:
	var s := root.get_viewport_rect().size
	flash = maxf(0.0, flash - _dt)
	big.text = wasted
	big.position = Vector2(s.x * 0.5 - 300, s.y * 0.38)
	money.position = Vector2(s.x - 300, 46)
	stars.position = Vector2(s.x - 232, 88)
	hint.position = Vector2(s.x * 0.5 - 200, 70)
	mlabel.position = Vector2(s.x * 0.5 - 350, s.y - 70)
	var tt := ""
	if mission_timer > 0.0:
		tt = "   ⏱ %d:%02d" % [int(mission_timer) / 60, int(mission_timer) % 60]
	mlabel.text = mission_text + tt
	_banner.position = Vector2(s.x * 0.5 - 500, s.y * 0.26)
	_banner_t -= _dt
	_banner.visible = _banner_t > 0.0
	stars.modulate.a = (0.25 if int(Time.get_ticks_msec() / 300) % 2 == 0 else 1.0) if stars_blink else 1.0
	root.queue_redraw()

func take_cam_drag() -> Vector2:
	var d := cam_drag
	cam_drag = Vector2.ZERO
	return d

func _draw_bars(s: Vector2) -> void:
	var r := Rect2(s.x - 300, 14, 280, 22)
	root.draw_rect(r, Color(0, 0, 0, 0.45))
	root.draw_rect(Rect2(r.position + Vector2(3, 3), Vector2((r.size.x - 6) * clampf(hp / 100.0, 0.0, 1.0), r.size.y - 6)), Color(0.85, 0.12, 0.12))
	if breath >= 0.0:
		var rb := Rect2(s.x - 300, 52, 280, 10)
		root.draw_rect(rb, Color(0, 0, 0, 0.45))
		root.draw_rect(Rect2(rb.position + Vector2(3, 2), Vector2((rb.size.x - 6) * clampf(breath / 100.0, 0.0, 1.0), rb.size.y - 4)), Color(0.35, 0.8, 1.0))
	if armor > 0.0:
		var ra := Rect2(s.x - 300, 38, 280, 10)
		root.draw_rect(ra, Color(0, 0, 0, 0.45))
		root.draw_rect(Rect2(ra.position + Vector2(3, 2), Vector2((ra.size.x - 6) * clampf(armor / 100.0, 0.0, 1.0), ra.size.y - 4)), Color(0.75, 0.85, 0.95))

## minimapa redondo (gira com a câmera), ruas da grade, jogador e polícia
func _draw_minimap() -> void:
	var C := Vector2(118, 128)
	var R := 100.0
	var sc := R / 90.0
	root.draw_circle(C, R + 4, Color(0, 0, 0, 0.6))
	root.draw_circle(C, R, Color(0.24, 0.33, 0.22))
	var f := Vector2(sin(map_yaw), cos(map_yaw))
	var rt := Vector2(-f.y, f.x)
	var tr := func(w: Vector3) -> Vector2:
		var rel := Vector2(w.x - map_player.x, w.z - map_player.z)
		return C + Vector2(rel.dot(rt), -rel.dot(f)) * sc
	var rw := 90.0
	for c in map_roads:
		for axis in 2:
			var d: float = c - (map_player.x if axis == 0 else map_player.z)
			if absf(d) >= rw:
				continue
			var h := sqrt(rw * rw - d * d)
			var a: Vector3
			var b: Vector3
			if axis == 0:
				a = Vector3(c, 0, map_player.z - h)
				b = Vector3(c, 0, map_player.z + h)
			else:
				a = Vector3(map_player.x - h, 0, c)
				b = Vector3(map_player.x + h, 0, c)
			root.draw_line(tr.call(a), tr.call(b), Color(0.16, 0.16, 0.18), map_roadw * sc)
	for bl in map_blips:
		var bp: Vector2 = tr.call(bl.pos)
		if bp.distance_to(C) > R - 7:
			bp = C + (bp - C).normalized() * (R - 7)
		root.draw_circle(bp, 6, Color(0, 0, 0, 0.7))
		root.draw_circle(bp, 4.5, bl.col)
	if map_police != Vector3.INF:
		var pp: Vector2 = tr.call(map_police)
		if pp.distance_to(C) < R - 6:
			root.draw_circle(pp, 6, Color(0.2, 0.45, 1.0) if int(Time.get_ticks_msec() / 250) % 2 == 0 else Color(1, 0.15, 0.15))
	# seta do jogador (sempre para cima, o mapa gira)
	root.draw_colored_polygon(PackedVector2Array([C + Vector2(0, -11), C + Vector2(8, 8), C + Vector2(0, 3), C + Vector2(-8, 8)]), Color(1, 1, 1))
	root.draw_arc(C, R, 0, TAU, 64, Color(1, 1, 1, 0.8), 3.0)

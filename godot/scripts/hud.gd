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
	buttons["enter"] = Rect2(s.x - b - 24, s.y * 0.38, b, b)
	if driving:
		buttons["gas"] = Rect2(s.x - b - 24, s.y - b - 30, b, b * 1.15)
		buttons["brake"] = Rect2(s.x - b * 2 - 44, s.y - b - 30, b, b * 1.15)
	else:
		buttons["fire"] = Rect2(s.x - b * 1.2 - 24, s.y - b * 1.2 - 30, b * 1.2, b * 1.2)
		buttons["jump"] = Rect2(s.x - b * 2.2 - 44, s.y - b - 30, b, b)
		buttons["sprint"] = Rect2(s.x - b * 1.2 - 24, s.y - b * 2.3 - 50, b * 1.2, b * 0.8)
	buttons["weapon"] = Rect2(s.x - 250, 128, 230, 44)
	if shop_label != "" and not driving:
		buttons["shop"] = Rect2(s.x - b - 24, s.y * 0.38 - b - 16, b, b)

func _input(e: InputEvent) -> void:
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
			if on: jump_pressed.emit()
		"gas": gas = on
		"brake": brk = on
		"sprint": sprint = on
		"fire": fire = on
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
	var names := {"enter": "CARRO", "jump": "PULO", "sprint": "CORRER", "gas": "ACEL", "brake": "FREIO", "fire": "ATIRAR", "weapon": weapon_text, "shop": shop_label}
	var font := ThemeDB.fallback_font
	for k in buttons:
		var r: Rect2 = buttons[k]
		var on: bool = k in _btn_ids.values()
		root.draw_rect(r, Color(1, 1, 1, 0.35 if on else 0.18))
		root.draw_rect(r, Color(1, 1, 1, 0.7), false, 2.0)
		root.draw_string(font, r.position + Vector2(0, r.size.y * 0.58), names[k], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 18, Color(1, 1, 1))

func _process(_dt: float) -> void:
	var s := root.get_viewport_rect().size
	flash = maxf(0.0, flash - _dt)
	big.text = wasted
	big.position = Vector2(s.x * 0.5 - 300, s.y * 0.38)
	money.position = Vector2(s.x - 300, 46)
	stars.position = Vector2(s.x - 232, 88)
	hint.position = Vector2(s.x * 0.5 - 200, 70)
	root.queue_redraw()

func take_cam_drag() -> Vector2:
	var d := cam_drag
	cam_drag = Vector2.ZERO
	return d

func _draw_bars(s: Vector2) -> void:
	var r := Rect2(s.x - 300, 14, 280, 22)
	root.draw_rect(r, Color(0, 0, 0, 0.45))
	root.draw_rect(Rect2(r.position + Vector2(3, 3), Vector2((r.size.x - 6) * clampf(hp / 100.0, 0.0, 1.0), r.size.y - 6)), Color(0.85, 0.12, 0.12))
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
	if map_police != Vector3.INF:
		var pp: Vector2 = tr.call(map_police)
		if pp.distance_to(C) < R - 6:
			root.draw_circle(pp, 6, Color(0.2, 0.45, 1.0) if int(Time.get_ticks_msec() / 250) % 2 == 0 else Color(1, 0.15, 0.15))
	# seta do jogador (sempre para cima, o mapa gira)
	root.draw_colored_polygon(PackedVector2Array([C + Vector2(0, -11), C + Vector2(8, 8), C + Vector2(0, 3), C + Vector2(-8, 8)]), Color(1, 1, 1))
	root.draw_arc(C, R, 0, TAU, 64, Color(1, 1, 1, 0.8), 3.0)

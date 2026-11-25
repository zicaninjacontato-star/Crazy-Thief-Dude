extends CanvasLayer
## HUD e controles de toque (multitoque): joystick à esquerda, botões à direita, arrastar no meio gira a câmera.

signal enter_pressed
signal jump_pressed

var joy := Vector2.ZERO
var gas := false
var brk := false
var sprint := false
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
	stars.position = Vector2(-220, 8)
	stars.add_theme_color_override("font_color", Color(1, 0.82, 0.2))
	speed = _label(Vector2(16, 40), 26)
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
		buttons["jump"] = Rect2(s.x - b - 24, s.y - b - 30, b, b)
		buttons["sprint"] = Rect2(s.x - b * 2 - 44, s.y - b - 30, b, b)

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

func _draw_controls() -> void:
	_layout()
	var s := root.get_viewport_rect().size
	var c := _joy_center if _joy_id >= 0 else Vector2(150, s.y - 150)
	root.draw_circle(c, R, Color(0, 0, 0, 0.28))
	root.draw_arc(c, R, 0, TAU, 48, Color(1, 1, 1, 0.5), 3.0)
	root.draw_circle(c + joy * R, 32, Color(1, 1, 1, 0.75))
	var names := {"enter": "CARRO", "jump": "PULO", "sprint": "CORRER", "gas": "ACEL", "brake": "FREIO"}
	var font := ThemeDB.fallback_font
	for k in buttons:
		var r: Rect2 = buttons[k]
		var on: bool = k in _btn_ids.values()
		root.draw_rect(r, Color(1, 1, 1, 0.35 if on else 0.18))
		root.draw_rect(r, Color(1, 1, 1, 0.7), false, 2.0)
		root.draw_string(font, r.position + Vector2(0, r.size.y * 0.58), names[k], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 18, Color(1, 1, 1))

func _process(_dt: float) -> void:
	root.queue_redraw()

func take_cam_drag() -> Vector2:
	var d := cam_drag
	cam_drag = Vector2.ZERO
	return d

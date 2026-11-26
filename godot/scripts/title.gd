extends CanvasLayer
## Tela de título: aparece na hora e mostra o carregamento (a cidade é montada aos poucos por trás).
## INICIAR (libera quando termina), CONFIGURAÇÕES e SAIR.

signal start_pressed
signal settings_pressed

var _bar: ColorRect
var _bar_bg: ColorRect
var _status: Label
var _start: Button
var _cfg: Button
var _root: Control
var ready_to_play := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	# faixas diagonais (asfalto/neon) para não ficar uma tela vazia
	for k in 7:
		var st := ColorRect.new()
		st.color = Color(1.0, 0.75, 0.1, 0.06 + 0.02 * (k % 3))
		st.size = Vector2(2600, 26 + k * 6)
		st.position = Vector2(-600, 120 + k * 95)
		st.rotation = -0.22
		_root.add_child(st)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(560, 0)
	box.position = Vector2(-280, -230)
	box.add_theme_constant_override("separation", 14)
	_root.add_child(box)
	var t := Label.new()
	t.text = "CRAZY THIEF DUDE"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 58)
	t.add_theme_color_override("font_color", Color(1, 0.8, 0.15))
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	t.add_theme_constant_override("outline_size", 12)
	box.add_child(t)
	var sub := Label.new()
	sub.text = "a cidade é sua"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	box.add_child(sub)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 26)
	box.add_child(sp)
	_start = _button(box, "CARREGANDO...", func(): if ready_to_play: start_pressed.emit())
	_start.disabled = true
	_cfg = _button(box, "CONFIGURAÇÕES", func(): if ready_to_play: settings_pressed.emit())
	_cfg.disabled = true
	_button(box, "SAIR DO JOGO", func(): get_tree().quit())
	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(0, 18)
	box.add_child(sp2)
	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(1, 1, 1, 0.12)
	_bar_bg.custom_minimum_size = Vector2(560, 12)
	box.add_child(_bar_bg)
	_bar = ColorRect.new()
	_bar.color = Color(1, 0.8, 0.15)
	_bar.size = Vector2(0, 12)
	_bar_bg.add_child(_bar)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	box.add_child(_status)

func _button(box: Container, txt: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(560, 66)
	b.add_theme_font_size_override("font_size", 28)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.13, 0.17, 0.95)
	sb.set_corner_radius_all(12)
	sb.border_color = Color(1, 0.8, 0.15, 0.6)
	sb.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", sb)
	var sh: StyleBoxFlat = sb.duplicate()
	sh.bg_color = Color(0.22, 0.2, 0.12, 0.95)
	b.add_theme_stylebox_override("hover", sh)
	b.add_theme_stylebox_override("pressed", sh)
	var sd: StyleBoxFlat = sb.duplicate()
	sd.bg_color = Color(0.1, 0.1, 0.12, 0.7)
	sd.border_color = Color(0.4, 0.4, 0.4, 0.4)
	b.add_theme_stylebox_override("disabled", sd)
	b.pressed.connect(cb)
	box.add_child(b)
	return b

func progress(p: float, what: String) -> void:
	_bar.size = Vector2(_bar_bg.size.x * clampf(p, 0.0, 1.0), 12)
	_status.text = "%s · %d%%" % [what, int(p * 100.0)]
	if not ready_to_play:
		_start.text = "CARREGANDO %d%%" % int(p * 100.0)

func done() -> void:
	ready_to_play = true
	progress(1.0, "Pronto")
	_start.text = "INICIAR"
	_start.disabled = false
	_cfg.disabled = false

func show_title() -> void:
	_root.visible = true

func hide_title() -> void:
	_root.visible = false

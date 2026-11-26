extends CanvasLayer
## Celular do jogador (botão no topo da tela):
##   Câmera  — modo foto: esconde o HUD, botão de disparo; a foto vai para user://photos/
##   Galeria — miniaturas das fotos; toque para ver grande; apagar
##   Telefone — teclado: 190 polícia vem até você · 192 ambulância vem e cura · 666 (raramente atende…)
##   Uber    — pedir um carro até um destino · trabalhar de Uber com o carro em que está

const DIR := "user://photos"

var main: Node3D
var _root: Control = null
var _shot_ui: Control = null
var _num := ""
var _disp: Label = null
var _view_tex: TextureRect = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 12

func is_open() -> bool:
	return _root != null or _shot_ui != null

func close() -> void:
	if _root:
		_root.queue_free()
		_root = null
	if _shot_ui:
		_shot_ui.queue_free()
		_shot_ui = null
		main.hud.visible = true
	get_tree().paused = false

# ---------------------------------------------------------------- moldura
func _frame(title: String) -> VBoxContainer:
	if _root:
		_root.queue_free()
	get_tree().paused = true
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: close())
	_root.add_child(dim)
	var s := get_viewport().get_visible_rect().size
	var h := minf(s.y - 30.0, 700.0)
	var w := h * 0.52
	var body := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.08)
	sb.set_corner_radius_all(34)
	sb.border_color = Color(0.25, 0.25, 0.28)
	sb.set_border_width_all(6)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 30
	sb.content_margin_bottom = 26
	body.add_theme_stylebox_override("panel", sb)
	body.position = Vector2(s.x - w - 60.0, (s.y - h) * 0.5)
	body.size = Vector2(w, h)
	body.custom_minimum_size = Vector2(w, h)
	_root.add_child(body)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	body.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var clock := Label.new()
	clock.text = "%02d:%02d" % [int(main.tod), int(fmod(main.tod, 1.0) * 60.0)]
	clock.add_theme_font_size_override("font_size", 18)
	clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(clock)
	var bat := Label.new()
	bat.text = "87%"
	bat.add_theme_font_size_override("font_size", 16)
	top.add_child(bat)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 28)
	t.add_theme_color_override("font_color", Color(1, 1, 1))
	v.add_child(t)
	return v

func _app_btn(box: Container, txt: String, col: Color, cb: Callable, h := 64.0) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_font_size_override("font_size", 22)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(16)
	b.add_theme_stylebox_override("normal", sb)
	var sh: StyleBoxFlat = sb.duplicate()
	sh.bg_color = col.lightened(0.15)
	b.add_theme_stylebox_override("hover", sh)
	b.add_theme_stylebox_override("pressed", sh)
	b.pressed.connect(cb)
	box.add_child(b)
	return b

func _label(box: Container, txt: String, size := 18, col := Color(0.8, 0.8, 0.85)) -> Label:
	var l := Label.new()
	l.text = txt
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	box.add_child(l)
	return l

# ---------------------------------------------------------------- tela inicial
func open_home() -> void:
	if main.combat.dead or main.vehanim.busy():
		return
	var v := _frame("")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)
	for a in [["CÂMERA", Color(0.25, 0.25, 0.3), open_camera], ["GALERIA", Color(0.55, 0.3, 0.65), open_gallery],
			["TELEFONE", Color(0.15, 0.55, 0.25), open_dialer], ["UBER", Color(0.08, 0.08, 0.08), open_uber]]:
		var b := _app_btn(grid, a[0], a[1], a[2], 120.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	_app_btn(v, "FECHAR", Color(0.2, 0.2, 0.22), close, 52.0)

# ---------------------------------------------------------------- câmera
func open_camera() -> void:
	close()
	main.hud.visible = false
	_shot_ui = Control.new()
	_shot_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shot_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shot_ui)
	var s := get_viewport().get_visible_rect().size
	# moldura de visor
	for r in [Rect2(40, 40, 60, 6), Rect2(40, 40, 6, 60), Rect2(s.x - 100, 40, 60, 6), Rect2(s.x - 46, 40, 6, 60),
			Rect2(40, s.y - 46, 60, 6), Rect2(40, s.y - 100, 6, 60), Rect2(s.x - 100, s.y - 46, 60, 6), Rect2(s.x - 46, s.y - 100, 6, 60)]:
		var c := ColorRect.new()
		c.color = Color(1, 1, 1, 0.8)
		c.position = r.position
		c.size = r.size
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_shot_ui.add_child(c)
	var shoot := Button.new()
	shoot.text = "FOTO"
	shoot.add_theme_font_size_override("font_size", 26)
	shoot.size = Vector2(120, 120)
	shoot.position = Vector2(s.x - 170, s.y * 0.5 - 60)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.85)
	sb.set_corner_radius_all(60)
	shoot.add_theme_stylebox_override("normal", sb)
	shoot.add_theme_stylebox_override("hover", sb)
	shoot.add_theme_stylebox_override("pressed", sb)
	shoot.add_theme_color_override("font_color", Color(0.9, 0.15, 0.15))
	shoot.pressed.connect(_take_photo)
	_shot_ui.add_child(shoot)
	var back := Button.new()
	back.text = "SAIR"
	back.add_theme_font_size_override("font_size", 24)
	back.position = Vector2(60, 60)
	back.pressed.connect(close)
	_shot_ui.add_child(back)
	var gal := Button.new()
	gal.text = "Galeria"
	gal.add_theme_font_size_override("font_size", 22)
	gal.position = Vector2(s.x - 190, s.y * 0.5 + 80)
	gal.pressed.connect(func(): close(); open_gallery())
	_shot_ui.add_child(gal)

func _take_photo() -> void:
	if _shot_ui == null:
		return
	_shot_ui.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(DIR)
	var name := "%s/foto_%d.png" % [DIR, Time.get_unix_time_from_system() * 1000.0]
	img.save_png(name)
	main.audio.play("shutter", null, 0.0)
	if _shot_ui:
		_shot_ui.visible = true
		var fl := ColorRect.new()
		fl.color = Color(1, 1, 1, 0.9)
		fl.set_anchors_preset(Control.PRESET_FULL_RECT)
		fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_shot_ui.add_child(fl)
		var tw := create_tween()
		tw.tween_property(fl, "color:a", 0.0, 0.35)
		tw.tween_callback(fl.queue_free)

# ---------------------------------------------------------------- galeria
func _photos() -> Array:
	var out := []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".png"):
			out.append(DIR + "/" + f)
	out.sort()
	out.reverse()
	return out

func open_gallery() -> void:
	var v := _frame("Galeria")
	var ph := _photos()
	if ph.is_empty():
		_label(v, "Nenhuma foto ainda. Abra a Câmera e toque no botão branco.")
	else:
		var sc := ScrollContainer.new()
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		v.add_child(sc)
		if main.ui and main.ui.get("_scrolls") != null:
			main.ui._scrolls.append(sc)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		sc.add_child(grid)
		for path in ph.slice(0, 24):
			var img := Image.load_from_file(path)
			if img == null:
				continue
			img.resize(160, 90)
			var b := TextureButton.new()
			b.texture_normal = ImageTexture.create_from_image(img)
			b.ignore_texture_size = true
			b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			b.custom_minimum_size = Vector2(150, 86)
			var pth: String = path
			b.pressed.connect(func(): _view_photo(pth))
			grid.add_child(b)
	_app_btn(v, "VOLTAR", Color(0.2, 0.2, 0.22), open_home, 52.0)

func _view_photo(path: String) -> void:
	var v := _frame("Foto")
	var img := Image.load_from_file(path)
	if img:
		var tr := TextureRect.new()
		tr.texture = ImageTexture.create_from_image(img)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(tr)
	_app_btn(v, "APAGAR", Color(0.6, 0.12, 0.12), func(): DirAccess.remove_absolute(path); open_gallery(), 52.0)
	_app_btn(v, "VOLTAR", Color(0.2, 0.2, 0.22), open_gallery, 52.0)

# ---------------------------------------------------------------- telefone
func open_dialer() -> void:
	var v := _frame("Telefone")
	_disp = _label(v, _num if _num != "" else "Digite o número", 34, Color(1, 1, 1))
	_disp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	for k in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"]:
		var key: String = k
		var b := _app_btn(grid, key, Color(0.18, 0.18, 0.2), func(): _press(key), 62.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var del := _app_btn(row, "APAGAR", Color(0.3, 0.3, 0.32), func(): _num = _num.substr(0, maxi(0, _num.length() - 1)); _refresh(), 58.0)
	del.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var call := _app_btn(row, "LIGAR", Color(0.12, 0.6, 0.25), _call, 58.0)
	call.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(v, "190 Polícia · 192 Ambulância", 15, Color(0.6, 0.6, 0.65))
	_app_btn(v, "VOLTAR", Color(0.2, 0.2, 0.22), open_home, 48.0)

func _press(k: String) -> void:
	if _num.length() < 12:
		_num += k
	main.audio.play("beep", null, -6.0)
	_refresh()

func _refresh() -> void:
	if _disp:
		_disp.text = _num if _num != "" else "Digite o número"

func _call() -> void:
	var n := _num
	_num = ""
	if n == "":
		return
	close()
	main.audio.play("ring", null, -2.0)
	await get_tree().create_timer(2.4).timeout
	match n:
		"190":
			main.call_service("police")
		"192":
			main.call_service("ambulance")
		"666":
			main.call_666()
		_:
			main.audio.play("busy", null, -2.0)

# ---------------------------------------------------------------- Uber
func open_uber() -> void:
	var v := _frame("Uber")
	var m = main.missions
	if not m.ride.is_empty():
		_label(v, "Seu Uber está a caminho (%s)." % m.ride.name, 18)
		_app_btn(v, "CANCELAR CORRIDA", Color(0.55, 0.15, 0.15), func(): m.end_ride(false); close(), 54.0)
	elif main.player.vehicle == null:
		_label(v, "Para onde?", 20, Color(1, 1, 1))
		var sc := ScrollContainer.new()
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		v.add_child(sc)
		if main.ui and main.ui.get("_scrolls") != null:
			main.ui._scrolls.append(sc)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 8)
		sc.add_child(list)
		for d in _destinations():
			var dd: Array = d
			_app_btn(list, "%s  ·  ~$%d" % [dd[0], int(10.0 + main.player.global_position.distance_to(dd[1]) * 0.3)], Color(0.12, 0.12, 0.14), func(): m.request_ride(dd[1], dd[0]); close(), 52.0)
	if main.player.vehicle != null and m.active == "" and main.player.vehicle.get("kind") not in ["bus", "plane", "heli", "boat", "moto"] and main.player.vehicle.get("police") != true:
		_app_btn(v, "TRABALHAR DE UBER", Color(0.12, 0.5, 0.25), func(): m.start_fares("uber"); close(), 58.0)
	elif m.active == "uber":
		_app_btn(v, "PARAR DE TRABALHAR", Color(0.55, 0.15, 0.15), func(): m._taxi_end(); close(), 58.0)
	elif main.player.vehicle == null:
		_label(v, "Para trabalhar de Uber, entre num carro.", 15, Color(0.6, 0.6, 0.65))
	_app_btn(v, "VOLTAR", Color(0.2, 0.2, 0.22), open_home, 48.0)

func _destinations() -> Array:
	var c = main.city
	var out := []
	if main.hud.map_waypoint != Vector3.INF:
		out.append(["Ponto marcado no mapa", main.hud.map_waypoint])
	if not c.safehouse.is_empty():
		out.append(["Casa", c.safehouse.door])
	out.append(["Hospital", c.hospital_pos])
	out.append(["Delegacia", c.police_pos])
	for sh in c.shops:
		out.append([sh.name, sh.pos])
	out.append(["Praia", Vector3(main.world2.SHORE_X - 30.0, 0.3, 0.0)])
	out.append(["Aeroporto", Vector3(main.world2.AIR_X + 120.0, 0.3, 30.0)])
	return out

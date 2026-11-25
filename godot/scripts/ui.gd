extends CanvasLayer
## Menus: tela inicial, pausa, configurações, lojas (armas e carros) e save/carregamento.
## Enquanto um menu está aberto o jogo fica pausado (este nó continua rodando).

const SAVE := "user://save.json"
const SETS := "user://settings.json"
const QUAL := ["BAIXO", "MÉDIO", "ALTO"]

const GUNS := [
	{"id": "pistol", "name": "Pistola", "price": 300, "ammo": 60},
	{"id": "smg", "name": "Submetralhadora", "price": 900, "ammo": 180},
	{"id": "shotgun", "name": "Espingarda", "price": 1200, "ammo": 30},
	{"id": "ammo_pistol", "name": "Munição de pistola (+60)", "price": 80},
	{"id": "ammo_smg", "name": "Munição de submetralhadora (+150)", "price": 150},
	{"id": "ammo_shotgun", "name": "Cartuchos (+20)", "price": 120},
	{"id": "armor", "name": "Colete (100%)", "price": 250},
]
const CARS := [
	{"id": "hatch", "name": "Hatch", "price": 3000},
	{"id": "sedan", "name": "Sedã", "price": 6000},
	{"id": "pickup", "name": "Picape", "price": 9000},
	{"id": "suv", "name": "SUV", "price": 12000},
	{"id": "sport", "name": "Esportivo", "price": 45000},
]
const COLORS := [Color(0.6, 0.04, 0.04), Color(0.92, 0.92, 0.93), Color(0.05, 0.05, 0.06), Color(0.06, 0.2, 0.55), Color(0.85, 0.55, 0.05), Color(0.1, 0.35, 0.15), Color(0.45, 0.47, 0.5), Color(0.4, 0.1, 0.45)]

var main: Node3D
var settings := {"blood": true, "gore": true, "quality": 1, "volume": 80, "fps": true}
var overlay: Control
var pause_btn: Button
var car_color := 3

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_load_settings()
	pause_btn = Button.new()
	pause_btn.text = "II"
	pause_btn.add_theme_font_size_override("font_size", 26)
	pause_btn.custom_minimum_size = Vector2(64, 56)
	pause_btn.pressed.connect(show_pause)
	add_child(pause_btn)

func _process(_dt: float) -> void:
	var s := get_viewport().get_visible_rect().size
	pause_btn.position = Vector2(s.x * 0.5 - 32, 38)
	pause_btn.visible = overlay == null

# ---------------- utilidades de interface ----------------
func _open(title: String) -> VBoxContainer:
	_close()
	get_tree().paused = true
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.62)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.1, 0.94)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(22)
	sb.border_color = Color(1, 0.8, 0.2, 0.7)
	sb.set_border_width_all(2)
	pc.add_theme_stylebox_override("panel", sb)
	center.add_child(pc)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pc.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 34)
	t.add_theme_color_override("font_color", Color(1, 0.82, 0.2))
	box.add_child(t)
	# altura máxima: 85% da tela (com rolagem)
	var h := get_viewport().get_visible_rect().size.y * 0.85
	scroll.custom_minimum_size.y = minf(h, 640.0)
	return box

func _close() -> void:
	if overlay:
		overlay.queue_free()
		overlay = null
	get_tree().paused = false

func _btn(box: Container, text: String, cb: Callable, enabled := true) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(500, 60)
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(cb)
	box.add_child(b)
	return b

func _info(box: Container, text: String, color := Color(0.8, 0.8, 0.8)) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", color)
	box.add_child(l)
	return l

# ---------------- telas ----------------
func show_main_menu() -> void:
	var box := _open("CRAZY THIEF DUDE")
	_info(box, "versão Godot · fatia de teste", Color(0.6, 0.6, 0.6))
	_btn(box, "CONTINUAR", func(): main.load_game(); _close(), FileAccess.file_exists(SAVE))
	_btn(box, "NOVO JOGO", func(): main.new_game(); _close())
	_btn(box, "CONFIGURAÇÕES", func(): show_settings(show_main_menu))

func show_pause() -> void:
	var box := _open("PAUSA")
	_btn(box, "CONTINUAR", _close)
	_btn(box, "SALVAR JOGO", func(): save_game(); _info(box, "Jogo salvo!", Color(0.4, 1, 0.4)))
	_btn(box, "CONFIGURAÇÕES", func(): show_settings(show_pause))
	_btn(box, "MENU INICIAL", func(): save_game(); show_main_menu())

func show_settings(back: Callable) -> void:
	var box := _open("CONFIGURAÇÕES")
	_btn(box, "Sangue: %s" % _on(settings.blood), func(): settings.blood = not settings.blood; _apply(); show_settings(back))
	_btn(box, "Gore (membros arrancados): %s" % _on(settings.gore), func(): settings.gore = not settings.gore; _apply(); show_settings(back))
	_btn(box, "Qualidade gráfica: %s" % QUAL[settings.quality], func(): settings.quality = (settings.quality + 1) % 3; _apply(); show_settings(back))
	_btn(box, "Volume: %d%%" % settings.volume, func(): settings.volume = (settings.volume + 20) % 120; _apply(); show_settings(back))
	_btn(box, "Contador de FPS: %s" % _on(settings.fps), func(): settings.fps = not settings.fps; _apply(); show_settings(back))
	_btn(box, "VOLTAR", back)

func _on(v: bool) -> String:
	return "LIGADO" if v else "DESLIGADO"

func show_shop(kind: String) -> void:
	if kind == "guns":
		var box := _open("AMMU★NATION")
		_info(box, "Dinheiro: $%d" % main.money, Color(0.4, 1, 0.4))
		for it in GUNS:
			var owned: bool = main.combat.owned.get(it.id, false)
			var label: String = "%s — $%d" % [it.name, it.price]
			if owned and it.has("ammo"):
				label = "%s (já tem) — munição $%d" % [it.name, it.price / 4]
			_btn(box, label, func(): _buy_gun(it); show_shop("guns"), main.money >= (it.price / 4 if owned and it.has("ammo") else it.price))
		_btn(box, "SAIR", _close)
	else:
		var box := _open("CONCESSIONÁRIA")
		_info(box, "Dinheiro: $%d · cor escolhida abaixo" % main.money, Color(0.4, 1, 0.4))
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 6)
		box.add_child(row)
		for i in COLORS.size():
			var cb := Button.new()
			cb.custom_minimum_size = Vector2(52, 52)
			var st := StyleBoxFlat.new()
			st.bg_color = COLORS[i]
			st.set_corner_radius_all(26)
			if i == car_color:
				st.border_color = Color(1, 0.85, 0.2)
				st.set_border_width_all(4)
			cb.add_theme_stylebox_override("normal", st)
			cb.add_theme_stylebox_override("hover", st)
			cb.add_theme_stylebox_override("pressed", st)
			cb.pressed.connect(func(): car_color = i; show_shop("cars"))
			row.add_child(cb)
		for it in CARS:
			_btn(box, "%s — $%d" % [it.name, it.price], func(): _buy_car(it), main.money >= it.price)
		_btn(box, "SAIR", _close)

func _buy_gun(it: Dictionary) -> void:
	var c = main.combat
	var id: String = it.id
	if id.begins_with("ammo_"):
		var w := id.substr(5)
		if main.money < it.price: return
		main.money -= it.price
		c.ammo[w] = c.ammo.get(w, 0) + (60 if w == "pistol" else (150 if w == "smg" else 20))
	elif id == "armor":
		if main.money < it.price: return
		main.money -= it.price
		main.armor = 100.0
	else:
		var owned: bool = c.owned.get(id, false)
		var price: int = it.price / 4 if owned else it.price
		if main.money < price: return
		main.money -= price
		c.owned[id] = true
		c.ammo[id] = c.ammo.get(id, 0) + it.ammo
		c.weapon = id
		c._equip()
	main.audio.play("cash")
	save_game()

func _buy_car(it: Dictionary) -> void:
	if main.money < it.price:
		return
	main.money -= it.price
	var col: Color = COLORS[car_color]
	main.owned_cars.append({"kind": it.id, "color": col.to_html()})
	main.spawn_owned_car(it.id, col, true)
	main.audio.play("cash")
	save_game()
	_close()
	main._msg("%s comprado! Está na rua em frente à loja." % it.name)

# ---------------- configurações e save ----------------
func _apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.001, settings.volume / 100.0)))
	if main:
		main.apply_settings(settings)
	var f := FileAccess.open(SETS, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))

func _load_settings() -> void:
	if FileAccess.file_exists(SETS):
		var d = JSON.parse_string(FileAccess.get_file_as_string(SETS))
		if d is Dictionary:
			for k in d:
				settings[k] = d[k]
	settings.quality = int(settings.quality)
	settings.volume = int(settings.volume)

func apply_now() -> void:
	_apply()

func save_game() -> void:
	var c = main.combat
	var d := {"money": main.money, "armor": main.armor, "owned": c.owned, "ammo": c.ammo, "weapon": c.weapon, "cars": main.owned_cars}
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))

func load_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	return d if d is Dictionary else {}

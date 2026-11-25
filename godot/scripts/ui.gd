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
	{"id": "rifle", "name": "Fuzil", "price": 2500, "ammo": 150},
	{"id": "sniper", "name": "Sniper", "price": 4000, "ammo": 15},
	{"id": "rpg", "name": "Bazuca", "price": 8000, "ammo": 4},
	{"id": "grenade", "name": "Granadas (5)", "price": 600, "ammo": 5},
	{"id": "ammo_pistol", "name": "Munição de pistola (+60)", "price": 80, "pack": 60},
	{"id": "ammo_smg", "name": "Munição de submetralhadora (+150)", "price": 150, "pack": 150},
	{"id": "ammo_shotgun", "name": "Cartuchos (+20)", "price": 120, "pack": 20},
	{"id": "ammo_rifle", "name": "Munição de fuzil (+120)", "price": 300, "pack": 120},
	{"id": "ammo_sniper", "name": "Munição de sniper (+10)", "price": 400, "pack": 10},
	{"id": "ammo_rpg", "name": "Foguetes (+3)", "price": 1500, "pack": 3},
	{"id": "armor", "name": "Colete (100%)", "price": 250},
]
const CARS := [
	{"id": "moto", "name": "Moto", "price": 1500},
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
	pause_btn.visible = overlay == null and wheel == null

# ---------------- utilidades de interface ----------------
func _open(title: String, side := false) -> VBoxContainer:
	_close()
	get_tree().paused = true
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.15 if side else 0.62)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var center: Container
	if side:
		# painel à esquerda (o personagem aparece à direita, para provar roupas)
		center = MarginContainer.new()
		for k in ["margin_left", "margin_top", "margin_bottom"]:
			center.add_theme_constant_override(k, 14)
	else:
		center = CenterContainer.new()
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
	pc.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480 if side else 560, 0)
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
	var h := get_viewport().get_visible_rect().size.y * (0.9 if side else 0.85)
	scroll.custom_minimum_size.y = minf(h, 640.0)
	return box

func _close() -> void:
	if wheel:
		_close_wheel()
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

# ---------------- roleta de armas (câmera lenta enquanto aberta) ----------------
var wheel: Control

func show_wheel() -> void:
	if wheel or overlay:
		return
	var W := preload("res://scripts/weapons.gd")
	Engine.time_scale = 0.15
	main.hud.input_block = true
	main.hud.fire = false
	wheel = Control.new()
	wheel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(wheel)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.35)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _close_wheel())
	wheel.add_child(bg)
	var s := get_viewport().get_visible_rect().size
	var c := s * 0.5
	var list: Array = W.ORDER
	var R := minf(s.y * 0.34, 230.0)
	for i in list.size():
		var w: String = list[i]
		var a := -PI * 0.5 + TAU * i / list.size()
		var b := Button.new()
		var has: bool = main.combat.owned.get(w, false)
		var am: int = main.combat.ammo.get(w, 0)
		b.text = W.DATA[w].name + ("" if w == "fist" else "\n%d" % am)
		b.disabled = not has or (w != "fist" and am <= 0)
		b.custom_minimum_size = Vector2(150, 90)
		b.size = Vector2(150, 90)
		b.position = c + Vector2(cos(a), sin(a)) * R - b.size * 0.5
		b.add_theme_font_size_override("font_size", 20)
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.1, 0.1, 0.12, 0.85) if w != main.combat.weapon else Color(0.75, 0.55, 0.1, 0.9)
		st.set_corner_radius_all(45)
		st.border_color = Color(1, 0.85, 0.3, 0.8)
		st.set_border_width_all(2)
		b.add_theme_stylebox_override("normal", st)
		b.pressed.connect(func(): main.combat.select(w); _close_wheel())
		wheel.add_child(b)
	var lb := Label.new()
	lb.text = "ARMAS"
	lb.add_theme_font_size_override("font_size", 30)
	lb.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	lb.position = c - Vector2(45, 20)
	wheel.add_child(lb)

func _close_wheel() -> void:
	if wheel:
		wheel.queue_free()
		wheel = null
	Engine.time_scale = 1.0
	main.hud.input_block = false

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
	_btn(box, "CÓDIGOS", show_cheats)
	_btn(box, "MENU INICIAL", func(): save_game(); show_main_menu())

## códigos (por enquanto só liga/desliga; os nomes dos códigos virão depois)
func show_cheats() -> void:
	var box := _open("CÓDIGOS")
	_btn(box, "Vida infinita: %s" % _on(main.god), func(): main.god = not main.god; show_cheats())
	_btn(box, "Muito dinheiro (+$99.999)", func(): main.money += 99999; main.audio.play("cash"); show_cheats())
	_info(box, "Dinheiro: $%d" % main.money, Color(0.4, 1, 0.4))
	_btn(box, "VOLTAR", show_pause)

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
	if kind == "clothes":
		_clothes_begin()
		return
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

# ---------------- loja de roupas (prova ao vivo no personagem) ----------------
const SHIRTS := ["216b42", "f2f2f0", "141416", "a3141a", "1d4fa8", "e0a020", "6b2c80", "d96aa0", "4f6b2a", "8a8f96"]
const PANTS := ["1f2945", "141416", "4a4f57", "6b5a3e", "2f4a2a", "e8e4da"]
const JACKETS := ["", "141416", "5a3a22", "263a5c", "7a1a1a", "3d4a2f", "b8b8b4"]
const HATC := ["1a1a1f", "a3141a", "1d4fa8", "e8e4da", "2f4a2a", "e0a020"]
const HAIRS := ["291a0f", "0d0d0d", "6b4a2a", "c9a25a", "8a8a8a", "9a3a1a"]
const CPRICE := {"shirt": 60, "pants": 80, "jacket": 220, "hat": 50, "hat_c": 0, "glasses": 40, "hair": 30}
var _orig_outfit := {}
var _cam_saved := Transform3D()

func _clothes_begin() -> void:
	var p = main.player
	_orig_outfit = p.outfit.duplicate()
	_cam_saved = main.cam.global_transform
	_clothes_cam()
	_show_clothes()

## câmera de frente para o jogador, com ele no lado direito da tela
func _clothes_cam() -> void:
	var p = main.player
	var c: Camera3D = main.cam
	var f: Vector3 = c.global_position - p.global_position
	f.y = 0
	f = f.normalized() if f.length() > 0.1 else Vector3.BACK
	p.body.rotation.y = atan2(f.x, f.z)
	var base: Vector3 = p.global_position + Vector3(0, 1.0, 0)
	c.global_position = base + f * 3.1 + Vector3(0, 0.35, 0)
	var right: Vector3 = (-f).cross(Vector3.UP).normalized()
	c.look_at(base - right * 1.0, Vector3.UP)

func _outfit_cost() -> int:
	var o: Dictionary = main.player.outfit
	var t := 0
	for k in CPRICE:
		if str(o[k]) != str(_orig_outfit[k]):
			t += CPRICE[k]
	if str(o.hat_c) != str(_orig_outfit.hat_c) and int(o.hat) != 0 and str(o.hat) == str(_orig_outfit.hat):
		t += CPRICE.hat
	return t

func _set_outfit(k: String, v) -> void:
	var p = main.player
	p.outfit[k] = v
	p.rebuild_body()
	main.combat._equip()
	_clothes_cam()
	_show_clothes()

func _swatches(box: Container, title: String, key: String, list: Array) -> void:
	_info(box, title, Color(0.95, 0.85, 0.5))
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	box.add_child(row)
	for hx in list:
		var b := Button.new()
		b.custom_minimum_size = Vector2(44, 44)
		var st := StyleBoxFlat.new()
		st.set_corner_radius_all(22)
		if hx == "":
			st.bg_color = Color(0.2, 0.2, 0.22)
			b.text = "✕"
		else:
			st.bg_color = Color.html(hx)
		if str(main.player.outfit[key]) == hx:
			st.border_color = Color(1, 0.85, 0.2)
			st.set_border_width_all(4)
		for sn in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(sn, st)
		b.pressed.connect(func(): _set_outfit(key, hx))
		row.add_child(b)

func _opts(box: Container, title: String, key: String, names: Array, values: Array) -> void:
	_info(box, title, Color(0.95, 0.85, 0.5))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	for i in names.size():
		var b := Button.new()
		b.text = names[i]
		b.toggle_mode = true
		b.button_pressed = str(main.player.outfit[key]) == str(values[i])
		b.custom_minimum_size = Vector2(120, 46)
		b.add_theme_font_size_override("font_size", 20)
		var v = values[i]
		b.pressed.connect(func(): _set_outfit(key, v))
		row.add_child(b)

func _show_clothes() -> void:
	var box := _open("LOJA DE ROUPAS", true)
	var cost := _outfit_cost()
	_info(box, "Dinheiro: $%d · Total: $%d" % [main.money, cost], Color(0.4, 1, 0.4) if main.money >= cost else Color(1, 0.4, 0.4))
	_swatches(box, "Camiseta ($%d)" % CPRICE.shirt, "shirt", SHIRTS)
	_swatches(box, "Calça ($%d)" % CPRICE.pants, "pants", PANTS)
	_swatches(box, "Jaqueta ($%d)" % CPRICE.jacket, "jacket", JACKETS)
	_opts(box, "Chapéu ($%d)" % CPRICE.hat, "hat", ["Nenhum", "Boné", "Touca"], [0, 1, 2])
	if int(main.player.outfit.hat) != 0:
		_swatches(box, "Cor do chapéu", "hat_c", HATC)
	_opts(box, "Óculos escuros ($%d)" % CPRICE.glasses, "glasses", ["Sem", "Com"], [false, true])
	_swatches(box, "Cabelo ($%d)" % CPRICE.hair, "hair", HAIRS)
	var buy := _btn(box, "COMPRAR ($%d)" % cost, _clothes_buy, cost > 0 and main.money >= cost)
	buy.custom_minimum_size.x = 420
	var ex := _btn(box, "SAIR SEM COMPRAR" if cost > 0 else "SAIR", _clothes_exit)
	ex.custom_minimum_size.x = 420

func _clothes_buy() -> void:
	var cost := _outfit_cost()
	if main.money < cost:
		return
	main.money -= cost
	_orig_outfit = main.player.outfit.duplicate()
	main.audio.play("cash")
	save_game()
	_show_clothes()

func _clothes_exit() -> void:
	var p = main.player
	if str(p.outfit) != str(_orig_outfit):
		p.outfit = _orig_outfit.duplicate()
		p.rebuild_body()
		main.combat._equip()
	main.cam.global_transform = _cam_saved
	_close()

func _buy_gun(it: Dictionary) -> void:
	var c = main.combat
	var id: String = it.id
	if id.begins_with("ammo_"):
		var w := id.substr(5)
		if main.money < it.price: return
		main.money -= it.price
		c.ammo[w] = c.ammo.get(w, 0) + int(it.pack)
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
	var d := {"money": main.money, "armor": main.armor, "owned": c.owned, "ammo": c.ammo, "weapon": c.weapon, "cars": main.owned_cars, "outfit": main.player.outfit, "time": main.tod}
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))

func load_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	return d if d is Dictionary else {}

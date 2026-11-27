extends CanvasLayer
## Menus: tela inicial, pausa, configurações, lojas (armas e carros) e save/carregamento.
## Enquanto um menu está aberto o jogo fica pausado (este nó continua rodando).

const SAVE := "user://save.json"           # save antigo (vira o slot 1)
const SLOTS := 3
var slot := 1
func slot_path(n: int) -> String:
	return "user://save_slot%d.json" % n
## informações de um slot para a lista (vazio = {})
func slot_info(n: int) -> Dictionary:
	var p := slot_path(n)
	if n == 1 and not FileAccess.file_exists(p) and FileAccess.file_exists(SAVE):
		p = SAVE
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {}
func last_slot() -> int:
	var best := 0
	var bt := -1.0
	for n in range(1, SLOTS + 1):
		var d := slot_info(n)
		if not d.is_empty() and float(d.get("saved_at", 0.0)) >= bt:
			bt = float(d.get("saved_at", 0.0))
			best = n
	return best
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
	{"id": "bike", "name": "Bicicleta", "price": 300},
	{"id": "moto", "name": "Moto", "price": 1500},
	{"id": "sportbike", "name": "Moto esportiva", "price": 7000},
	{"id": "hatch", "name": "Hatch", "price": 3000},
	{"id": "sedan", "name": "Sedã", "price": 6000},
	{"id": "pickup", "name": "Picape", "price": 9000},
	{"id": "suv", "name": "SUV", "price": 12000},
	{"id": "van", "name": "Van", "price": 8000},
	{"id": "offroad", "name": "Fora de estrada", "price": 15000},
	{"id": "truck", "name": "Caminhão", "price": 20000},
	{"id": "sport", "name": "Esportivo", "price": 45000},
	{"id": "super", "name": "Supercarro", "price": 90000},
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
	_scroll_inertia(_dt)
	var s := get_viewport().get_visible_rect().size
	pause_btn.position = Vector2(s.x * 0.5 - 32, 38)
	pause_btn.visible = overlay == null and wheel == null

# ---------------- utilidades de interface ----------------
## rolagem por arrasto (dedo ou mouse) nas listas: passou de 12 px na vertical = rolando; o botão
## onde o dedo começou é "desarmado" (movimento falso fora dele) e não dispara ao soltar
var _scrolls: Array = []
var _sc_cur: ScrollContainer = null
var _sc_y0 := 0.0
var _sc_s0 := 0.0
var _sc_drag := false
var _sc_vel := 0.0
var _sc_last := 0.0
func _input(ev: InputEvent) -> void:
	_scrolls = _scrolls.filter(func(x): return is_instance_valid(x) and x.is_visible_in_tree())
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_sc_cur = null
			_sc_drag = false
			_sc_vel = 0.0
			for sc in _scrolls:
				if sc.get_global_rect().has_point(ev.position):
					_sc_cur = sc
					_sc_y0 = ev.position.y
					_sc_s0 = sc.scroll_vertical
					_sc_last = ev.position.y
		else:
			_sc_cur = null if not _sc_drag else _sc_cur
			_sc_drag = false
	elif ev is InputEventMouseMotion and _sc_cur != null and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT):
		if ev.position.x < -5000.0:
			return                      # o nosso evento falso
		var dy: float = ev.position.y - _sc_y0
		if not _sc_drag and absf(dy) > 12.0:
			_sc_drag = true
			var fake := InputEventMouseMotion.new()
			fake.position = Vector2(-9999, -9999)
			fake.global_position = fake.position
			fake.button_mask = MOUSE_BUTTON_MASK_LEFT
			Input.parse_input_event(fake)
		if _sc_drag and is_instance_valid(_sc_cur):
			_sc_cur.scroll_vertical = int(_sc_s0 - dy)
			_sc_vel = (_sc_last - ev.position.y) / maxf(get_process_delta_time(), 0.008)
			_sc_last = ev.position.y
			get_viewport().set_input_as_handled()

func _scroll_inertia(dt: float) -> void:
	if _sc_drag or _sc_cur == null or not is_instance_valid(_sc_cur) or absf(_sc_vel) < 20.0:
		return
	_sc_cur.scroll_vertical += int(_sc_vel * dt)
	_sc_vel *= pow(0.04, dt)

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
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER    # rola arrastando o dedo
	pc.add_child(scroll)
	_scrolls.append(scroll)
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

# ---------------- tela de carregamento cinematográfica (entrar/sair das lojas) ----------------
var _cine: ColorRect
func cinematic(title: String, sub: String, mid: Callable) -> void:
	if _cine:
		return
	_cine = ColorRect.new()
	_cine.color = Color(0, 0, 0, 1)
	_cine.modulate.a = 0.0
	_cine.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cine.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_cine)
	var s := get_viewport().get_visible_rect().size
	for k in 2:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0)
		bar.size = Vector2(s.x, s.y * 0.12)
		bar.position = Vector2(0, 0 if k == 0 else s.y * 0.88)
		_cine.add_child(bar)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 52)
	t.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	t.add_theme_constant_override("outline_size", 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size = Vector2(s.x, 70)
	t.position = Vector2(0, s.y * 0.42)
	t.modulate.a = 0.0
	_cine.add_child(t)
	var st := Label.new()
	st.text = sub
	st.add_theme_font_size_override("font_size", 22)
	st.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.size = Vector2(s.x, 40)
	st.position = Vector2(0, s.y * 0.42 + 70)
	st.modulate.a = 0.0
	_cine.add_child(st)
	main.hud.input_block = true
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_cine, "modulate:a", 1.0, 0.45)
	tw.parallel().tween_property(t, "modulate:a", 1.0, 0.45)
	tw.parallel().tween_property(st, "modulate:a", 1.0, 0.45)
	tw.tween_callback(mid)
	tw.tween_interval(0.7)
	tw.tween_property(t, "modulate:a", 0.0, 0.3)
	tw.parallel().tween_property(st, "modulate:a", 0.0, 0.3)
	tw.tween_property(_cine, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func(): _cine.queue_free(); _cine = null; main.hud.input_block = false)

## botão de renascer (tela de morte)
var _resp: Control
func show_respawn(text: String, cb: Callable) -> void:
	hide_respawn()
	var s := get_viewport().get_visible_rect().size
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 30)
	b.custom_minimum_size = Vector2(420, 80)
	b.position = Vector2(s.x * 0.5 - 210, s.y * 0.66)
	b.pressed.connect(cb)
	b.modulate.a = 0.0
	add_child(b)
	_resp = b
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(b, "modulate:a", 1.0, 0.5)

func hide_respawn() -> void:
	if _resp and is_instance_valid(_resp):
		_resp.queue_free()
	_resp = null

## tela de carregamento (morte, prisão): esconde o mundo sendo refeito
var _load: Control
func loading(on: bool, text := "Carregando...") -> void:
	if _load and is_instance_valid(_load):
		_load.queue_free()
		_load = null
	if not on:
		return
	var s := get_viewport().get_visible_rect().size
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.04)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	var t := Label.new()
	t.text = text
	t.add_theme_font_size_override("font_size", 34)
	t.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size = Vector2(s.x, 60)
	t.position = Vector2(0, s.y * 0.44)
	bg.add_child(t)
	var tip := Label.new()
	var tips: Array = preload("res://scripts/title.gd").TIPS
	tip.text = "Dica: " + tips[randi() % tips.size()]
	# troca de dica a cada 3 s enquanto carrega
	var tm := Timer.new()
	tm.wait_time = 3.0
	tm.process_mode = Node.PROCESS_MODE_ALWAYS
	tm.autostart = true
	tm.timeout.connect(func(): tip.text = "Dica: " + tips[randi() % tips.size()])
	bg.add_child(tm)
	tip.add_theme_font_size_override("font_size", 20)
	tip.add_theme_color_override("font_color", Color(0.7, 0.7, 0.72))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.size = Vector2(s.x, 40)
	tip.position = Vector2(0, s.y * 0.44 + 70)
	bg.add_child(tip)
	_load = bg

## faixas pretas de cinema (sem escurecer a tela) com um título
var _lb: Control
func letterbox(on: bool, title := "") -> void:
	if _lb:
		_lb.queue_free()
		_lb = null
	if not on:
		return
	_lb = Control.new()
	_lb.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lb)
	var s := get_viewport().get_visible_rect().size
	for k in 2:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0)
		bar.size = Vector2(s.x, s.y * 0.13)
		bar.position = Vector2(0, 0 if k == 0 else s.y * 0.87)
		_lb.add_child(bar)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 40)
	t.add_theme_color_override("font_color", Color(0.9, 0.85, 0.8))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size = Vector2(s.x, 60)
	t.position = Vector2(0, s.y * 0.9)
	_lb.add_child(t)

# ---------------- telas ----------------
## tela de missão: nome, descrição e opções [[texto, habilitado, Callable], ...]
func show_mission_offer(title: String, desc: String, opts: Array) -> void:
	var box := _open(title)
	var l := _info(box, desc)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(500, 0)
	for o in opts:
		var cb: Callable = o[2]
		_btn(box, o[0], func(): _close(); cb.call(), o[1])
	_btn(box, "AGORA NÃO", _close)

## menu do racha: voltar ao último ponto, recomeçar ou desistir
func show_race_menu() -> void:
	var box := _open("RACHA")
	_btn(box, "VOLTAR AO ÚLTIMO PONTO", func(): _close(); main.missions.race_to_checkpoint())
	_btn(box, "RECOMEÇAR DO INÍCIO", func(): _close(); main.missions.race_restart())
	_btn(box, "DESISTIR", func(): _close(); main.missions.fail("Você desistiu"))
	_btn(box, "CONTINUAR", _close)

func show_main_menu() -> void:
	var box := _open("CRAZY THIEF DUDE")
	_info(box, "versão Godot · fatia de teste", Color(0.6, 0.6, 0.6))
	var ls := last_slot()
	_btn(box, "CONTINUAR" + (" (slot %d)" % ls if ls > 0 else ""), func(): slot = ls; main.load_game(); _close(), ls > 0)
	_btn(box, "CARREGAR JOGO", func(): show_slots("load"), ls > 0)
	_btn(box, "NOVO JOGO", func(): show_slots("new"))
	_btn(box, "CONFIGURAÇÕES", func(): show_settings(show_main_menu))

## slots de save: carregar, novo jogo (escolhe onde salvar) ou salvar
func show_slots(mode: String) -> void:
	var box := _open({"load": "CARREGAR JOGO", "new": "NOVO JOGO · escolha o slot", "save": "SALVAR JOGO"}[mode])
	for n in range(1, SLOTS + 1):
		var d := slot_info(n)
		var txt := "SLOT %d · vazio" % n
		if not d.is_empty():
			var dt := Time.get_datetime_dict_from_unix_time(int(d.get("saved_at", 0.0)))
			var pm := int(d.get("play_s", 0.0)) / 60
			txt = "SLOT %d · $%d · %dh%02d de jogo · salvo %02d/%02d %02d:%02d" % [n, int(d.get("money", 0)), pm / 60, pm % 60, dt.day, dt.month, dt.hour, dt.minute]
		var nn := n
		match mode:
			"load":
				_btn(box, txt, func(): slot = nn; main.load_game(); _close(), not d.is_empty())
			"new":
				_btn(box, txt + ("  (será apagado)" if not d.is_empty() else ""), func(): slot = nn; main.new_game(); _close())
			"save":
				_btn(box, txt, func(): slot = nn; save_game(); show_slots("save"))
	if mode == "save":
		_info(box, "Jogando no slot %d" % slot, Color(0.4, 1, 0.4))
	_btn(box, "VOLTAR", show_pause if mode == "save" else show_main_menu)

func show_pause() -> void:
	var box := _open("PAUSA")
	_btn(box, "CONTINUAR", _close)
	_btn(box, "SALVAR JOGO (slot %d)" % slot, func(): save_game(); _info(box, "Jogo salvo!", Color(0.4, 1, 0.4)))
	_btn(box, "SALVAR EM OUTRO SLOT", func(): show_slots("save"))
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
	_btn(box, "Câmera: %s" % CAMS[clampi(int(settings.get("cam", 1)), 0, 2)], func(): settings.cam = (clampi(int(settings.get("cam", 1)), 0, 2) + 1) % 3; _apply(); show_settings(back))
	_btn(box, "EDITAR HUD (posição e tamanho dos botões)", func(): open_hud_editor(back))
	_btn(box, "VOLTAR", back)

const CAMS := ["Perto", "Média", "Longe", "Primeira pessoa"]

# ---------------------------------------------------------------- editor de HUD
var _hed: Control
var _hed_back: Callable
var _hed_drive := false
func open_hud_editor(back: Callable) -> void:
	_close()
	_hed_back = back
	get_tree().paused = true
	var h = main.hud
	h.edit_mode = true
	h.edit_sel = ""
	_hed_flags()
	var s := get_viewport().get_visible_rect().size
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.1, 0.92)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(10)
	sb.border_color = Color(1, 0.8, 0.2, 0.8)
	sb.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", sb)
	add_child(p)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	p.add_child(row)
	var mk := func(t: String, cb: Callable) -> void:
		var b := Button.new()
		b.text = t
		b.custom_minimum_size = Vector2(0, 54)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(cb)
		row.add_child(b)
	mk.call("A pé / Dirigindo", func(): _hed_drive = not _hed_drive; _hed_flags())
	mk.call("  −  ", func(): h.edit_scale(0.9))
	mk.call("  +  ", func(): h.edit_scale(1.1))
	var tb := Button.new()
	tb.text = "Transparência %d%%" % int(round((1.0 - h.hud_alpha) * 100.0))
	tb.custom_minimum_size = Vector2(0, 54)
	tb.add_theme_font_size_override("font_size", 20)
	tb.pressed.connect(func():
		h.hud_alpha = 1.0 if h.hud_alpha <= 0.45 else h.hud_alpha - 0.15
		h.root.modulate.a = h.hud_alpha
		tb.text = "Transparência %d%%" % int(round((1.0 - h.hud_alpha) * 100.0)))
	row.add_child(tb)
	mk.call("Restaurar", func(): h.layout_ovr = {}; h.hud_alpha = 1.0; h.root.modulate.a = 1.0; h.root.queue_redraw())
	mk.call("SALVAR", func(): _hed_close(true))
	mk.call("Cancelar", func(): _hed_close(false))
	p.position = Vector2(s.x * 0.5 - 430, 8)
	_hed = p
	_hed_saved = [h.layout_ovr.duplicate(true), h.hud_alpha]
	await get_tree().process_frame
	if is_instance_valid(p):
		p.position.x = s.x * 0.5 - p.size.x * 0.5
		h.edit_block = Rect2(p.position, p.size)

var _hed_saved := []
## mostra todos os botões possíveis do modo escolhido (a pé ou dirigindo) para poder arrumar
func _hed_flags() -> void:
	var h = main.hud
	h.driving = _hed_drive
	h.can_enter = true
	h.armed = _hed_drive
	h.siren_avail = _hed_drive
	h.rob_avail = not _hed_drive
	h.hostage_on = false
	h.swim_mode = false
	h.shop_label = "LOJA"
	h.root.queue_redraw()

func _hed_close(save: bool) -> void:
	var h = main.hud
	if save:
		settings["hud_layout"] = h.layout_ovr.duplicate(true)
		settings["hud_alpha"] = h.hud_alpha
		_apply()
	else:
		h.layout_ovr = _hed_saved[0]
		h.hud_alpha = _hed_saved[1]
		h.root.modulate.a = h.hud_alpha
	h.edit_mode = false
	h.edit_sel = ""
	h.edit_block = Rect2()
	if _hed and is_instance_valid(_hed):
		_hed.queue_free()
	_hed = null
	get_tree().paused = false
	if _hed_back.is_valid():
		_hed_back.call()

func _on(v: bool) -> String:
	return "LIGADO" if v else "DESLIGADO"

func show_shop(kind: String) -> void:
	if kind == "clothes":
		_clothes_begin()
		return
	if kind == "guns":
		show_guns("pistol")
		return
	if kind == "guns_old":
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
		c.add_ammo(w, int(it.pack))
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
		c.add_ammo(id, it.ammo)
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
	main._msg("%s comprado! Está na rua em frente à loja." % it.name, true)

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
	var d := {"money": main.money, "armor": main.armor, "owned": c.owned, "ammo": c.ammo, "weapon": c.weapon, "cars": main.owned_cars, "outfit": main.player.outfit, "time": main.tod,
		"saved_at": Time.get_unix_time_from_system(), "play_s": main.play_s}
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))

func load_save() -> Dictionary:
	return slot_info(slot)

# ---------------------------------------------------------------- casa segura: dormir (salva e passa o tempo)
func show_sleep() -> void:
	var box := _open("DORMIR")
	_info(box, "Dormir recupera a vida e salva o jogo. Acordar:", Color(0.85, 0.9, 1.0))
	for opt in [["De manhã (07:00)", 7.0], ["À tarde (14:00)", 14.0], ["À noite (20:00)", 20.0]]:
		var hour: float = opt[1]
		_btn(box, opt[0], func(): _close(); main.sleep_until(hour))
	_btn(box, "CANCELAR", _close)

# ---------------------------------------------------------------- oficina tuning: pintura e conserto
const TUNE_COLORS := [["Preto", Color(0.03, 0.03, 0.035)], ["Branco", Color(0.92, 0.92, 0.93)], ["Vermelho", Color(0.7, 0.03, 0.03)], ["Azul", Color(0.06, 0.2, 0.6)],
	["Verde", Color(0.05, 0.4, 0.15)], ["Amarelo", Color(0.95, 0.75, 0.05)], ["Laranja", Color(0.95, 0.4, 0.05)], ["Roxo", Color(0.35, 0.08, 0.5)], ["Prata", Color(0.6, 0.62, 0.65)], ["Rosa", Color(0.95, 0.4, 0.65)]]
const TN := preload("res://scripts/tuning.gd")
var _tune_old := {}
var _tune_new := {}
var _tune_cat := ""
var _tune_car = null

## abre a oficina (chamado pelo main quando o carro termina de entrar)
func show_tuning() -> void:
	var c = main.player.vehicle
	if c == null:
		return
	_tune_car = c
	_tune_old = c.mods.duplicate()
	_tune_new = c.mods.duplicate()
	_tune_cat = ""
	_tune_panel()

func _tune_panel() -> void:
	var c = _tune_car
	var box := _open("OFICINA TUNING", true)
	var cost: int = TN.cost(_tune_old, _tune_new)
	_info(box, "Dinheiro: $%d   ·   Alterações: $%d" % [main.money, cost], Color(0.4, 1, 0.4) if main.money >= cost else Color(1, 0.4, 0.3))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	for d in [["◀ Girar", -0.6], ["Girar ▶", 0.6]]:
		var b := Button.new()
		b.text = d[0]
		b.custom_minimum_size = Vector2(150, 54)
		b.add_theme_font_size_override("font_size", 22)
		var da: float = d[1]
		b.pressed.connect(func(): main.tune_cam(da))
		row.add_child(b)
	var hpv: float = c.get("hp") if c.get("hp") != null else 100.0
	var rb := Button.new()
	rb.text = "Consertar $150 (%d%%)" % int(clampf(hpv, 0.0, 100.0))
	rb.custom_minimum_size = Vector2(180, 54)
	rb.add_theme_font_size_override("font_size", 18)
	rb.disabled = main.money < 150 or hpv >= 99.9
	rb.pressed.connect(func():
		if main.money >= 150:
			main.money -= 150
			main.repair_vehicle(c)
			main.audio.play("cash")
			_tune_panel())
	row.add_child(rb)
	for cat in TN.cats_for(c):
		var info: Dictionary = TN.CATS[cat]
		var cur = _tune_new.get(cat, 0 if cat != "paint" else "")
		var label: String = info.name
		if cat != "paint":
			label += ":  " + info.opts[int(cur)]
		var b := _btn(box, ("▼ " if _tune_cat == cat else "▶ ") + label, func():
			_tune_cat = "" if _tune_cat == cat else cat
			_tune_panel())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(440, 52)
		b.add_theme_font_size_override("font_size", 21)
		if _tune_cat != cat:
			continue
		if cat == "paint":
			var grid := GridContainer.new()
			grid.columns = 5
			grid.add_theme_constant_override("h_separation", 8)
			grid.add_theme_constant_override("v_separation", 8)
			box.add_child(grid)
			for tc in TUNE_COLORS:
				var pb := Button.new()
				pb.custom_minimum_size = Vector2(80, 54)
				var sb := StyleBoxFlat.new()
				sb.bg_color = tc[1]
				sb.set_corner_radius_all(8)
				sb.border_color = Color(1, 0.85, 0.3) if str(cur) == tc[1].to_html() else Color(1, 1, 1, 0.5)
				sb.set_border_width_all(4 if str(cur) == tc[1].to_html() else 2)
				for st in ["normal", "hover", "pressed"]:
					pb.add_theme_stylebox_override(st, sb)
				var col: Color = tc[1]
				pb.pressed.connect(func(): _tune_set("paint", col.to_html()))
				grid.add_child(pb)
			_info(box, "Pintura: $%d" % TN.price("paint", 0), Color(1, 0.85, 0.4))
			_tune_buy_btn(box, cat)
			continue
		for i in info.opts.size():
			var owned: bool = int(_tune_old.get(cat, 0)) == i
			var txt: String = ("   ✓ " if int(cur) == i else "      ") + info.opts[i]
			if i > 0 and not owned:
				txt += "   $%d" % TN.price(cat, i)
			elif owned:
				txt += "   (instalado)"
			var ob := _btn(box, txt, func(): _tune_set(cat, i))
			ob.alignment = HORIZONTAL_ALIGNMENT_LEFT
			ob.custom_minimum_size = Vector2(440, 46)
			ob.add_theme_font_size_override("font_size", 19)
		_tune_buy_btn(box, cat)
	_btn(box, "COMPRAR TUDO ($%d)" % cost, func():
		var cc: int = TN.cost(_tune_old, _tune_new)
		if main.money >= cc:
			main.money -= cc
			_tune_old = _tune_new.duplicate()
			main.save_mods(_tune_car)
			if cc > 0:
				main.audio.play("cash")
			_tune_panel(), cost > 0 and main.money >= cost)
	_btn(box, "SAIR DA OFICINA (desfaz o que não foi comprado)", func():
		TN.apply(_tune_car, _tune_old)
		_close()
		main.end_tuning())

## escolher uma opção só mostra no carro (prévia); este botão compra só a peça desta categoria
func _tune_buy_btn(box: VBoxContainer, cat: String) -> void:
	var cur = _tune_new.get(cat, 0 if cat != "paint" else "")
	var old = _tune_old.get(cat, 0 if cat != "paint" else "")
	if str(cur) == str(old):
		_info(box, "Toque numa opção para ver no carro antes de comprar", Color(0.7, 0.7, 0.72))
		return
	var p: int = TN.price(cat, cur) if cat != "paint" else TN.price("paint", 0)
	var b := _btn(box, "COMPRAR ESTA PEÇA ($%d)" % p, func():
		if main.money >= p:
			main.money -= p
			_tune_old[cat] = cur
			main.save_mods(_tune_car)
			if p > 0:
				main.audio.play("cash")
			_tune_panel(), main.money >= p)
	b.add_theme_color_override("font_color", Color(0.4, 1, 0.4))

func _tune_set(cat: String, v) -> void:
	if _tune_car == null or not is_instance_valid(_tune_car):
		return
	_tune_new[cat] = v
	TN.apply(_tune_car, _tune_new)
	_tune_panel()

# ---------------------------------------------------------------- AMMU★NATION nova: prévia 3D + estatísticas
const W := preload("res://scripts/weapons.gd")
const GUN_LIST := ["pistol", "smg", "shotgun", "rifle", "sniper", "rpg", "grenade"]
var _gun_sel := "pistol"

func _gun_item(id: String) -> Dictionary:
	for it in GUNS:
		if it.id == id:
			return it
	return {}

func _ammo_item(id: String) -> Dictionary:
	for it in GUNS:
		if it.id == "ammo_" + id:
			return it
	return {}

func show_guns(sel: String) -> void:
	_close()
	_gun_sel = sel
	get_tree().paused = true
	overlay = ColorRect.new()
	overlay.color = Color(0.02, 0.02, 0.03, 0.88)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mc.add_theme_constant_override(k, 24)
	overlay.add_child(mc)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 22)
	mc.add_child(hb)
	var c = main.combat
	# ---- lista à esquerda
	var lsc := ScrollContainer.new()
	lsc.custom_minimum_size = Vector2(392, 0)
	lsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lsc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	hb.add_child(lsc)
	_scrolls.append(lsc)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(380, 0)
	left.add_theme_constant_override("separation", 8)
	lsc.add_child(left)
	var t := Label.new()
	t.text = "AMMU★NATION"
	t.add_theme_font_size_override("font_size", 40)
	t.add_theme_color_override("font_color", Color(1, 0.25, 0.2))
	left.add_child(t)
	_info(left, "Dinheiro: $%d" % main.money, Color(0.4, 1, 0.4))
	for id in GUN_LIST:
		var it := _gun_item(id)
		var owned: bool = c.owned.get(id, false)
		var b := Button.new()
		b.text = "%s   %s" % [it.name, "✓ SUA" if owned else "$%d" % it.price]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(380, 54)
		b.add_theme_font_size_override("font_size", 22)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.6, 0.12, 0.1, 0.95) if id == sel else Color(0.12, 0.13, 0.16, 0.95)
		sb.set_corner_radius_all(8)
		sb.set_content_margin_all(10)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.pressed.connect(func(): show_guns(id))
		left.add_child(b)
	var arm: Dictionary = _gun_item("armor")
	_btn(left, "Colete à prova de balas — $%d" % arm.price, func(): _buy_gun(arm); show_guns(_gun_sel), main.money >= arm.price and main.armor < 99.0).custom_minimum_size = Vector2(380, 54)
	_btn(left, "SAIR", _close).custom_minimum_size = Vector2(380, 54)
	# ---- detalhe à direita: prévia 3D girando e estatísticas
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	hb.add_child(right)
	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = Vector2(560, 260)
	svc.stretch = true
	right.add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(sv)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.15, 1.6)
	cam.fov = 40.0
	sv.add_child(cam)
	var l1 := DirectionalLight3D.new()
	l1.rotation_degrees = Vector3(-40, 30, 0)
	l1.light_energy = 1.6
	sv.add_child(l1)
	var l2 := OmniLight3D.new()
	l2.position = Vector3(-1.2, 0.8, 1.2)
	l2.light_energy = 1.4
	l2.omni_range = 6.0
	sv.add_child(l2)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.21, 0.25)
	we.environment = env
	sv.add_child(we)
	var pivot := Node3D.new()
	sv.add_child(pivot)
	var gun: Node3D = W.gun_mesh(sel)
	var length: float = {"pistol": 0.3, "smg": 0.5, "shotgun": 0.95, "rifle": 1.05, "sniper": 1.15, "rpg": 1.15, "grenade": 0.15}[sel]
	gun.scale = Vector3.ONE * (1.25 / length if sel != "grenade" else 4.0)
	# no modelo o cano é −Y e o cabo é −Z: cano para +X e cabo para baixo, centralizado
	gun.basis = Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)).scaled(gun.scale)
	var holder := Node3D.new()
	holder.rotation.x = 0.2
	holder.add_child(gun)
	gun.position = Vector3(-length * gun.scale.x * 0.45, 0.05, 0) if sel != "grenade" else Vector3.ZERO
	pivot.add_child(holder)
	var tw := pivot.create_tween().set_loops()
	pivot.rotation.y = -0.5
	tw.tween_property(pivot, "rotation:y", TAU - 0.5, 8.0).from(-0.5)
	# nome e estatísticas
	var d: Dictionary = W.DATA[sel]
	var nm := Label.new()
	nm.text = d.name
	nm.add_theme_font_size_override("font_size", 34)
	nm.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	right.add_child(nm)
	var pel: int = d.get("pellets", 1)
	var stats := [["Dano", minf(1.0, d.dmg * pel / 200.0), "%d" % int(d.dmg * pel)],
		["Cadência", minf(1.0, (1.0 / d.rate) / 12.0), "%.1f tiros/s" % (1.0 / d.rate)],
		["Recuo", c.RECOIL.get(sel, 0.0), "%d%%" % int(c.RECOIL.get(sel, 0.0) * 100.0)],
		["Recarga", minf(1.0, c.RELOAD.get(sel, 0.0) / 3.0), "%.1f s" % c.RELOAD.get(sel, 0.0)],
		["Alcance", minf(1.0, d.range / 140.0), "%d m" % int(d.range)],
		["Pente", minf(1.0, c.MAG.get(sel, 1) / 30.0), "%d" % c.MAG.get(sel, 1)]]
	for st in stats:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		right.add_child(row)
		var lb := Label.new()
		lb.text = st[0]
		lb.custom_minimum_size = Vector2(130, 0)
		lb.add_theme_font_size_override("font_size", 22)
		row.add_child(lb)
		var bar := Control.new()
		bar.custom_minimum_size = Vector2(300, 18)
		row.add_child(bar)
		var bg := ColorRect.new()
		bg.color = Color(0.2, 0.2, 0.24)
		bg.size = Vector2(300, 18)
		bar.add_child(bg)
		var fg := ColorRect.new()
		fg.color = Color(1, 0.35, 0.25).lerp(Color(1, 0.8, 0.2), st[1])
		fg.size = Vector2(300.0 * clampf(st[1], 0.03, 1.0), 18)
		bar.add_child(fg)
		var vl := Label.new()
		vl.text = st[2]
		vl.add_theme_font_size_override("font_size", 20)
		vl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
		row.add_child(vl)
	var have: int = c.ammo.get(sel, 0)
	var mx: int = c.MAX_AMMO.get(sel, 0)
	_info(right, "Munição: %d / %d (máximo)" % [have, mx], Color(0.75, 0.85, 1.0))
	var it2 := _gun_item(sel)
	var owned2: bool = c.owned.get(sel, false)
	if not owned2:
		_btn(right, "COMPRAR %s — $%d" % [it2.name.to_upper(), it2.price], func(): _buy_gun(it2); show_guns(sel), main.money >= it2.price)
	var am := _ammo_item(sel)
	if not am.is_empty() and owned2:
		_btn(right, "%s — $%d" % [am.name, am.price], func(): _buy_gun(am); show_guns(sel), main.money >= am.price and have < mx)
	elif sel == "grenade" and owned2:
		_btn(right, "Mais granadas (+5) — $%d" % it2.price, func():
			if main.money >= it2.price and have < mx:
				main.money -= it2.price
				c.add_ammo("grenade", 5)
				main.audio.play("cash")
			show_guns(sel), main.money >= it2.price and have < mx)

extends Node3D
## Segurança do aeroporto: cerca alta em volta (não dá para pular; dá para derrubar com o carro ou
## explodir), portão na pista (lado leste), rampa meio escondida na ilha para pular a cerca de carro,
## seguranças armados e vigias desarmados. Entrou sem permissão → um vigia/segurança te vê, avisa
## pelo rádio e os armados vêm até você SEM atirar; o portão abre. Indo para o portão, eles deixam
## você sair. Ficando lá dentro, abrem fogo.

const Cop := preload("res://scripts/cop.gd")
const Ped := preload("res://scripts/ped.gd")
const M := preload("res://scripts/mats.gd")
const FX := preload("res://scripts/fx.gd")

const X0 := -578.0
const X1 := -252.0
const Z0 := -46.0
const Z1 := 46.0
const H := 3.6
const SEG := 4.0
const GATE_Z0 := -11.0
const GATE_Z1 := 11.0

var main: Node3D
var body: StaticBody3D
var mm: MultiMesh
var segs: Array = []         # {a, b, shape, idx, alive, xf}
var gate: Node3D
var gate_body: StaticBody3D
var gate_open := 0.0
var gate_want := 0.0
var guards: Array = []       # Cop armados
var spotters: Array = []     # Ped desarmados (vigias)
var state := "calm"          # calm / warn / hostile
var warn_t := 0.0
var _gate_d := 0.0
var _gate_chk := 0.0
var _outside_t := 0.0
var rng := RandomNumberGenerator.new()

func build(m: Node3D) -> void:
	main = m
	rng.seed = 404
	body = StaticBody3D.new()
	add_child(body)
	# painéis da cerca (alambrado escuro) num MultiMesh só; colisão por trecho
	var panel := BoxMesh.new()
	panel.size = Vector3(SEG, H, 0.08)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.35, 0.37, 0.4)
	pm.metallic = 0.6
	pm.roughness = 0.5
	panel.material = pm
	var xfs: Array = []
	var edges := [[Vector3(X0, 0, Z0), Vector3(X1, 0, Z0)], [Vector3(X0, 0, Z1), Vector3(X1, 0, Z1)], [Vector3(X0, 0, Z0), Vector3(X0, 0, Z1)], [Vector3(X1, 0, Z0), Vector3(X1, 0, Z1)]]
	for e in edges:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var L := a.distance_to(b)
		var n := int(ceil(L / SEG))
		var dir := (b - a).normalized()
		for k in n:
			var c := a + dir * (k + 0.5) * (L / n)
			if absf(c.x - X1) < 0.1 and c.z > GATE_Z0 - 1.0 and c.z < GATE_Z1 + 1.0:
				continue            # vão do portão
			var yaw := atan2(dir.x, dir.z) + PI * 0.5
			var xf := Transform3D(Basis(Vector3.UP, yaw), c + Vector3(0, H * 0.5, 0))
			var cs := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			bx.size = Vector3(SEG, H, 0.3)
			cs.shape = bx
			cs.transform = xf
			body.add_child(cs)
			segs.append({"c": c, "dir": dir, "shape": cs, "idx": xfs.size(), "alive": true, "xf": xf})
			xfs.append(xf)
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = panel
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	# postes e arame farpado no topo (decoração, 1 MultiMesh cada)
	var post := BoxMesh.new()
	post.size = Vector3(0.14, H + 0.5, 0.14)
	post.material = pm
	var wire := BoxMesh.new()
	wire.size = Vector3(SEG, 0.06, 0.06)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.55, 0.55, 0.58)
	wire.material = wm
	var pmm := MultiMesh.new()
	pmm.transform_format = MultiMesh.TRANSFORM_3D
	pmm.mesh = post
	pmm.instance_count = segs.size()
	var wmm := MultiMesh.new()
	wmm.transform_format = MultiMesh.TRANSFORM_3D
	wmm.mesh = wire
	wmm.instance_count = segs.size() * 2
	for i in segs.size():
		var sg: Dictionary = segs[i]
		var pxf := Transform3D(Basis(), sg.c - sg.dir * SEG * 0.5 + Vector3(0, (H + 0.5) * 0.5, 0))
		pmm.set_instance_transform(i, pxf)
		for k in 2:
			var w: Transform3D = sg.xf
			w.origin += Vector3(0, H * 0.5 + 0.12 + k * 0.18, 0)
			wmm.set_instance_transform(i * 2 + k, w)
	for mmx in [pmm, wmm]:
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mmx
		add_child(mi)
	_wire_mm = wmm
	_gate()
	_ramp()
	_signs()
	spawn_staff()

var _wire_mm: MultiMesh

func _gate() -> void:
	gate = Node3D.new()
	add_child(gate)
	gate.position = Vector3(X1, 0, (GATE_Z0 + GATE_Z1) * 0.5)
	var L := GATE_Z1 - GATE_Z0
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, H, L)
	mi.mesh = bm
	mi.material_override = M.plain(Color(0.85, 0.7, 0.1), 0.4, 0.6)
	mi.position.y = H * 0.5
	gate.add_child(mi)
	for k in 5:
		var st := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.14, 0.3, L * 0.98)
		st.mesh = sm
		st.material_override = M.plain(Color(0.1, 0.1, 0.1), 0.5)
		st.position = Vector3(0, 0.5 + k * 0.7, 0)
		gate.add_child(st)
	gate_body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(0.4, H, L)
	cs.shape = bx
	cs.position.y = H * 0.5
	gate_body.add_child(cs)
	gate.add_child(gate_body)
	# guarita
	var gh := MeshInstance3D.new()
	var gbm := BoxMesh.new()
	gbm.size = Vector3(3.0, 2.8, 3.0)
	gh.mesh = gbm
	gh.material_override = M.concrete(Color(0.85, 0.85, 0.82))
	gh.position = Vector3(X1 - 3.0, 1.4, GATE_Z1 + 3.5)
	add_child(gh)
	var gcs := CollisionShape3D.new()
	var gbx := BoxShape3D.new()
	gbx.size = gbm.size
	gcs.shape = gbx
	gcs.position = gh.position
	body.add_child(gcs)

## rampa de terra meio escondida atrás das árvores, do lado da ilha, apontada para a cerca leste
func _ramp() -> void:
	var rp := Vector3(-238.5, 0.0, -22.0)
	var L := 12.0
	var hh := 2.6
	var w := 4.2
	# cunha de verdade (prisma triangular): começa rente ao chão, sobe para o oeste
	var xa := rp.x + L * 0.5      # ponta baixa (leste)
	var xb := rp.x - L * 0.5      # ponta alta (oeste)
	var pts := PackedVector3Array()
	for z in [rp.z - w * 0.5, rp.z + w * 0.5]:
		pts.append(Vector3(xa, -0.05, z))
		pts.append(Vector3(xb, hh, z))
		pts.append(Vector3(xb, -0.05, z))
	var shp := ConvexPolygonShape3D.new()
	shp.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = shp
	body.add_child(cs)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var A0 := pts[0]
	var B0 := pts[1]
	var C0 := pts[2]
	var A1 := pts[3]
	var B1 := pts[4]
	var C1 := pts[5]
	for tri in [[A0, B1, B0], [A0, A1, B1], [B0, B1, C1], [B0, C1, C0], [A0, B0, C0], [A1, C1, B1]]:
		var n: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
		for v in tri:
			st.set_normal(n)
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := M.plain(Color(0.45, 0.34, 0.22), 0.95)
	mi.material_override = mat
	add_child(mi)
	# arbustos em volta (escondem a rampa)
	for k in 6:
		var b := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.5
		sm.height = 2.4
		b.mesh = sm
		b.material_override = M.plain(Color(0.18, 0.38, 0.16), 0.95)
		b.position = rp + Vector3(rng.randf_range(-6.0, 6.0), 0.9, (3.4 if k % 2 == 0 else -3.4) + rng.randf_range(-0.5, 0.5))
		add_child(b)

func _signs() -> void:
	for p in [Vector3(X1 + 0.3, 2.4, GATE_Z1 + 2.0), Vector3(X1 + 0.3, 2.4, -30.0), Vector3(X1 + 0.3, 2.4, 30.0)]:
		var l := Label3D.new()
		l.text = "ÁREA RESTRITA\nAEROPORTO · SEGURANÇA"
		l.font_size = 46
		l.pixel_size = 0.008
		l.modulate = Color(1, 0.2, 0.15)
		l.outline_size = 8
		l.shaded = false
		l.position = p
		l.rotation.y = PI * 0.5
		add_child(l)

# ---------------------------------------------------------------- equipe
var posts: Array = [Vector3(-262.0, 0.3, 14.0), Vector3(-262.0, 0.3, -16.0), Vector3(-340.0, 0.3, -20.0), Vector3(-450.0, 0.3, 20.0), Vector3(-300.0, 0.3, 30.0)]
func spawn_staff() -> void:
	for g in guards + spotters:
		if is_instance_valid(g):
			g.queue_free()
	guards = []
	spotters = []
	for i in 4:
		var cp := Cop.new()
		main.add_child(cp)
		cp.setup(rng.randi(), "guard")
		cp.global_position = posts[i]
		cp.set_weapon("pistol" if i % 2 == 0 else "smg")
		cp.patrol = [posts[i], posts[i] + Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-6, 6))]
		cp.shot_player.connect(main.combat._on_cop_shot)
		cp.remove_from_group("tmp")
		guards.append(cp)
	var loops := [[Vector3(-270, 0.3, 40), Vector3(-420, 0.3, 40), Vector3(-420, 0.3, 38), Vector3(-270, 0.3, 38)],
		[Vector3(-300, 0.3, -40), Vector3(-520, 0.3, -40), Vector3(-520, 0.3, -38), Vector3(-300, 0.3, -38)],
		[Vector3(-258, 0.3, -30), Vector3(-258, 0.3, 30), Vector3(-260, 0.3, 30), Vector3(-260, 0.3, -30)]]
	for k in loops.size():
		var p := Ped.new()
		main.add_child(p)
		p.setup(loops[k], 0, rng)
		p._cols = [Color(0.95, 0.75, 0.1), Color(0.15, 0.15, 0.18), p._cols[2], p._cols[3]]   # colete refletivo
		p.body.queue_free()
		p._make_body()
		p.speed = 1.2
		p.died.connect(main._on_ped_died)
		p.remove_from_group("tmp")
		main.peds.append(p)
		spotters.append(p)

# ---------------------------------------------------------------- lógica
func inside(p: Vector3) -> bool:
	return p.x > X0 and p.x < X1 and p.z > Z0 and p.z < Z1

func _sees(from: Vector3, to: Vector3, r: float) -> bool:
	if from.distance_to(to) > r:
		return false
	var q := PhysicsRayQueryParameters3D.create(from + Vector3(0, 1.6, 0), to + Vector3(0, 1.2, 0), 1)
	q.exclude = [main.player.get_rid()]
	if main.player.vehicle:
		q.exclude.append(main.player.vehicle.get_rid())
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func tick(dt: float) -> void:
	if main == null or main.combat.dead:
		return
	_gate_tick(dt)
	var pl = main.player
	var pp: Vector3 = pl.vehicle.global_position if pl.vehicle else pl.global_position
	var flying: bool = pl.vehicle != null and pl.vehicle.kind in ["plane", "heli", "jet", "attack"] and pp.y > 6.0
	var in_now: bool = inside(pp) and not flying
	guards = guards.filter(func(g): return is_instance_valid(g))
	match state:
		"calm":
			gate_want = 0.0
			if in_now:
				for w in spotters + guards:
					if is_instance_valid(w) and not w.down and _sees(w.global_position, pp, 38.0):
						_alarm(w)
						break
		"warn":
			gate_want = 1.0
			_watch_leaving(dt, pp)
			for g in guards:
				if g.down:
					continue
				g.target = pl.vehicle if pl.vehicle else pl
				g.searching = true          # aproximam e apontam, sem atirar
				g.pref = 7.0
				g.cool = maxf(g.cool, 0.5)
			if not in_now:
				_outside_t += dt
				if _outside_t > 5.0:
					_calm()
			else:
				_outside_t = 0.0
				warn_t -= dt
				if warn_t <= 0.0:
					state = "hostile"
					main.hud.banner("SEGURANÇA: FOGO!", Color(1, 0.2, 0.15), 2.0)
		"hostile":
			gate_want = 1.0
			for g in guards:
				if g.down:
					continue
				g.target = pl.vehicle if pl.vehicle else pl
				g.searching = false
			if not in_now:
				_outside_t += dt
				if _outside_t > 8.0:
					_calm()
			else:
				_outside_t = 0.0
	# reposição dos seguranças quando o jogador está longe
	if state == "calm" and pp.distance_to(Vector3((X0 + X1) * 0.5, 0, 0)) > 260.0 and guards.filter(func(g): return not g.down).size() < 2:
		spawn_staff()

## jogador indo para o portão: a contagem volta (eles deixam sair)
func _watch_leaving(dt: float, pp: Vector3) -> void:
	_gate_chk -= dt
	if _gate_chk > 0.0:
		return
	_gate_chk = 1.0
	var gp := Vector3(X1, 0, (GATE_Z0 + GATE_Z1) * 0.5)
	var d := Vector2(pp.x - gp.x, pp.z - gp.z).length()
	if d < _gate_d - 1.2 or d < 18.0:
		warn_t = maxf(warn_t, 7.0)
	_gate_d = d

func _alarm(w) -> void:
	state = "warn"
	warn_t = 12.0
	_outside_t = 0.0
	_gate_d = 1e9
	main.audio.play("radio" if main.audio.sounds.has("radio") else "click", w.global_position, 2.0)
	if w is Node3D and w.get("body") and w.body.get("arm_pose") != null:
		w.body.arm_pose = "phone"
	main.hud.banner("SEGURANÇA: ÁREA RESTRITA! SAIA PELO PORTÃO", Color(1, 0.8, 0.2), 4.0)

func _calm() -> void:
	state = "calm"
	_outside_t = 0.0
	for g in guards:
		if is_instance_valid(g) and not g.down:
			g.target = null
			g.searching = false
	for s in spotters:
		if is_instance_valid(s) and s.get("body"):
			s.body.arm_pose = ""

func _gate_tick(dt: float) -> void:
	gate_open = move_toward(gate_open, gate_want, dt * 0.5)
	if gate:
		gate.position.z = (GATE_Z0 + GATE_Z1) * 0.5 + gate_open * (GATE_Z1 - GATE_Z0 + 1.0)

# ---------------------------------------------------------------- cerca quebrável
## batida registrada pelo carro perto da cerca (velocidade antes da batida)
func crash_at(c, dv: float) -> void:
	if dv < 6.0 or not is_instance_valid(c):
		return
	var p: Vector3 = c.global_position
	var best = null
	var bd := maxf(c.body_size.x, c.body_size.z) * 0.5 + 1.2
	for sg in segs:
		if sg.alive:
			var d := Vector2(p.x - sg.c.x, p.z - sg.c.z).length()
			if d < bd + SEG * 0.5:
				var rel: Vector3 = p - sg.c
				rel.y = 0
				var nd := absf(rel.dot(Vector3(-sg.dir.z, 0, sg.dir.x)))
				if nd < bd and absf(rel.dot(sg.dir)) < SEG * 0.5 + 0.8:
					best = sg
					bd = nd
	if best != null:
		_break(best, c.linear_velocity if c.linear_velocity.length() > 1.0 else (best.c - p))

## carro rápido encostando num trecho da cerca derruba o trecho
func vehicle_tick(c) -> void:
	if c == null or not is_instance_valid(c):
		return
	var p: Vector3 = c.global_position + c.linear_velocity * 0.12      # antecipa (a colisão para o carro antes)
	if p.x < X0 - 6.0 or p.x > X1 + 6.0 or p.z < Z0 - 6.0 or p.z > Z1 + 6.0:
		return
	var v: float = c.linear_velocity.length()
	if v < 7.0:
		return
	var half: float = maxf(c.body_size.x, c.body_size.z) * 0.5 + 0.6
	for sg in segs:
		if not sg.alive:
			continue
		var rel: Vector3 = p - sg.c
		rel.y = 0
		var along := rel.dot(sg.dir)
		var nrm := Vector3(-sg.dir.z, 0, sg.dir.x)
		if absf(along) < SEG * 0.5 + 0.5 and absf(rel.dot(nrm)) < half:
			_break(sg, c.linear_velocity)
			if c.has_method("take_damage"):
				c.take_damage(4.0)

func explosion(pos: Vector3, r: float) -> void:
	for sg in segs:
		if sg.alive and Vector2(sg.c.x - pos.x, sg.c.z - pos.z).length() < r + SEG * 0.5:
			_break(sg, (sg.c - pos).normalized() * 6.0)

func _break(sg: Dictionary, push: Vector3) -> void:
	sg.alive = false
	sg.shape.disabled = true
	# painel caído no chão, virado para onde foi empurrado
	var nrm := Vector3(-sg.dir.z, 0, sg.dir.x)
	var side := signf(push.dot(nrm))
	if side == 0.0:
		side = 1.0
	var fallen: Transform3D = sg.xf
	fallen = Transform3D(fallen.basis * Basis(Vector3.RIGHT, PI * 0.5 * side), sg.c + nrm * side * (H * 0.5) + Vector3(0, 0.08, 0))
	mm.set_instance_transform(sg.idx, fallen)
	var i: int = segs.find(sg)
	for k in 2:
		_wire_mm.set_instance_transform(i * 2 + k, Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), sg.c))
	main.audio.play("crash", sg.c, 2.0)
	FX.sparks(main, sg.c + Vector3(0, 1.0, 0))
	# derrubar a cerca na frente de alguém = também conta como invasão
	if state == "calm":
		for w in spotters + guards:
			if is_instance_valid(w) and not w.down and w.global_position.distance_to(sg.c) < 45.0:
				_alarm(w)
				break

## mundo refeito (morte/prisão): cerca de pé, portão fechado, equipe nova
func reset() -> void:
	for sg in segs:
		sg.alive = true
		sg.shape.disabled = false
		mm.set_instance_transform(sg.idx, sg.xf)
	for i in segs.size():
		for k in 2:
			var w: Transform3D = segs[i].xf
			w.origin += Vector3(0, H * 0.5 + 0.12 + k * 0.18, 0)
			_wire_mm.set_instance_transform(i * 2 + k, w)
	state = "calm"
	gate_open = 0.0
	gate_want = 0.0
	spawn_staff()

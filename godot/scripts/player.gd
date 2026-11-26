extends CharacterBody3D
## Jogador a pé: movimento relativo à câmera com aceleração progressiva, pulo e gravidade.

const Humanoid := preload("res://scripts/humanoid.gd")

var body: Node3D
var move_input := Vector2.ZERO   # x = lado, y = frente (-1..1)
var cam_yaw := 0.0
var sprint := false
var walk_speed := 2.2
var run_speed := 6.5
var accel := 9.0
var gravity := 18.0
var jump_v := 6.2
var vehicle: Node = null
var swimming := false
var world2: Node = null
var aim_yaw := NAN          # mira: corpo virado para onde a câmera olha
var diving := false         # segurando MERGULHAR (botão PULO na água)
var rising := false         # segurando SUBIR (debaixo d'água)
var underwater := false
var pk_t := -1.0            # parkour em andamento (tempo)
var pk_dur := 0.0
var pk_pts: Array = []
var pk_kind := ""

func _ready() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.78
	cs.shape = cap
	cs.position.y = 0.89
	add_child(cs)
	rebuild_body()
	floor_snap_length = 0.3
	collision_layer = 2
	collision_mask = 1

const OUTFIT0 := {"shirt": "216b42", "pants": "1f2945", "hair": "291a0f", "jacket": "", "hat": 0, "hat_c": "1a1a1f", "glasses": false}
var outfit: Dictionary = OUTFIT0.duplicate()

func rebuild_body(keep_wounds := true) -> void:
	var wd: Array = []
	if body and is_instance_valid(body):
		if keep_wounds:
			wd = body.wound_data.duplicate()
		body.queue_free()
	body = make_body()
	add_child(body)
	if not wd.is_empty():
		body.apply_wounds(wd)

## corpo com a roupa atual (também usado para o jogador sentado no veículo)
func make_body():
	var h := Humanoid.new()
	var o := outfit
	h.build(Color.html(o.shirt), Color.html(o.pants), Color(0.86, 0.66, 0.5), Color.html(o.hair),
		{"jacket": Color.html(o.jacket) if o.jacket != "" else Color(0, 0, 0, 0), "hat": int(o.hat), "hat_c": Color.html(o.hat_c), "glasses": bool(o.glasses)})
	return h

func jump() -> void:
	if ride != null:
		jump_off_ride()
		return
	if is_on_floor() and not swimming:
		velocity.y = jump_v

func _physics_process(dt: float) -> void:
	if vehicle != null or body.ragdolled:
		return
	if pk_t >= 0.0:
		_parkour_tick(dt)
		return
	if ride != null:
		_ride_tick(dt)
		return
	if body.pose == "getup":
		# levantando: fica parado até terminar a animação
		velocity = Vector3(0, velocity.y - gravity * dt if not is_on_floor() else 0.0, 0)
		move_and_slide()
		body.animate(0.0, dt)
		return
	var f := Vector3(sin(cam_yaw), 0, cos(cam_yaw))
	var r := Vector3(-f.z, 0, f.x)
	var want := (f * move_input.y + r * move_input.x)
	var mag := minf(1.0, want.length())
	var target_speed := lerpf(0.0, run_speed if (sprint or mag > 0.85) else walk_speed * 1.6, mag)
	# nado: no mar, na altura da água (no píer, a 1,6 m, anda normal)
	var wy: float = world2.WATER_Y if world2 else 0.9
	var swim_now: bool = world2 != null and world2.is_swim(global_position.x, global_position.z) and global_position.y < wy - 0.15 + (0.6 if swimming else 0.0)
	if swim_now != swimming:
		swimming = swim_now
		body.swimming = swimming
		if swimming and get_tree().current_scene.has_method("splash_at"):
			get_tree().current_scene.splash_at(global_position)
	body.swimming = swimming     # todo quadro (o corpo pode ter sido recriado na água)
	if swimming:
		target_speed = lerpf(0.0, 5.0 if sprint else 3.3, mag)
	var hv := Vector3(velocity.x, 0, velocity.z)
	var tv := want.normalized() * target_speed if mag > 0.05 else Vector3.ZERO
	hv = hv.move_toward(tv, accel * dt * (1.6 if tv == Vector3.ZERO else 1.0))
	velocity.x = hv.x
	velocity.z = hv.z
	underwater = false
	if swimming:
		# superfície: cabeça para fora; MERGULHAR (segurar PULO) desce até o fundo
		# debaixo d'água fica na profundidade em que está (flutuação neutra): MERGULHAR desce, SUBIR sobe
		var surf := wy - 0.78
		var under := global_position.y < surf - 0.35
		if diving:
			velocity.y = move_toward(velocity.y, -2.6, dt * 6.0)
		elif rising:
			velocity.y = move_toward(velocity.y, 2.4, dt * 6.0)
			if global_position.y > surf - 0.1:
				velocity.y = clampf((surf - global_position.y) * 3.0, -2.5, 2.8)
		elif under:
			velocity.y = move_toward(velocity.y, 0.0, dt * 4.0)
		else:
			velocity.y = clampf((surf - global_position.y) * 3.0, -2.5, 2.8)
		underwater = global_position.y < surf - 0.5
		body.dive = diving or underwater
	elif not is_on_floor():
		velocity.y -= gravity * dt
	move_and_slide()
	_step_up(tv)
	_check_ride()
	if hv.length() > 0.2:
		var ang := atan2(hv.x, hv.z)
		body.rotation.y = lerp_angle(body.rotation.y, ang, minf(1.0, dt * 10.0))
	if not is_nan(aim_yaw):
		body.rotation.y = aim_yaw
	body.animate(hv.length(), dt)
	# parkour: correndo contra um obstáculo baixo (pula por cima) ou um muro/beirada até 2,6 m (escala)
	if is_on_floor() and not swimming and hv.length() > 3.2 and mag > 0.6:
		_try_parkour(hv.normalized())


# ---------------------------------------------------------------- carona em cima de veículos
## pisou no teto/caçamba de um carro: passa a andar junto com ele (posição local no carro)
var ride = null
var ride_local := Vector3.ZERO
var _ride_yaw := 0.0
var _ride_v := Vector3.ZERO
var _ride_acc := Vector3.ZERO
func _check_ride() -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var o = col.get_collider()
		if col.get_normal().y > 0.7 and o is VehicleBody3D and o.get("kind") != "moto":
			ride = o
			ride_local = o.global_transform.affine_inverse() * global_position
			_ride_yaw = o.global_rotation.y
			_ride_v = o.linear_velocity
			_ride_acc = Vector3.ZERO
			return

func _ride_tick(dt: float) -> void:
	var c = ride
	if not is_instance_valid(c) or c.get("dead") == true and c.linear_velocity.length() < 0.5:
		ride = null
		return
	var half: Vector3 = c.body_size * 0.5
	# anda sobre o carro com o joystick (direção da câmera, convertida para o espaço do carro)
	var f := Vector3(sin(cam_yaw), 0, cos(cam_yaw))
	var r := Vector3(-f.z, 0, f.x)
	var want := (f * move_input.y + r * move_input.x)
	var lw: Vector3 = c.global_transform.basis.inverse() * want
	lw.y = 0
	ride_local += lw.limit_length(1.0) * walk_speed * 0.9 * dt
	global_position = c.global_transform * ride_local
	velocity = c.linear_velocity
	# a câmera gira junto com o carro
	var dyaw: float = angle_difference(_ride_yaw, c.global_rotation.y)
	_ride_yaw = c.global_rotation.y
	body.rotation.y += dyaw
	if want.length() > 0.1:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(want.x, want.z), minf(1.0, dt * 8.0))
	body.animate(want.length() * walk_speed * 0.9, dt)
	# freada/batida forte joga o jogador para fora; saiu da borda = cai
	# só a aceleração horizontal, suavizada (o carro assentando na suspensão não derruba)
	var acc: Vector3 = (c.linear_velocity - _ride_v) / maxf(dt, 0.001)
	acc.y = 0.0
	_ride_v = c.linear_velocity
	_ride_acc = _ride_acc.lerp(acc, minf(1.0, dt * 6.0))
	var main := get_tree().current_scene
	if _ride_acc.length() > 20.0:
		ride = null
		main.combat.knockdown(c.linear_velocity * 0.9 - acc * 0.12 + Vector3(0, 2.5, 0), 2.4)
		return
	if absf(ride_local.x) > half.x + 0.15 or absf(ride_local.z) > half.z + 0.15:
		ride = null
		velocity = c.linear_velocity
		return

func jump_off_ride() -> void:
	if ride != null:
		var v: Vector3 = ride.linear_velocity
		ride = null
		velocity = v + Vector3(0, jump_v, 0)

## degrau automático: meio-fio/calçada (até 0,4 m) é subido andando, sem pular
func _step_up(tv: Vector3) -> void:
	if swimming or tv.length() < 0.3 or not (is_on_floor() or velocity.y <= 0.1):
		return
	var fwd := tv.normalized()
	var p := global_position
	var low := _ray(p + Vector3(0, 0.05, 0), p + Vector3(0, 0.05, 0) + fwd * 0.55)
	if low.is_empty() or absf(low.normal.y) > 0.6:
		return
	if not _ray(p + Vector3(0, 0.45, 0), p + Vector3(0, 0.45, 0) + fwd * 0.6).is_empty():
		return
	var probe: Vector3 = low.position + fwd * 0.12
	var top := _ray(Vector3(probe.x, p.y + 0.5, probe.z), Vector3(probe.x, p.y - 0.05, probe.z))
	if top.is_empty():
		return
	var dh: float = top.position.y - p.y
	if dh > 0.02 and dh < 0.42:
		global_position = Vector3(p.x, top.position.y + 0.02, p.z) + fwd * 0.06
		velocity.y = 0.0

func _ray(a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)

func _try_parkour(fwd: Vector3) -> void:
	var p := global_position
	var hit := _ray(p + Vector3(0, 0.45, 0), p + Vector3(0, 0.45, 0) + fwd * 0.95)
	if hit.is_empty():
		return
	var n: Vector3 = hit.normal
	if absf(n.y) > 0.5:
		return
	var wallp: Vector3 = hit.position
	var probe := wallp + fwd * 0.18      # muros finos (0,3–0,5 m) também contam
	var top_hit := _ray(probe + Vector3(0, 3.0, 0), probe + Vector3(0, 0.3, 0))
	if top_hit.is_empty():
		return
	var top: float = top_hit.position.y
	var h := top - p.y
	if h < 0.35 or h > 3.1:
		return
	# precisa de espaço em cima do obstáculo
	if not _ray(Vector3(probe.x, top + 0.15, probe.z), Vector3(probe.x, top + 1.9, probe.z)).is_empty():
		return
	pk_pts = [p]
	if h <= 1.3:
		# salto por cima: se do outro lado for livre e baixo, passa; senão sobe e fica em cima
		var land := wallp + fwd * 1.9
		var land_hit := _ray(Vector3(land.x, top + 0.5, land.z), Vector3(land.x, p.y - 3.0, land.z))
		var land_y: float = land_hit.position.y if not land_hit.is_empty() else p.y
		pk_kind = "vault"
		pk_pts.append(Vector3(probe.x, top + 0.35, probe.z))
		if land_y < top - 0.3:
			pk_pts.append(Vector3(land.x, land_y, land.z))
		else:
			pk_pts.append(Vector3(probe.x, top, probe.z) + fwd * 0.4)
		pk_dur = 0.55
	else:
		pk_kind = "climb"
		pk_pts.append(Vector3(wallp.x, top - 1.5, wallp.z) - fwd * 0.3)
		pk_pts.append(Vector3(probe.x, top, probe.z) + fwd * 0.35)
		pk_dur = 1.0
	pk_t = 0.0
	collision_mask = 0
	velocity = Vector3.ZERO
	body.rotation.y = atan2(fwd.x, fwd.z)
	body.pose = pk_kind

func _parkour_tick(dt: float) -> void:
	pk_t += dt
	var k := clampf(pk_t / pk_dur, 0.0, 1.0)
	body.pose_t = k
	var pos: Vector3
	if pk_kind == "vault":
		# curva suave pelo ponto de apoio
		var a: Vector3 = pk_pts[0]
		var b: Vector3 = pk_pts[1]
		var c: Vector3 = pk_pts[2]
		pos = a.lerp(b, k).lerp(b.lerp(c, k), k)
	else:
		var a2: Vector3 = pk_pts[0]
		var b2: Vector3 = pk_pts[1]
		var c2: Vector3 = pk_pts[2]
		# 0-45%: sobe pendurado; 45-100%: passa o corpo por cima
		if k < 0.45:
			pos = a2.lerp(b2, smoothstep(0.0, 1.0, k / 0.45))
		else:
			var kk := (k - 0.45) / 0.55
			pos = b2.lerp(c2, smoothstep(0.0, 1.0, kk))
			pos.y = lerpf(b2.y, c2.y, minf(1.0, kk * 1.6))
	global_position = pos
	body.animate(0.0, dt)
	if k >= 1.0:
		pk_t = -1.0
		body.pose = ""
		collision_mask = 1
		velocity = Vector3.ZERO

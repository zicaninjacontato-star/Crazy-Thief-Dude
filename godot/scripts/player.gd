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

func rebuild_body() -> void:
	if body and is_instance_valid(body):
		body.queue_free()
	body = make_body()
	add_child(body)

## corpo com a roupa atual (também usado para o jogador sentado no veículo)
func make_body():
	var h := Humanoid.new()
	var o := outfit
	h.build(Color.html(o.shirt), Color.html(o.pants), Color(0.86, 0.66, 0.5), Color.html(o.hair),
		{"jacket": Color.html(o.jacket) if o.jacket != "" else Color(0, 0, 0, 0), "hat": int(o.hat), "hat_c": Color.html(o.hat_c), "glasses": bool(o.glasses)})
	return h

func jump() -> void:
	if is_on_floor() and not swimming:
		velocity.y = jump_v

func _physics_process(dt: float) -> void:
	if vehicle != null or body.ragdolled:
		return
	if pk_t >= 0.0:
		_parkour_tick(dt)
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
		target_speed = lerpf(0.0, 3.6 if sprint else 2.3, mag)
	var hv := Vector3(velocity.x, 0, velocity.z)
	var tv := want.normalized() * target_speed if mag > 0.05 else Vector3.ZERO
	hv = hv.move_toward(tv, accel * dt * (1.6 if tv == Vector3.ZERO else 1.0))
	velocity.x = hv.x
	velocity.z = hv.z
	underwater = false
	if swimming:
		# superfície: cabeça para fora; MERGULHAR (segurar PULO) desce até o fundo
		var surf := wy - 0.78
		if diving:
			velocity.y = move_toward(velocity.y, -2.6, dt * 6.0)
		else:
			velocity.y = clampf((surf - global_position.y) * 3.0, -2.5, 2.8)
		underwater = global_position.y < surf - 0.5
		body.dive = diving or underwater
	elif not is_on_floor():
		velocity.y -= gravity * dt
	move_and_slide()
	if hv.length() > 0.2:
		var ang := atan2(hv.x, hv.z)
		body.rotation.y = lerp_angle(body.rotation.y, ang, minf(1.0, dt * 10.0))
	if not is_nan(aim_yaw):
		body.rotation.y = aim_yaw
	body.animate(hv.length(), dt)
	# parkour: correndo contra um obstáculo baixo (pula por cima) ou um muro/beirada até 2,6 m (escala)
	if is_on_floor() and not swimming and hv.length() > 3.2 and mag > 0.6:
		_try_parkour(hv.normalized())


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
	var probe := wallp + fwd * 0.35
	var top_hit := _ray(probe + Vector3(0, 3.0, 0), probe + Vector3(0, 0.3, 0))
	if top_hit.is_empty():
		return
	var top: float = top_hit.position.y
	var h := top - p.y
	if h < 0.35 or h > 2.6:
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

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
	var f := Vector3(sin(cam_yaw), 0, cos(cam_yaw))
	var r := Vector3(-f.z, 0, f.x)
	var want := (f * move_input.y + r * move_input.x)
	var mag := minf(1.0, want.length())
	var target_speed := lerpf(0.0, run_speed if (sprint or mag > 0.85) else walk_speed * 1.6, mag)
	# nado: no mar, a partir de onde a água fica funda
	var swim_now: bool = world2 != null and world2.is_swim(global_position.x)
	if swim_now != swimming:
		swimming = swim_now
		body.swimming = swimming
		if swimming and get_tree().current_scene.has_method("splash_at"):
			get_tree().current_scene.splash_at(global_position)
	if swimming:
		target_speed = lerpf(0.0, 3.6 if sprint else 2.3, mag)
	var hv := Vector3(velocity.x, 0, velocity.z)
	var tv := want.normalized() * target_speed if mag > 0.05 else Vector3.ZERO
	hv = hv.move_toward(tv, accel * dt * (1.6 if tv == Vector3.ZERO else 1.0))
	velocity.x = hv.x
	velocity.z = hv.z
	if swimming:
		velocity.y = (0.12 - global_position.y) * 5.0
	elif not is_on_floor():
		velocity.y -= gravity * dt
	move_and_slide()
	if hv.length() > 0.2:
		var ang := atan2(hv.x, hv.z)
		body.rotation.y = lerp_angle(body.rotation.y, ang, minf(1.0, dt * 10.0))
	if not is_nan(aim_yaw):
		body.rotation.y = aim_yaw
	body.animate(hv.length(), dt)

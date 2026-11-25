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

func rebuild_body() -> void:
	if body and is_instance_valid(body):
		body.queue_free()
	body = Humanoid.new()
	body.build(Color(0.13, 0.42, 0.26), Color(0.12, 0.16, 0.27), Color(0.86, 0.66, 0.5), Color(0.16, 0.1, 0.06))
	add_child(body)

func jump() -> void:
	if is_on_floor():
		velocity.y = jump_v

func _physics_process(dt: float) -> void:
	if vehicle != null or body.ragdolled:
		return
	var f := Vector3(sin(cam_yaw), 0, cos(cam_yaw))
	var r := Vector3(-f.z, 0, f.x)
	var want := (f * move_input.y + r * move_input.x)
	var mag := minf(1.0, want.length())
	var target_speed := lerpf(0.0, run_speed if (sprint or mag > 0.85) else walk_speed * 1.6, mag)
	var hv := Vector3(velocity.x, 0, velocity.z)
	var tv := want.normalized() * target_speed if mag > 0.05 else Vector3.ZERO
	hv = hv.move_toward(tv, accel * dt * (1.6 if tv == Vector3.ZERO else 1.0))
	velocity.x = hv.x
	velocity.z = hv.z
	if not is_on_floor():
		velocity.y -= gravity * dt
	move_and_slide()
	if hv.length() > 0.2:
		var ang := atan2(hv.x, hv.z)
		body.rotation.y = lerp_angle(body.rotation.y, ang, minf(1.0, dt * 10.0))
	body.animate(hv.length(), dt)

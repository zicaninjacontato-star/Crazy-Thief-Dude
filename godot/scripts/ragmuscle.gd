extends Node
## Ragdoll "ativo" (inspirado no Euphoria): em vez de juntas soltas, cada parte tem "músculos"
## (torque de mola amortecida) que tentam manter o ângulo em relação ao pai como estava na pose do
## momento do impacto. A força cai com o tempo: quem só foi derrubado tenta se proteger e continua
## firme; quem morreu fica tenso por um instante e depois relaxa — mas nunca vira "boneco de pano".
## Também faz o corpo boiar no mar (peças abaixo da superfície recebem empuxo).

var parts := {}          # nome -> RigidBody3D
var parent_of := {}
var rel0 := {}           # nome -> Basis alvo (pai⁻¹ · filho)
var inertia := {}
var alive := false
var t := 0.0
var world2: Node = null

const W0 := 11.0         # frequência natural da "mola" (rad/s)

func _physics_process(dt: float) -> void:
	t += dt
	var any := false
	for n in parts:
		if is_instance_valid(parts[n]):
			any = true
			break
	if not any:
		queue_free()
		return
	# rigidez: vivo (derrubado) segura bem e relaxa até 45%; morto relaxa em ~1,5 s até 18%
	var stiff: float = lerpf(1.0, 0.45, clampf(t / 2.5, 0.0, 1.0)) if alive else lerpf(0.85, 0.18, clampf(t / 1.5, 0.0, 1.0))
	var kp := W0 * W0 * stiff
	var kd := 2.0 * W0 * sqrt(stiff)
	for n in parent_of:
		var c = parts.get(n)
		var p = parts.get(parent_of[n])
		if c == null or p == null or not is_instance_valid(c) or not is_instance_valid(p):
			continue
		if c.sleeping and p.sleeping:
			continue
		var want: Basis = p.global_basis * rel0[n]
		var err: Quaternion = (want * c.global_basis.inverse()).orthonormalized().get_rotation_quaternion()
		if err.w < 0.0:
			err = -err
		var ang := 2.0 * acos(clampf(err.w, -1.0, 1.0))
		var axis := Vector3(err.x, err.y, err.z)
		var al := axis.length()
		var corr := Vector3.ZERO
		if al > 0.0001 and ang > 0.002:
			corr = axis / al * ang
		var rel_av: Vector3 = c.angular_velocity - p.angular_velocity
		# aceleração angular desejada (mola amortecida), limitada; torque = inércia real × aceleração
		var acc: Vector3 = (corr * kp - rel_av * kd).limit_length(260.0)
		var stc := PhysicsServer3D.body_get_direct_state(c.get_rid())
		if stc == null:
			continue
		var ii: Vector3 = stc.inverse_inertia
		if ii.x <= 0.0 or ii.y <= 0.0 or ii.z <= 0.0:
			continue
		var bas: Basis = c.global_basis.orthonormalized()
		var la: Vector3 = bas.transposed() * acc
		var tq: Vector3 = bas * Vector3(la.x / ii.x, la.y / ii.y, la.z / ii.z)
		if not tq.is_finite():
			continue
		c.apply_torque(tq)
		p.apply_torque(-tq * 0.5)
	# boiar no mar
	if world2 != null:
		var wy: float = world2.WATER_Y
		for n in parts:
			var b = parts[n]
			if not is_instance_valid(b):
				continue
			var bp: Vector3 = b.global_position
			if bp.y < wy + 0.1 and world2.is_water(bp.x, bp.z):
				var depth := clampf((wy + 0.1 - bp.y) * 2.5, 0.0, 1.5)
				b.apply_central_force(Vector3.UP * b.mass * 9.8 * (0.6 + depth))
				b.linear_velocity *= 1.0 - minf(0.9, 2.5 * dt)
				b.angular_velocity *= 1.0 - minf(0.9, 2.0 * dt)

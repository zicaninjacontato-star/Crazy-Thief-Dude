extends Node3D
## Corpo humano provisório (sem modelo com esqueleto disponível ainda): proporções reais (1,78 m),
## partes arredondadas e animação procedural de andar/correr. Será trocado por um modelo
## com esqueleto e animações assim que houver um personagem realista com licença livre.

const M := preload("res://scripts/mats.gd")

var phase := 0.0
var legs: Array = []
var arms: Array = []
var torso: Node3D
var head: Node3D
var sitting := false

func build(shirt: Color, pants: Color, skin_c: Color, hair: Color) -> void:
	var skin := M.skin(skin_c)
	var cloth := M.plain(shirt, 0.85)
	var jeans := M.plain(pants, 0.9)
	var shoe := M.plain(Color(0.08, 0.08, 0.09), 0.5)
	var hairm := M.plain(hair, 0.75)
	torso = Node3D.new()
	torso.position = Vector3(0, 1.0, 0)
	add_child(torso)
	_cap(torso, 0.19, 0.62, Vector3(0, 0.3, 0), cloth, Vector3(1.0, 1.0, 0.7))      # tronco
	_cap(torso, 0.17, 0.3, Vector3(0, 0.02, 0), jeans, Vector3(1.05, 1.0, 0.75))    # quadril
	_cap(torso, 0.055, 0.14, Vector3(0, 0.64, 0), skin)                              # pescoço
	head = Node3D.new()
	head.position = Vector3(0, 0.8, 0)
	torso.add_child(head)
	_sph(head, 0.115, Vector3.ZERO, skin, Vector3(0.9, 1.08, 1.0))
	_sph(head, 0.12, Vector3(0, 0.05, -0.015), hairm, Vector3(0.95, 0.85, 1.0))
	_sph(head, 0.02, Vector3(-0.04, 0.01, 0.105), M.plain(Color(0.05, 0.05, 0.05), 0.3))
	_sph(head, 0.02, Vector3(0.04, 0.01, 0.105), M.plain(Color(0.05, 0.05, 0.05), 0.3))
	_sph(head, 0.022, Vector3(0, -0.02, 0.115), skin, Vector3(1, 1.2, 1))
	for s in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.1 * s, 0.98, 0)
		add_child(hip)
		_cap(hip, 0.08, 0.5, Vector3(0, -0.24, 0), jeans)
		var knee := Node3D.new()
		knee.position = Vector3(0, -0.48, 0)
		hip.add_child(knee)
		_cap(knee, 0.065, 0.48, Vector3(0, -0.23, 0), jeans)
		_box(knee, Vector3(0.11, 0.08, 0.27), Vector3(0, -0.47, 0.05), shoe)
		legs.append([hip, knee])
		var sh := Node3D.new()
		sh.position = Vector3(0.235 * s, 0.56, 0)
		torso.add_child(sh)
		_cap(sh, 0.058, 0.32, Vector3(0, -0.14, 0), cloth)
		var elbow := Node3D.new()
		elbow.position = Vector3(0, -0.29, 0)
		sh.add_child(elbow)
		_cap(elbow, 0.045, 0.28, Vector3(0, -0.13, 0), skin)
		_sph(elbow, 0.05, Vector3(0, -0.3, 0), skin, Vector3(0.8, 1.1, 0.6))
		arms.append([sh, elbow, s])

func _cap(p: Node3D, r: float, h: float, pos: Vector3, mat: Material, sc := Vector3.ONE) -> void:
	var mi := MeshInstance3D.new()
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = max(h, r * 2.0)
	c.radial_segments = 12
	c.rings = 4
	mi.mesh = c
	mi.position = pos
	mi.scale = sc
	mi.material_override = mat
	p.add_child(mi)

func _sph(p: Node3D, r: float, pos: Vector3, mat: Material, sc := Vector3.ONE) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 14
	s.rings = 8
	mi.mesh = s
	mi.position = pos
	mi.scale = sc
	mi.material_override = mat
	p.add_child(mi)

func _box(p: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	p.add_child(mi)

## speed em m/s (0 = parado). Corrida acima de 3,5 m/s.
func animate(speed: float, dt: float) -> void:
	if sitting:
		for l in legs:
			l[0].rotation.x = -1.45
			l[1].rotation.x = 1.4
		for a in arms:
			a[0].rotation.x = -0.9
			a[1].rotation.x = -0.4
		return
	var run := clampf((speed - 2.0) / 3.0, 0.0, 1.0)
	phase += dt * (2.0 + speed * 1.9)
	var amp := clampf(speed / 2.0, 0.0, 1.0) * lerpf(0.55, 0.95, run)
	var s := sin(phase)
	for k in legs.size():
		var sg := 1.0 if k == 0 else -1.0
		var l = legs[k]
		l[0].rotation.x = s * amp * sg
		l[1].rotation.x = max(0.0, -sin(phase + 0.9) * sg) * amp * 1.3 + run * 0.25
	for a in arms:
		a[0].rotation.x = -s * amp * a[2] * 0.8
		a[1].rotation.x = -(0.25 + run * 0.9) * minf(1.0, speed)
	torso.rotation.x = run * 0.18
	torso.position.y = 1.0 + absf(cos(phase)) * 0.04 * amp

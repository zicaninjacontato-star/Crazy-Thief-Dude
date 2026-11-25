extends RefCounted
## Armas: dados, modelo na mão e efeitos de tiro (clarão, rastro, faísca no impacto).

const M := preload("res://scripts/mats.gd")

const DATA := {
	"fist": {"name": "SOCO", "dmg": 34.0, "rate": 0.45, "range": 1.7, "auto": false, "spread": 0.0},
	"pistol": {"name": "PISTOLA", "dmg": 42.0, "rate": 0.32, "range": 45.0, "auto": false, "spread": 0.02, "mag": 60},
	"smg": {"name": "SUBMETRALHADORA", "dmg": 19.0, "rate": 0.085, "range": 38.0, "auto": true, "spread": 0.05, "mag": 240},
	"shotgun": {"name": "ESPINGARDA", "dmg": 22.0, "rate": 0.9, "range": 18.0, "auto": false, "spread": 0.09, "pellets": 7, "mag": 30},
	"rifle": {"name": "FUZIL", "dmg": 30.0, "rate": 0.11, "range": 60.0, "auto": true, "spread": 0.03, "mag": 180},
	"sniper": {"name": "SNIPER", "dmg": 160.0, "rate": 1.3, "range": 140.0, "auto": false, "spread": 0.0, "mag": 20},
	"rpg": {"name": "BAZUCA", "dmg": 200.0, "rate": 1.6, "range": 120.0, "auto": false, "spread": 0.0, "mag": 6, "rocket": true},
	"grenade": {"name": "GRANADA", "dmg": 180.0, "rate": 1.0, "range": 30.0, "auto": false, "spread": 0.0, "mag": 8, "throw": true},
}
const ORDER := ["fist", "pistol", "smg", "shotgun", "rifle", "sniper", "rpg", "grenade"]
const ICON := {"fist": "👊", "pistol": "🔫", "smg": "SMG", "shotgun": "ESP", "rifle": "FZL", "sniper": "SNP", "rpg": "RPG", "grenade": "GRN"}

static func gun_mesh(kind: String) -> Node3D:
	var root := Node3D.new()
	if kind == "fist":
		return root
	var dark := M.plain(Color(0.08, 0.08, 0.09), 0.35, 0.8)
	var grip := M.plain(Color(0.12, 0.1, 0.09), 0.7)
	if kind == "grenade":
		var g := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.13
		g.mesh = sm
		g.material_override = M.plain(Color(0.22, 0.28, 0.15), 0.6)
		g.position = Vector3(0, -0.04, 0.02)
		root.add_child(g)
		return root
	if kind == "rpg":
		_b(root, Vector3(0.12, 1.05, 0.12), Vector3(0, -0.1, 0.0), M.plain(Color(0.25, 0.3, 0.18), 0.6))
		_b(root, Vector3(0.18, 0.2, 0.18), Vector3(0, -0.66, 0.0), M.plain(Color(0.3, 0.32, 0.2), 0.6))
		_b(root, Vector3(0.04, 0.05, 0.14), Vector3(0, 0.02, -0.06), grip)
		return root
	var length := 0.22 if kind == "pistol" else (0.42 if kind == "smg" else (0.85 if kind in ["rifle", "sniper"] else 0.75))
	if kind == "rifle":
		_b(root, Vector3(0.045, 0.06, 0.18), Vector3(0, -0.2, -0.08), dark)
		_b(root, Vector3(0.05, 0.26, 0.08), Vector3(0, 0.22, 0.0), M.plain(Color(0.4, 0.25, 0.12), 0.6))
	if kind == "sniper":
		_b(root, Vector3(0.05, 0.28, 0.06), Vector3(0, -0.1, 0.07), dark)
		_b(root, Vector3(0.05, 0.3, 0.08), Vector3(0, 0.24, 0.0), M.plain(Color(0.25, 0.27, 0.2), 0.6))
	_b(root, Vector3(0.045, length, 0.07), Vector3(0, -length * 0.5 + 0.06, 0.03), dark)
	_b(root, Vector3(0.04, 0.05, 0.12), Vector3(0, 0.02, -0.04), grip)
	if kind == "smg":
		_b(root, Vector3(0.035, 0.05, 0.16), Vector3(0, -0.12, -0.06), dark)
	if kind == "shotgun":
		_b(root, Vector3(0.05, 0.3, 0.06), Vector3(0, 0.2, 0.0), M.plain(Color(0.35, 0.22, 0.12), 0.6))
	return root

static func _b(p: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)

static func tracer(world: Node, a: Vector3, b: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var d := a.distance_to(b)
	bm.size = Vector3(0.025, 0.025, d)
	mi.mesh = bm
	mi.material_override = M.emissive(Color(1.0, 0.85, 0.45), 4.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	mi.global_position = (a + b) * 0.5
	if d > 0.01:
		mi.look_at(b, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)
	mi.get_tree().create_timer(0.05).timeout.connect(mi.queue_free)
	# clarão na boca do cano
	var f := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.09
	s.height = 0.18
	s.radial_segments = 8
	s.rings = 4
	f.mesh = s
	f.material_override = M.emissive(Color(1.0, 0.75, 0.3), 6.0)
	world.add_child(f)
	f.global_position = a
	f.get_tree().create_timer(0.04).timeout.connect(f.queue_free)

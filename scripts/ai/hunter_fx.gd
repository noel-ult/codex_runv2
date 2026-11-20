class_name HunterFX
extends RefCounted
## Short-lived visual effects for Hunter weapons (beams, flashes).


static func beam(parent: Node, from: Vector3, to: Vector3, color: Color, life: float = 0.25) -> void:
	var length: float = from.distance_to(to)
	if length < 0.01 or parent == null:
		return
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.03
	cylinder.bottom_radius = 0.03
	cylinder.height = length
	cylinder.radial_segments = 6
	mesh.mesh = cylinder
	var material := MaterialLibrary.emissive(color, 8.0, false)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	mesh.global_position = (from + to) * 0.5
	var direction: Vector3 = (to - from).normalized()
	var up: Vector3 = Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	mesh.global_basis = Basis.looking_at(direction, up) * Basis(Vector3.RIGHT, PI * 0.5)
	var tween := mesh.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, life)
	tween.tween_callback(mesh.queue_free)


static func flash(parent: Node, at: Vector3, color: Color, radius: float = 4.0) -> void:
	if parent == null:
		return
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 6.0
	light.omni_range = radius
	parent.add_child(light)
	light.global_position = at
	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.35)
	tween.tween_callback(light.queue_free)

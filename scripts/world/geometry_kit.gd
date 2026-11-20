class_name GeometryKit
extends RefCounted
## Static helpers that turn primitive meshes + materials into scene nodes.
## Every solid piece of the world goes through `solid_box` so collision layers stay consistent.

const WORLD_LAYER: int = 1
const DOOR_LAYER: int = 32


static func mesh_box(parent: Node3D, center: Vector3, size: Vector3, material: Material, shadows: bool = true) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = material
	instance.position = center
	if not shadows:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


## Collidable box on the world layer (parsed by the navmesh baker). Returns the visual mesh.
static func solid_box(parent: Node3D, center: Vector3, size: Vector3, material: Material, layer: int = WORLD_LAYER) -> MeshInstance3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	return mesh_box(body, Vector3.ZERO, size, material)


static func collider_box(parent: Node3D, center: Vector3, size: Vector3, layer: int = WORLD_LAYER) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	return body


static func cylinder(parent: Node3D, center: Vector3, radius_top: float, radius_bottom: float, height: float, material: Material, segments: int = 16) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius_top
	mesh.bottom_radius = radius_bottom
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	instance.mesh = mesh
	instance.material_override = material
	instance.position = center
	parent.add_child(instance)
	return instance


static func sphere(parent: Node3D, center: Vector3, radius: float, material: Material, squash: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 20
	mesh.rings = 10
	instance.mesh = mesh
	instance.material_override = material
	instance.position = center
	instance.scale = squash
	parent.add_child(instance)
	return instance


static func capsule(parent: Node3D, center: Vector3, radius: float, height: float, material: Material, squash: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.0)
	mesh.radial_segments = 16
	mesh.rings = 6
	instance.mesh = mesh
	instance.material_override = material
	instance.position = center
	instance.scale = squash
	parent.add_child(instance)
	return instance


## Box rotated around an arbitrary axis (for slanted windscreens, ramps, struts).
static func tilted_box(parent: Node3D, center: Vector3, size: Vector3, euler_degrees: Vector3, material: Material) -> MeshInstance3D:
	var instance := mesh_box(parent, center, size, material)
	instance.rotation_degrees = euler_degrees
	return instance


static func set_facade(instance: MeshInstance3D, wall_color: Color, style: float, seed_value: float, lit_ratio: float, base_y: float, top_y: float, storefront: bool) -> void:
	instance.set_instance_shader_parameter(&"wall_color", wall_color)
	instance.set_instance_shader_parameter(&"facade_style", style)
	instance.set_instance_shader_parameter(&"seed", seed_value)
	instance.set_instance_shader_parameter(&"lit_ratio", lit_ratio)
	instance.set_instance_shader_parameter(&"base_y", base_y)
	instance.set_instance_shader_parameter(&"top_y", top_y)
	instance.set_instance_shader_parameter(&"storefront", 1.0 if storefront else 0.0)

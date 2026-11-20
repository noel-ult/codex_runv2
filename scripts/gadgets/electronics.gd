class_name Electronics
extends RefCounted
## Contract for anything the Runner's gadgets can disable:
##   - node is in group ELECTRONICS_GROUP and implements `disable_for(seconds: float)`
##   - node owns a hitbox on HITBOX_LAYER so Jammer Darts can hit it
## Hunters join EMP_GROUP and implement `apply_emp(seconds: float)` (stun / visor scramble).

const ELECTRONICS_GROUP: StringName = &"electronics"
const EMP_GROUP: StringName = &"emp_receivers"
const HITBOX_LAYER: int = 64


static func add_hitbox(owner_node: Node3D, local_position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = HITBOX_LAYER
	body.collision_mask = 0
	body.position = local_position
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	owner_node.add_child(body)
	return body


## Walks up from a collider to the first node implementing the given group contract.
static func resolve(collider: Object, group: StringName) -> Node:
	var node := collider as Node
	while node != null:
		if node.is_in_group(group):
			return node
		node = node.get_parent()
	return null


static func disable_in_radius(tree: SceneTree, center: Vector3, radius: float, seconds: float) -> int:
	var count: int = 0
	for node: Node in tree.get_nodes_in_group(ELECTRONICS_GROUP):
		var device := node as Node3D
		if device != null and device.global_position.distance_to(center) <= radius and device.has_method(&"disable_for"):
			device.call(&"disable_for", seconds)
			count += 1
	return count


static func emp_in_radius(tree: SceneTree, center: Vector3, radius: float, seconds: float) -> int:
	var count: int = 0
	for node: Node in tree.get_nodes_in_group(EMP_GROUP):
		var target := node as Node3D
		if target != null and target.global_position.distance_to(center) <= radius and target.has_method(&"apply_emp"):
			target.call(&"apply_emp", seconds)
			count += 1
	return count


static func sparks(parent: Node, at: Vector3, color: Color) -> void:
	if parent == null:
		return
	var particles := GPUParticles3D.new()
	particles.amount = 24
	particles.lifetime = 0.5
	particles.one_shot = true
	particles.explosiveness = 0.9
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 180.0
	process.initial_velocity_min = 2.0
	process.initial_velocity_max = 5.0
	process.gravity = Vector3(0.0, -9.8, 0.0)
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var material := MaterialLibrary.emissive(color, 6.0, false)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = material
	particles.draw_pass_1 = quad
	parent.add_child(particles)
	particles.global_position = at
	particles.emitting = true
	var timer := parent.get_tree().create_timer(1.0)
	timer.timeout.connect(particles.queue_free)

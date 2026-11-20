extends RefCounted
## Consolidates the city builder's static primitives. The collision bodies and
## authored objects stay in place. Batches are small enough to cull by street section.

const CHUNK_SIZE: float = 24.0
const ANIMATED_GROUP: StringName = &"animated_world_props"


class MeshGroup:
	var sources: Array[MeshInstance3D] = []
	var shape: PrimitiveMesh
	var material: Material
	var box_scale: bool = false
	var paint: Variant
	var chunk: Vector2i


static func optimize(geometry: Node3D) -> void:
	var groups: Dictionary[Array, MeshGroup] = {}
	_collect(geometry, geometry.global_transform.affine_inverse(), groups)
	var batches := Node3D.new()
	batches.name = "StaticMeshBatches"
	geometry.add_child(batches)
	var unit_box := BoxMesh.new()
	unit_box.size = Vector3.ONE
	for group: MeshGroup in groups.values():
		if group.sources.size() > 1:
			_add_batch(geometry, batches, group, unit_box)


static func _collect(node: Node3D, world_to_geometry: Transform3D, groups: Dictionary[Array, MeshGroup]) -> void:
	for child: Node in node.get_children():
		var spatial: Node3D = child as Node3D
		if spatial == null or not spatial.visible or spatial.top_level or spatial.get_script() != null:
			continue
		if spatial.is_in_group(ANIMATED_GROUP):
			continue
		if spatial is MeshInstance3D:
			_collect_mesh(spatial as MeshInstance3D, world_to_geometry, groups)
		elif spatial.get_class() in ["Node3D", "StaticBody3D"]:
			_collect(spatial, world_to_geometry, groups)


static func _collect_mesh(instance: MeshInstance3D, world_to_geometry: Transform3D, groups: Dictionary[Array, MeshGroup]) -> void:
	# Keep anything with custom culling, lighting, overrides or dependent children separate.
	if instance.get_child_count() != 0 or instance.material_overlay != null or not instance.visibility_parent.is_empty():
		return
	if instance.visibility_range_begin != 0.0 or instance.visibility_range_end != 0.0:
		return
	if instance.extra_cull_margin != 0.0 or instance.lod_bias != 1.0 or instance.ignore_occlusion_culling:
		return
	if instance.custom_aabb != AABB() or instance.sorting_offset != 0.0:
		return

	var shape: PrimitiveMesh = instance.mesh as PrimitiveMesh
	if shape == null or shape.flip_faces or shape.add_uv2:
		return
	var material: Material = instance.material_override
	if material == null:
		return
	var standard: StandardMaterial3D = material as StandardMaterial3D
	# Road paint uses world coordinates. Copy its instance tint to a per-color batch.
	# Other shaders can depend on per-object uniforms or local transforms.
	var paint: Variant = null
	if standard == null:
		if material != MaterialLibrary.road_paint():
			return
		paint = instance.get_instance_shader_parameter(&"paint")
	elif standard.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return

	var box_scale: bool = shape is BoxMesh and (standard == null or not standard.uv1_triplanar or standard.uv1_world_triplanar)
	var shape_key: Array = _shape_signature(shape, box_scale)
	if shape_key.is_empty():
		return
	var origin: Vector3 = world_to_geometry * instance.global_position
	var chunk := Vector2i(roundi(origin.x / CHUNK_SIZE), roundi(origin.z / CHUNK_SIZE))
	var key: Array = [shape_key, material, paint, chunk, instance.cast_shadow, instance.layers, instance.gi_mode]
	var group: MeshGroup = groups.get(key) as MeshGroup
	if group == null:
		group = MeshGroup.new()
		group.shape = shape
		group.material = material
		group.box_scale = box_scale
		group.paint = paint
		group.chunk = chunk
		groups[key] = group
	group.sources.append(instance)


static func _shape_signature(shape: PrimitiveMesh, box_scale: bool) -> Array:
	if shape is BoxMesh:
		var box: BoxMesh = shape as BoxMesh
		if box.subdivide_width != 0 or box.subdivide_height != 0 or box.subdivide_depth != 0:
			return []
		return [&"box", Vector3.ONE if box_scale else box.size]
	if shape is CylinderMesh:
		var cylinder: CylinderMesh = shape as CylinderMesh
		return [&"cylinder", cylinder.top_radius, cylinder.bottom_radius, cylinder.height, cylinder.radial_segments, cylinder.rings, cylinder.cap_top, cylinder.cap_bottom]
	if shape is SphereMesh:
		var sphere: SphereMesh = shape as SphereMesh
		return [&"sphere", sphere.radius, sphere.height, sphere.radial_segments, sphere.rings, sphere.is_hemisphere]
	return []


static func _add_batch(geometry: Node3D, destination: Node3D, group: MeshGroup, unit_box: BoxMesh) -> void:
	var first: MeshInstance3D = group.sources[0]
	var local_origin := Vector3(group.chunk.x * CHUNK_SIZE, 0.0, group.chunk.y * CHUNK_SIZE)
	var chunk_to_world: Transform3D = geometry.global_transform.translated_local(local_origin)
	var world_to_chunk: Transform3D = chunk_to_world.affine_inverse()
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = unit_box if group.box_scale else group.shape
	batch.instance_count = group.sources.size()
	for i: int in group.sources.size():
		var source: MeshInstance3D = group.sources[i]
		var relative: Transform3D = world_to_chunk * source.global_transform
		if group.box_scale:
			var box: BoxMesh = source.mesh as BoxMesh
			relative = relative.scaled_local(box.size)
		batch.set_instance_transform(i, relative)
	var combined := MultiMeshInstance3D.new()
	combined.position = local_origin
	combined.multimesh = batch
	combined.material_override = group.material
	combined.cast_shadow = first.cast_shadow
	combined.gi_mode = first.gi_mode
	combined.layers = first.layers
	destination.add_child(combined)
	if group.paint != null:
		combined.set_instance_shader_parameter(&"paint", group.paint)
	for source: MeshInstance3D in group.sources:
		source.free()

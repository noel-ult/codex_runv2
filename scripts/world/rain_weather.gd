class_name RainWeather
extends Node3D
## Night drizzle: a GPU particle volume that follows the active camera, with camera-facing
## streaks stretched along their fall velocity (the wet-asphalt shader provides the puddles).

@export var drops: int = 5000
@export var area: Vector3 = Vector3(26.0, 1.0, 26.0)
@export var height_above: float = 14.0
@export var fall_speed: float = 24.0

var _rain: GPUParticles3D
var _material: StandardMaterial3D
var _intensity: float = 1.0


func _ready() -> void:
	_rain = GPUParticles3D.new()
	_rain.amount = drops
	_rain.lifetime = (height_above + 4.0) / fall_speed
	_rain.preprocess = _rain.lifetime
	_rain.local_coords = false
	_rain.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	_rain.visibility_aabb = AABB(Vector3(-area.x, -height_above - 6.0, -area.z), Vector3(area.x * 2.0, height_above + 10.0, area.z * 2.0))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = area
	process.direction = Vector3(0.12, -1.0, 0.05)
	process.spread = 2.0
	process.initial_velocity_min = fall_speed * 0.9
	process.initial_velocity_max = fall_speed * 1.1
	process.gravity = Vector3.ZERO
	_rain.process_material = process
	var streak := QuadMesh.new()
	streak.size = Vector2(0.012, 0.55)
	var material := StandardMaterial3D.new()
	_material = material
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.75, 0.8, 0.9, 0.22)
	material.disable_receive_shadows = true
	streak.material = material
	_rain.draw_pass_1 = streak
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rain)



## 0 = dry, 1 = downpour. Driven by WeatherSystem.
func set_intensity(value: float) -> void:
	_intensity = clampf(value, 0.0, 1.0)
	if _rain == null:
		return
	_rain.amount_ratio = maxf(_intensity, 0.001)
	_rain.emitting = _intensity > 0.02
	_material.albedo_color.a = lerpf(0.12, 0.3, _intensity)


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var at: Vector3 = camera.global_position
	_rain.global_position = Vector3(at.x, at.y + height_above, at.z) - camera.global_basis.z * 6.0

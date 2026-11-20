class_name ResidualEcho
extends Node3D
## A decaying breadcrumb left behind by an Ignited Codex.
## Its `strength` falls from 1.0 to 0.0 over `lifetime`; when it reaches zero the echo
## emits `expired` and frees itself. Visuals are generated procedurally.

signal expired(echo: ResidualEcho)

const ECHO_COLOR: Color = Color(1.0, 0.45, 0.1)

@export var lifetime: float = 16.0

var strength: float = 1.0
var _age: float = 0.0
var _core_material: StandardMaterial3D
var _ring_material: StandardMaterial3D
var _ring: MeshInstance3D
var _light: OmniLight3D


func _ready() -> void:
	_core_material = _make_material(0.9)
	_ring_material = _make_material(0.6)

	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.7
	core.mesh = sphere
	core.material_override = _core_material
	core.position = Vector3(0.0, 1.0, 0.0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)

	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.1
	_ring.mesh = torus
	_ring.material_override = _ring_material
	_ring.position = Vector3(0.0, 0.05, 0.0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	_light = OmniLight3D.new()
	_light.light_color = ECHO_COLOR
	_light.omni_range = 6.0
	_light.light_energy = 1.5
	_light.position = Vector3(0.0, 1.0, 0.0)
	add_child(_light)


func _process(delta: float) -> void:
	_age += delta
	strength = clampf(1.0 - _age / lifetime, 0.0, 1.0)
	var pulse: float = 1.0 + 0.25 * sin(_age * 6.0)
	_ring.scale = Vector3.ONE * (1.0 + (1.0 - strength) * 2.5) * pulse
	_core_material.albedo_color.a = 0.9 * strength
	_ring_material.albedo_color.a = 0.6 * strength
	_light.light_energy = 1.5 * strength
	if strength <= 0.0:
		expired.emit(self)
		queue_free()


func _make_material(alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(ECHO_COLOR, alpha)
	material.emission_enabled = true
	material.emission = ECHO_COLOR
	material.emission_energy_multiplier = 2.0
	return material

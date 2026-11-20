class_name DecoyEmitter
extends Node3D
## Deployable fake Codex. Placing one costs Resonance Cells; it does nothing until the Runner
## imprints it with part of their own Resonance (hold E). An armed decoy:
##   - takes the next Codex Release in the Runner's place (spending charge), and
##   - echoes Ignition broadcasts as a fake beacon, draining charge.
## Hunters that reach a decoy shoot it apart. Implements the CodexSignalSystem DECOY_* contract.

signal destroyed(decoy: DecoyEmitter)
signal charge_changed(decoy: DecoyEmitter, charge: float)

const GROUP: StringName = &"decoy_emitters"

@export var max_charge: float = 60.0
@export var imprint_amount: float = 30.0
@export var min_imprint_resonance: float = 15.0

var charge: float = 0.0
var interactable: Interactable

var _core_material: StandardMaterial3D
var _ring: MeshInstance3D
var _light: OmniLight3D
var _label: Label3D
var _shock: MeshInstance3D
var _shock_material: StandardMaterial3D
var _shock_t: float = -1.0
var _time: float = 0.0
var _dying: float = -1.0


func _ready() -> void:
	add_to_group(GROUP)
	var steel := MaterialLibrary.coated(Color(0.16, 0.17, 0.19), 0.85, 0.35)
	var brass := MaterialLibrary.coated(Color(0.7, 0.55, 0.25), 0.95, 0.25)
	for i: int in 3:
		var a: float = TAU * float(i) / 3.0
		GeometryKit.tilted_box(self, Vector3(cos(a) * 0.28, 0.35, sin(a) * 0.28), Vector3(0.05, 0.8, 0.05), Vector3(sin(a) * 20.0, 0.0, -cos(a) * 20.0), steel)
	GeometryKit.cylinder(self, Vector3(0.0, 0.75, 0.0), 0.18, 0.22, 0.12, steel, 16)
	for y: float in [0.86, 1.0, 1.14]:
		GeometryKit.cylinder(self, Vector3(0.0, y, 0.0), 0.13, 0.13, 0.04, brass, 16)
	_core_material = MaterialLibrary.emissive(Color(0.4, 0.4, 0.45), 0.5, false)
	GeometryKit.sphere(self, Vector3(0.0, 1.32, 0.0), 0.14, _core_material)
	GeometryKit.cylinder(self, Vector3(0.0, 1.6, 0.0), 0.01, 0.015, 0.45, steel, 6)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.24
	torus.outer_radius = 0.27
	_ring.mesh = torus
	_ring.material_override = _core_material
	_ring.position = Vector3(0.0, 1.32, 0.0)
	add_child(_ring)
	_light = OmniLight3D.new()
	_light.light_energy = 0.0
	_light.omni_range = 6.0
	_light.position = Vector3(0.0, 1.4, 0.0)
	add_child(_light)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 32
	_label.pixel_size = 0.008
	_label.outline_size = 6
	_label.position = Vector3(0.0, 2.0, 0.0)
	add_child(_label)
	_shock_material = MaterialLibrary.hologram(Color(1.0, 0.7, 0.25), 0.0)
	_shock = MeshInstance3D.new()
	var shock_mesh := TorusMesh.new()
	shock_mesh.inner_radius = 0.9
	shock_mesh.outer_radius = 1.0
	_shock.mesh = shock_mesh
	_shock.material_override = _shock_material
	_shock.position = Vector3(0.0, 0.2, 0.0)
	_shock.visible = false
	add_child(_shock)

	interactable = Interactable.new()
	interactable.prompt = "Imprint your Codex signature (-%d Resonance)" % int(imprint_amount)
	interactable.hold_time = 2.5
	interactable.radius = 2.0
	interactable.position = Vector3(0.0, 0.5, 0.0)
	interactable.requirement = func(actor: Node3D) -> bool: return _actor_resonance(actor) >= min_imprint_resonance and charge < max_charge - 1.0
	interactable.requirement_hint = "Decoy needs at least %d Resonance to imprint (build some first)" % int(min_imprint_resonance)
	add_child(interactable)
	interactable.completed.connect(_on_imprint)
	_refresh()


func _process(delta: float) -> void:
	_time += delta
	_ring.rotation = Vector3(_time * 1.3, _time * 2.1, 0.0)
	if _shock_t >= 0.0:
		_shock_t += delta
		var k: float = _shock_t / 1.2
		_shock.visible = true
		_shock.scale = Vector3.ONE * (1.0 + k * 22.0)
		_shock_material.albedo_color = Color(1.0, 0.7, 0.25, 0.5 * (1.0 - k))
		if k >= 1.0:
			_shock_t = -1.0
			_shock.visible = false
	if _dying >= 0.0:
		_dying += delta
		scale = Vector3.ONE * maxf(1.0 - _dying * 1.5, 0.01)
		if _dying > 0.65:
			queue_free()


# --- Decoy contract -----------------------------------------------------------------

func get_charge() -> float:
	return charge if _dying < 0.0 else 0.0


func consume_charge(amount: float) -> void:
	charge = maxf(charge - amount, 0.0)
	_refresh()


func play_pulse() -> void:
	_shock_t = 0.0


## Called by Hunter weapons when they reach the decoy.
func hunter_disable() -> void:
	if _dying >= 0.0:
		return
	_dying = 0.0
	charge = 0.0
	interactable.enabled = false
	destroyed.emit(self)


func _actor_resonance(actor: Node3D) -> float:
	var runner := actor as PlayerController
	return runner.get_codex().resonance if runner != null else 0.0


func _on_imprint(_i: Interactable, actor: Node3D) -> void:
	var runner := actor as PlayerController
	if runner == null:
		return
	var moved: float = runner.get_codex().drain_resonance(minf(imprint_amount, max_charge - charge))
	charge = minf(charge + moved, max_charge)
	runner.get_codex().feedback.emit("Decoy imprinted: charge %d (each Release costs 20)." % int(charge))
	_refresh()


func _refresh() -> void:
	var armed: bool = charge >= 1.0
	var color: Color = Color(1.0, 0.72, 0.25) if armed else Color(0.4, 0.4, 0.45)
	_core_material.albedo_color = color
	_core_material.emission = color
	_core_material.emission_energy_multiplier = 0.5 + 4.0 * charge / max_charge
	_light.light_color = color
	_light.light_energy = 2.5 * charge / max_charge
	_label.text = "DECOY  %d%%" % int(100.0 * charge / max_charge) if armed else "DECOY  UNPRIMED"
	_label.modulate = color
	charge_changed.emit(self, charge)

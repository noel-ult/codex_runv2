class_name Interactable
extends Node3D
## Hold-to-use world interaction point (hack panels, vault console, device, uplink, hatch).
## The PlayerController finds the nearest enabled Interactable in range, shows its prompt and
## accumulates hold time while the interact key is held. When the hold completes the
## interactable emits `completed`; game systems connect to that signal.

signal completed(interactable: Interactable, actor: Node3D)
signal hold_progress(interactable: Interactable, progress: float)

const GROUP: StringName = &"interactables"

@export var prompt: String = "Interact"
@export var hold_time: float = 1.0
## Horizontal reach from the actor's feet.
@export var radius: float = 2.2
## Max vertical gap between the actor's feet and this point (keeps roof/ground prompts apart).
@export var height_tolerance: float = 1.8
@export var enabled: bool = true
@export var one_shot: bool = false
## Optional: only usable by actors that satisfy this callable (set from code).
var requirement: Callable
var requirement_hint: String = ""


func _ready() -> void:
	add_to_group(GROUP)


func is_available_for(actor: Node3D) -> bool:
	if not enabled:
		return false
	var offset: Vector3 = global_position - actor.global_position
	return Vector2(offset.x, offset.z).length() <= radius and absf(offset.y) <= height_tolerance


func meets_requirement(actor: Node3D) -> bool:
	return not requirement.is_valid() or bool(requirement.call(actor))


func get_prompt_text(actor: Node3D) -> String:
	if not meets_requirement(actor):
		return requirement_hint
	return "[Hold E] %s" % prompt


func report_progress(progress: float) -> void:
	hold_progress.emit(self, progress)


func complete(actor: Node3D) -> void:
	if one_shot:
		enabled = false
	completed.emit(self, actor)

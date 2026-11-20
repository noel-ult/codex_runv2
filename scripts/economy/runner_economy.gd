class_name RunnerEconomy
extends Node
## Credits earned from city work and spent on supplies. Capture leaves the wallet intact.

signal credits_changed(balance: int)
signal feedback(message: String)

const STARTING_CREDITS: int = 40
const MAX_CREDITS: int = 1000000000

var credits: int:
	get:
		return _credits

var _credits: int = STARTING_CREDITS
var _transacting: bool = false


func get_balance() -> int:
	return _credits


func earn(amount: int, reason: String = "") -> bool:
	if amount < 0 or amount > MAX_CREDITS - _credits or _transacting:
		return false
	if amount == 0:
		return true
	_credits += amount
	credits_changed.emit(_credits)
	feedback.emit("%s +%d credits  ·  Balance %d" % [reason if not reason.is_empty() else "Payment", amount, _credits])
	return true


func spend(amount: int) -> bool:
	if amount < 0 or amount > _credits or _transacting:
		return false
	if amount == 0:
		return true
	_credits -= amount
	credits_changed.emit(_credits)
	return true


func catalog() -> Array[Dictionary]:
	return [
		{"id": &"darts", "title": "Jammer darts ×3", "price": 18, "quantity": 3, "description": "Silent ammunition for the Jammer. Disables a device or scrambles a Hunter's visor."},
		{"id": &"emp", "title": "EMP charge", "price": 25, "quantity": 1, "description": "A throwable charge that shuts down nearby electronics and stuns Hunters. The discharge builds Resonance."},
		{"id": &"cells", "title": "Resonance cells ×2", "price": 16, "quantity": 2, "description": "Two cells build one Decoy Codex. Place the decoy, then hold E to imprint it."},
		{"id": &"salvage", "title": "Salvage parts ×2", "price": 20, "quantity": 2, "description": "Materials for fabrication and permanent upgrades at the Storage 07 prep station."},
	]


func purchase_block_reason(item_id: StringName, belt: GadgetBelt) -> String:
	if _transacting:
		return "Finish the current purchase first."
	if not is_instance_valid(belt):
		return "Supplies are unavailable."
	var item: Dictionary = _find_item(item_id)
	if item.is_empty():
		return "Unknown supply item."
	var quantity: int = int(item["quantity"])
	match item_id:
		&"darts":
			if belt.max_darts - belt.darts < quantity:
				return "Need room for all 3 darts in the rack."
		&"emp":
			if belt.max_emps - belt.emps < quantity:
				return "EMP capacity is full."
		&"cells":
			if belt.max_cells - belt.cells < quantity:
				return "Need room for both cells in the pouch."
		&"salvage":
			if belt.parts > MAX_CREDITS - quantity:
				return "Salvage storage is full."
	if _credits < int(item["price"]):
		return "Need %d more credits." % (int(item["price"]) - _credits)
	return ""


## Validate all state before changing either inventory or balance. Signals publish the final pair.
func purchase(item_id: StringName, belt: GadgetBelt) -> bool:
	var blocked: String = purchase_block_reason(item_id, belt)
	if not blocked.is_empty():
		feedback.emit(blocked)
		return false
	var item: Dictionary = _find_item(item_id)
	var quantity: int = int(item["quantity"])
	_transacting = true
	_credits -= int(item["price"])
	match item_id:
		&"darts":
			belt.darts += quantity
		&"emp":
			belt.emps += quantity
		&"cells":
			belt.cells += quantity
		&"salvage":
			belt.parts += quantity
	# Prevent callbacks from spending the new balance during a partially published transaction.
	credits_changed.emit(_credits)
	if item_id == &"salvage":
		belt.parts_changed.emit(belt.parts)
	belt.publish()
	_transacting = false
	feedback.emit("Purchased %s for %d credits." % [String(item["title"]), int(item["price"])])
	return true


func _find_item(item_id: StringName) -> Dictionary:
	for item: Dictionary in catalog():
		if item["id"] == item_id:
			return item
	return {}

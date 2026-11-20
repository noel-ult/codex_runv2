class_name WorldConditions
extends RefCounted
## Shared read-only snapshot of the environment, written by TimeOfDay / WeatherSystem and read
## by sensors and AI (cameras, turrets, drones, the Codex). Static so any system can sample it
## without holding references to the environment nodes.

static var hour: float = 21.0
## 1 = night, 0 = full daylight.
static var night_factor: float = 1.0
static var is_day: bool = false
## Multiplier on sensor/vision ranges (fog and rain lower it, daylight raises it).
static var visibility: float = 1.0
static var weather_name: String = "CLEAR"
static var drones_grounded: bool = false


static func reset() -> void:
	hour = 21.0
	night_factor = 1.0
	is_day = false
	visibility = 1.0
	weather_name = "CLEAR"
	drones_grounded = false

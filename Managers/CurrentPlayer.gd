extends Node

const SIGNAL_STATS_CHANGED = "stats_changed"

var country_name: String = "iraq"
var flag_texture: Texture2D = _get_flag(country_name)

#-------
# Stats
var political_power: float = 50.0
var stability: float = 0.75   # 0.0 → 1.0
var dollars: float = 1000.0
var manpower: int = 50000



# Constants for now
const MAX_STABILITY := 1.0
const MIN_STABILITY := 0.0
const POLITICAL_POWER_GAIN_DAILY := 2.0
const DOLLAR_INCOME_DAILY := 480.0      # example: 20/hour * 24
const MANPOWER_GROWTH_DAILY := 600       # example: 25/hour * 24


signal stats_changed()

func _ready() -> void:
	await get_tree().process_frame  # wait until all singletons are ready
	if MainClock and not MainClock.is_connected("day_passed", Callable(self, "_on_day_passed")):
		MainClock.connect("day_passed", Callable(self, "_on_day_passed"))



func get_country():
	return self.country_name.to_lower()

# Connected to day_passed signal of gameclock
func _on_day_passed(day) -> void:
	_update_daily_resources()
	emit_signal(SIGNAL_STATS_CHANGED)

# Resource updates
func _update_daily_resources() -> void:
	_add_political_power(POLITICAL_POWER_GAIN_DAILY)
	_add_dollars(DOLLAR_INCOME_DAILY)
	_add_manpower(MANPOWER_GROWTH_DAILY)
	_update_stability_over_time()

# pp stuff 
func _add_political_power(amount: float) -> void:
	political_power += amount
	political_power = max(political_power, 0.0)

func spend_political_power(amount: float) -> bool:
	if political_power < amount:
		return false
	political_power -= amount
	return true


func change_stability(delta: float) -> void:
	stability = clamp(stability + delta, MIN_STABILITY, MAX_STABILITY)


# This logic is getting changed. This is just for testing
func _update_stability_over_time() -> void:
	var target := 0.75
	stability += (target - stability) * 0.01
	stability = clamp(stability, MIN_STABILITY, MAX_STABILITY)



func _add_dollars(amount: float) -> void:
	dollars += amount

func spend_dollars(amount: float) -> bool:
	if dollars < amount:
		return false
	dollars -= amount
	return true


func _add_manpower(amount: int) -> void:
	manpower += amount

func spend_manpower(amount: int) -> bool:
	if manpower < amount:
		return false
	manpower -= amount
	return true

func _get_flag(country):
	var path = "res://assets/flags/%s_flag.png" % country.to_lower()
	if ResourceLoader.exists(path):
		var image = Image.new()
		var error = image.load(path)
		if error == OK:
			var texture = ImageTexture.new()
			texture.create_from_image(image)
			return texture
		else:
			print("Failed to load image: ", path)
			return null
	else:
		print("Resource does not exist: ", path)
		return null



func setup_player_country(_name: String, _flagName: String) -> void:
	country_name = _name
	#flag_texture = DataManager.get_country_flag(country_name) 
	print("Player country set to:", country_name)
	emit_signal(SIGNAL_STATS_CHANGED)



# Helper
func get_summary() -> Dictionary:
	return {
		"name": country_name,
		"flag": flag_texture,
		"political_power": int(political_power),
		"stability": int(stability * 100.0),
		"dollars": int(dollars),
		"manpower": manpower
	}

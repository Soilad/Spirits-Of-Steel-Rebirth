extends Node
class_name GameClock

signal hour_passed(hour: int)
signal day_passed(year: int, month: int, day: int)
signal month_passed(year: int, month: int)
signal year_passed(year: int)
signal time_scale_changed(speed: float)

# ------------------------
# Config
# ------------------------
@export var hours_per_tick := 1 # How many in-game hours pass per tick
@export var seconds_per_tick := 1.0 # Real seconds per tick
@export var start_hour := 0
# New: Start Date
@export var start_year := 2010
@export var start_month := 1 # 1-12
@export var start_day := 1 # 1-31

var MAX_SPEED := 75.0
var PAUSE := 0.0

# Speed control (1 = normal, 2 = 2x faster, 0 = paused)
var time_scale := 0.0


		
# ------------------------
# Internal state
# ------------------------
var hour: int
var date_dict: Dictionary # Stores year, month, day
var accumulated_time: float = 0.0

# ------------------------
# Lifecycle
# ------------------------
func _ready() -> void:
	hour = start_hour
	date_dict = {
		"year": start_year,
		"month": start_month,
		"day": start_day
	}
	accumulated_time = 0.0

# This makes sure there’s only one global instance
static var instance: GameClock

func _enter_tree() -> void:
	if instance == null:
		instance = self
	else:
		queue_free() # Prevent duplicates

func _process(delta: float) -> void:
	if time_scale <= PAUSE:
		return

	accumulated_time += delta * time_scale

	while accumulated_time >= seconds_per_tick:
		accumulated_time -= seconds_per_tick
		_tick_hour()

# ------------------------
# Internal logic
# ------------------------
func _tick_hour() -> void:
	hour += hours_per_tick
	emit_signal("hour_passed", hour)

	while hour >= 24:
		hour -= 24
		_tick_day()

func _tick_day() -> void:
	var old_month = date_dict.month
	var old_year = date_dict.year
	
	# Use the Time class to advance the date by 1 day
	date_dict = Time.get_datetime_dict_from_unix_time(
		Time.get_unix_time_from_datetime_dict(date_dict) + (24 * 60 * 60)
	)
	
	emit_signal("day_passed", date_dict.year, date_dict.month, date_dict.day)

	# Check for Month/Year change and emit signals
	if date_dict.month != old_month:
		emit_signal("month_passed", date_dict.year, date_dict.month)
		
		if date_dict.year != old_year:
			emit_signal("year_passed", date_dict.year)

# ------------------------
# Utility
# ------------------------
func get_time_string() -> String:
	# Returns the time as HH:00
	return "%02d:00" % hour

func get_date_string() -> String:
	# Returns the date as YYYY-MM-DD
	return "%04d-%02d-%02d" % [date_dict.year, date_dict.month, date_dict.day]

# Optional: Get a full datetime string (e.g., 2010-01-01 15:00)
func get_datetime_string() -> String:
	return "%s %s" % [get_time_string(), get_date_string()]

# ------------------------
# Speed control
# ------------------------
func set_speed(scale: float) -> void:
	time_scale = clamp(scale, PAUSE, MAX_SPEED)
	emit_signal("time_scale_changed", time_scale)

func decreaseSpeed():
	set_speed(time_scale - 15)

func increaseSpeed():
	set_speed(time_scale + 15)

func maxSpeed():
	set_speed(MAX_SPEED)

func pause() -> void:
	set_speed(PAUSE)

func resume() -> void:
	set_speed(1.0)

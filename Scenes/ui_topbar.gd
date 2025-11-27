extends CanvasLayer

@onready var nation_flag: TextureRect = $ColorRect/MarginContainer/HBoxContainer/nation_flag
@onready var label_date: Label = $ColorRect/MarginContainer2/ColorRect/MarginContainer/label_date
@onready var check_button: CheckButton = $CheckButton

@onready var labelMerge: Label = $Label

func _ready() -> void:
	labelMerge.text = "A" if TroopManager.AUTO_MERGE else "M"
	
	var texture = _get_flag(CurrentPlayer.get_country())  # check country code used
	if texture:
		nation_flag.texture = texture
		print("Flag texture set successfully.")
	else:
		print("Failed to set flag texture.")
		
	MainClock.connect("hour_passed", Callable(self, "_update_visuals"))
func _update_visuals(hour):
	label_date.text = MainClock.get_datetime_string()

func on_check_toggle(pressed):
	TroopManager.change_merge()

func _get_flag(country):
	var path = "res://assets/flags/%s_flag.png" % country.to_lower()
	if ResourceLoader.exists(path):
		var image = Image.new()
		var err = image.load(path)
		if err == OK:
			var texture = ImageTexture.create_from_image(image)  # Static call returns new texture
			return texture
		else:
			push_error("Failed to load image: %s" % path)
			return null
	else:
		push_error("Flag texture does not exist: %s" % path)
		return null




func _on_button_mouse_entered() -> void:
	MusicManager.play_sfx(MusicManager.SFX.HOVERED)
	pass # Replace with function body.


func _on_speed_button_pressed(increase: bool) -> void:
	if increase:
		MainClock.increaseSpeed()
	elif not increase:
		MainClock.decreaseSpeed()
	pass # Replace with function body.


func _on_button_pressed() -> void:
	TroopManager.change_merge()
	labelMerge.text = "A" if TroopManager.AUTO_MERGE else "M"
	pass # Replace with function body.

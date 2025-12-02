class_name ActionRow
extends HBoxContainer

# Export specific nodes so you can assign them in the Inspector
# (or keep strict naming if you prefer, but this is safer)
@onready var _button: Button = $ColorRect/Button
@onready var _cost_label: Label = $ColorRect2/Label

var _required_pp: int = 0
var _callback: Callable

func setup(text: String, cost: int, on_click: Callable) -> void:
	_required_pp = cost
	_callback = on_click
	

	if is_inside_tree():
		_update_visuals(text, cost)

func _ready() -> void:
	if _button:
		_button.pressed.connect(_on_button_pressed)
	
	if _button and _button.text == "": 
		pass 

func _update_visuals(text: String, cost: int) -> void:
	if _button: _button.text = text
	if _cost_label: _cost_label.text = str(cost)

func check_affordability(current_pp: int) -> void:
	if _button:
		_button.disabled = (current_pp < _required_pp)

func _on_button_pressed() -> void:
	if _callback.is_valid():
		_callback.call()

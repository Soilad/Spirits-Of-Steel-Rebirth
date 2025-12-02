# KeyboardManager.gd
extends Node

signal toggle_menu()

var _debounce := false

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("open_menu") and not _debounce:
		_debounce = true
		emit_signal("toggle_menu")
	elif not Input.is_action_pressed("open_menu"):
		_debounce = false

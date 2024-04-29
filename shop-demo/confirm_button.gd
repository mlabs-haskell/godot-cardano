class_name ConfirmButton
extends Button

signal confirmed()

var confirming: bool

var prev_text: String = ""

func _init():
	prev_text = text
	pressed.connect(self._on_pressed)
	focus_exited.connect(self._on_focus_exited)
	set_custom_minimum_size(Vector2(80, 0))
	
func _process(delta: float):
	if confirming:
		text = "Confirm?"
	else:
		text = prev_text

func _on_pressed() -> void:
	if confirming:
		confirmed.emit()
		confirming = false
	else:
		prev_text = text
		confirming = true

func _on_focus_exited() -> void:
	confirming = false

@tool
class_name InventoryItem
extends Item

func _process(delta: float):
	$Sprite.modulate = color

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_pressed():
		item_selected.emit(self)

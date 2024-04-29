@tool
class_name InventoryItem
extends Item

@export
var stock: int

var confirming: bool

func _process(delta: float):
	$Sprite.modulate = color

func from_item(item: Item):
	item_name = item.item_name
	price = item.price
	sku = item.sku
	color = item.color

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_pressed():
		item_selected.emit()

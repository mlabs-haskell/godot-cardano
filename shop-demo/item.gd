@tool
class_name Item
extends PanelContainer

@export
var item_name: String
@export
var price: float
@export
var sku: int
@export
var color: Color = Color.WHITE

signal item_bought()
signal item_sold()
signal item_selected()

func stats_string() -> String:
	return "Red: %.2f\nGreen: %.2f\nBlue: %.2f" % [color.r, color.g, color.b]

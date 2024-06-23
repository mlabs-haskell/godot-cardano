@tool
class_name Item
extends PanelContainer

@export
var item_name: String
@export
var price: BigIntNode
@export
var conf: MintCip68
@export
var color: Color = Color.WHITE

signal item_bought(item: Item)
signal item_sold(item: Item)
signal item_selected(item: Item)
	
func stats_string() -> String:
	return "Red: %.2f\nGreen: %.2f\nBlue: %.2f" % [color.r, color.g, color.b]

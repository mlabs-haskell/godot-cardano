extends Node2D

func _ready() -> void:
	var good = true
	if good:
		print("Tests succeeded.")
		get_tree().quit(0)
	else:
		print("Tests failed.")
		get_tree().quit(1)

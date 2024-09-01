extends GridContainer

class_name LightWalletUI

var _name_field

signal on_light_wallet_picked(name: String)

# Called when the node enters the scene tree for the first time.
func _ready():
	var sep1 = Label.new()
	sep1.text = "Use light wallet (e.g.: nami, gerowallet, flint, LodeWallet, eternl)"
	sep1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sep1)
	
	_name_field = LineEdit.new()
	_name_field.text = "nami"
	add_child(_name_field)
	
	var go_btn = Button.new()
	go_btn.text = "Enable wallet"
	go_btn.pressed.connect(_pick_wallet)
	add_child(go_btn)

func _pick_wallet():
	on_light_wallet_picked.emit(_name_field.text)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

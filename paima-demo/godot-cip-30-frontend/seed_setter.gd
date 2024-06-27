extends GridContainer

class_name SeedSetter

var _seed_field

signal on_seed_received(seed_phrase)


# Called when the node enters the scene tree for the first time.
func _ready():
	var sep1 = Label.new()
	sep1.text = "Init wallet from seed phrase"
	sep1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sep1)
	
	_seed_field = LineEdit.new()
	add_child(_seed_field)
	
	var set_seed_btn = Button.new()
	set_seed_btn.text = "Set seed"
	set_seed_btn.pressed.connect(set_seed)
	add_child(set_seed_btn)

func set_seed():
	on_seed_received.emit(_seed_field.text)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

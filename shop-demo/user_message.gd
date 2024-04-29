class_name UserMessage
extends Label

var opacity: float = 1
var speed: float = 15
var color: Color = Color.WHITE

func set_message(msg: String):
	text = msg

func set_color(color: Color):
	self.color = color

func _ready():
	position = get_viewport().get_mouse_position() + Vector2(10, -10)
	add_theme_color_override("font_color", Color(color, opacity))

func _process(delta: float):
	add_theme_color_override("font_color", Color(color, opacity))
	position.y -= speed * delta
	opacity -= 0.1 * speed * delta
	if opacity <= 0:
		queue_free()

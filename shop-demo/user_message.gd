class_name UserMessage
extends Label

var _opacity: float = 1
var _speed: float = 15
var _color: Color = Color.WHITE

func set_message(msg: String):
	text = msg

func set_color(color: Color):
	_color = color

func _ready():
	position = get_viewport().get_mouse_position() + Vector2(10, -10)
	add_theme_color_override("font_color", Color(_color, _opacity))

func _process(delta: float):
	add_theme_color_override("font_color", Color(_color, _opacity))
	position.y -= _speed * delta
	_opacity -= 0.1 * _speed * delta
	if _opacity <= 0:
		queue_free()

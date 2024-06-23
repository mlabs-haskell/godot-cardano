# @tool
class_name ShopItem
extends Item

@export
var stock: int

func _process(delta: float):
	if stock > 0:
		%StickerLabel.text = "x%d" % stock
	else:
		%StickerLabel.text = "Sold out"

	%Name.text = item_name
	%Price.text = "%s tADA" % price.b.format_price()
	%Icon.custom_minimum_size = %Sprite.texture.get_size()

	%Sticker.position = Vector2(get_rect().size.x - 20, 20)
	
	var label_size: Vector2 = %StickerLabel.get_rect().size
	%StickerLabel.position = -label_size / 2

	var points := PackedVector2Array()
	const steps := 30
	
	for i in range(steps):
		var t := float(i) / steps * 2 * PI
		points.append(label_size * 1.25 / 2 * Vector2(cos(t), sin(t)))

	%Sticker.polygon = points
	%StickerLabel.size.x = 32

	%BuyButton.disabled = stock <= 0
	
	%Sprite.modulate = color

func _on_buy_confirmed() -> void:
	item_bought.emit(self)

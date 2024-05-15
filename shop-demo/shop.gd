extends Node2D

var ShopItem = preload("res://shop_item.tscn")
var InventoryItem = preload("res://inventory_item.tscn")
var UserMessage = preload("res://user_message.tscn")

var shop_items: Array[ShopItem]
@export
var display_inventory: bool = false
var selected_item: InventoryItem = null
var selection_stylebox: StyleBox = null
var unselected_stylebox: StyleBox = null

func _ready():
	shop_items = []
	selection_stylebox = StyleBoxFlat.new()
	selection_stylebox.bg_color = Color.WHITE
	selection_stylebox.set_expand_margin_all(2)
	selection_stylebox.set_corner_radius_all(16)
	unselected_stylebox = StyleBoxEmpty.new()
	
	for n in range(8):
		var item := ShopItem.instantiate() as ShopItem
		item.item_name = "Item %d" % n
		item.price.b = BigInt.from_int(int(randfn(800000000, 300000000)))
		item.stock = randi_range(0,5)
		item.sku = n
		item.color = Color(randf_range(0, 1), randf_range(0, 1), randf_range(0, 1))
		item.item_bought.connect(_on_buy_shop_item)
		shop_items.push_back(item)
	var item_container := %ItemContainer
	var container_children = item_container.get_children()
	for child in container_children:
		item_container.remove_child(child)
		
	for item in shop_items:
		item_container.add_child(item)
	
func _process(delta: float):
	%UserFundsLabel.text = "%s t₳" % WalletSingleton.user_funds.format_price()
	
	var inventory_screen := $InventoryScreen
	
	if display_inventory:
		inventory_screen.visible = true
		if inventory_screen.scale.x < 1:
			inventory_screen.scale += Vector2.ONE * delta * 5
		if inventory_screen.scale.x >= 1:
			inventory_screen.scale = Vector2.ONE
	else:
		if inventory_screen.scale.x > 0:
			inventory_screen.scale -= Vector2.ONE * delta * 5
		if inventory_screen.scale.x <= 0:
			inventory_screen.visible = false
	
	if selected_item == null:
		%SelectedItemDescription.text = ""
		%SelectedItemPrice.text = ""
		%SelectedItemSellButton.disabled = true
	else:
		%SelectedItemDescription.text = selected_item.stats_string()
		%SelectedItemPrice.text = "%s t₳" % selected_item.price.b.format_price()
		%SelectedItemSellButton.disabled = false

func deselect_item():
	if selected_item != null:
		selected_item.add_theme_stylebox_override("panel", unselected_stylebox)
		selected_item = null
		
func create_new_wallet():
	var new_wallet_result := SingleAddressWalletLoader.create("1234", 0, "My Account", "")
	
	if new_wallet_result.is_err():
		push_error("Failed to create wallet: %s" % new_wallet_result.error)
		return
	
	ResourceSaver.save(new_wallet_result.value._create_res.wallet_store, "user://user_wallet.tres")

func load_wallet():
	var loaded_wallet: _SingleAddressWalletStore = load("user://user_wallet.tres") as _SingleAddressWalletStore
	print(loaded_wallet)
	
func _on_inventory_button_pressed() -> void:
	display_inventory = not display_inventory
	if selected_item:
		selected_item.remove_theme_stylebox_override("panel")
		deselect_item()

func _on_main_screen_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		display_inventory = false

func _on_selected_item_sell_button_confirmed() -> void:
	%UserItemContainer.remove_child(selected_item)
	shop_items[selected_item.sku].stock += 1
	#user_funds = user_funds.add(selected_item.price.b)
	var new_message = UserMessage.instantiate()
	new_message.set_message("+%s t₳" % selected_item.price.b.format_price())
	new_message.set_color(Color.GREEN)
	add_child(new_message)
	deselect_item()
		
func _on_buy_shop_item(item: ShopItem):
	var new_message := UserMessage.instantiate()
	if WalletSingleton.user_funds.lt(item.price.b):
		new_message.set_message("Insufficient funds")
		new_message.set_color(Color.RED)
	else:
		new_message.set_message("-%s t₳" % item.price.b.format_price())
		new_message.set_color(Color.GOLD)
		var user_item: InventoryItem = InventoryItem.instantiate()
		user_item.from_item(item as Item)
		user_item.add_theme_stylebox_override(
			"panel",
			unselected_stylebox
		)
		user_item.item_selected.connect(_on_select_inventory_item)
		%UserItemContainer.add_child(user_item)
		user_item.gui_input
		#user_funds = user_funds.sub(item.price.b)
		item.stock -= 1
	add_child(new_message)
	
func _on_select_inventory_item(selection: InventoryItem):
	deselect_item()
	selected_item = selection
	selected_item.add_theme_stylebox_override(
		"panel",
		selection_stylebox
	)
	%SelectedItemSellButton.release_focus()

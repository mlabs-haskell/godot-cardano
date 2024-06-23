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
var update_timer: Timer = null

var cip68_data: Array[MintCip68] = []

var tag: BigInt = BigInt.from_int(2421665)
# TODO: make scripts resources?
@onready
var minting_policy := PlutusData.apply_script_parameters(
	load_script_from_blueprint("res://scripts.json", "shop.tagged_mint"),
	[tag]
)
@onready
var ref_lock := PlutusData.apply_script_parameters(
	load_script_from_blueprint("res://scripts.json", "shop.tagged_spend"),
	[tag]
)
@onready
var shop_script := load_script_from_blueprint("res://scripts.json", "shop.spend")

func _ready():
	shop_items = []
	selection_stylebox = StyleBoxFlat.new()
	selection_stylebox.bg_color = Color.WHITE
	selection_stylebox.set_expand_margin_all(2)
	selection_stylebox.set_corner_radius_all(16)
	unselected_stylebox = StyleBoxEmpty.new()
	
	WalletSingleton.wallet_ready.connect(self.mint_tokens)
	
	var cip68_files := DirAccess.get_files_at("res://cip68_data")
	for path in cip68_files:
		cip68_data.push_back(load("res://cip68_data/%s" % path))

	var item_container := %ItemContainer
	var container_children = item_container.get_children()
	for child in container_children:
		child.queue_free()
	
	update_timer = Timer.new()
	update_timer.autostart = true
	update_timer.wait_time = 40
	update_timer.one_shot = false
	update_timer.timeout.connect(
		func () -> void:
			var provider: Provider = WalletSingleton.provider
			var shop_utxos = await provider.get_utxos_at_address(
				provider.make_address(Credential.from_script(shop_script))
			)
			var shop_assets = MultiAsset.empty()
			for utxo in shop_utxos:
				shop_assets.merge(utxo.assets())
			shop_items = []
			for conf: MintCip68 in cip68_data:
				var item := await cip68_to_item(conf)
				item.stock = shop_assets.get_asset_quantity(
					conf.make_user_asset_class(minting_policy)
				).to_int()
				shop_items.push_back(item)
				
			container_children = item_container.get_children()
			for child in container_children:
				child.queue_free()
				
			for item in shop_items:
				item_container.add_child(item)
			
			var wallet_utxos: Array[Utxo] = await WalletSingleton.wallet._get_updated_utxos()
			wallet_utxos.sort_custom(
				func (a: Utxo, b: Utxo) -> bool:
					return a.tx_hash().to_hex() < b.tx_hash().to_hex() or a.output_index() < b.output_index()
			)
			
			for child in %UserItemContainer.get_children():
				child.queue_free()

			for utxo in wallet_utxos:
				for conf: MintCip68 in cip68_data:
					var quantity := utxo.assets().get_asset_quantity(
						conf.make_user_asset_class(minting_policy)
					)
					for i in range(quantity.to_int()):
						var user_item: InventoryItem = InventoryItem.instantiate()
						user_item.from_item(await cip68_to_item(conf, true))
						user_item.add_theme_stylebox_override(
							"panel",
							unselected_stylebox
						)
						user_item.item_selected.connect(_on_select_inventory_item)
						%UserItemContainer.add_child(user_item)
						user_item.gui_input # TODO: remember what this means?
	)
	add_child(update_timer)
	WalletSingleton.wallet_ready.connect(
		func ():
			shop_script = PlutusData.apply_script_parameters(
				shop_script,
				[PlutusBytes.new(WalletSingleton.wallet.get_payment_pub_key_hash().to_bytes())]
			)
			await WalletSingleton.wallet.got_updated_utxos
			update_timer.timeout.emit()
	)

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
	
func _on_inventory_button_pressed() -> void:
	display_inventory = not display_inventory
	if selected_item:
		selected_item.remove_theme_stylebox_override("panel")
		deselect_item()

func _on_main_screen_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		display_inventory = false

func _on_selected_item_sell_button_confirmed() -> void:
	var new_message = UserMessage.instantiate()
	new_message.set_message("+%s t₳" % selected_item.price.b.format_price())
	new_message.set_color(Color.GREEN)
	buy_item(selected_item.conf, -1)
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
		buy_item(item.conf, 1)
	add_child(new_message)
	
func _on_select_inventory_item(selection: InventoryItem):
	deselect_item()
	selected_item = selection
	selected_item.add_theme_stylebox_override(
		"panel",
		selection_stylebox
	)
	%SelectedItemSellButton.release_focus()

func mint_tokens():
	var provider: Provider = WalletSingleton.provider
	var new_tx_result := await WalletSingleton.wallet.new_tx()
	if new_tx_result.is_err():
		push_error("Could not create transaction: %s" % new_tx_result.error)
		return
	
	var tx_builder = new_tx_result.value
	
	var new_mint = false
	for conf in cip68_data:
		var asset_class := conf.make_ref_asset_class(minting_policy)
		var utxos := await provider.get_utxos_with_asset(asset_class)
		if utxos.size() == 0:
			new_mint = true
			tx_builder.mint_cip68_pair(minting_policy, VoidData.new().to_data(), conf)
			tx_builder.pay_cip68_ref_token(
				minting_policy,
				WalletSingleton.provider.make_address(
					Credential.from_script(ref_lock),
				),
				conf
			)
			tx_builder.pay_cip68_user_tokens_with_datum(
				minting_policy,
				WalletSingleton.provider.make_address(
					Credential.from_script(shop_script)
				),
				VoidData.new().to_data(),
				conf
			)

	if not new_mint:
		return

	var complete_result := await tx_builder.complete()
	
	if complete_result.is_err():
		push_error("Failed to build transaction: %s" % complete_result.error)
		return
	
	var tx := complete_result.value
	tx.sign("1234")
	var submit_result := await tx.submit()
	
	if submit_result.is_err():
		push_error("Failed to submit transaction: %s" % submit_result.error)
		return
	
	print("Waiting for transaction %s..." % submit_result.value.to_hex())
	await WalletSingleton.provider.await_tx(submit_result.value)
	print("Minted")

func buy_item(conf: MintCip68, quantity: int) -> void:
	if quantity == 0:
		return
		
	var provider: Provider = WalletSingleton.provider
	var new_tx_result := await WalletSingleton.wallet.new_tx()
	
	if new_tx_result.is_err():
		push_error("Could not create transaction: %s" % new_tx_result.error)
		return
	
	var tx_builder = new_tx_result.value
	
	var shop_utxos = await provider.get_utxos_at_address(
		provider.make_address(Credential.from_script(shop_script))
	)
	
	var user_asset_class = conf.make_user_asset_class(minting_policy)
	var selected_utxo: Utxo = null
	if quantity > 0:
		for utxo in shop_utxos:
			if utxo.assets().get_asset_quantity(user_asset_class).gt(BigInt.from_int(quantity - 1)):
				selected_utxo = utxo
				break
	else:
		for utxo in shop_utxos:
			if utxo.coin().to_int() > conf.extra_plutus_data.to_int() * -quantity:
				selected_utxo = utxo
				break

	tx_builder.collect_from_script(
		PlutusScriptSource.from_script(shop_script),
		[selected_utxo],
		VoidData.new().to_data()
	)
	
	var ref_utxo := await provider.get_utxos_with_asset(
		conf.make_ref_asset_class(minting_policy)
	)
	tx_builder.add_reference_input(ref_utxo[0])
	
	var assets := selected_utxo.assets().duplicate()
	assets.add_asset(conf.make_user_asset_class(minting_policy), BigInt.from_int(-quantity))
	tx_builder.pay_to_address_with_datum(
		WalletSingleton.provider.make_address(
			Credential.from_script(shop_script)
		),
		selected_utxo.coin().add(BigInt.from_int(conf.extra_plutus_data.to_int() * quantity)),
		assets,
		VoidData.new().to_data()
	)
	
	var complete_result := await tx_builder.complete()
	
	if complete_result.is_err():
		push_error("Failed to build transaction: %s" % complete_result.error)
		return
	
	var tx := complete_result.value
	tx.sign("1234")
	var submit_result := await tx.submit()
	
	if submit_result.is_err():
		push_error("Failed to submit transaction: %s" % submit_result.error)
		return
	
	await WalletSingleton.provider.await_tx(submit_result.value)
	update_timer.timeout.emit()

func load_script_from_blueprint(path: String, validator_name: String) -> PlutusScript:
	var contents := FileAccess.get_file_as_string(path)
	var contents_json: Dictionary = JSON.parse_string(contents)
	for validator: Dictionary in contents_json['validators']:
		if validator['title'] == validator_name:
			return PlutusScript.create((validator['compiledCode'] as String).hex_decode())
	
	push_error("Failed to load %s from %s" % [validator_name, path])
	return null

func cip68_to_item(conf: MintCip68, local_data := false) -> Item:
	var data: Cip68Datum = Cip68Datum.from_constr(conf.to_data())
	if not local_data:
		var remote_data := await WalletSingleton.provider.get_cip68_datum(conf, minting_policy)
		if remote_data != null:
			data = remote_data
		
	var item := ShopItem.instantiate() as ShopItem
	item.item_name = data.name()
	item.price.b = data.get_extra_plutus_data()
	item.conf = conf
	var red: BigInt = data.get_metadata("Red")
	var green: BigInt = data.get_metadata("Green")
	var blue: BigInt = data.get_metadata("Blue")
	item.color = Color(
		red.to_int() / 255.0,
		green.to_int() / 255.0,
		blue.to_int() / 255.0
	)
	item.item_bought.connect(_on_buy_shop_item)
	return item

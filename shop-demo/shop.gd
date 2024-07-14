extends Control

var ShopItem = preload("res://shop_item.tscn")
var InventoryItem = preload("res://inventory_item.tscn")
var UserMessage = preload("res://user_message.tscn")

var shop_items: Array[ShopItem] = []
var inventory_items: Array[InventoryItem] = []
@export
var display_inventory: bool = false
var selected_item: InventoryItem = null
var selection_stylebox: StyleBox = null
var unselected_stylebox: StyleBox = null
var update_timer: Timer = null

var cip68_data: Array[MintCip68] = []

var owner_pub_key_hash: PubKeyHash = null
var tag: BigInt = BigInt.from_int(239058)
var ref_lock_source: PlutusScriptSource
var shop_script_source: PlutusScriptSource

var provider: Provider
var wallet: OnlineWallet.OnlineSingleAddressWallet

signal data_updated

var busy: bool = false

func _ready():
	selection_stylebox = StyleBoxFlat.new()
	selection_stylebox.bg_color = Color.WHITE
	selection_stylebox.set_expand_margin_all(2)
	selection_stylebox.set_corner_radius_all(16)
	unselected_stylebox = StyleBoxEmpty.new()

	var cip68_files := DirAccess.get_files_at("res://cip68_data")
	for path in cip68_files:
		var res = load_user_or_res("cip68_data/%s" % path)
		if res is MintCip68:
			cip68_data.push_back(res)

	for conf: MintCip68 in cip68_data:
		var item = await cip68_to_item(conf, true)
		shop_items.push_back(item)
		%ItemContainer.add_child(item)
	
	data_updated.connect(self._on_data_updated)

	update_timer = Timer.new()
	update_timer.autostart = true
	update_timer.wait_time = 40
	update_timer.one_shot = false
	update_timer.timeout.connect(self.update_data)
	add_child(update_timer)
	WalletSingleton.wallet_ready.connect(_on_wallet_ready)

func _on_wallet_ready():
	wallet = WalletSingleton.wallet
	provider = WalletSingleton.provider
	
	for conf in cip68_data:
		await conf.init_script(provider)
		WalletSingleton.provider.chain_asset(conf.make_ref_asset_class())
		
	DirAccess.make_dir_absolute("user://cip68_data")
	ref_lock_source = await load_script_and_create_ref("ref_lock.tres")
	shop_script_source = await load_script_and_create_ref("shop_script.tres")
	
	await wallet.got_updated_utxos

	var shop_address := provider.make_address(
		Credential.from_script_source(shop_script_source)
	)
	provider.chain_address(shop_address)
	owner_pub_key_hash = wallet.get_payment_pub_key_hash()
	print('using shop %s' % shop_address.to_bech32())
	print('using minting policy %s' % cip68_data[0].minting_policy_source.hash().to_hex())
	busy = true
	await mint_tokens()
	busy = false
	data_updated.emit()

func _on_data_updated():
	var i := 0
	var user_items := %UserItemContainer.get_children()
	while i < inventory_items.size():
		if i < user_items.size():
			var old_item = user_items[i] as InventoryItem
			old_item.from_item(inventory_items[i])
			old_item.visible = true
		else:
			inventory_items[i].add_theme_stylebox_override(
				"panel",
				unselected_stylebox
			)
			inventory_items[i].item_selected.connect(_on_select_inventory_item)
			%UserItemContainer.add_child(inventory_items[i])
		i += 1
	while i < user_items.size():
		user_items[i].visible = false
		i += 1

func _process(delta: float):
	var inventory_screen := $InventoryScreen
	%UserFundsLabel.text = "%s t₳" % WalletSingleton.user_funds.format_price()
	
	if WalletSingleton.is_node_ready():
		pass

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
		%SelectedItemSellButton.disabled = busy
	
	for shop_item in %ItemContainer.get_children():
		shop_item.busy = busy

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
	if await buy_item(selected_item.conf, -1):
		add_child(new_message)

func _on_buy_shop_item(item: ShopItem):
	var new_message := UserMessage.instantiate()
	if WalletSingleton.user_funds.lt(item.price.b):
		new_message.set_message("Insufficient funds")
		new_message.set_color(Color.RED)
		add_child(new_message)
	else:
		new_message.set_message("-%s t₳" % item.price.b.format_price())
		new_message.set_color(Color.GOLD)
		if await buy_item(item.conf, 1):
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
	busy = true
	var new_tx_result := await wallet.new_tx()
	if new_tx_result.is_err():
		push_error("Could not create transaction: %s" % new_tx_result.error)
		return
	var shop_address := provider.make_address(
		Credential.from_script_source(shop_script_source)
	)
	var tx_builder = new_tx_result.value

	var new_mint = false
	for conf in cip68_data:
		var asset_class := conf.make_ref_asset_class()
		var utxo := await provider.get_utxo_with_nft(asset_class)
		if utxo == null:
			new_mint = true
			tx_builder.mint_cip68_pair(VoidData.new().to_data(), conf)
			tx_builder.pay_cip68_ref_token(
				provider.make_address(
					Credential.from_script_source(ref_lock_source),
				),
				conf
			)
			tx_builder.pay_cip68_user_tokens_with_datum(
				shop_address,
				PlutusBytes.new(owner_pub_key_hash.to_bytes()),
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

	provider.invalidate_cache()
	update_timer.timeout.emit()
	print("Minted")
	busy = false

func burn_tokens():
	busy = true
	deselect_item()

	var shop_utxos = await provider.get_utxos_at_address(
		provider.make_address(Credential.from_script_source(shop_script_source))
	)

	var owner_shop_utxos = shop_utxos.filter(
		func (utxo: Utxo):
			return PlutusBytes.new(owner_pub_key_hash.to_bytes()).equals(utxo.datum())
	)

	var ref_lock_utxos = await provider.get_utxos_at_address(
		provider.make_address(Credential.from_script_source(ref_lock_source))
	)

	var burns: Array[TxBuilder.MintToken] = []
	for conf in cip68_data:
		var user_asset_class := conf.make_user_asset_class()
		var quantity_remaining := BigInt.zero()
		for utxo in owner_shop_utxos:
			quantity_remaining = quantity_remaining.add(
				utxo.assets().get_asset_quantity(user_asset_class)
			)

		if quantity_remaining.gt(BigInt.zero()):
			burns.push_back(
				TxBuilder.MintToken.new(user_asset_class._asset_name, quantity_remaining.negate()),
			)

		var ref_asset_class := conf.make_ref_asset_class()
		for utxo in ref_lock_utxos:
			var ref_count = utxo.assets().get_asset_quantity(ref_asset_class)
			if ref_count.eq(BigInt.zero()):
				continue

			burns.push_back(TxBuilder.MintToken.new(ref_asset_class._asset_name, BigInt.from_int(-1)))

	if burns.is_empty():
		return
	
	var tx_hash := await wallet.tx_with(
		func (tx_builder: TxBuilder):
			tx_builder.collect_from_script(ref_lock_source, ref_lock_utxos, VoidData.to_data())
			# FIXME: should have better way to burn CIP68 tokens
			tx_builder.mint_assets(cip68_data[0].minting_policy_source, burns, VoidData.to_data())

			tx_builder.collect_from_script(shop_script_source, owner_shop_utxos, VoidData.to_data())
			tx_builder.add_required_signer(wallet.get_payment_pub_key_hash()),
		func (tx: TxComplete):
			tx.sign("1234")
	)

	update_timer.timeout.emit()
	print("Burned")
	busy = false
	return tx_hash != null

func buy_item(conf: MintCip68, quantity: int) -> bool:
	if quantity == 0:
		return false

	busy = true
	deselect_item()
	
	var shop_utxos = await provider.get_utxos_at_address(
		provider.make_address(Credential.from_script_source(shop_script_source))
	)
	var ref_utxo := await provider.get_utxo_with_nft(
		conf.make_ref_asset_class()
	)
	var user_asset_class = conf.make_user_asset_class()
	var selected_utxo: Utxo = null
	if quantity > 0:
		for utxo in shop_utxos:
			if utxo.assets().get_asset_quantity(user_asset_class).gt(BigInt.from_int(quantity - 1)):
				selected_utxo = utxo
				break
	else:
		for utxo: Utxo in shop_utxos:
			if utxo.coin().to_int() > conf.extra_plutus_data.data.to_int() * -quantity:
				selected_utxo = utxo
				break

	var assets := selected_utxo.assets().duplicate()
	assets.add_asset(conf.make_user_asset_class(), BigInt.from_int(-quantity))
	
	if !selected_utxo.datum_info().has_datum_inline():
		push_error("Selected UTxO does not have an inline datum")
		busy = false
		return false
	var shop_datum := selected_utxo.datum()
	
	var tx_hash := await wallet.tx_with(
		func (tx_builder: TxBuilder):
			tx_builder.collect_from_script(
				shop_script_source,
				[selected_utxo],
				VoidData.to_data()
			)
			tx_builder.add_reference_input(ref_utxo)
			tx_builder.pay_to_address(
				WalletSingleton.provider.make_address(
					Credential.from_script_source(shop_script_source)
				),
				selected_utxo.coin().add(BigInt.from_int(conf.extra_plutus_data.data.to_int() * quantity)),
				assets,
				shop_datum
			),
		func (tx: TxComplete):
			tx.sign("1234")
	)

	update_timer.timeout.emit()
	busy = false
	return tx_hash != null

func update_data() -> void:
	var shop_utxos = await provider.get_utxos_at_address(
		provider.make_address(Credential.from_script_source(shop_script_source))
	)
	var shop_assets = MultiAsset.empty()
	for utxo in shop_utxos:
		shop_assets.merge(utxo.assets())
	for conf: MintCip68 in cip68_data:
		var item: ShopItem = null
		for v in shop_items:
			if v.conf == conf:
				item = v
				break
		item.from_item(await cip68_to_item(conf, true))
		item.stock = shop_assets.get_asset_quantity(
			conf.make_user_asset_class()
		).to_int()

	var wallet_utxos: Array[Utxo] = await wallet._get_updated_utxos()
	var new_inventory_items: Array[InventoryItem] = []
	for utxo in wallet_utxos:
		for conf: MintCip68 in cip68_data:
			var quantity := utxo.assets().get_asset_quantity(
				conf.make_user_asset_class()
			)
			for i in range(quantity.to_int()):
				var user_item: InventoryItem = InventoryItem.instantiate()
				user_item.from_item(await cip68_to_item(conf, true))
				new_inventory_items.push_back(user_item)

	inventory_items = new_inventory_items
	wallet.update_utxos()
	data_updated.emit()

func load_script_from_blueprint(path: String, validator_name: String) -> PlutusScript:
	var contents := FileAccess.get_file_as_string(path)
	var contents_json: Dictionary = JSON.parse_string(contents)
	for validator: Dictionary in contents_json['validators']:
		if validator['title'] == validator_name:
			return PlutusScript.create((validator['compiledCode'] as String).hex_decode())

	push_error("Failed to load %s from %s" % [validator_name, path])
	return null

func cip68_to_item(conf: MintCip68, local_data := false) -> Item:
	var data: Cip68Datum = Cip68Datum.unsafe_from_constr(conf.to_data())
	if not local_data:
		var remote_data := await WalletSingleton.provider.get_cip68_datum(conf)
		if remote_data != null:
			data = remote_data

	var item := ShopItem.instantiate() as ShopItem
	item.item_name = data.name()
	item.price.b = data.extra_plutus_data()
	item.conf = conf
	item.stock = -1
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

func load_user_or_res(path: String, type_hint := "") -> Resource:
	var res_path := "res://%s" % path
	var user_path := "user://%s" % path
	
	return ResourceLoader.load(
		user_path if FileAccess.file_exists(user_path) else res_path,
		type_hint
	)

func load_script_and_create_ref(filename: String) -> PlutusScriptSource:
	var source := await provider.load_script(load_user_or_res("cip68_data/%s" % filename) as ScriptResource)
	if not source.is_ref():
		var tx_hash := await wallet.tx_with(
			func(tx_builder: TxBuilder):
				tx_builder.pay_to_address(
					provider.make_address(
						Credential.from_script_source(source)
					),
					BigInt.zero(),
					MultiAsset.empty(),
					VoidData.to_data(),
					source.script()
				),
			func (tx: TxComplete):
				tx.sign("1234")
		)

		if tx_hash != null:
			var res := ScriptFromOutRef.new(tx_hash, 0)
			await provider.await_tx(tx_hash)
			ResourceSaver.save(res, "user://cip68_data/%s" % filename)
			source = await provider.load_script(res)
	return source

## Updates the configuration in the given [param filename] using the 
## [param update] provided. The result will be saved under user://cip68_data/
## and will be used when this config is loaded in future.
func update_cip68_conf(filename: String, update: Callable) -> void:
	var conf = update.call(load_user_or_res("cip68_data/%s" % filename))
	var ref_utxo := await provider.get_utxo_with_nft(
		conf.make_ref_asset_class()
	)
	wallet.tx_with(
		func (tx_builder: TxBuilder) -> void:
			tx_builder.collect_from_script(
				ref_lock_source,
				[ref_utxo],
				VoidData.to_data()
			)
			tx_builder.pay_cip68_ref_token(
				provider.make_address(
					Credential.from_script_source(ref_lock_source)
				),
				conf
			),
		func (tx: TxComplete) -> void:
			tx.sign("1234")
	)
	ResourceSaver.save(conf, "user://cip68_data/%s" % filename)
	
func sync_cip68_conf_from_chain(filename: String) -> void:
	var conf = load_user_or_res("cip68_data/%s" % filename)
	var new_datum := await provider.get_cip68_datum(conf)
	new_datum.copy_to_conf(conf)
	ResourceSaver.save(conf, "user://cip68_data/%s" % filename)

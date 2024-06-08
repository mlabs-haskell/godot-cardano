extends GutTest

func test_assert_bigint_eq() -> void:
	var bigint := BigInt.from_int(1)
	assert_true(
		bigint.eq(BigInt.one()),
		"BigInt.from_int(1) should equal Bigint.one()"
	)

class TestData extends GutTest:
	var _cbor_data: Dictionary

	func before_all() -> void:
		assert(FileAccess.file_exists("res://test_data.json"))
		var data_json := FileAccess.get_file_as_string("res://test_data.json")
		var data: Dictionary = JSON.parse_string(data_json)
		_cbor_data = data.cbor
			
	func test_cbor_ints(case=use_parameters(_cbor_data.ints)) -> void:
		var from_str_result := BigInt.from_str(case.value.int)
		assert(from_str_result.is_ok())
		if from_str_result.is_ok():
			var serialize_result := PlutusData.serialize(from_str_result.value)
			assert(serialize_result.is_ok())
			if serialize_result.is_ok():
				assert_eq(serialize_result.value.hex_encode(), case.hex_bytes)

	func test_cbor_lists(case=use_parameters(_cbor_data.lists)):
		var serialize_result := PlutusData.serialize(PlutusData.from_json(case.value))
		if serialize_result.is_ok():
			assert_eq(serialize_result.value.hex_encode(), case.hex_bytes)
			
	func test_cbor_bytearrays(case=use_parameters(_cbor_data.bytearrays)):
		var serialize_result := PlutusData.serialize(PlutusData.from_json(case.value))
		if serialize_result.is_ok():
			assert_eq(serialize_result.value.hex_encode(), case.hex_bytes)

	func test_to_data_invertible() -> void:
		var strict := true
		var before := ExampleDatum.new()
		var bytes_result := PlutusData.serialize(before.to_data())
		assert(bytes_result.is_ok(), "Example datum serializes")
		if bytes_result.is_ok():
			var data_result := Cbor.deserialize(bytes_result.value)

			assert(data_result.is_ok(), "Example datum deserializes")
			if data_result.is_ok():
				var after := ExampleDatum.from_data(data_result.value)
				assert_true(before.eq(after), "Example datum unchanged after deserializing")
			else:
				push_error(data_result.error)
		else:
			push_error(bytes_result.error)

class TestWallets extends GutTest:
	var _wallets: Array
	
	func before_all() -> void:
		assert(FileAccess.file_exists("res://test_data.json"))
		var data_json := FileAccess.get_file_as_string("res://test_data.json")
		var data: Dictionary = JSON.parse_string(data_json)
		_wallets = data.wallets
	
	func test_create_and_import(
		account_index: int = use_parameters([0,12])
	) -> void:
		var create_result := SingleAddressWalletLoader.create(
			"1234",
			account_index,
			"",
			"",
			ProviderApi.Network.PREVIEW
		)
		assert_true(
			create_result.is_ok(),
			"Create new wallet with account %d" % account_index
		)
		
		var loader := SingleAddressWalletLoader.new(ProviderApi.Network.PREVIEW)
		var import_result := await loader.import_from_seedphrase(
			create_result.value.seed_phrase,
			"",
			"1234",
			account_index,
			"",
			""
		)
		assert_true(
			import_result.is_ok(),
			"Import created wallet with account %d" % account_index
		)
		
		var wallet := Wallet.MnemonicWallet.new(
			import_result.value.wallet,
			null,
			false
		)
		wallet.add_account(account_index, "1234")
		assert_eq(
			create_result.value.wallet.get_address_bech32(),
			wallet._get_change_address().to_bech32()
		)
		wallet.free()
		
	func test_wallet_import() -> void:
		var loader := SingleAddressWalletLoader.new(ProviderApi.Network.PREVIEW)
		for wallet_data: Dictionary in _wallets:
			var seed_phrase: String = wallet_data['seedPhrase']
			var import_result := await loader.import_from_seedphrase(
				seed_phrase,
				"",
				"1234",
				0,
				"",
				""
			)
			assert_true(
				import_result.is_ok(),
				"Import wallet from seed phrase"
			)
			
			for account_data: Dictionary in wallet_data['accounts']:
				var wallet := Wallet.MnemonicWallet.new(
					import_result.value.wallet,
					null,
					false
				)
				var index: int = account_data['index']
				var address: String = account_data['address']
				wallet.add_account(index, "1234")
				wallet.switch_account(index)

				assert_eq(address, wallet._get_change_address().to_bech32())
				wallet.free()

class TestSdk extends GutTest:
	signal tx_test_finished(result: Dictionary)
	
	var blockfrost_tests := [blockfrost_payment, blockfrost_mint, blockfrost_spend_script]
	var _script_data: Dictionary
	var _funding_address: Address
	var _provider: Provider
	var _wallets: Array[Wallet.MnemonicWallet] = []
	
	const correct_password := "1234"
	const incorrect_password := "12345"
	
	func before_all():
		assert(FileAccess.file_exists("res://test_data.json"))
		var data_json := FileAccess.get_file_as_string("res://test_data.json")
		var data: Dictionary = JSON.parse_string(data_json)
		_script_data = data.scripts

		or_quit(FileAccess.file_exists("res://preview_token.txt"), "No Blockfrost token available")
		var preview_token := FileAccess.get_file_as_string("res://preview_token.txt").strip_edges()
		
		var provider_api = BlockfrostProviderApi.new(
			ProviderApi.Network.PREVIEW,
			preview_token,
		)
		add_child(provider_api)
		_provider = Provider.new(provider_api)
		add_child(_provider)

	func or_quit(test: bool, msg: String = "") -> void:
		if not test:
			push_error(msg)
			assert_true(false, msg)
			get_tree().quit(1)
			
	func load_funding_wallet() -> SingleAddressWallet:
		var funding_wallet_phrase := OS.get_environment("TESTNET_SEED_PHRASE")
		if funding_wallet_phrase == "":
			or_quit(
				FileAccess.file_exists("res://seed_phrase.txt"),
				"No funding wallet available"
			)
			funding_wallet_phrase = FileAccess.get_file_as_string("res://seed_phrase.txt")
		var loader := SingleAddressWalletLoader.new(ProviderApi.Network.PREVIEW)
		var import_result := await loader.import_from_seedphrase(
			funding_wallet_phrase,
			"",
			correct_password,
			0,
			"",
			""
		)
		or_quit(
			import_result.is_ok(),
			"Import funding wallet"
		)
		return import_result.value.wallet

	func tx_with(
		wallet: Wallet.MnemonicWallet,
		build: Callable,
		test_name: String = "test",
		post_complete: Callable = func (x): return x.sign("1234"),
	) -> TransactionHash:
		var create_tx_result := await wallet.new_tx()
		if create_tx_result.is_ok():
			var tx := create_tx_result.value
			await build.call(tx)
			var complete_tx_result := await tx.complete()
			assert_true(complete_tx_result.is_ok(), "Build %s tx" % test_name)
			if complete_tx_result.is_ok():
				var tx_complete: TxComplete = await post_complete.call(complete_tx_result.value)
				var submit_result := await tx_complete.submit()
				or_quit(submit_result.is_ok())
				var tx_hash := submit_result.value
				or_quit(tx_hash != null)
				return tx_hash
			else:
				gut.p(complete_tx_result.error)
		else:
			gut.p('Failed to create transaction: %s' % create_tx_result.error)
		return null
	
	func tx_fail_with(
		wallet: Wallet.MnemonicWallet,
		build: Callable,
		test_name: String = "test"
	) -> void:
		var create_tx_result := await wallet.new_tx()
		if create_tx_result.is_ok():
			var tx := create_tx_result.value
			build.call(tx)
			var result = await tx.complete()
			assert_true(result.is_err(), "Build %s tx fails" % test_name)

	func init_blockfrost_tests() -> void:
		var funding_wallet := await load_funding_wallet()

		var wallet := Wallet.MnemonicWallet.new(funding_wallet, _provider)
		add_child(wallet)
		_funding_address = wallet._get_change_address()
		
		for _t: Callable in blockfrost_tests:
			var create_result := SingleAddressWalletLoader.create(
				"1234",
				0,
				"",
				"",
				ProviderApi.Network.PREVIEW
			)
			if create_result.is_err():
				continue
				
			var new_wallet := Wallet.MnemonicWallet.new(
				create_result.value.wallet,
				_provider
			)
			_wallets.push_back(new_wallet)
					
			# backup the seed phrase in case of an early exit
			var file = FileAccess.open(
				"user://%s" % new_wallet._get_change_address().to_bech32(),
				FileAccess.WRITE
			)
			file.store_string(create_result.value.seed_phrase + "\n")
			file.close()

		assert_true(
			blockfrost_tests.size() == _wallets.size(),
			"Create test wallets"
		)
		
		var fund_tx_hash := await tx_with(
			wallet,
			func (tx: TxBuilder) -> void:
				for test_wallet in _wallets:
					tx.pay_to_address(
						test_wallet._get_change_address(),
						BigInt.from_int(20_000_000),
						MultiAsset.empty()
					),
			"test wallet funding"
		)
		or_quit(fund_tx_hash != null)
		var status = await _provider.await_utxos_at(
			wallet._get_change_address(),
			fund_tx_hash,
			180
		)
		or_quit(status)
		gut.p('Test wallets funded')
		wallet.queue_free()

	func test_invalid_signature() -> void:
		var funding_wallet := await load_funding_wallet()

		var wallet := Wallet.MnemonicWallet.new(funding_wallet, _provider)
		_funding_address = wallet._get_change_address()
		add_child(wallet)
		
		await wallet._get_updated_utxos()
		var create_tx_result := await wallet.new_tx()
		assert_true(create_tx_result.is_ok(), "Create test wallet funding tx")
		if create_tx_result.is_ok():
			var fund_tx := create_tx_result.value
			var complete_tx_result := await fund_tx.complete()
			assert_true(complete_tx_result.is_ok(), "Build test wallet funding tx")
			if complete_tx_result.is_ok():
				var complete_tx := complete_tx_result.value
				complete_tx.sign(incorrect_password)
				assert_true(
					complete_tx._results[0].tag() == TxComplete.TxCompleteStatus.INVALID_SIGNATURE,
					"Signing transaction with incorrect password fails"
				)
		else:
			print("Failed to create transaction: %s" % create_tx_result.error)
		wallet.queue_free()

	func blockfrost_payment(wallet: Wallet) -> TransactionHash:
		await _provider.await_utxos_at(wallet._get_change_address(), null, 180)
		var tx_hash = await tx_with(
			wallet,
			func(_tx: TxBuilder) -> void: pass,
			"simple payment"
		)
		tx_test_finished.emit({
			"name": "payment",
			"address": wallet._get_change_address(),
			"tx_hash": tx_hash
		})
		return tx_hash

	func blockfrost_mint(wallet: Wallet) -> TransactionHash:
		var previous_tx_hash: TransactionHash = null
		
		await _provider.await_utxos_at(wallet._get_change_address(), null, 180)
		for script_data in _script_data.mint:
			var script = PlutusScript.create(script_data.bytes.hex_decode())
			if script_data.invalid_redeemer != null:
				await tx_fail_with(
					wallet,
					func (tx: TxBuilder) -> void:
						tx.mint_assets(
							script,
							[ TxBuilder.MintToken.new("example token".to_utf8_buffer(), BigInt.one()) ],
							PlutusData.from_json(script_data.invalid_redeemer)
						),
					"minting token with invalid redeemer"
				)
		previous_tx_hash = await tx_with(
			wallet,
			func(tx: TxBuilder) -> void:
				for script_data in _script_data.mint:
					var script = PlutusScript.create(script_data.bytes.hex_decode())
					tx.mint_assets(
						script,
						[ TxBuilder.MintToken.new("example token".to_utf8_buffer(), BigInt.one()) ],
						PlutusData.from_json(script_data.valid_redeemer)
					),
			"minting token"
		)
		await _provider.await_tx(previous_tx_hash)
			
		previous_tx_hash = await tx_with(
			wallet,
			func(tx: TxBuilder) -> void:
				for script_data in _script_data.mint:
					var script = PlutusScript.create(script_data.bytes.hex_decode())
					tx.mint_assets(
						script,
						[ TxBuilder.MintToken.new("example token".to_utf8_buffer(), BigInt.one().negate()) ],
						PlutusData.from_json(script_data.valid_redeemer)
					),
			"burning token"
		)
		await _provider.await_tx(previous_tx_hash)
		tx_test_finished.emit({
			"name": "mint",
			"address": wallet._get_change_address(),
			"tx_hash": previous_tx_hash
		})
		return previous_tx_hash

	func blockfrost_spend_script(wallet: Wallet) -> TransactionHash:
		var previous_tx_hash: TransactionHash = null
		
		await _provider.await_utxos_at(wallet._get_change_address(), null, 180)
		previous_tx_hash = await tx_with(
			wallet,
			func(tx: TxBuilder) -> void:
				for script_data in _script_data.spend:
					var script = PlutusScript.create(
						script_data.bytes.hex_decode()
					)
					var address = _provider.make_address(Credential.from_script(script))
					
					assert_eq(address.to_bech32(), script_data.address)
					tx.pay_to_address_with_datum(
						address,
						BigInt.from_int(3_000_000),
						MultiAsset.empty(),
						PlutusData.from_json(script_data.valid_datum)
					),
			"pay to script"
		)
		
		if previous_tx_hash != null:
			await _provider.await_utxos_at(
				wallet._get_change_address(),
				previous_tx_hash,
				180
			)

		var spends: Array[Dictionary] = []
		for script_data in _script_data.spend:
			var script = PlutusScript.create(
				script_data.bytes.hex_decode()
			)
			var address = _provider.make_address(Credential.from_script(script))
			var utxos := await _provider.get_utxos_at_address(address)
			var utxos_filtered = utxos.filter(
				func(u: Utxo): return u.datum_info().has_datum()
			).slice(0, 1)

			assert_gt(utxos_filtered.size(), 0, "Script UTxO found") 
			if script_data.invalid_redeemer != null:
				tx_fail_with(
					wallet,
					func(tx: TxBuilder) -> void:
						tx.collect_from_script(
							PlutusScriptSource.from_script(script),
							utxos_filtered,
							PlutusData.from_json(script_data.invalid_redeemer)
						),
					"spend from script with invalid redeemer"
				)
			spends.push_back({
				"script": script,
				"utxos": utxos_filtered,
				"redeemer": script_data.valid_redeemer
			})
				
		previous_tx_hash = await tx_with(
			wallet,
			func(tx: TxBuilder) -> void:
				for spend in spends:
					tx.collect_from_script(
						PlutusScriptSource.from_script(spend.script),
						spend.utxos,
						PlutusData.from_json(spend.redeemer)
					),
			"spend from script"
		)
		
		if previous_tx_hash != null:
			await _provider.await_tx(previous_tx_hash)
		
		tx_test_finished.emit({
			"name": "spend script",
			"address": wallet._get_change_address(),
			"tx_hash": previous_tx_hash
		})
		return previous_tx_hash

	func test_blockfrost() -> void:
		await init_blockfrost_tests()

		for test in blockfrost_tests:
			var ix = blockfrost_tests.find(test)
			var wallet := _wallets[ix]
			add_child(wallet)
			test.call(wallet)
	
		var results: Array[Dictionary] = []
		while results.size() < blockfrost_tests.size():
			results.push_back(await tx_test_finished)
		
		gut.p("Collected results")
		var success: bool = true
		for result in results:
			success = success and result.tx_hash != null
			if result.tx_hash == null:
				push_error("Test failed: %s" % result.name)
				continue
			var status := await _provider.await_utxos_at(
				result.address,
				result.tx_hash,
				180
			)
		assert_true(success, "All Blockfrost tests successfully completed")
		
		await tx_with(
			_wallets[0],
			func (tx: TxBuilder) -> void:
				for test in blockfrost_tests:
					var ix = blockfrost_tests.find(test)
					var wallet := _wallets[ix]
					var utxos = await wallet._get_updated_utxos()
					tx.collect_from(utxos)
				tx.set_change_address(_funding_address),
			"funding return",
			func (tx: TxComplete) -> TxComplete:
				for test in blockfrost_tests:
					var ix = blockfrost_tests.find(test)
					var wallet := _wallets[ix]
					tx.sign("1234", wallet)
				return tx
		)
		
		for test in blockfrost_tests:
			var ix = blockfrost_tests.find(test)
			var wallet := _wallets[ix]
			wallet.queue_free()

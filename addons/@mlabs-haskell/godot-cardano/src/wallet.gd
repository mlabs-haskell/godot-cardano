extends Node

class_name Wallet

signal got_updated_utxos(utxos: Array[Utxo])

var _provider: Provider
var active: bool = false

func _get_utxos() -> Array[Utxo]:
	return []
	
func _get_change_address() -> Address:
	return null
	
func total_lovelace() -> BigInt:
	var utxos := await self._get_utxos()
	return utxos.reduce(
		func (accum: BigInt, utxo: Utxo) -> BigInt: return accum.add(utxo.coin()),
		BigInt.zero()
	)

func new_tx() -> TxBuilder.CreateResult:
	var create_result := await _provider.new_tx()
	
	if create_result.is_ok():
		create_result.value.set_wallet(self)

	return create_result

class SignTxResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: Signature:
		get: return _res.unsafe_value() as Signature
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()
		
func _sign_transaction(password: String, _transaction: Transaction) -> SignTxResult:
	return null

class MnemonicWallet extends Wallet:
	var _single_address_wallet: SingleAddressWallet

	@export
	var utxos_update_age: float = 30
	@export
	var utxos_cache_age: float = 30

	# Time left before the Utxos are refreshed. If equal to zero, then the utxos
	# are currently being fetched.
	var time_left: float:
		get: return timer.time_left
	
	var timer: Timer

	## Cached utxos, these can and _will_ be outdated. To get the latest utxos,
	## call [MnemonicWallet.get_utxos].
	var utxos: Array[Utxo] = []
		
	func _init(
		single_address_wallet: SingleAddressWallet, 
		provider: Provider,
		auto_update_utxos: bool = true
	) -> void:
		_provider = provider
		_single_address_wallet = single_address_wallet
		self.active = true
		# Connect and start the timer
		timer = Timer.new()
		timer.one_shot = false
		var _status := timer.timeout.connect(update_utxos)
		timer.wait_time = utxos_update_age
		add_child(timer)
		if auto_update_utxos:
			timer.autostart = true
			# Initialize UTxOs immediately
			update_utxos()
		
	## Update the cached utxos. The same as [MnemonicWallet.get_utxos], but
	## without returning the updated utxos.
	func update_utxos() -> void:
		print_debug("update_utxos called")
		var _utxos := await self._get_updated_utxos()
		return
		
	## Return the cached UTxOs in the wallet. These may be outdated.
	func _get_utxos() -> Array[Utxo]:
		#print_debug("get_utxos called")
		if self.timer.time_left > utxos_cache_age:
			var new_utxos := await _get_updated_utxos()
			return new_utxos
		else:
			return self.utxos
	
	## Asynchronously obtain the wallet's UTxOs. This method will fetch them
	## from the blockchain and the response will represent the wallet's state
	## at the time the request was made.
	##
	## It will also update the cached utxos and reset the timer.
	func _get_updated_utxos() -> Array[Utxo]:
		self.timer.stop()
		self.utxos = await _provider.get_utxos_at_address(_single_address_wallet.get_address())
		got_updated_utxos.emit(self.utxos)
		if is_inside_tree():
			self.timer.start()
		return self.utxos
		
	func _get_change_address() -> Address:
		return _single_address_wallet.get_address()
		
	func _sign_transaction(password: String, transaction: Transaction) -> SignTxResult:
		return _single_address_wallet._sign_transaction(password, transaction)

	func add_account(account_index: int, password: String) -> SingleAddressWallet.AddAccountResult:
		return _single_address_wallet.add_account(account_index, password)
		
	func switch_account(account: Account) -> int:
		return _single_address_wallet.switch_account(account)

	func send_lovelace_to(password: String, recipient: String, amount: BigInt) -> void:
		@warning_ignore("redundant_await")
		var change_address := await _get_change_address()
		@warning_ignore("redundant_await")
		var utxos := await _get_utxos()
		var total_lovelace := await total_lovelace()
		
		if amount.gt(total_lovelace):
			print("Error: not enough lovelace in wallet")
			return
		
		var address_result = Address.from_bech32(recipient)
		
		if address_result.is_err():
			push_error("Failed to decode address bech32: %s" % address_result.error)
			return
			
		var create_result := await new_tx()
		
		if create_result.is_err():
			push_error("Could not create new transaction")
			return
		
		var builder := create_result.value
		builder.pay_to_address(address_result.value, amount, MultiAsset.empty())
		var transaction := await builder.complete()
		transaction.sign(password)
		transaction.submit()

extends Node
class_name OnlineWallet

## A wallet class with online functionality, enabled by a Provider
##
## This class is used for providing wallet-related online functionality, such
## as querying for the assets or UTxOs locked at the wallet. These features are
## possible due to the required [Provider] in its constructor.

signal got_updated_utxos(utxos: Array[Utxo])

var _provider: Provider
var active: bool = false

func _get_utxos() -> Array[Utxo]:
	return []
	
func _get_change_address() -> Address:
	return null

## Get the amount of Lovelace locked among all of the wallet's UTxOs
func total_lovelace() -> BigInt:
	var utxos := await self._get_utxos()
	return utxos.reduce(
		func (accum: BigInt, utxo: Utxo) -> BigInt: return accum.add(utxo.coin()),
		BigInt.zero()
	)

## Create a [TxBuilder] and set this to be the wallet used by it. Equivalent to
## using [Provider.new_tx] and then [TxBuilder.set_wallet].
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

func _sign_transaction(_password: String, _transaction: Transaction) -> SignTxResult:
	return null

func sign_transaction(password: String, transaction: Transaction) -> SignTxResult:
	return _sign_transaction(password, transaction)

func get_address() -> Address:
	return _get_change_address()

func get_utxos() -> Array[Utxo]:
	return _get_utxos()
	
func get_payment_pub_key_hash() -> PubKeyHash:
	return _get_change_address().payment_credential().to_pub_key_hash().value
	
## An implementation on top of [SingleAddressWallet].
class OnlineSingleAddressWallet extends OnlineWallet:
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
	## call [OnlineWallet._get_utxos].
	var utxos: Array[Utxo] = []
	
	## Construct the wallet by providing a [SingleAddressWallet] (which serves
	## as the underlying key) and a [Provider] (for the network functionality).
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
		
	func _ready():
		# Initialize UTxOs immediately
		update_utxos()
		
	## Update the cached utxos. The same as [OnlineWallet._get_utxos], but
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
		return _single_address_wallet.sign_transaction(password, transaction)
	
	## Add a new account to the wallet.
	func add_account(account_index: int, password: String) -> SingleAddressWallet.AddAccountResult:
		return _single_address_wallet.add_account(account_index, password)
	## Switch the active account in the wallet.
	func switch_account(account: Account) -> int:
		return _single_address_wallet.switch_account(account)
	## Send a lovelace amount to a [param recipient] BECH32 address. This is
	## provided for convenience, as it avoids using the [TxBuilder] interface.
	func send_lovelace_to(password: String, recipient: String, amount: BigInt) -> TransactionHash:
		var total_lovelace := await total_lovelace()
		
		if amount.gt(total_lovelace):
			print("Error: not enough lovelace in wallet")
			return null
		
		var address_result := Address.from_bech32(recipient)
		
		if address_result.is_err():
			push_error("Failed to decode address bech32: %s" % address_result.error)
			return null
			
		var create_result := await new_tx()
		
		if create_result.is_err():
			push_error("Could not create new transaction: %s" % create_result.error)
			return null
		
		var tx_builder := create_result.value
		tx_builder.pay_to_address(address_result.value, amount)
		
		var complete_result := await tx_builder.complete()
		if complete_result.is_err():
			push_error("Failed to build transaction: %s" % complete_result.error)
			return null

		var tx := complete_result.value
		tx.sign(password)
		var submit_result := await tx.submit()

		if submit_result.is_err():
			push_error("Failed to submit transaction: %s" % submit_result.error)
		
		return submit_result.value

	## See [method Provider.tx_with]
	func tx_with(builder: Callable, signer: Callable) -> TransactionHash:
		return await _provider.tx_with(self, builder, signer)

extends Node

class_name Wallet

signal got_updated_utxos(utxos: Array[Utxo])

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

func _sign_transaction(password: String, _transaction: Transaction) -> Signature:
	return null
	
class MnemonicWallet extends Wallet:
	var provider: Provider
	var single_address_wallet: SingleAddressWallet

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
		
	func _init(single_address_wallet_: SingleAddressWallet, provider_: Provider) -> void:
		self.provider = provider_
		self.single_address_wallet = single_address_wallet_
		self.active = true
		# Connect and start the timer
		timer = Timer.new()
		timer.one_shot = false
		timer.autostart = true
		var _status := timer.timeout.connect(update_utxos)
		timer.wait_time = utxos_update_age
		add_child(timer)
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
		var address_bech32 = single_address_wallet.get_address_bech32()
		self.utxos = await self.provider._get_utxos_at_address(address_bech32)
		got_updated_utxos.emit(self.utxos)
		self.timer.start()
		return self.utxos
		
	func _get_change_address() -> Address:
		return single_address_wallet.get_address()
		
	func _sign_transaction(password: String, transaction: Transaction) -> Signature:
		var res := single_address_wallet._sign_transaction(password, transaction)
		if res.is_ok():
			return res.value
		else:
			# TODO: Do not fail, return error
			push_error("Could not sign transaction, found error", res.error)
			return

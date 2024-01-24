extends Node

class_name Wallet

signal got_updated_utxos(utxos: Array[Utxo])

var active: bool = false

func get_utxos() -> Array[Utxo]:
	return []
	
func get_change_address() -> String:
	return ""
	
func total_lovelace() -> BigInt:
	var utxos := await self.get_utxos()
	return utxos.reduce(
		func (accum: BigInt, utxo: Utxo) -> BigInt: return accum.add(utxo.coin()),
		BigInt.zero()
	)

func sign_transaction(_transaction: Transaction) -> Signature:
	return null
	
class MnemonicWallet extends Wallet:
	var provider: Provider
	var private_key_account: PrivateKeyAccount

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
		
	func _init(account: PrivateKeyAccount, provider_: Provider) -> void:
		self.provider = provider_
		self.private_key_account = account
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
		var _utxos := await self.get_updated_utxos()
		return
		
	## Return the cached UTxOs in the wallet. These may be outdated.
	func get_utxos() -> Array[Utxo]:
		#print_debug("get_utxos called")
		if self.timer.time_left > utxos_cache_age:
			var new_utxos := await get_updated_utxos()
			return new_utxos
		else:
			return self.utxos
	
	## Asynchronously obtain the wallet's UTxOs. This method will fetch them
	## from the blockchain and the response will represent the wallet's state
	## at the time the request was made.
	##
	## It will also update the cached utxos and reset the timer.
	func get_updated_utxos() -> Array[Utxo]:
		print_debug("get_updated_utxos called")
		self.timer.stop()
		var result := private_key_account.get_address_bech32()
		if result.is_ok():
			var address := result.value
			self.utxos = await self.provider.get_utxos_at_address(address)
		else:
			push_error("An error was found while getting the address of an account", result.error)
		got_updated_utxos.emit(self.utxos)
		self.timer.start()
		return self.utxos
		
	func get_change_address() -> String:
		var result := private_key_account.get_address_bech32()
		match result.tag():
			PrivateKeyAccount.Status.SUCCESS:
				return result.value
			_:
				push_error("An error was found while getting the address of an account", result.error)
				return ""
		
	func sign_transaction(transaction: Transaction) -> Signature:
		return private_key_account.sign_transaction(transaction)

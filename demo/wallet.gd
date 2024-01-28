class_name Wallet
extends Abstract

signal utxos_updated(utxos: Array[Utxo])

var active: bool = false

func _get_utxos() -> Array[Utxo]:
	push_error("_get_utxos() virtual method called")
	return []
	
func _get_change_address() -> Address:
	push_error("_get_change_address() virtual method called")
	return null
	
func _sign_transaction(_transaction: Transaction) -> Signature:
	push_error("_sign_transaction() virtual method called")
	return null

class MnemonicWallet extends Wallet:
	var _provider: Provider
	var _private_key_account: PrivateKeyAccount
	var _utxos: Array[Utxo] = []
	var _timer: Timer
		
	func _init(phrase: String, provider: Provider) -> void:
		self._provider = provider
		self._private_key_account = PrivateKeyAccount.from_mnemonic(phrase)
		
		self._timer = Timer.new()
		self._timer.wait_time = 2.0
		self._timer.one_shot = false
		self._timer.autostart = true
		self._timer.timeout.connect(update_utxos)
		add_child(self._timer)
		
		self.active = true
		
	func _ready() -> void:
		update_utxos()
		
	func _process(_delta: float) -> void:
		pass
		
	func _get_utxos() -> Array[Utxo]:
		return _utxos
		
	func _get_change_address() -> Address:
		return self._private_key_account.get_address()
		
	func _sign_transaction(transaction: Transaction) -> Signature:
		return _private_key_account.sign_transaction(transaction)

	func update_utxos() -> void:
		_utxos = await self._provider._get_utxos_at_address(_private_key_account.get_address_bech32())
		utxos_updated.emit(_utxos)
		
func total_lovelace() -> BigInt:
	var utxos := self._get_utxos()
	return utxos.reduce(
		func (accum: BigInt, utxo: Utxo) -> BigInt: return accum.add(utxo.coin),
		BigInt.zero()
	)

extends Node

class_name Wallet

var active: bool = false

func get_utxos() -> Array[Utxo]:
	return []
	
func get_change_address() -> String:
	return ""
	
func total_lovelace() -> BigInt:
	var utxos = await self.get_utxos()
	return utxos.reduce(
		func (accum: BigInt, utxo: Utxo): return accum.add(utxo.coin),
		BigInt.zero()
	)

func sign_transaction(transaction: Transaction) -> Signature:
	return null
	
class MnemonicWallet extends Wallet:
	var provider: Provider
	var private_key_account: PrivateKeyAccount
	var utxos: Array[Utxo] = []
	var update: float = 0
	var update_interval: float = 2
		
	func _init(phrase: String, provider: Provider):
		self.provider = provider
		self.private_key_account = PrivateKeyAccount.from_mnemonic(phrase)
		self.active = true
		
	func _process(delta: float):
		update -= delta
		
	func get_utxos() -> Array[Utxo]:
		if update <= 0:
			update = update_interval
			utxos = await self.provider.get_utxos_at_address(private_key_account.get_address_bech32())
		return utxos
		
	func get_change_address() -> String:
		return self.private_key_account.get_address_bech32()
		
	func sign_transaction(transaction: Transaction) -> Signature:
		return private_key_account.sign_transaction(transaction)

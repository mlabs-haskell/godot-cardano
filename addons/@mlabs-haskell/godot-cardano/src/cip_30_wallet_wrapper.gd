extends Cip30WalletApi

class_name  Cip30SingleAddressWallet

var _single_address_wallet: SingleAddressWallet

func _init(single_address_wallet: SingleAddressWallet):
	_single_address_wallet = single_address_wallet
	
func get_address():
	return _single_address_wallet.get_address_hex()
	
func owns_address(address: String) -> bool:
	return address == _single_address_wallet.get_address_bech32() || address == _single_address_wallet.get_address_hex()
	
func sign_data(password: String, hex_encoded_data: String) -> JavaScriptObject:
	var sign_result := _single_address_wallet.sign_data(password, hex_encoded_data)
	return _mk_sign_response(sign_result)

func _mk_sign_response(sign_result):
	var sign_response = JavaScriptBridge.create_object("Object")
	sign_response.key = sign_result.value._cose_key_hex()
	sign_response.signature = sign_result.value._cose_sig1_hex()
	return sign_response

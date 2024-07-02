extends RefCounted

class_name  Cip30WalletApi

func get_address() -> String:
		assert(false, "Not implmeneted: get_address()")
		return ""

func owns_address(address: String) -> bool:
	assert(false, "Not implmeneted: owns_address()")
	return false

func sign_data(password: String, hex_encoded_data: String) -> JavaScriptObject:
	assert(false, "Not implmeneted: sign_data()")
	return JavaScriptBridge.create_object("Object")


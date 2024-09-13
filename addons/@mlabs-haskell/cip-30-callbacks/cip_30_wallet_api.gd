extends RefCounted
class_name Cip30WalletApi

## Virtual class for implementing a CIP-30 compatible wallet
##
## This class represents a CIP-30 compatible wallet. Inherit it and override
## all of its methods to obtain a CIP-30 wallet that may be registered in the browser
## window with [Cip30Callbacks]. Check that class to see an example
## of use.

## [b]WARNING: Virtual function.[/b][br]
## Return the address of the wallet as a [String].
func get_address() -> String:
		assert(false, "Not implemented: get_address()")
		return ""

## [b]WARNING: Virtual function.[/b][br]
## Check whether [param address] is owned by the wallet or not.
func owns_address(address: String) -> bool:
	assert(false, "Not implemented: owns_address()")
	return false

## [b]WARNING: Virtual function.[/b][br]
## Sign a piece of [param hex_encoded_data] using the [param password].
func sign_data(password: String, hex_encoded_data: String) -> JavaScriptObject:
	assert(false, "Not implemented: sign_data()")
	return JavaScriptBridge.create_object("Object")


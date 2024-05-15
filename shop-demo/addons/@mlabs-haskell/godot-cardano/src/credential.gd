extends Node

class_name Credential

var _credential: _Credential = null

func _init(credential: _Credential):
	_credential = credential

static func from_script(script: PlutusScript) -> Credential:
	return new(_Credential.from_script_hash(script.hash()))
	
static func from_key_hash(key_hash: PubKeyHash) -> Credential:
	return new(_Credential.from_key_hash(key_hash._pub_key_hash))

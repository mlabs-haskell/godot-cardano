extends RefCounted
class_name Credential

## A Cardano credential

var _credential: _Credential = null

enum CredentialType {
	PAYMENT = 0,
	STAKE = 1,
}

enum Status { SUCCESS = 0, INCORRECT_TYPE = 1 }

class ToPubKeyHashResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: PubKeyHash:
		get: return PubKeyHash.new(_res.unsafe_value())
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()
		
class ToScriptHashResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: ScriptHash:
		get: return ScriptHash.new(_res.unsafe_value())
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()
		
func _init(credential: _Credential):
	_credential = credential

static func from_script(script: PlutusScript) -> Credential:
	return new(_Credential.from_script_hash(script.hash()))
	
static func from_script_hash(script_hash: ScriptHash) -> Credential:
	return new(_Credential.from_script_hash(script_hash._script_hash))
	
static func from_script_source(script_source: PlutusScriptSource) -> Credential:
	return new(_Credential.from_script_hash(script_source.hash()))
	
static func from_key_hash(key_hash: PubKeyHash) -> Credential:
	return new(_Credential.from_key_hash(key_hash._pub_key_hash))

func get_type() -> CredentialType:
	return _credential.get_type()
	
func to_bytes() -> PackedByteArray:
	return _credential.to_bytes()

func to_hex() -> String:
	return _credential.to_hex()

func to_pub_key_hash() -> ToPubKeyHashResult:
	return ToPubKeyHashResult.new(_credential.to_pub_key_hash())

func to_script_hash() -> ToScriptHashResult:
	return ToScriptHashResult.new(_credential.to_script_hash())

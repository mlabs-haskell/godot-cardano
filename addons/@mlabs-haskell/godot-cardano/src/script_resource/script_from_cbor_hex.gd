class_name ScriptFromCborHex
extends ScriptResource

@export_multiline
var cbor_hex: String = ""
@export
var plutus_version: int = 2

func _load_script(provider: Provider) -> PlutusScriptSource:
	if plutus_version == 1:
		return PlutusScriptSource.from_script(PlutusScript.create_v1(cbor_hex.hex_decode()))
	return PlutusScriptSource.from_script(PlutusScript.create(cbor_hex.hex_decode()))

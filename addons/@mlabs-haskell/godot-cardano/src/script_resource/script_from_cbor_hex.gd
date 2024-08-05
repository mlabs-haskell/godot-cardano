class_name ScriptFromCborHex
extends ScriptResource

@export_multiline
var cbor_hex: String = ""
@export
var plutus_version: int = 2
@export
var script_args: Array[PlutusDataResource]

func _load_script(provider: Provider) -> PlutusScriptSource:
	var script: PlutusScript = null
	if plutus_version == 1:
		script = PlutusScript.create_v1(cbor_hex.hex_decode())
	script = PlutusScript.create(cbor_hex.hex_decode())
	var args: Array[PlutusData] = []
	for arg: PlutusDataResource in script_args:
		args.push_back(arg.data)
	return PlutusScriptSource.from_script(PlutusData.apply_script_parameters(script, args))

@tool
class_name ScriptFromBlueprint
extends ScriptResource

@export_file("*.json")
var blueprint_path: String
@export
var validator_name: String
@export
var script_args: Array[PlutusDataResource]

func _load_script(provider: Provider) -> PlutusScriptSource:
	var contents := FileAccess.get_file_as_string(blueprint_path)
	var contents_json: Dictionary = JSON.parse_string(contents)
	for validator: Dictionary in contents_json['validators']:
		if validator['title'] == validator_name:
			var script = PlutusScript.create((validator['compiledCode'] as String).hex_decode())
			var args: Array[PlutusData] = []
			for arg: PlutusDataResource in script_args:
				args.push_back(arg.data)
			return PlutusScriptSource.from_script(PlutusData.apply_script_parameters(script, args))
	push_error("Failed to load %s from %s" % [validator_name, blueprint_path])
	return null

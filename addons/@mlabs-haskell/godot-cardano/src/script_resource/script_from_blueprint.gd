@tool
class_name ScriptFromBlueprint
extends ScriptFromCborHex

@export_file("*.json")
var blueprint_path: String
@export
var validator_name: String

func _load_script(provider: Provider) -> PlutusScriptSource:
	var contents := FileAccess.get_file_as_string(blueprint_path)
	var contents_json: Dictionary = JSON.parse_string(contents)
	plutus_version = 1 if contents_json['preamble']['plutusVersion'] == "v1" else 2
	for validator: Dictionary in contents_json['validators']:
		if validator['title'] == validator_name:
			cbor_hex = validator['compiledCode'] as String
			return super(provider)
	push_error("Failed to load %s from %s" % [validator_name, blueprint_path])
	return null

func _validate_property(property):
	var hide_conditions: Array[bool] = [
		property.name == 'cbor_hex',
		property.name == 'plutus_version',
	]
	if hide_conditions.any(func (x): return x):
		property.usage &= ~PROPERTY_USAGE_EDITOR

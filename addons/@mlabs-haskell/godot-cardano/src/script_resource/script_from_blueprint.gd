@tool
class_name ScriptFromBlueprint
extends ScriptResource

@export_file("*.json")
var blueprint_path: String
@export
var validator_name: String
@export
var script_args: Array[PlutusDataResource]

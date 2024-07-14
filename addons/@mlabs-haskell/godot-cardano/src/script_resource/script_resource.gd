@tool
class_name ScriptResource
extends Resource

func _load_script(provider: Provider) -> PlutusScriptSource:
	return null
	
func load_script(provider: Provider = null) -> PlutusScriptSource:
	return _load_script(provider)

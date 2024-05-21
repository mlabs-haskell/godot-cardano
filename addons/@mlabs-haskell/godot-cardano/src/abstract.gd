class_name Abstract
extends RefCounted
## Used to represent abstract classes which should never be instantiated. 
## Concrete classes inheriting from this class should always override _init.

func _init() -> void:
	var abstract_name: String = get("_abstract_name")
	assert(false, "Abstract class `%s` instantiated" % (abstract_name if abstract_name else "Unknown"))

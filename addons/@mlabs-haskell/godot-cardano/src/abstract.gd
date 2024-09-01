class_name Abstract
extends RefCounted

## Used for representing abstract classes
##
## Used to represent abstract classes which should never be instantiated. 
## Concrete classes inheriting from this class should always override
## [method Abstract._init].

## [b]WARNING: Do not use without overriding![/b].
func _init() -> void:
	var abstract_name: String = get("_abstract_name")
	var err_msg := "Abstract class `%s` instantiated" % (abstract_name if abstract_name else "Unknown")
	assert(false, err_msg)
	push_error(err_msg)

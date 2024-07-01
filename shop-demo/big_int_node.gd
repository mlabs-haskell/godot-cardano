@tool
class_name BigIntNode 
extends Node

var b: BigInt = BigInt.zero()

@export
var value: int:
	get:
		return int(b.to_str())
	set(value):
		b = BigInt.from_int(value)
		
func _to_string() -> String:
	return b.to_string()

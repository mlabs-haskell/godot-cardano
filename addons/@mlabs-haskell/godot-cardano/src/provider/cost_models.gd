extends RefCounted
class_name CostModels

## The Plutus cost models
##
## This class is used to represent the cost models of the different Plutus
## versions supported by the SDK.

var _cost_models: _CostModels

func _init(cost_models: Dictionary) -> void:
	_cost_models = _CostModels.create()

	_cost_models.set_plutus_v1_model(_to_ops_list(cost_models.PlutusV1))
	_cost_models.set_plutus_v2_model(_to_ops_list(cost_models.PlutusV2))

func _to_ops_list(model: Dictionary):
	var ops: Array[int] = []
	var keys = model.keys()
	keys.sort()
	for key in keys:
		ops.append(int(model[key]))
	return ops

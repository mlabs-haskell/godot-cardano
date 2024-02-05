extends RefCounted

class_name CostModels

var _cost_models: _CostModels

func _init(cost_models: Dictionary) -> void:
	_cost_models = _CostModels.create()

	_cost_models.set_plutus_v1_model(to_ops_list(cost_models.PlutusV1))
	_cost_models.set_plutus_v2_model(to_ops_list(cost_models.PlutusV2))

func to_ops_list(model: Dictionary):
	var ops: Array[int] = []
	var keys = model.keys()
	keys.sort()
	for key in keys:
		ops.append(int(model[key]))
	return ops

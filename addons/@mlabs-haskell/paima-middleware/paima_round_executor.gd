extends RefCounted

## Wrapper for Paima Round Executor.
## Results of calling [RoundExecutor.tick], [RoundExecutor.end_state], [RoundExecutor.get_current_state]
## and [RoundExecutor.processAllTicks] will depend on concrete game
## so this wrapper uses the most general type [JavaScriptObject] or Array[JavaScriptObject]
class_name RoundExecutor

var _round_executor: JavaScriptObject

func _init(round_executor: JavaScriptObject):
	_round_executor = round_executor

func tick() -> Array[JavaScriptObject]:
	return _to_gd_array(_round_executor.tick())
	
func process_all_ticks() -> Array[JavaScriptObject]:
	return _to_gd_array(_round_executor.processAllTicks())

func _to_gd_array(js_tick_events: JavaScriptObject):
	var tick_events: Array[JavaScriptObject] = []
	if js_tick_events:
		var tick_array_i = JavaScriptBridge.get_interface("Array").from(js_tick_events)
		for i in range(0, tick_array_i.length):
			tick_events.push_front(tick_array_i[i])
	return tick_events

func end_state() -> JavaScriptObject:
	return _round_executor.endState()
	
func get_current_tick() -> int:
	return _round_executor.currentTick

func get_current_state() -> JavaScriptObject:
	return _round_executor.currentState

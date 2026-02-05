extends Node
class_name TestActionProcessor

var registry: CardRegistry
var ap: ActionProcessor

func _ready() -> void:
	print("TestActionProcessor _ready() fired")
	test_discard_target_must_play_then_meld_and_layoffs()
	print("Done.")


func test_discard_target_must_play_then_meld_and_layoffs() -> void:
	
	print("")

extends Node

func _ready() -> void:
	print("TestNewGame _ready() fired")
	var registry := CardRegistry.new()
	var state := NewGame.create_game(2, registry)
	print("NEW GAME:", state.debug_summary())
	print("Top discard card:", registry.get_card(state.discard[-1]))

	await get_tree().create_timer(0.2).timeout
	get_tree().quit()


extends RefCounted
class_name CardRegistry

var cards_by_id: Dictionary = {}

func clear() -> void:
	cards_by_id.clear()

func add_card(card_id: String, deck: int, suit: String, rank: int) -> void:
	# rank: 1..13 (A=1, J=11, Q=12, K=13), suit: "S","H","D","C"
	cards_by_id[card_id] = {
		"id": card_id,
		"deck": deck,
		"suit": suit,
		"rank": rank
	}

func get_card(card_id: String) -> Dictionary:
	return cards_by_id.get(card_id, {})

func has_card(card_id: String) -> bool:
	return cards_by_id.has(card_id)

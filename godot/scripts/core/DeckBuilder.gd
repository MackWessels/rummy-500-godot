
extends RefCounted
class_name DeckBuilder

const SUITS = ["S","H","D","C"]
const RANKS = [1,2,3,4,5,6,7,8,9,10,11,12,13]

static func build_shoe(num_decks: int, registry: CardRegistry) -> Array:
	registry.clear()
	
	var shoe: Array = []
	var serial = 0
	
	for deck in range(num_decks):
		for suit in SUITS:
			for rank in RANKS:
				serial += 1
				var card_id = "D%s-%s%s-%04d" % [deck, suit, str(rank), serial]
				registry.add_card(card_id, deck, suit, rank)
				shoe.append(card_id)
	
	return shoe

static func shuffle_in_place(arr: Array) -> void:
	arr.shuffle()

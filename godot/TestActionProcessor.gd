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

func _cid(deck: int, suit: String, rank: int) -> String:
	# Find the unique CardID (deck,suit,rank)
	for id in registry.cards_by_id.keys():
		var c = registry.get_card(String(id))
		if c.is_empty():
			continue
		if int(c["deck"]) == deck and String(c["suit"]) == suit and int(c["rank"]) == rank:
			return String(id)
	return ""

func _count_in_hand(hand: Array, card_id: String) -> int:
	var n = 0
	for cid in hand:
		if String(cid) == card_id:
			n += 1
	return n

func _expect(cond: bool, label: String) -> void:
	if cond:
		print("OK:", label)
	else:
		push_error("FAIL: %s" % label)

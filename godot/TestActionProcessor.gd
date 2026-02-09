extends Node
class_name TestActionProcessor

var registry: CardRegistry
var ap: ActionProcessor

func _ready() -> void:
	print("TestActionProcessor _ready() fired")
	test_discard_target_must_play_then_meld_and_layoffs()
	print("Done.")


func test_discard_target_must_play_then_meld_and_layoffs() -> void:
	print("\n--- test_discard_target_must_play_then_meld_and_layoffs ---")
	
	registry = CardRegistry.new()
	DeckBuilder.build_shoe(1, registry) # no shuffle needed; we just want registry populated
	
	ap = ActionProcessor.new(registry, ActionProcessor.StockEmptyPolicy.RESHUFFLE_EXCEPT_TOP, 123)
	
	var state = GameState.new()
	state.num_players = 2
	state.init_for_players(2)
	state.turn_player = 0
	state.phase = "DRAW"
	state.hand_over = false
	state.hand_end_reason = ""
	state.went_out_player = -1
	
	# Grab specific cards by suit/rank
	var c7C = _cid(0, "C", 7)
	var c7H = _cid(0, "H", 7)
	var c7D = _cid(0, "D", 7)
	var c7S = _cid(0, "S", 7)
	
	var c3S = _cid(0, "S", 3)
	var c4S = _cid(0, "S", 4)
	var c5S = _cid(0, "S", 5)
	var c6S = _cid(0, "S", 6)
	
	var c2C = _cid(0, "C", 2)
	var c9S = _cid(0, "S", 9)
	var cKH = _cid(0, "H", 13) # king
	
	var c8H = _cid(0, "H", 8)
	var cQD = _cid(0, "D", 12)
	
	_expect(c7C != "" and c7H != "" and c7D != "" and c7S != "", "Found all 7s")
	_expect(c3S != "" and c4S != "" and c5S != "" and c6S != "", "Found spade run cards 3-6")
	_expect(c2C != "" and c9S != "" and cKH != "", "Found filler cards for discard pile")
	_expect(c8H != "" and cQD != "", "Found filler cards for player1/stock")
	
	# Player 0 has: a future SET (7C,7H + target 7D later) and a RUN (3S-4S-5S)
	state.hands[0] = [c7C, c7H, c3S, c4S, c5S]
	# Player 1 has layoff cards: 7S for set, 6S for run, plus a filler
	state.hands[1] = [c7S, c6S, c8H]
	
	# Discard pile is fully visible; top is back().
	# Put target 7D in the middle, with 9S and KH above it.
	state.discard = [c2C, c7D, c9S, cKH] # top = KH
	# Stock just needs at least 1 card for player1 draw.
	state.stock = [cQD] # top = QD
	
	print("Initial:", state.debug_summary())
	print("P0 hand:", state.hands[0])
	print("P1 hand:", state.hands[1])
	print("Discard (bottom->top):", state.discard)
	print("Stock (top is last):", state.stock)
	
	# 1) Player 0 draws discard stack down to target 7D.
	var r = ap.apply(state, 0, {"type":"DRAW_DISCARD_STACK", "target_card_id": c7D})
	_expect(r.ok, "P0 DRAW_DISCARD_STACK ok")
	_expect(state.phase == "PLAY", "Phase advanced to PLAY after drawing")
	_expect(state.must_play_discard_pending[0] == true, "must_play pending set for P0")
	_expect(state.must_play_discard_target[0] == c7D, "must_play target is 7D")
	_expect(state.discard.size() == 1 and state.discard[0] == c2C, "Discard left below target only (kept 2C)")
	_expect(_count_in_hand(state.hands[0], c7D) == 1, "P0 received target 7D into hand")
	
	# 2) P0 tries to CREATE a valid meld that does NOT include target (RUN 3S-4S-5S). Should be rejected.
	r = ap.apply(state, 0, {"type":"CREATE_MELD", "meld_kind":"RUN", "card_ids":[c3S, c4S, c5S]})
	_expect(not r.ok, "P0 CREATE_MELD run (without target) rejected")
	_expect(r.reason == "MUST_PLAY_DISCARD_TARGET_THIS_TURN", "Rejected because must-play target not used")
	
	# 3) P0 tries DISCARD while must-play pending. Should be rejected.
	r = ap.apply(state, 0, {"type":"DISCARD", "card_id": c3S})
	_expect(not r.ok, "P0 DISCARD rejected while must-play pending")
	_expect(r.reason == "MUST_PLAY_DISCARD_TARGET_BEFORE_DISCARD", "Correct discard rejection reason")
	
	# 4) P0 creates SET including the target: 7C-7H-7D. Should succeed and clear must-play.
	r = ap.apply(state, 0, {"type":"CREATE_MELD", "meld_kind":"SET", "card_ids":[c7C, c7H, c7D]})
	_expect(r.ok, "P0 CREATE_MELD set including target ok")
	_expect(state.must_play_discard_pending[0] == false, "must_play cleared after using target in meld")
	_expect(state.melds.size() == 1, "One meld exists after set creation")
	_expect(String(state.melds[0]["type"]) == "SET", "Meld[0] is a SET")
	_expect(int(state.melds[0]["rank"]) == 7, "SET rank is 7")
	
	# 5) Now that must-play is cleared, P0 creates RUN 3S-4S-5S (same turn). Should succeed.
	r = ap.apply(state, 0, {"type":"CREATE_MELD", "meld_kind":"RUN", "card_ids":[c3S, c4S, c5S]})
	_expect(r.ok, "P0 CREATE_MELD run ok after must-play cleared")
	_expect(state.melds.size() == 2, "Two melds exist after run creation")
	_expect(String(state.melds[1]["type"]) == "RUN", "Meld[1] is a RUN")
	_expect(String(state.melds[1]["suit"]) == "S", "RUN suit is Spades")
	
	# 6) P0 discards one card to end turn (discard 9S they drew).
	_expect(state.hands[0].has(c9S), "P0 has 9S available to discard")
	r = ap.apply(state, 0, {"type":"DISCARD", "card_id": c9S})
	_expect(r.ok, "P0 DISCARD ok")
	_expect(state.turn_player == 1, "Turn advanced to P1")
	_expect(state.phase == "DRAW", "Phase reset to DRAW for next player")
	_expect(state.discard.back() == c9S, "Top of discard is now 9S")
	
	# 7) P1 draws from stock.
	r = ap.apply(state, 1, {"type":"DRAW_STOCK"})
	_expect(r.ok, "P1 DRAW_STOCK ok")
	_expect(state.phase == "PLAY", "P1 phase advanced to PLAY after draw")
	
	# 8) P1 lays off 7S onto P0's SET (meld_id 0).
	r = ap.apply(state, 1, {"type":"LAYOFF", "meld_id": 0, "card_id": c7S})
	_expect(r.ok, "P1 LAYOFF 7S onto SET ok")
	_expect(not state.hands[1].has(c7S), "7S removed from P1 hand")
	_expect(state.melds[0]["cards"].has(c7S), "7S is now part of the SET")
	
	# 9) P1 lays off 6S onto P0's RUN (meld_id 1) on the RIGHT end (3-4-5 -> add 6).
	r = ap.apply(state, 1, {"type":"LAYOFF", "meld_id": 1, "card_id": c6S, "end":"RIGHT"})
	_expect(r.ok, "P1 LAYOFF 6S onto RUN RIGHT ok")
	_expect(not state.hands[1].has(c6S), "6S removed from P1 hand")
	_expect(state.melds[1]["cards"].back() == c6S, "6S appended to the right end of the run")
	
	# 10) P1 discards exactly one card to end turn (discard 8H).
	r = ap.apply(state, 1, {"type":"DISCARD", "card_id": c8H})
	_expect(r.ok, "P1 DISCARD ok")
	_expect(state.turn_player == 0, "Turn advanced back to P0")
	_expect(state.phase == "DRAW", "Phase reset to DRAW for P0")
	_expect(state.hand_over == false, "Hand not ended by this test case")
	
	print("Final:", state.debug_summary())
	print("Melds:", state.melds)
	print("Discard (bottom->top):", state.discard)

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

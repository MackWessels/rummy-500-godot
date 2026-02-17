extends Node
class_name TestActionProcessor

var registry: CardRegistry
var ap: ActionProcessor

func _ready() -> void:
	print("TestActionProcessor _ready() fired")
	test_discard_target_must_play_then_meld_and_layoffs()
	test_must_play_target_via_layoff_and_invalid_actions()
	
	test_scoring_contrib_and_deadwood()
	test_stock_exhausted_ends_hand()
	
	print("Done.")

func test_stock_exhausted_ends_hand() -> void:
	print("\n--- test_stock_exhausted_ends_hand ---")

	registry = CardRegistry.new()
	DeckBuilder.build_shoe(1, registry)
	ap = ActionProcessor.new(registry, ActionProcessor.StockEmptyPolicy.RESHUFFLE_EXCEPT_TOP, 123)

	var state = GameState.new()
	state.init_for_players(2)
	state.turn_player = 0
	state.phase = "DRAW"

	var c2C = _cid(0, "C", 2)
	_expect(c2C != "", "Found 2C")

	state.stock = []          # empty stock
	state.discard = [c2C]     # discard < 2 => cannot refill

	var r = ap.apply(state, 0, {"type":"DRAW_STOCK"})
	_expect(not r.ok, "DRAW_STOCK fails when no cards to refill")
	_expect(r.hand_ended == true, "hand_ended true")
	_expect(r.reason == "NO_CARDS_TO_REFILL_STOCK", "reason NO_CARDS_TO_REFILL_STOCK")
	_expect(state.hand_over == true, "state.hand_over true")
	_expect(state.hand_end_reason == "NO_CARDS_TO_REFILL_STOCK", "state.hand_end_reason matches")
	_expect(state.hand_scored == true, "hand_scored still runs on forced end")


func test_scoring_contrib_and_deadwood() -> void:
	print("\n--- test_scoring_contrib_and_deadwood ---")

	registry = CardRegistry.new()
	DeckBuilder.build_shoe(2, registry) # IMPORTANT: 2 decks for duplicate 7C
	ap = ActionProcessor.new(registry, ActionProcessor.StockEmptyPolicy.RESHUFFLE_EXCEPT_TOP, 123)

	var state = GameState.new()
	state.init_for_players(2)
	state.turn_player = 0
	state.phase = "DRAW"

	# Cards (deck 0 for main meld, deck 1 for extra 7C that P0 will keep)
	var c7C0 = _cid(0, "C", 7)
	var c7H0 = _cid(0, "H", 7)
	var c7D0 = _cid(0, "D", 7)
	var c7S0 = _cid(0, "S", 7)

	var c7C1 = _cid(1, "C", 7) # extra 7C from deck 1

	var c2C0 = _cid(0, "C", 2)
	var c9D0 = _cid(0, "D", 9)
	var cQD0 = _cid(0, "D", 12)
	var c8H0 = _cid(0, "H", 8)

	_expect(c7C0 != "" and c7H0 != "" and c7D0 != "" and c7S0 != "" and c7C1 != "", "Found needed 7s (including duplicate 7C)")
	_expect(c2C0 != "" and c9D0 != "" and cQD0 != "" and c8H0 != "", "Found filler cards")

	# P0 will create meld with 3x7 (deck0), but keep 7C(deck1) in hand to avoid going out early.
	state.hands[0] = [c7C0, c7H0, c7D0, c7C1]
	state.hands[1] = [c7S0, c9D0]

	# Stock draw order: pop_back()
	# P0 draws 2C, P1 draws QD, P0 draws 8H
	state.stock = [c8H0, cQD0, c2C0]
	state.discard = []

	# P0 draw stock (2C)
	var r = ap.apply(state, 0, {"type":"DRAW_STOCK"})
	_expect(r.ok, "P0 DRAW_STOCK ok")
	_expect(state.hands[0].has(c2C0), "P0 received 2C")

	# P0 create SET 7C0-7H0-7D0
	r = ap.apply(state, 0, {"type":"CREATE_MELD", "meld_kind":"SET", "card_ids":[c7C0, c7H0, c7D0]})
	_expect(r.ok, "P0 CREATE_MELD set ok")
	_expect(state.melds.size() == 1, "One meld on table")
	_expect(int(state.melds[0].get("owner", -1)) == 0, "Meld owner is P0")

	# P0 discard 2C (NOT last card, should NOT end hand)
	r = ap.apply(state, 0, {"type":"DISCARD", "card_id": c2C0})
	_expect(r.ok, "P0 DISCARD 2C ok")
	_expect(state.hand_over == false, "Hand NOT over after P0 discard (didn't go out)")
	_expect(state.turn_player == 1 and state.phase == "DRAW", "Turn -> P1 DRAW")

	# P1 draw stock (QD)
	r = ap.apply(state, 1, {"type":"DRAW_STOCK"})
	_expect(r.ok, "P1 DRAW_STOCK ok")
	_expect(state.hands[1].has(cQD0), "P1 received QD")

	# P1 layoff 7S0 onto meld 0 (contrib -> P1)
	r = ap.apply(state, 1, {"type":"LAYOFF", "meld_id": 0, "card_id": c7S0})
	_expect(r.ok, "P1 LAYOFF 7S onto set ok")
	_expect(int(state.melds[0]["contrib"].get(c7S0, -1)) == 1, "contrib 7S -> P1")

	# P1 discard 9D (keeps QD as deadwood)
	r = ap.apply(state, 1, {"type":"DISCARD", "card_id": c9D0})
	_expect(r.ok, "P1 DISCARD 9D ok")
	_expect(state.turn_player == 0 and state.phase == "DRAW", "Turn -> P0 DRAW")

	# P0 final turn: has 7C1 in hand, draws 8H, layoffs 7C1 onto set, then discards 8H to go out.
	r = ap.apply(state, 0, {"type":"DRAW_STOCK"})
	_expect(r.ok, "P0 DRAW_STOCK (8H) ok")
	_expect(state.hands[0].has(c7C1) and state.hands[0].has(c8H0), "P0 has 7C1 + 8H")

	r = ap.apply(state, 0, {"type":"LAYOFF", "meld_id": 0, "card_id": c7C1})
	_expect(r.ok, "P0 LAYOFF 7C1 onto set ok")
	_expect(not state.hands[0].has(c7C1), "7C1 removed from P0 hand")

	r = ap.apply(state, 0, {"type":"DISCARD", "card_id": c8H0})
	_expect(r.ok and r.hand_ended and r.went_out, "P0 DISCARD last card => went out")
	_expect(state.hand_end_reason == "WENT_OUT", "hand_end_reason WENT_OUT")
	_expect(state.hand_scored == true, "hand_scored true")

	# Scoring expectations:
	# P0 table: 7+7+7 + 7 = 28 (3 meld cards + their own layoff 7C1)
	# P1 table: 7 (their layoff)
	# P1 deadwood: QD = 10
	_expect(state.hand_points_table[0] == 28, "P0 table points = 28")
	_expect(state.hand_points_table[1] == 7,  "P1 table points = 7")
	_expect(state.hand_points_deadwood[0] == 0,  "P0 deadwood = 0")
	_expect(state.hand_points_deadwood[1] == 10, "P1 deadwood = 10 (QD)")
	_expect(state.hand_points_net[0] == 28, "P0 net = 28")
	_expect(state.hand_points_net[1] == -3, "P1 net = 7-10 = -3")




func test_must_play_target_via_layoff_and_invalid_actions() -> void:
	print("\n--- test_must_play_target_via_layoff_and_invalid_actions ---")

	registry = CardRegistry.new()
	DeckBuilder.build_shoe(1, registry)

	ap = ActionProcessor.new(registry, ActionProcessor.StockEmptyPolicy.RESHUFFLE_EXCEPT_TOP, 123)

	var state = GameState.new()
	state.num_players = 2
	state.init_for_players(2)
	state.turn_player = 0
	state.phase = "DRAW"
	state.hand_over = false
	state.hand_end_reason = ""
	state.went_out_player = -1

	# Card ids we need
	var c3S = _cid(0, "S", 3)
	var c4S = _cid(0, "S", 4)
	var c5S = _cid(0, "S", 5)
	var c6S = _cid(0, "S", 6)

	var c7C = _cid(0, "C", 7)
	var c7H = _cid(0, "H", 7)
	var c7D = _cid(0, "D", 7)

	var c2C = _cid(0, "C", 2)
	var c9D = _cid(0, "D", 9)
	var cQD = _cid(0, "D", 12)
	var c8H = _cid(0, "H", 8)

	_expect(c3S != "" and c4S != "" and c5S != "" and c6S != "", "Found run cards 3S-6S")
	_expect(c7C != "" and c7H != "" and c7D != "", "Found set cards 7C/7H/7D")
	_expect(c2C != "" and c9D != "" and cQD != "" and c8H != "", "Found filler cards")

	# Pre-existing melds on the table:
	# RUN: 3S-4S-5S (id 0)
	# SET: 7C-7D-7H (id 1)
	state.melds = [
		{"id": 0, "type": "RUN", "cards": [c3S, c4S, c5S], "suit": "S", "ace_mode": "UNSET"},
		{"id": 1, "type": "SET", "cards": [c7C, c7D, c7H], "rank": 7}
	]

	# Player 0 will draw discard-stack with target 6S and must immediately play 6S into a meld this turn.
	state.hands[0] = [c2C] # just a filler card to show hand changes
	# Player 1 has cards for invalid layoff tests later
	state.hands[1] = [c4S, c8H]

	# Discard: put target 6S in the middle, with 9D above it.
	state.discard = [c7C, c6S, c9D] # bottom->top, top is 9D
	# Stock: give player 1 something to draw
	state.stock = [cQD]

	print("Initial:", state.debug_summary())
	print("Melds:", state.melds)
	print("P0 hand:", state.hands[0])
	print("P1 hand:", state.hands[1])
	print("Discard (bottom->top):", state.discard)
	print("Stock (top is last):", state.stock)

	# 1) P0 draws discard stack down to target 6S (takes 6S + 9D)
	var r = ap.apply(state, 0, {"type":"DRAW_DISCARD_STACK", "target_card_id": c6S})
	_expect(r.ok, "P0 DRAW_DISCARD_STACK ok")
	_expect(state.phase == "PLAY", "Phase is PLAY after discard-stack draw")
	_expect(state.must_play_discard_pending[0] == true, "must_play pending set for P0")
	_expect(state.must_play_discard_target[0] == c6S, "must_play target is 6S")
	_expect(state.discard.size() == 1, "Discard left below target only")
	_expect(state.hands[0].has(c6S) and state.hands[0].has(c9D), "P0 received 6S and 9D")

	# 2) P0 tries to DISCARD before satisfying must-play -> reject
	r = ap.apply(state, 0, {"type":"DISCARD", "card_id": c9D})
	_expect(not r.ok, "P0 DISCARD rejected while must-play pending")
	_expect(r.reason == "MUST_PLAY_DISCARD_TARGET_BEFORE_DISCARD", "Correct reason for discard rejection")

	# 3) P0 tries to lay off 6S to the WRONG end (LEFT) of run 3S-4S-5S -> reject
	r = ap.apply(state, 0, {"type":"LAYOFF", "meld_id": 0, "card_id": c6S, "end":"LEFT"})
	_expect(not r.ok, "P0 LAYOFF 6S on wrong end rejected")
	_expect(r.reason == "Card does not extend left end", "Correct reason for wrong-end run layoff")
	_expect(state.must_play_discard_pending[0] == true, "must_play still pending after failed layoff")

	# 4) P0 tries to DRAW_STOCK while in PLAY -> reject
	r = ap.apply(state, 0, {"type":"DRAW_STOCK"})
	_expect(not r.ok, "P0 DRAW_STOCK rejected in PLAY")
	_expect(r.reason == "BAD_PHASE_NEED_DRAW", "Correct reason for draw in wrong phase")

	# 5) P0 lays off 6S to RIGHT end of run -> ok, must-play clears
	r = ap.apply(state, 0, {"type":"LAYOFF", "meld_id": 0, "card_id": c6S, "end":"RIGHT"})
	_expect(r.ok, "P0 LAYOFF 6S on RIGHT ok")
	_expect(state.melds[0]["cards"].back() == c6S, "6S appended to run")
	_expect(state.must_play_discard_pending[0] == false, "must_play cleared after successful layoff")

	# 6) Now P0 can discard and end turn
	r = ap.apply(state, 0, {"type":"DISCARD", "card_id": c9D})
	_expect(r.ok, "P0 DISCARD ok after satisfying must-play")
	_expect(state.turn_player == 1, "Turn advanced to P1")
	_expect(state.phase == "DRAW", "Phase reset to DRAW for P1")

	# 7) P0 tries to act out of turn -> reject
	r = ap.apply(state, 0, {"type":"DRAW_STOCK"})
	_expect(not r.ok, "P0 action rejected when not your turn")
	_expect(r.reason == "NOT_YOUR_TURN", "Correct reason for out-of-turn action")

	# 8) P1 draws stock
	r = ap.apply(state, 1, {"type":"DRAW_STOCK"})
	_expect(r.ok, "P1 DRAW_STOCK ok")
	_expect(state.phase == "PLAY", "P1 phase is PLAY after draw")

	# 9) P1 tries to lay off a duplicate rank already in run (4S is already in 3S-4S-5S-6S) -> reject
	r = ap.apply(state, 1, {"type":"LAYOFF", "meld_id": 0, "card_id": c4S, "end":"RIGHT"})
	_expect(not r.ok, "P1 duplicate-rank run layoff rejected")
	_expect(r.reason == "Run already has that rank", "Correct reason for duplicate rank in run")

	# 10) P1 tries to lay off wrong rank onto SET(7s) using 8H -> reject
	r = ap.apply(state, 1, {"type":"LAYOFF", "meld_id": 1, "card_id": c8H})
	_expect(not r.ok, "P1 wrong-rank set layoff rejected")
	_expect(r.reason == "SET_LAYOFF_WRONG_RANK", "Correct reason for wrong-rank set layoff")

	print("Final:", state.debug_summary())
	print("Melds:", state.melds)
	print("Discard (bottom->top):", state.discard)

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

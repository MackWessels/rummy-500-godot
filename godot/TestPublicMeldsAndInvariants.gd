extends Node

var _fails: int = 0

func _ready() -> void:
	print("TestPublicMeldsAndInvariants _ready() fired")

	test_split_run_public_links_and_turn_flow()
	test_discard_stack_must_play_clears_on_meld()

	if _fails == 0:
		print("\nALL TESTS PASSED")
	else:
		print("\nTESTS FAILED: %s failure(s)" % _fails)


func test_split_run_public_links_and_turn_flow() -> void:
	print("\n--- test_split_run_public_links_and_turn_flow ---")

	var registry := CardRegistry.new()
	var rules := RulesConfig.new()
	var ap := ActionProcessor.new(
		registry,
		ActionProcessor.StockEmptyPolicy.RESHUFFLE_EXCEPT_TOP,
		123456,
		rules
	)

	var shoe := DeckBuilder.build_shoe(1, registry)
	var state := GameState.new()
	state.init_for_players(2)

	var h5 := _find_card_id(shoe, registry, "H", 5, 0)
	var h6 := _find_card_id(shoe, registry, "H", 6, 0)
	var h7 := _find_card_id(shoe, registry, "H", 7, 0)
	var h8 := _find_card_id(shoe, registry, "H", 8, 0)
	var h9 := _find_card_id(shoe, registry, "H", 9, 0)

	var d2 := _find_card_id(shoe, registry, "D", 2, 0)
	var c2 := _find_card_id(shoe, registry, "C", 2, 0)
	var c4 := _find_card_id(shoe, registry, "C", 4, 0)
	var d3 := _find_card_id(shoe, registry, "D", 3, 0)
	var s2 := _find_card_id(shoe, registry, "S", 2, 0)

	_ok(h5 != "", "found H5")
	_ok(h6 != "", "found H6")
	_ok(h7 != "", "found H7")
	_ok(h8 != "", "found H8")
	_ok(h9 != "", "found H9")
	_ok(d2 != "", "found D2")
	_ok(c2 != "", "found C2")
	_ok(c4 != "", "found C4")
	_ok(d3 != "", "found D3")
	_ok(s2 != "", "found S2")

	# Player 1 will create 5-6-7, Player 0 will lay off 8, Player 1 will lay off 9.
	state.hands[0] = [h8, c2]
	state.hands[1] = [h5, h6, h7, h9, d2]
	state.stock = [c4, d3] # pop_back -> d3 first, then c4
	state.discard = [s2]

	state.turn_player = 1
	state.phase = ActionProcessor.PHASE_PLAY

	_check_invariants(state, registry, rules, "initial state")

	# P1 create meld 5-6-7
	var r1 = ap.apply(state, 1, {
		"type": ActionProcessor.TYPE_CREATE_MELD,
		"meld_kind": ActionProcessor.MELD_RUN,
		"card_ids": [h5, h6, h7]
	})
	_ok(r1["ok"], "P1 created run 5-6-7")
	if not r1["ok"]:
		_fail("P1 create meld reason=" + String(r1["reason"]))
		return

	var meld_id := int(r1["events"][0]["meld_id"])
	_eq(meld_id, 1, "first meld id is 1")
	_check_invariants(state, registry, rules, "after P1 create meld")

	# P1 discard to end turn
	var r2 = ap.apply(state, 1, {
		"type": ActionProcessor.TYPE_DISCARD,
		"card_id": d2
	})
	_ok(r2["ok"], "P1 discarded D2")
	_eq(state.turn_player, 0, "turn advanced to P0")
	_eq(state.phase, ActionProcessor.PHASE_DRAW, "phase returned to DRAW")
	_check_invariants(state, registry, rules, "after P1 discard")

	# P0 draw stock
	var r3 = ap.apply(state, 0, {
		"type": ActionProcessor.TYPE_DRAW_STOCK
	})
	_ok(r3["ok"], "P0 drew from stock")
	_eq(state.phase, ActionProcessor.PHASE_PLAY, "phase moved to PLAY after draw")
	_ok(state.hands[0].has(d3), "P0 received D3 from stock")
	_check_invariants(state, registry, rules, "after P0 draw stock")

	# P0 lay off H8 to the right end
	var r4 = ap.apply(state, 0, {
		"type": ActionProcessor.TYPE_LAYOFF,
		"meld_id": meld_id,
		"card_id": h8,
		"end": ActionProcessor.END_RIGHT
	})
	_ok(r4["ok"], "P0 laid off H8 to the run")
	_check_invariants(state, registry, rules, "after P0 layoff H8")

	# P0 discard to end turn
	var r5 = ap.apply(state, 0, {
		"type": ActionProcessor.TYPE_DISCARD,
		"card_id": c2
	})
	_ok(r5["ok"], "P0 discarded C2")
	_eq(state.turn_player, 1, "turn advanced back to P1")
	_eq(state.phase, ActionProcessor.PHASE_DRAW, "phase returned to DRAW again")
	_check_invariants(state, registry, rules, "after P0 discard")

	# P1 draw stock
	var r6 = ap.apply(state, 1, {
		"type": ActionProcessor.TYPE_DRAW_STOCK
	})
	_ok(r6["ok"], "P1 drew from stock")
	_ok(state.hands[1].has(c4), "P1 received C4 from stock")
	_check_invariants(state, registry, rules, "after P1 draw stock")

	# P1 lay off H9 to the right end
	var r7 = ap.apply(state, 1, {
		"type": ActionProcessor.TYPE_LAYOFF,
		"meld_id": meld_id,
		"card_id": h9,
		"end": ActionProcessor.END_RIGHT
	})
	_ok(r7["ok"], "P1 laid off H9 to the run")
	_check_invariants(state, registry, rules, "after P1 layoff H9")

	var pub := state.to_public(0, true)
	_eq(pub["melds"].size(), 1, "one public meld exists")

	var pmeld: Dictionary = pub["melds"][0]
	_eq(int(pmeld["id"]), meld_id, "public meld id matches event meld id")
	_eq(String(pmeld["type"]), ActionProcessor.MELD_RUN, "public meld is RUN")

	var pub_card_ids: Array = []
	var pub_played_by: Array = []
	var pub_logical_indexes: Array = []

	for entry_any in pmeld["cards"]:
		var entry: Dictionary = entry_any
		pub_card_ids.append(String(entry["card_id"]))
		pub_played_by.append(int(entry["played_by"]))
		pub_logical_indexes.append(int(entry["logical_index"]))

	_eq(pub_card_ids, [h5, h6, h7, h8, h9], "public run cards are in logical order")
	_eq(pub_played_by, [1, 1, 1, 0, 1], "public run keeps per-card played_by")
	_eq(pub_logical_indexes, [0, 1, 2, 3, 4], "public run logical indexes are correct")

	var link_strings := _links_to_strings(pmeld["links"])
	_eq(link_strings, [
		"%s->%s" % [h5, h6],
		"%s->%s" % [h6, h7],
		"%s->%s" % [h7, h8],
		"%s->%s" % [h8, h9]
	], "public run links connect adjacent logical cards")


func test_discard_stack_must_play_clears_on_meld() -> void:
	print("\n--- test_discard_stack_must_play_clears_on_meld ---")

	var registry := CardRegistry.new()
	var rules := RulesConfig.new()
	var ap := ActionProcessor.new(
		registry,
		ActionProcessor.StockEmptyPolicy.RESHUFFLE_EXCEPT_TOP,
		123456,
		rules
	)

	var shoe := DeckBuilder.build_shoe(1, registry)
	var state := GameState.new()
	state.init_for_players(2)

	var h5 := _find_card_id(shoe, registry, "H", 5, 0)
	var h6 := _find_card_id(shoe, registry, "H", 6, 0)
	var h7 := _find_card_id(shoe, registry, "H", 7, 0)
	var c2 := _find_card_id(shoe, registry, "C", 2, 0)
	var d2 := _find_card_id(shoe, registry, "D", 2, 0)

	_ok(h5 != "", "found H5 for must-play test")
	_ok(h6 != "", "found H6 for must-play test")
	_ok(h7 != "", "found H7 for must-play test")
	_ok(c2 != "", "found C2 for must-play test")
	_ok(d2 != "", "found D2 for must-play test")

	state.hands[0] = [h5, h6, c2]
	state.hands[1] = [d2]
	state.stock = []
	state.discard = [h7]
	state.turn_player = 0
	state.phase = ActionProcessor.PHASE_DRAW

	_check_invariants(state, registry, rules, "must-play initial state")

	# Draw discard stack with target H7
	var r1 = ap.apply(state, 0, {
		"type": ActionProcessor.TYPE_DRAW_DISCARD_STACK,
		"target_card_id": h7
	})
	_ok(r1["ok"], "P0 drew discard stack with H7 as target")
	_eq(bool(state.must_play_discard_pending[0]), true, "must-play pending became true")
	_eq(String(state.must_play_discard_target[0]), h7, "must-play target is H7")
	_eq(state.phase, ActionProcessor.PHASE_PLAY, "phase moved to PLAY after discard-stack draw")
	_check_invariants(state, registry, rules, "after discard-stack draw")

	var pub1 := state.to_public(0, false)
	_eq(bool(pub1["must_play"]["pending"]), true, "public must_play pending is true")
	_eq(String(pub1["must_play"]["target_card_id"]), h7, "public must_play target matches H7")

	# Should not be able to discard while must-play is pending
	var r2 = ap.apply(state, 0, {
		"type": ActionProcessor.TYPE_DISCARD,
		"card_id": c2
	})
	_ok(not r2["ok"], "discard rejected while must-play is pending")
	_eq(String(r2["reason"]), "MUST_PLAY_PENDING_CANNOT_DISCARD", "discard reject reason is correct")

	# Use H7 in a new meld 5-6-7
	var r3 = ap.apply(state, 0, {
		"type": ActionProcessor.TYPE_CREATE_MELD,
		"meld_kind": ActionProcessor.MELD_RUN,
		"card_ids": [h5, h6, h7]
	})
	_ok(r3["ok"], "P0 created run 5-6-7 using must-play target")
	_eq(bool(state.must_play_discard_pending[0]), false, "must-play pending cleared after meld")
	_eq(String(state.must_play_discard_target[0]), "", "must-play target cleared after meld")
	_check_invariants(state, registry, rules, "after must-play meld creation")

	var pub2 := state.to_public(0, false)
	_eq(bool(pub2["must_play"]["pending"]), false, "public must_play pending cleared")

	# Now discard should work again
	var r4 = ap.apply(state, 0, {
		"type": ActionProcessor.TYPE_DISCARD,
		"card_id": c2
	})
	_ok(r4["ok"], "discard works again after must-play was satisfied")
	_eq(state.turn_player, 1, "turn advanced to P1 after discard")
	_eq(state.phase, ActionProcessor.PHASE_DRAW, "phase returned to DRAW after discard")
	_check_invariants(state, registry, rules, "after final discard")

	var pub3 := state.to_public(0, true)
	_eq(pub3["melds"].size(), 1, "must-play test produced one meld")

	var pmeld: Dictionary = pub3["melds"][0]
	var pub_card_ids: Array = []
	var pub_played_by: Array = []
	for entry_any in pmeld["cards"]:
		var entry: Dictionary = entry_any
		pub_card_ids.append(String(entry["card_id"]))
		pub_played_by.append(int(entry["played_by"]))

	_eq(pub_card_ids, [h5, h6, h7], "must-play public run has correct order")
	_eq(pub_played_by, [0, 0, 0], "must-play public run stores played_by correctly")
	_eq(_links_to_strings(pmeld["links"]), [
		"%s->%s" % [h5, h6],
		"%s->%s" % [h6, h7]
	], "must-play public links are correct")


func _find_card_id(shoe: Array, registry: CardRegistry, suit: String, rank: int, deck: int = 0) -> String:
	for cid_any in shoe:
		var cid := String(cid_any)
		var c := registry.get_card(cid)
		if c.is_empty():
			continue
		if String(c["suit"]) == suit and int(c["rank"]) == rank and int(c["deck"]) == deck:
			return cid
	return ""


func _links_to_strings(links: Array) -> Array:
	var out: Array = []
	for link_any in links:
		var link: Array = link_any
		if link.size() == 2:
			out.append("%s->%s" % [String(link[0]), String(link[1])])
	return out


func _check_invariants(state: GameState, registry: CardRegistry, rules: RulesConfig, label: String) -> void:
	var inv: Dictionary = RummyInvariants.validate(state, registry, rules)
	if bool(inv["ok"]):
		print("OK:%s invariants valid" % label)
	else:
		_fail("%s invariants invalid: %s" % [label, str(inv["errors"])])


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("OK:%s" % msg)
	else:
		_fail(msg)


func _eq(actual, expected, msg: String) -> void:
	if actual == expected:
		print("OK:%s (got=%s expected=%s)" % [msg, str(actual), str(expected)])
	else:
		_fail("%s (got=%s expected=%s)" % [msg, str(actual), str(expected)])


func _fail(msg: String) -> void:
	_fails += 1
	print("FAIL:%s" % msg)

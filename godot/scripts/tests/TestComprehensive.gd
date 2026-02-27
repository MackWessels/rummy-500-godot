extends Node
class_name TestComprehensive

var fails = 0

func _ready() -> void:
	print("TestComprehensive _ready() fired")

	test_wrap_run_allowed_k_a_2()
	test_set_duplicate_suit_toggle_create_meld()
	test_set_duplicate_suit_toggle_layoff()
	test_ace_scoring_in_runs_low_vs_high()
	test_must_play_discard_target_layoff_then_go_out_and_score()

	print("Done. fails=%s" % fails)


# -------------------------
# Assertions / helpers
# -------------------------

func _expect(cond: bool, ok_msg: String, fail_msg: String) -> void:
	if cond:
		print("OK:%s" % ok_msg)
	else:
		fails += 1
		push_warning("FAIL:%s" % fail_msg)

func _has_prop(obj: Object, prop: String) -> bool:
	for p in obj.get_property_list():
		if String(p.name) == prop:
			return true
	return false

func _set_if_has(obj: Object, prop: String, value) -> void:
	if obj != null and _has_prop(obj, prop):
		obj.set(prop, value)

func _setup_registry(decks: int) -> Dictionary:
	var registry = CardRegistry.new()
	var shoe: Array = DeckBuilder.build_shoe(decks, registry) # deterministic order, no shuffle
	return {"registry": registry, "shoe": shoe}

func _pick_card_id(registry: CardRegistry, shoe: Array, suit: String, rank: int, deck: int = -1) -> String:
	for cid_any in shoe:
		var cid = String(cid_any)
		var c = registry.get_card(cid)
		if c.is_empty():
			continue
		if String(c.get("suit", "")) != suit:
			continue
		if int(c.get("rank", -1)) != rank:
			continue
		if deck != -1 and int(c.get("deck", -1)) != deck:
			continue
		return cid
	return "" # not found

func _make_rules(allow_dup_suits_in_set: bool) -> RulesConfig:
	var rules := RulesConfig.new()
	_set_if_has(rules, "allow_wrap_runs", true)
	_set_if_has(rules, "allow_duplicate_suits_in_set", allow_dup_suits_in_set)
	_set_if_has(rules, "ace_run_high_requires_qk", true)
	_set_if_has(rules, "ace_low_points", 1)
	_set_if_has(rules, "ace_high_points", 15)
	return rules

func _make_ap(registry: CardRegistry, rules: RulesConfig) -> ActionProcessor:
	# Use the current 3-arg init so this compiles even before you add the 4th arg.
	var ap := ActionProcessor.new(registry, ActionProcessor.StockEmptyPolicy.RESHUFFLE_EXCEPT_TOP, 1234)

	# If you added `var rules: RulesConfig` to ActionProcessor, set it here.
	if _has_prop(ap, "rules"):
		ap.rules = rules
	return ap

func _make_state(num_players: int) -> GameState:
	var state := GameState.new()
	state.init_for_players(num_players)
	state.turn_player = 0
	state.phase = ActionProcessor.PHASE_DRAW
	state.hand_over = false
	state.hand_scored = false
	state.hand_end_reason = ""
	state.went_out_player = -1
	state.melds = []
	state.stock = []
	state.discard = []
	return state


# -------------------------
# Tests
# -------------------------

func test_wrap_run_allowed_k_a_2() -> void:
	var ctx := _setup_registry(1)
	var registry: CardRegistry = ctx["registry"]
	var shoe: Array = ctx["shoe"]

	var ck := _pick_card_id(registry, shoe, "C", 13, 0) # K♣
	var ca := _pick_card_id(registry, shoe, "C", 1, 0)  # A♣
	var c2 := _pick_card_id(registry, shoe, "C", 2, 0)  # 2♣

	_expect(ck != "" and ca != "" and c2 != "", "found cards for K-A-2 run", "missing cards for K-A-2 run")

	var rules := _make_rules(true)
	var ap := _make_ap(registry, rules)
	var state := _make_state(2)

	state.phase = ActionProcessor.PHASE_PLAY
	state.hands[0] = [ck, ca, c2]

	var res := ap.apply(state, 0, {
		"type": ActionProcessor.TYPE_CREATE_MELD,
		"meld_kind": ActionProcessor.MELD_RUN,
		"card_ids": [ck, ca, c2]
	})

	_expect(bool(res.ok), "wrap run K-A-2 accepted", "wrap run K-A-2 rejected: %s" % String(res.reason))
	_expect(state.melds.size() == 1, "meld added for K-A-2", "expected 1 meld, got %s" % state.melds.size())


func test_set_duplicate_suit_toggle_create_meld() -> void:
	var ctx := _setup_registry(2)
	var registry: CardRegistry = ctx["registry"]
	var shoe: Array = ctx["shoe"]

	var s7_d0 := _pick_card_id(registry, shoe, "S", 7, 0)
	var s7_d1 := _pick_card_id(registry, shoe, "S", 7, 1)
	var h7_d0 := _pick_card_id(registry, shoe, "H", 7, 0)

	_expect(s7_d0 != "" and s7_d1 != "" and h7_d0 != "", "found 2x S7 + H7", "missing duplicate suit cards for set test")

	# Disallow duplicates -> should reject
	var rules_no_dup := _make_rules(false)
	var ap_no_dup := _make_ap(registry, rules_no_dup)
	var state1 := _make_state(2)
	state1.phase = ActionProcessor.PHASE_PLAY
	state1.hands[0] = [s7_d0, s7_d1, h7_d0]

	var res1 := ap_no_dup.apply(state1, 0, {
		"type": ActionProcessor.TYPE_CREATE_MELD,
		"meld_kind": ActionProcessor.MELD_SET,
		"card_ids": [s7_d0, s7_d1, h7_d0]
	})

	_expect(not bool(res1.ok), "set w/ duplicate suit rejected when toggle OFF", "set w/ duplicate suit was allowed when toggle OFF")
	_expect(String(res1.reason) == "SET_DUPLICATE_SUIT_NOT_ALLOWED",
		"reject reason correct (SET_DUPLICATE_SUIT_NOT_ALLOWED)",
		"unexpected reject reason: %s" % String(res1.reason))

	# Allow duplicates -> should accept
	var rules_allow_dup := _make_rules(true)
	var ap_allow_dup := _make_ap(registry, rules_allow_dup)
	var state2 := _make_state(2)
	state2.phase = ActionProcessor.PHASE_PLAY
	state2.hands[0] = [s7_d0, s7_d1, h7_d0]

	var res2 := ap_allow_dup.apply(state2, 0, {
		"type": ActionProcessor.TYPE_CREATE_MELD,
		"meld_kind": ActionProcessor.MELD_SET,
		"card_ids": [s7_d0, s7_d1, h7_d0]
	})

	_expect(bool(res2.ok), "set w/ duplicate suit accepted when toggle ON", "set w/ duplicate suit rejected when toggle ON: %s" % String(res2.reason))


func test_set_duplicate_suit_toggle_layoff() -> void:
	var ctx := _setup_registry(2)
	var registry: CardRegistry = ctx["registry"]
	var shoe: Array = ctx["shoe"]

	var s7_d0 := _pick_card_id(registry, shoe, "S", 7, 0)
	var s7_d1 := _pick_card_id(registry, shoe, "S", 7, 1)
	var h7_d0 := _pick_card_id(registry, shoe, "H", 7, 0)
	var d7_d0 := _pick_card_id(registry, shoe, "D", 7, 0)

	_expect(s7_d0 != "" and s7_d1 != "" and h7_d0 != "" and d7_d0 != "",
		"found cards for layoff duplicate suit test",
		"missing cards for layoff duplicate suit test")

	# Base meld: SET rank 7 contains S7(d0), H7(d0), D7(d0)
	var base_meld := {
		"id": 0,
		"type": ActionProcessor.MELD_SET,
		"rank": 7,
		"cards": [s7_d0, h7_d0, d7_d0],
		"owner": 0,
		"contrib": {
			s7_d0: 0,
			h7_d0: 0,
			d7_d0: 0
		}
	}

	# Disallow duplicates -> laying off S7(d1) should fail
	var rules_no_dup := _make_rules(false)
	var ap_no_dup := _make_ap(registry, rules_no_dup)
	var state1 := _make_state(2)
	state1.phase = ActionProcessor.PHASE_PLAY
	state1.melds = [base_meld.duplicate(true)]
	state1.hands[0] = [s7_d1]

	var res1 := ap_no_dup.apply(state1, 0, {
		"type": ActionProcessor.TYPE_LAYOFF,
		"meld_id": 0,
		"card_id": s7_d1
	})

	_expect(not bool(res1.ok), "layoff duplicate suit rejected when toggle OFF", "layoff duplicate suit was allowed when toggle OFF")
	_expect(String(res1.reason) == "SET_DUPLICATE_SUIT_NOT_ALLOWED",
		"layoff reject reason correct",
		"unexpected layoff reject reason: %s" % String(res1.reason))

	# Allow duplicates -> laying off S7(d1) should succeed
	var rules_allow_dup := _make_rules(true)
	var ap_allow_dup := _make_ap(registry, rules_allow_dup)
	var state2 := _make_state(2)
	state2.phase = ActionProcessor.PHASE_PLAY
	state2.melds = [base_meld.duplicate(true)]
	state2.hands[0] = [s7_d1]

	var res2 := ap_allow_dup.apply(state2, 0, {
		"type": ActionProcessor.TYPE_LAYOFF,
		"meld_id": 0,
		"card_id": s7_d1
	})

	_expect(bool(res2.ok), "layoff duplicate suit accepted when toggle ON", "layoff duplicate suit rejected when toggle ON: %s" % String(res2.reason))


func test_ace_scoring_in_runs_low_vs_high() -> void:
	var ctx := _setup_registry(1)
	var registry: CardRegistry = ctx["registry"]
	var shoe: Array = ctx["shoe"]

	var ca := _pick_card_id(registry, shoe, "C", 1, 0)
	var c2 := _pick_card_id(registry, shoe, "C", 2, 0)
	var c3 := _pick_card_id(registry, shoe, "C", 3, 0)

	var cq := _pick_card_id(registry, shoe, "C", 12, 0) # Q
	var ck := _pick_card_id(registry, shoe, "C", 13, 0) # K

	_expect(ca != "" and c2 != "" and c3 != "" and cq != "" and ck != "",
		"found cards for ace scoring tests",
		"missing cards for ace scoring tests")

	var rules := _make_rules(true) # dup suits irrelevant here
	_set_if_has(rules, "ace_run_high_requires_qk", true)
	_set_if_has(rules, "ace_low_points", 1)
	_set_if_has(rules, "ace_high_points", 15)

	# A-2-3 (Ace should be LOW on table => 1+2+3=6)
	var s1 := _make_state(1)
	s1.melds = [{
		"id": 0,
		"type": "RUN",
		"cards": [ca, c2, c3],
		"owner": 0,
		"contrib": {ca: 0, c2: 0, c3: 0},
		"suit": "C",
		"ace_mode": "LOW"
	}]
	s1.hands[0] = []

	HandResolver.resolve_hand(s1, registry, rules)
	_expect(int(s1.hand_points_table[0]) == 6, "A-2-3 table points = 6 (Ace low)", "A-2-3 table points wrong: %s" % str(s1.hand_points_table))

	# Q-K-A (Ace should be HIGH on table => 10+10+15=35)
	var s2 := _make_state(1)
	s2.melds = [{
		"id": 0,
		"type": "RUN",
		"cards": [cq, ck, ca],
		"owner": 0,
		"contrib": {cq: 0, ck: 0, ca: 0},
		"suit": "C",
		"ace_mode": "HIGH"
	}]
	s2.hands[0] = []

	HandResolver.resolve_hand(s2, registry, rules)
	_expect(int(s2.hand_points_table[0]) == 35, "Q-K-A table points = 35 (Ace high)", "Q-K-A table points wrong: %s" % str(s2.hand_points_table))


func test_must_play_discard_target_layoff_then_go_out_and_score() -> void:
	var ctx := _setup_registry(1)
	var registry: CardRegistry = ctx["registry"]
	var shoe: Array = ctx["shoe"]

	# Cards we need
	var c2 := _pick_card_id(registry, shoe, "C", 2, 0)
	var d3 := _pick_card_id(registry, shoe, "D", 3, 0)

	var c7 := _pick_card_id(registry, shoe, "C", 7, 0)
	var h7 := _pick_card_id(registry, shoe, "H", 7, 0)
	var d7 := _pick_card_id(registry, shoe, "D", 7, 0)
	var s7 := _pick_card_id(registry, shoe, "S", 7, 0)

	_expect(c2 != "" and d3 != "" and c7 != "" and h7 != "" and d7 != "" and s7 != "",
		"found cards for must-play + go-out test",
		"missing cards for must-play + go-out test")

	# Rules: disallow duplicate suits (not required here, but ensures layoff gate is rule-aware)
	var rules := _make_rules(false)
	var ap := _make_ap(registry, rules)

	var state := _make_state(2)
	state.turn_player = 0
	state.phase = ActionProcessor.PHASE_DRAW

	# P0 starts with one filler card (will discard it to go out)
	state.hands[0] = [c2]
	state.hands[1] = [d3]

	# Discard pile has only the target (so taken stack == [s7])
	state.discard = [s7]

	# Table already has a SET of 7s owned by P1 (so P0 can layoff s7 and earn contrib credit)
	state.melds = [{
		"id": 0,
		"type": ActionProcessor.MELD_SET,
		"rank": 7,
		"cards": [c7, h7, d7],
		"owner": 1,
		"contrib": {c7: 1, h7: 1, d7: 1}
	}]

	# 1) Draw discard stack (must-play should become pending)
	var r1 := ap.apply(state, 0, {"type": ActionProcessor.TYPE_DRAW_DISCARD_STACK, "target_card_id": s7})
	_expect(bool(r1.ok), "draw discard stack ok", "draw discard stack failed: %s" % String(r1.reason))
	_expect(bool(state.must_play_discard_pending[0]), "must-play pending set", "must-play pending not set")
	_expect(String(state.must_play_discard_target[0]) == s7, "must-play target set", "must-play target not set")
	_expect(state.phase == ActionProcessor.PHASE_PLAY, "phase moved to PLAY", "phase not PLAY after draw discard")

	# 2) Attempt to discard before playing target -> should fail
	var r2 := ap.apply(state, 0, {"type": ActionProcessor.TYPE_DISCARD, "card_id": c2})
	_expect(not bool(r2.ok), "discard blocked by must-play", "discard was allowed while must-play pending")
	_expect(String(r2.reason) == "MUST_PLAY_DISCARD_TARGET_BEFORE_DISCARD",
		"discard block reason correct",
		"unexpected discard block reason: %s" % String(r2.reason))

	# 3) Layoff target onto set -> should clear must-play
	var r3 := ap.apply(state, 0, {"type": ActionProcessor.TYPE_LAYOFF, "meld_id": 0, "card_id": s7})
	_expect(bool(r3.ok), "layoff target ok", "layoff target failed: %s" % String(r3.reason))
	_expect(not bool(state.must_play_discard_pending[0]), "must-play cleared by layoff", "must-play not cleared by layoff")

	# 4) Discard last card -> goes out -> hand ends -> scoring computed
	var r4 := ap.apply(state, 0, {"type": ActionProcessor.TYPE_DISCARD, "card_id": c2})
	_expect(bool(r4.ok), "final discard ok", "final discard failed: %s" % String(r4.reason))
	_expect(bool(r4.hand_ended), "hand ended on discard last card", "hand did not end when expected")
	_expect(bool(r4.went_out), "went_out flagged", "went_out not flagged")
	_expect(state.hand_over, "state.hand_over true", "state.hand_over not true")
	_expect(String(state.hand_end_reason) == "WENT_OUT", "end reason WENT_OUT", "end reason wrong: %s" % String(state.hand_end_reason))
	_expect(int(state.went_out_player) == 0, "went_out_player=0", "went_out_player wrong: %s" % str(state.went_out_player))
	_expect(state.hand_scored, "hand scored", "hand not scored")

	# Scoring expectations with your current scoring model:
	# - P1 owns C7/H7/D7 => 7+7+7=21 table points
	# - P0 contributed S7 via layoff => 7 table points
	# - P0 deadwood = 0 (discarded last)
	# - P1 deadwood = D3 => 3
	_expect(int(state.hand_points_table[0]) == 7, "p0 table points=7", "p0 table points wrong: %s" % str(state.hand_points_table))
	_expect(int(state.hand_points_deadwood[0]) == 0, "p0 deadwood=0", "p0 deadwood wrong: %s" % str(state.hand_points_deadwood))
	_expect(int(state.hand_points_net[0]) == 7, "p0 net=7", "p0 net wrong: %s" % str(state.hand_points_net))

	_expect(int(state.hand_points_table[1]) == 21, "p1 table points=21", "p1 table points wrong: %s" % str(state.hand_points_table))
	_expect(int(state.hand_points_deadwood[1]) == 3, "p1 deadwood=3", "p1 deadwood wrong: %s" % str(state.hand_points_deadwood))
	_expect(int(state.hand_points_net[1]) == 18, "p1 net=18", "p1 net wrong: %s" % str(state.hand_points_net))

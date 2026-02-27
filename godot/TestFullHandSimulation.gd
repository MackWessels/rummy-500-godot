extends Node
class_name TestFullHandSimulation

var fails := 0

func _ready() -> void:
	print("TestFullHandSimulation _ready() fired")
	_test_full_hand_deterministic()
	_test_matchstate_accum_optional()
	print("Done. fails=%s" % fails)

# -----------------------------
# Assertions
# -----------------------------

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("OK:%s" % msg)
	else:
		fails += 1
		push_error("FAIL:%s" % msg)

func _eq(a, b, msg: String) -> void:
	_ok(a == b, "%s (got=%s expected=%s)" % [msg, str(a), str(b)])

# -----------------------------
# Helpers
# -----------------------------

func _pick(reg: CardRegistry, deck: int, suit: String, rank: int) -> String:
	for cid_any in reg.cards_by_id.keys():
		var cid := String(cid_any)
		var c: Dictionary = reg.cards_by_id[cid]
		if int(c.get("deck", -999)) == deck and String(c.get("suit", "")) == suit and int(c.get("rank", -999)) == rank:
			return cid
	return ""

func _apply(ap: ActionProcessor, st: GameState, p: int, action: Dictionary, expect_ok: bool, label: String) -> Dictionary:
	var res: Dictionary = ap.apply(st, p, action)
	_eq(bool(res.get("ok", false)), expect_ok, label)
	if not expect_ok:
		_ok(String(res.get("reason","")) != "", label + " has reason")
	return res

# -----------------------------
# Deterministic full-hand sim
# -----------------------------

func _test_full_hand_deterministic() -> void:
	print("\n--- test_full_hand_deterministic ---")

	var reg := CardRegistry.new()
	DeckBuilder.build_shoe(1, reg) # do NOT shuffle

	# Cards we will use
	var s7  := _pick(reg, 0, "S", 7)
	var d7  := _pick(reg, 0, "D", 7)
	var h7  := _pick(reg, 0, "H", 7)

	var jd  := _pick(reg, 0, "D", 11) # Jack of Diamonds
	var c8  := _pick(reg, 0, "C", 8)

	var qh  := _pick(reg, 0, "H", 12)
	var kh  := _pick(reg, 0, "H", 13)
	var ah  := _pick(reg, 0, "H", 1)

	var aS  := _pick(reg, 0, "S", 1)
	var s2  := _pick(reg, 0, "S", 2)
	var s3  := _pick(reg, 0, "S", 3)
	var s4  := _pick(reg, 0, "S", 4)

	var d9  := _pick(reg, 0, "D", 9)
	var c5  := _pick(reg, 0, "C", 5)

	var d6  := _pick(reg, 0, "D", 6)
	var c2  := _pick(reg, 0, "C", 2)
	var h9  := _pick(reg, 0, "H", 9)

	var c9  := _pick(reg, 0, "C", 9)

	_ok(s7 != "" and d7 != "" and h7 != "", "picked 7s")
	_ok(jd != "" and c8 != "", "picked discard cards")
	_ok(qh != "" and kh != "" and ah != "", "picked Q/K/A hearts")
	_ok(aS != "" and s2 != "" and s3 != "" and s4 != "", "picked spade run cards")
	_ok(d9 != "" and c5 != "", "picked P1 deadwood cards")
	_ok(d6 != "" and c2 != "" and h9 != "", "picked stock cards")
	_ok(c9 != "", "picked P0 last discard")

	# Rules
	var rules := RulesConfig.new()
	rules.allow_duplicate_suits_in_set = true
	rules.ace_run_high_requires_qk = true
	rules.ace_low_points = 1
	rules.ace_high_points = 15

	var ap := ActionProcessor.new(reg, ActionProcessor.StockEmptyPolicy.RESHUFFLE_EXCEPT_TOP, 12345, rules)

	# State (small hands on purpose)
	var st := GameState.new()
	st.init_for_players(2)
	st.turn_player = 0
	st.phase = "DRAW"

	# Hands
	st.hands[0] = [s7, d7, qh, kh, s4, c9]  # P0
	st.hands[1] = [aS, s2, s3, d9, c5]      # P1

	# Discard: bottom -> top (top is back)
	st.discard = [c8, h7, jd]

	# Stock: draw order is pop_back()
	# P1 draws d6 first, then P0 draws ah
	st.stock = [c2, h9, ah, d6]

	_eq(st.phase, "DRAW", "phase starts DRAW")
	_eq(st.turn_player, 0, "turn starts at player 0")

	# --- Turn 0 (P0): draw discard stack targeting H7 (takes H7 + JD) ---
	_apply(ap, st, 0, {"type":"DRAW_DISCARD_STACK", "target_card_id": h7}, true, "P0 DRAW_DISCARD_STACK target=H7")
	_eq(bool(st.must_play_discard_pending[0]), true, "must_play pending set")
	_eq(String(st.must_play_discard_target[0]), h7, "must_play target set")
	_eq(st.discard.size(), 1, "discard resized to leave bottom only")
	_eq(String(st.discard[0]), c8, "discard bottom remains")
	_eq(st.phase, "PLAY", "phase becomes PLAY after discard-stack draw")

	# Must-play enforcement: cannot discard yet
	_apply(ap, st, 0, {"type":"DISCARD", "card_id": jd}, false, "P0 DISCARD blocked while must-play pending")
	_eq(st.turn_player, 0, "turn still P0 after rejected discard")
	_eq(st.phase, "PLAY", "phase still PLAY after rejected discard")

	# Create SET of 7s including target
	_apply(ap, st, 0, {"type":"CREATE_MELD", "meld_kind":"SET", "card_ids":[s7, d7, h7]}, true, "P0 CREATE_MELD SET 7s (includes target)")
	_eq(st.melds.size(), 1, "table has 1 meld (set)")
	_eq(bool(st.must_play_discard_pending[0]), false, "must_play cleared after melding target")

	# Discard JD to end turn
	_apply(ap, st, 0, {"type":"DISCARD", "card_id": jd}, true, "P0 DISCARD JD ends turn")
	_eq(st.turn_player, 1, "turn passes to P1")
	_eq(st.phase, "DRAW", "phase resets to DRAW for next player")

	# --- Turn 1 (P1): draw stock, create A-2-3 spade run, discard 9D ---
	_apply(ap, st, 1, {"type":"DRAW_STOCK"}, true, "P1 DRAW_STOCK")
	# should have drawn D6
	_ok(st.hands[1].has(d6), "P1 has drawn D6")

	_apply(ap, st, 1, {"type":"CREATE_MELD", "meld_kind":"RUN", "card_ids":[aS, s2, s3]}, true, "P1 CREATE_MELD RUN A-2-3 spades")
	_eq(st.melds.size(), 2, "table has 2 melds (set + run)")

	_apply(ap, st, 1, {"type":"DISCARD", "card_id": d9}, true, "P1 DISCARD 9D ends turn")
	_eq(st.turn_player, 0, "turn returns to P0")
	_eq(st.phase, "DRAW", "phase is DRAW for P0")

	# --- Turn 2 (P0): draw stock (AH), layoff 4S onto P1 run, create Q-K-A hearts, discard last card to go out ---
	_apply(ap, st, 0, {"type":"DRAW_STOCK"}, true, "P0 DRAW_STOCK")
	_ok(st.hands[0].has(ah), "P0 has drawn AH")

	# Layoff 4S onto meld_id=1 (the run). In this test, meld ids are 0=set, 1=run, 2=next.
	_apply(ap, st, 0, {"type":"LAYOFF", "meld_id": 1, "card_id": s4, "end":"RIGHT"}, true, "P0 LAYOFF 4S onto spade run (RIGHT)")

	_apply(ap, st, 0, {"type":"CREATE_MELD", "meld_kind":"RUN", "card_ids":[qh, kh, ah]}, true, "P0 CREATE_MELD RUN Q-K-A hearts (Ace high)")

	# Discard last card (C9) to go out
	var res_out := _apply(ap, st, 0, {"type":"DISCARD", "card_id": c9}, true, "P0 DISCARD last card -> WENT_OUT")
	_eq(bool(res_out.get("hand_ended", false)), true, "action reports hand_ended")
	_eq(bool(res_out.get("went_out", false)), true, "action reports went_out")

	_eq(st.hand_over, true, "state.hand_over true")
	_eq(st.hand_end_reason, "WENT_OUT", "hand_end_reason WENT_OUT")
	_eq(st.went_out_player, 0, "went_out_player is P0")
	_eq(st.hand_scored, true, "hand_scored true")

	# Expected scoring:
	# P0 table: set 7s (21) + Q-K-A hearts (35) + layoff 4S (4) = 60 ; deadwood 0 => net 60
	# P1 table: A-2-3 (Ace low 1) => 1+2+3 = 6 ; deadwood left: 5C+6D=11 => net -5
	_eq(st.hand_points_table[0], 60, "P0 table points")
	_eq(st.hand_points_deadwood[0], 0, "P0 deadwood")
	_eq(st.hand_points_net[0], 60, "P0 net points")

	_eq(st.hand_points_table[1], 6, "P1 table points")
	_eq(st.hand_points_deadwood[1], 11, "P1 deadwood points")
	_eq(st.hand_points_net[1], -5, "P1 net points")

# -----------------------------
# Optional: MatchState accumulation sanity
# -----------------------------

func _test_matchstate_accum_optional() -> void:
	print("\n--- test_matchstate_accum_optional ---")

	# Fake “we just finished a hand”
	var ms := MatchState.new(2, 500, 0)

	var ended := GameState.new()
	ended.init_for_players(2)
	ended.hand_over = true
	ended.hand_scored = true
	ended.hand_points_net = [60, -5]

	var fin1 := ms.finalize_hand(ended)
	_eq(bool(fin1.get("ok", false)), true, "finalize_hand 1 ok")
	_eq(ms.total_scores[0], 60, "totals after hand1 p0")
	_eq(ms.total_scores[1], -5, "totals after hand1 p1")
	_eq(ms.winner, -1, "no winner yet")
	_eq(ms.dealer, 1, "dealer rotated to 1")
	_eq(ms.starting_player, 0, "starting player is left of dealer")

	# Second “ended hand” pushes P0 over 500
	var ended2 := GameState.new()
	ended2.init_for_players(2)
	ended2.hand_over = true
	ended2.hand_scored = true
	ended2.hand_points_net = [520, -20]

	var fin2 := ms.finalize_hand(ended2)
	_eq(bool(fin2.get("ok", false)), true, "finalize_hand 2 ok")
	_eq(ms.total_scores[0], 580, "totals after hand2 p0")
	_eq(ms.total_scores[1], -25, "totals after hand2 p1")
	_eq(ms.winner, 0, "winner is p0 (>=500)")

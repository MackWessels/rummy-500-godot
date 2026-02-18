extends Node

const SUIT_INDEX := {"S": 0, "H": 1, "D": 2, "C": 3}

func _ready() -> void:
	seed(123456)

	print("TestMeldRules _ready() fired")
	_run_all_tests()

	await get_tree().create_timer(0.2).timeout
	get_tree().quit()


func _assert_true(cond: bool, label: String) -> void:
	if not cond:
		print("FAIL:", label)
		push_error("ASSERT FAIL: " + label)
	else:
		print("OK:", label)

func _assert_eq(a, b, label: String) -> void:
	if a != b:
		print("FAIL:", label, " (got=", a, " expected=", b, ")")
		push_error("ASSERT FAIL: %s (got=%s expected=%s)" % [label, str(a), str(b)])
	else:
		print("OK:", label)

func _cid(deck: int, suit: String, rank: int) -> String:
	# Must match DeckBuilder.build_shoe() id format exactly.
	# serial = deck*52 + suit_index*13 + rank
	if not SUIT_INDEX.has(suit):
		push_error("Unknown suit for _cid: " + suit)
		return ""
	var serial := deck * 52 + int(SUIT_INDEX[suit]) * 13 + rank
	return "D%s-%s%s-%04d" % [deck, suit, str(rank), serial]

func _ranks_of(card_ids: Array, registry: CardRegistry) -> Array:
	var out: Array = []
	for cid in card_ids:
		out.append(int(registry.get_card(String(cid))["rank"]))
	return out

func _make_run_meld_from_build(res: Dictionary) -> Dictionary:
	return {
		"type": MeldRules.TYPE_RUN,
		"suit": String(res["suit"]),
		"ace_mode": String(res["ace_mode"]),
		"cards": res["ordered_card_ids"]
	}


func _run_all_tests() -> void:
	_test_sets()
	_test_runs_build()
	_test_runs_extend()


# -------------------------
# Tests
# -------------------------

func _test_sets() -> void:
	print("\n--- test_sets ---")

	var registry := CardRegistry.new()
	DeckBuilder.build_shoe(2, registry) # 2 decks to allow duplicates for sets

	# Valid 3-card set (7s)
	var s7 := _cid(0, "S", 7)
	var d7 := _cid(0, "D", 7)
	var h7 := _cid(0, "H", 7)
	_assert_true(MeldRules.is_valid_set([s7, d7, h7], registry), "valid set: 7-7-7")

	# Invalid set (mixed rank)
	var s8 := _cid(0, "S", 8)
	_assert_true(not MeldRules.is_valid_set([s7, d7, s8], registry), "invalid set: mixed ranks")

	# Big set possible with 2 decks (duplicates are distinct cards)
	var c5a := _cid(0, "C", 5)
	var c5b := _cid(1, "C", 5)
	var h5a := _cid(0, "H", 5)
	var h5b := _cid(1, "H", 5)
	var d5a := _cid(0, "D", 5)
	var s5a := _cid(0, "S", 5)
	_assert_true(MeldRules.is_valid_set([c5a, c5b, h5a, h5b, d5a, s5a], registry), "valid big set: 6x rank 5 (2 decks)")


func _test_runs_build() -> void:
	print("\n--- test_runs_build ---")

	var registry := CardRegistry.new()
	DeckBuilder.build_shoe(2, registry)

	# 4-5-6 hearts => ok, no Ace => UNSET
	var h4 := _cid(0, "H", 4)
	var h5 := _cid(0, "H", 5)
	var h6 := _cid(0, "H", 6)

	var res := MeldRules.build_run_meld([h4, h5, h6], registry)
	_assert_true(bool(res.get("ok", false)), "run build ok: 4-5-6 hearts")
	_assert_eq(String(res.get("ace_mode", "")), MeldRules.ACE_UNSET, "ace_mode UNSET when no Ace")
	_assert_eq(_ranks_of(res["ordered_card_ids"], registry), [4, 5, 6], "stored order = 4,5,6")

	# Q-K-A hearts => ok => HIGH
	var hq := _cid(0, "H", 12)
	var hk := _cid(0, "H", 13)
	var ha := _cid(0, "H", 1)

	res = MeldRules.build_run_meld([hq, hk, ha], registry)
	_assert_true(bool(res.get("ok", false)), "run build ok: Q-K-A hearts")
	_assert_eq(String(res.get("ace_mode", "")), MeldRules.ACE_HIGH, "ace_mode HIGH for Q-K-A")
	_assert_eq(_ranks_of(res["ordered_card_ids"], registry), [12, 13, 1], "stored order = Q,K,A")

	# K-A-2 hearts => ok => LOW
	var h2 := _cid(0, "H", 2)
	res = MeldRules.build_run_meld([hk, ha, h2], registry)
	_assert_true(bool(res.get("ok", false)), "run build ok: K-A-2 hearts (wrap)")
	_assert_eq(String(res.get("ace_mode", "")), MeldRules.ACE_LOW, "ace_mode LOW for K-A-2")
	_assert_eq(_ranks_of(res["ordered_card_ids"], registry), [13, 1, 2], "stored order = K,A,2")

	# Duplicate rank in a run (same suit) must fail (two 5s hearts)
	var h5a := _cid(0, "H", 5)
	var h5b := _cid(1, "H", 5)
	res = MeldRules.build_run_meld([h5a, h5b, h6], registry)
	_assert_true(not bool(res.get("ok", false)), "run build fails: duplicate rank in same suit")

	# Mixed suits must fail
	var s4 := _cid(0, "S", 4)
	res = MeldRules.build_run_meld([h4, h5, s4], registry)
	_assert_true(not bool(res.get("ok", false)), "run build fails: mixed suits")

	# Not consecutive must fail
	var h3 := _cid(0, "H", 3)
	res = MeldRules.build_run_meld([h3, h5, h6], registry)
	_assert_true(not bool(res.get("ok", false)), "run build fails: non-consecutive ranks")


func _test_runs_extend() -> void:
	print("\n--- test_runs_extend ---")

	var registry := CardRegistry.new()
	DeckBuilder.build_shoe(1, registry)

	# Start 2-3-4 hearts (ace_mode UNSET), add Ace LEFT => locks LOW, then wrap K, then add Q.
	var h2 := _cid(0, "H", 2)
	var h3 := _cid(0, "H", 3)
	var h4 := _cid(0, "H", 4)
	var ha := _cid(0, "H", 1)
	var hk := _cid(0, "H", 13)
	var hq := _cid(0, "H", 12)

	var res := MeldRules.build_run_meld([h2, h3, h4], registry)
	_assert_true(bool(res.get("ok", false)), "setup run ok: 2-3-4 hearts")
	_assert_eq(String(res.get("ace_mode", "")), MeldRules.ACE_UNSET, "setup ace_mode UNSET")

	var meld := _make_run_meld_from_build(res)

	var check := MeldRules.can_extend_run_end(meld, ha, "LEFT", registry)
	_assert_true(bool(check.get("ok", false)), "can extend LEFT with Ace onto 2-3-4")
	_assert_eq(String(check.get("new_ace_mode", "")), MeldRules.ACE_LOW, "Ace locks LOW when added to 2 end")
	meld["cards"].insert(0, ha)
	meld["ace_mode"] = String(check["new_ace_mode"])

	check = MeldRules.can_extend_run_end(meld, hk, "LEFT", registry)
	_assert_true(bool(check.get("ok", false)), "can wrap extend LEFT with K onto A-2-3-4")
	_assert_eq(String(check.get("new_ace_mode", "")), MeldRules.ACE_LOW, "ace_mode stays LOW after adding K")
	meld["cards"].insert(0, hk)
	meld["ace_mode"] = String(check["new_ace_mode"])

	check = MeldRules.can_extend_run_end(meld, hq, "LEFT", registry)
	_assert_true(bool(check.get("ok", false)), "can extend LEFT with Q onto K-A-2-3-4")
	_assert_eq(String(check.get("new_ace_mode", "")), MeldRules.ACE_LOW, "ace_mode remains LOW even though now includes Q-K-A")
	meld["cards"].insert(0, hq)
	meld["ace_mode"] = String(check["new_ace_mode"])

	_assert_eq(_ranks_of(meld["cards"], registry), [12, 13, 1, 2, 3, 4], "final LOW-history run = Q,K,A,2,3,4")

	# HIGH history: start J-Q-K, add Ace RIGHT => locks HIGH, then wrap to 2,3.
	var hj := _cid(0, "H", 11)
	res = MeldRules.build_run_meld([hj, hq, hk], registry)
	_assert_true(bool(res.get("ok", false)), "setup run ok: J-Q-K hearts")
	_assert_eq(String(res.get("ace_mode", "")), MeldRules.ACE_UNSET, "J-Q-K ace_mode UNSET before Ace")

	var meld2 := _make_run_meld_from_build(res)

	check = MeldRules.can_extend_run_end(meld2, ha, "RIGHT", registry)
	_assert_true(bool(check.get("ok", false)), "can extend RIGHT with Ace onto J-Q-K")
	_assert_eq(String(check.get("new_ace_mode", "")), MeldRules.ACE_HIGH, "Ace locks HIGH when added to K end")
	meld2["cards"].append(ha)
	meld2["ace_mode"] = String(check["new_ace_mode"])

	var h2b := _cid(0, "H", 2)
	var h3b := _cid(0, "H", 3)

	check = MeldRules.can_extend_run_end(meld2, h2b, "RIGHT", registry)
	_assert_true(bool(check.get("ok", false)), "Ace-HIGH run can wrap extend RIGHT with 2")
	_assert_eq(String(check.get("new_ace_mode", "")), MeldRules.ACE_HIGH, "ace_mode stays HIGH after adding 2")
	meld2["cards"].append(h2b)

	check = MeldRules.can_extend_run_end(meld2, h3b, "RIGHT", registry)
	_assert_true(bool(check.get("ok", false)), "Ace-HIGH run can extend RIGHT with 3")
	_assert_eq(String(check.get("new_ace_mode", "")), MeldRules.ACE_HIGH, "ace_mode stays HIGH after adding 3")
	meld2["cards"].append(h3b)

	_assert_eq(_ranks_of(meld2["cards"], registry), [11, 12, 13, 1, 2, 3], "final HIGH-history run = J,Q,K,A,2,3")

	# End-only rule: cannot insert in middle (try adding 5 to LEFT of 2-3-4)
	var h5 := _cid(0, "H", 5)
	var res3 := MeldRules.build_run_meld([h2, h3, h4], registry)
	var meld3 := _make_run_meld_from_build(res3)

	check = MeldRules.can_extend_run_end(meld3, h5, "LEFT", registry)
	_assert_true(not bool(check.get("ok", false)), "cannot add 5 to LEFT of 2-3-4 (wrong end extension)")

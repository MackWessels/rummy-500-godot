extends Node
class_name TestMatchEngineContract

const Invariants := preload("res://scripts/core/RummyInvariants.gd")

var fails := 0
var fail_msgs: Array[String] = []

func _ready() -> void:
	print("TestMatchEngineContract _ready() fired")

	_test_apply_contract_keys_and_version()
	_test_state_public_visibility_modes()
	_test_rules_propagate_through_matchengine_wrap_disabled()

	if fails > 0:
		print("\n--- FAILURES ---")
		for s in fail_msgs:
			print(s)

	print("Done. fails=%s" % fails)

# -----------------------------
# Assertions
# -----------------------------

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("OK:%s" % msg)
	else:
		fails += 1
		var s := "FAIL:%s" % msg
		fail_msgs.append(s)
		printerr(s)
		push_error(s)

func _eq(a, b, msg: String) -> void:
	_ok(a == b, "%s (got=%s expected=%s)" % [msg, str(a), str(b)])

func _has_key(d: Dictionary, k: String, msg: String) -> void:
	_ok(d.has(k), msg)

func _is_dict(v, msg: String) -> void:
	_ok(typeof(v) == TYPE_DICTIONARY, "%s (type=%s)" % [msg, str(typeof(v))])

func _is_array(v, msg: String) -> void:
	_ok(typeof(v) == TYPE_ARRAY, "%s (type=%s)" % [msg, str(typeof(v))])

func _is_string(v, msg: String) -> void:
	_ok(typeof(v) == TYPE_STRING, "%s (type=%s)" % [msg, str(typeof(v))])

func _is_int(v, msg: String) -> void:
	_ok(typeof(v) == TYPE_INT, "%s (type=%s)" % [msg, str(typeof(v))])

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

func _assert_apply_contract(res: Dictionary, label: String) -> void:
	_has_key(res, "ok", label + " has ok")
	_has_key(res, "reason", label + " has reason")
	_has_key(res, "events", label + " has events")
	_has_key(res, "hand_ended", label + " has hand_ended")
	_has_key(res, "went_out", label + " has went_out")
	_has_key(res, "state_version", label + " has state_version")
	_has_key(res, "state_public", label + " has state_public")

	_is_string(res.get("reason", ""), label + " reason is String")
	_is_array(res.get("events", []), label + " events is Array")
	_is_int(res.get("state_version", -1), label + " state_version is int")
	_is_dict(res.get("state_public", {}), label + " state_public is Dictionary")

func _assert_invariants_ok(engine: MatchEngine, label: String) -> void:
	var v := Invariants.validate(engine.state, engine.registry, engine.rules)
	if not bool(v.get("ok", false)):
		_ok(false, label + " invariants failed:\n - " + "\n - ".join(Array(v.get("errors", []))))
	else:
		print("OK:" + label + " invariants ok")
# -----------------------------
# Tests
# -----------------------------

func _test_apply_contract_keys_and_version() -> void:
	print("\n--- test_apply_contract_keys_and_version ---")

	var rules := RulesConfig.new()
	var engine := MatchEngine.new(2, 500, 0, ActionProcessor.StockEmptyPolicy.RESHUFFLE_EXCEPT_TOP, 123, rules)

	# get_state_public contract
	var snap := engine.get_state_public(0, true)
	_has_key(snap, "state_version", "get_state_public has state_version")
	_has_key(snap, "state_public", "get_state_public has state_public")
	_is_int(snap.get("state_version", -1), "get_state_public state_version is int")
	_is_dict(snap.get("state_public", {}), "get_state_public state_public is dict")

	var stp: Dictionary = snap["state_public"]
	_has_key(stp, "num_players", "state_public has num_players")
	_has_key(stp, "turn_player", "state_public has turn_player")
	_has_key(stp, "phase", "state_public has phase")
	_has_key(stp, "stock_count", "state_public has stock_count")
	_has_key(stp, "discard", "state_public has discard")
	_has_key(stp, "melds", "state_public has melds")

	var v0 := int(snap["state_version"])
	var p := int(stp["turn_player"])
	_eq(String(stp["phase"]), "DRAW", "new hand starts in DRAW phase")

	# Apply a normal action
	var res := engine.apply(p, {"type":"DRAW_STOCK"})
	_assert_apply_contract(res, "apply(DRAW_STOCK)")

	var v1 := int(res["state_version"])
	if bool(res.get("ok", false)):
		_eq(v1, v0 + 1, "state_version increments on ok=true")
		var sp1: Dictionary = res["state_public"]
		_eq(String(sp1.get("phase", "")), "PLAY", "after DRAW_STOCK phase becomes PLAY")
		_assert_invariants_ok(engine, "after DRAW_STOCK")
	else:
		_eq(v1, v0, "state_version unchanged on ok=false (DRAW_STOCK)")

func _test_state_public_visibility_modes() -> void:
	print("\n--- test_state_public_visibility_modes ---")

	var engine := MatchEngine.new(2, 500, 0, ActionProcessor.StockEmptyPolicy.RESHUFFLE_EXCEPT_TOP, 1, RulesConfig.new())

	# Multiplayer-safe view
	var snap_hidden := engine.get_state_public(0, false)
	var sp_h: Dictionary = snap_hidden["state_public"]

	_ok(not sp_h.has("hands"), "reveal_all=false does NOT include hands[]")
	_ok(not sp_h.has("must_play_discard_target"), "reveal_all=false does NOT include must_play_discard_target[]")
	_ok(not sp_h.has("must_play_discard_pending"), "reveal_all=false does NOT include must_play_discard_pending[]")

	_has_key(sp_h, "your_hand", "reveal_all=false includes your_hand")
	_has_key(sp_h, "other_hand_sizes", "reveal_all=false includes other_hand_sizes")
	_has_key(sp_h, "must_play", "reveal_all=false includes must_play object")
	_is_array(sp_h.get("your_hand", []), "your_hand is array")
	_is_array(sp_h.get("other_hand_sizes", []), "other_hand_sizes is array")
	_is_dict(sp_h.get("must_play", {}), "must_play is dict")
	_eq(Array(sp_h.get("other_hand_sizes", [])).size(), 1, "2p: other_hand_sizes has 1 entry")

	# Hotseat/dev view
	var snap_all := engine.get_state_public(0, true)
	var sp_a: Dictionary = snap_all["state_public"]

	_has_key(sp_a, "hands", "reveal_all=true includes hands[]")
	_has_key(sp_a, "must_play_discard_target", "reveal_all=true includes must_play_discard_target[]")
	_has_key(sp_a, "must_play_discard_pending", "reveal_all=true includes must_play_discard_pending[]")

	_is_array(sp_a.get("hands", []), "hands is array")
	_eq(Array(sp_a.get("hands", [])).size(), 2, "2p: hands has 2 arrays")

func _test_rules_propagate_through_matchengine_wrap_disabled() -> void:
	print("\n--- test_rules_propagate_through_matchengine_wrap_disabled ---")

	var rules := RulesConfig.new()
	rules.allow_wrap_runs = false

	var engine := MatchEngine.new(2, 500, 0, ActionProcessor.StockEmptyPolicy.RESHUFFLE_EXCEPT_TOP, 1, rules)

	# Deterministic situation: override the current hand
	var kS := _pick(engine.registry, 0, "S", 13)
	var aS := _pick(engine.registry, 0, "S", 1)
	var s2 := _pick(engine.registry, 0, "S", 2)
	_ok(kS != "" and aS != "" and s2 != "", "picked K/A/2 spades for wrap test")

	engine.state.phase = "PLAY"
	engine.state.turn_player = 0
	engine.state.hands[0] = [kS, aS, s2]
	engine.state.hands[1] = []
	engine.state.stock = []
	engine.state.discard = []
	engine.state.melds = []
	engine.state.clear_must_play(0)
	engine.state.clear_must_play(1)
	engine.state.hand_over = false
	engine.state.hand_scored = false
	engine.state.hand_end_reason = ""
	engine.state.went_out_player = -1

	_assert_invariants_ok(engine, "before wrap-disabled CREATE_MELD")

	var v0 := engine.state_version
	var res := engine.apply(0, {"type":"CREATE_MELD", "meld_kind":"RUN", "card_ids":[kS, aS, s2]})
	_assert_apply_contract(res, "apply(CREATE_MELD K-A-2)")

	_eq(bool(res.get("ok", true)), false, "wrap disabled rejects K-A-2 via MatchEngine.apply")
	_eq(String(res.get("reason", "")), "WRAP_RUNS_DISABLED", "reason is WRAP_RUNS_DISABLED")
	_eq(int(res.get("state_version", -999)), v0, "state_version does not increment on rejected action")

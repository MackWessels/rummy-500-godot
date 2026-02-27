extends RefCounted
class_name ActionProcessor

const PHASE_DRAW = "DRAW"
const PHASE_PLAY = "PLAY"
const TYPE_DRAW_STOCK = "DRAW_STOCK"
const TYPE_DRAW_DISCARD_STACK = "DRAW_DISCARD_STACK"
const TYPE_CREATE_MELD = "CREATE_MELD"
const TYPE_LAYOFF = "LAYOFF"
const TYPE_DISCARD = "DISCARD"
const MELD_SET = "SET"
const MELD_RUN = "RUN"
const END_LEFT = "LEFT"
const END_RIGHT = "RIGHT"

var rules: RulesConfig

enum StockEmptyPolicy {
	RESHUFFLE_EXCEPT_TOP,
	END_HAND_IMMEDIATELY
}

# Deterministic set ordering (display only)
const SUIT_ORDER = {"C": 0, "D": 1, "H": 2, "S": 3}

var registry: CardRegistry
var stock_empty_policy: int = StockEmptyPolicy.RESHUFFLE_EXCEPT_TOP
var rng = RandomNumberGenerator.new()

func _init(
	_registry: CardRegistry,
	_policy: int = StockEmptyPolicy.RESHUFFLE_EXCEPT_TOP,
	rng_seed: int = 0,
	_rules: RulesConfig = null
) -> void:
	registry = _registry
	stock_empty_policy = _policy
	
	rules = _rules if _rules != null else RulesConfig.new()
	
	if rng_seed != 0:
		rng.seed = rng_seed
	else:
		rng.randomize()

# Returns:
# {
#   ok: bool,
#   reason: String,
#   events: Array[Dictionary],
#   hand_ended: bool,
#   went_out: bool
# }
func apply(state: GameState, player: int, action: Dictionary) -> Dictionary:
	var out = {"ok": false, "reason": "", "events": [], "hand_ended": false, "went_out": false}
	
	if state.hand_over:
		out.reason = "HAND_OVER"
		return out
	
	if player != state.turn_player:
		out.reason = "NOT_YOUR_TURN"
		return out
	
	if not action.has("type"):
		out.reason = "MISSING_ACTION_TYPE"
		return out
	
	# Ensure must_play arrays are sized
	_ensure_must_play_arrays(state)
	
	match String(action["type"]):
		TYPE_DRAW_STOCK:
			return _do_draw_stock(state, player)
		TYPE_DRAW_DISCARD_STACK:
			return _do_draw_discard_stack(state, player, action)
		TYPE_CREATE_MELD:
			return _do_create_meld(state, player, action)
		TYPE_LAYOFF:
			return _do_layoff(state, player, action)
		TYPE_DISCARD:
			return _do_discard(state, player, action)
		_:
			out.reason = "UNKNOWN_ACTION_TYPE"
			return out


# -------------------------
# DRAW
# -------------------------

func _do_draw_stock(state: GameState, player: int) -> Dictionary:
	var out = {"ok": false, "reason": "", "events": [], "hand_ended": false, "went_out": false}
	
	if state.phase != PHASE_DRAW:
		out.reason = "BAD_PHASE_NEED_DRAW"
		return out
	
	# If stock is empty, try to refill it
	if state.stock.is_empty():
		var refill = _handle_stock_empty(state)
		if not refill["ok"]:
			_end_hand(state, "NO_CARDS_TO_REFILL_STOCK")
			out.reason = "NO_CARDS_TO_REFILL_STOCK"
			out.hand_ended = true
			return out
		out.events.append_array(refill["events"])
	
	# After a refill, stock should be non-empty
	if state.stock.is_empty():
		_end_hand(state, "NO_CARDS_TO_REFILL_STOCK")
		out.reason = "NO_CARDS_TO_REFILL_STOCK"
		out.hand_ended = true
		return out
	
	var card_id = String(state.stock.pop_back())
	state.hands[player].append(card_id)
	
	state.phase = PHASE_PLAY
	state.clear_must_play(player)
	
	out.ok = true
	out.events.append({"type":"DRAW_STOCK", "player":player, "card_id":card_id})
	return out


func _do_draw_discard_stack(state: GameState, player: int, action: Dictionary) -> Dictionary:
	var out = {"ok": false, "reason": "", "events": [], "hand_ended": false, "went_out": false}
	
	if state.phase != PHASE_DRAW:
		out.reason = "BAD_PHASE_NEED_DRAW"
		return out
	
	if state.discard.is_empty():
		out.reason = "DISCARD_EMPTY"
		return out
	
	if not action.has("target_card_id"):
		out.reason = "MISSING_target_card_id"
		return out
	
	var target = String(action["target_card_id"])
	var idx = state.discard.find(target)
	if idx == -1:
		out.reason = "TARGET_NOT_IN_DISCARD"
		return out
	
	# take target + all above it (toward top/back)
	var taken: Array = []
	for i in range(idx, state.discard.size()):
		taken.append(String(state.discard[i]))
	
	var target_card = registry.get_card(target)
	if target_card.is_empty():
		out.reason = "UNKNOWN_CARD_ID"
		return out
	
	# Reject if target cannot be played this turn (via layoff or new meld including target)
	var temp_hand: Array = state.hands[player].duplicate()
	temp_hand.append_array(taken) # include target + any cards above it (they can help form the meld)
	if not _discard_target_playable_this_turn(state, target, temp_hand):
		out.reason = "DISCARD_TARGET_NOT_PLAYABLE"
		return out
	
	# remove from discard
	state.discard.resize(idx)
	
	# add to hand
	for cid in taken:
		state.hands[player].append(cid)
	
	# must-play rule
	state.must_play_discard_target[player] = target
	state.must_play_discard_pending[player] = true
	
	state.phase = PHASE_PLAY
	
	out.ok = true
	out.events.append({
		"type":"DRAW_DISCARD_STACK",
		"player":player,
		"target_card_id":target,
		"taken":taken.duplicate()
	})
	return out


# -------------------------
# PLAY (meld/layoff optional)
# -------------------------

func _do_create_meld(state: GameState, player: int, action: Dictionary) -> Dictionary:
	var out = {"ok": false, "reason": "", "events": [], "hand_ended": false, "went_out": false}
	
	if state.phase != PHASE_PLAY:
		out.reason = "BAD_PHASE_NEED_PLAY"
		return out
	
	if not action.has("meld_kind") or not action.has("card_ids"):
		out.reason = "MISSING_meld_kind_or_card_ids"
		return out
	
	var meld_kind = String(action["meld_kind"])
	var card_ids: Array = action["card_ids"]
	
	# must-play discard target rule: any new meld must include the target if pending
	if bool(state.must_play_discard_pending[player]):
		var target = String(state.must_play_discard_target[player])
		if not card_ids.has(target):
			out.reason = "MUST_PLAY_TARGET_NOT_IN_MELD"
			return out
	
	# validate cards exist in player's hand
	for cid_any in card_ids:
		var cid = String(cid_any)
		if not state.hands[player].has(cid):
			out.reason = "CARD_NOT_IN_HAND"
			return out
	
	var build = _build_meld(meld_kind, card_ids)
	if not bool(build.get("ok", false)):
		out.reason = String(build.get("reason", "MELD_INVALID"))
		return out
	
	# remove meld cards from hand
	for cid_any in Array(build["ordered_card_ids"]):
		var cid = String(cid_any)
		var i = state.hands[player].find(cid)
		if i != -1:
			state.hands[player].remove_at(i)
	
	# add meld to table
	var meld_id = state.melds.size()
	var contrib = {}
	for cid in Array(build["ordered_card_ids"]):
		contrib[String(cid)] = player
	
	var meld: Dictionary = {
		"id": meld_id,
		"type": meld_kind,
		"cards": Array(build["ordered_card_ids"]).duplicate(),
		"owner": player,
		"contrib": contrib
	}
	
	if meld_kind == MELD_SET:
		meld["rank"] = int(build["rank"])
	elif meld_kind == MELD_RUN:
		meld["suit"] = String(build["suit"])
		meld["ace_mode"] = String(build["ace_mode"])
	
	state.melds.append(meld)
	
	# clear must-play if satisfied
	if bool(state.must_play_discard_pending[player]):
		var target2 = String(state.must_play_discard_target[player])
		if meld["cards"].has(target2):
			state.clear_must_play(player)
	
	out.ok = true
	out.events.append({"type":"CREATE_MELD", "player":player, "meld_id":meld_id, "meld":meld.duplicate(true)})
	return out


func _do_layoff(state: GameState, player: int, action: Dictionary) -> Dictionary:
	var out = {"ok": false, "reason": "", "events": [], "hand_ended": false, "went_out": false}
	
	if state.phase != PHASE_PLAY:
		out.reason = "BAD_PHASE_NEED_PLAY"
		return out
	
	if not action.has("meld_id") or not action.has("card_id"):
		out.reason = "MISSING_meld_id_or_card_id"
		return out
	
	var meld_id = int(action["meld_id"])
	var card_id = String(action["card_id"])
	
	# must-play discard target rule: if pending, the card laid off must be the target
	if bool(state.must_play_discard_pending[player]):
		var target = String(state.must_play_discard_target[player])
		if card_id != target:
			out.reason = "MUST_PLAY_TARGET_NOT_PLAYED"
			return out
	
	if not state.hands[player].has(card_id):
		out.reason = "CARD_NOT_IN_HAND"
		return out
	
	if meld_id < 0 or meld_id >= state.melds.size():
		out.reason = "BAD_meld_id"
		return out
	
	var meld: Dictionary = state.melds[meld_id]
	var mtype = String(meld.get("type", ""))
	
	if mtype == MELD_SET:
		var tc = registry.get_card(card_id)
		if tc.is_empty():
			out.reason = "UNKNOWN_CARD_ID"
			return out
		
		var rank = int(tc["rank"])
		var set_rank = int(meld.get("rank", 0))
		if rank != set_rank:
			out.reason = "SET_RANK_MISMATCH"
			return out
		
		if not rules.allow_duplicate_suits_in_set:
			var suit := String(tc["suit"])
			for cid_any in Array(meld.get("cards", [])):
				var c2 = registry.get_card(String(cid_any))
				if not c2.is_empty() and String(c2["suit"]) == suit:
					out.reason = "SET_DUPLICATE_SUIT_NOT_ALLOWED"
					return out
		
		meld["cards"].append(card_id)
		meld["contrib"][card_id] = player
	
	elif mtype == MELD_RUN:
		if not action.has("end"):
			out.reason = "MISSING_end"
			return out
		var end = String(action["end"])
		if end != END_LEFT and end != END_RIGHT:
			out.reason = "BAD_end"
			return out
		
		# validate via MeldRules.can_extend_run_end()
		var check = MeldRules.can_extend_run_end(meld, card_id, end, registry, rules.allow_wrap_runs)
		if not bool(check.get("ok", false)):
			out.reason = String(check.get("reason", "RUN_LAYOFF_INVALID"))
			return out
		
		# apply extension
		if end == END_LEFT:
			meld["cards"].insert(0, card_id)
		else:
			meld["cards"].append(card_id)
		
		meld["contrib"][card_id] = player
		
		# update ace_mode if needed
		if check.has("new_ace_mode"):
			meld["ace_mode"] = String(check["new_ace_mode"])
	
	else:
		out.reason = "BAD_MELD_KIND"
		return out
	
	# remove from hand
	var idx = state.hands[player].find(card_id)
	state.hands[player].remove_at(idx)
	
	# clear must-play if satisfied
	if bool(state.must_play_discard_pending[player]):
		if card_id == String(state.must_play_discard_target[player]):
			state.clear_must_play(player)
	
	out.ok = true
	out.events.append({"type":"LAYOFF", "player":player, "meld_id":meld_id, "card_id":card_id})
	return out


func _do_discard(state: GameState, player: int, action: Dictionary) -> Dictionary:
	var out = {"ok": false, "reason": "", "events": [], "hand_ended": false, "went_out": false}
	
	if state.phase != PHASE_PLAY:
		out.reason = "BAD_PHASE_NEED_PLAY"
		return out
	
	# must-play discard target rule: cannot discard while pending
	if bool(state.must_play_discard_pending[player]):
		out.reason = "MUST_PLAY_PENDING_CANNOT_DISCARD"
		return out
	
	if not action.has("card_id"):
		out.reason = "MISSING_card_id"
		return out
	
	var card_id = String(action["card_id"])
	if not state.hands[player].has(card_id):
		out.reason = "CARD_NOT_IN_HAND"
		return out
	
	# remove from hand
	var idx = state.hands[player].find(card_id)
	state.hands[player].remove_at(idx)
	
	# push to discard pile top/back
	state.discard.append(card_id)
	
	out.ok = true
	out.events.append({"type":"DISCARD", "player":player, "card_id":card_id})
	
	# If player discarded their last card -> went out and end hand
	if state.hands[player].is_empty():
		_end_hand(state, "WENT_OUT", player)
		out.hand_ended = true
		out.went_out = true
		return out
	
	# advance turn
	_advance_turn(state)
	return out


# -------------------------
# Meld building / validation
# -------------------------

func _build_meld(meld_kind: String, card_ids: Array) -> Dictionary:
	if meld_kind == MELD_SET:
		var chk = _validate_set(card_ids)
		if not bool(chk.get("ok", false)):
			return chk
		var ordered = card_ids.duplicate()
		_sort_set_cards_in_place(ordered)
		return {"ok": true, "rank": int(chk["rank"]), "ordered_card_ids": ordered}
	
	if meld_kind == MELD_RUN:
		# NOTE: pass allow_wrap_runs through to MeldRules
		return MeldRules.build_run_meld(card_ids, registry, rules.allow_wrap_runs)
	
	return {"ok": false, "reason": "BAD_meld_kind"}


func _validate_set(card_ids: Array) -> Dictionary:
	if card_ids.size() < 3:
		return {"ok": false, "reason": "SET needs 3+ cards"}
	
	var first = registry.get_card(String(card_ids[0]))
	if first.is_empty():
		return {"ok": false, "reason": "UNKNOWN_CARD_ID"}
	var rank = int(first["rank"])
	
	var suits_seen: Dictionary = {}
	for cid_any in card_ids:
		var cid = String(cid_any)
		var c = registry.get_card(cid)
		if c.is_empty():
			return {"ok": false, "reason": "UNKNOWN_CARD_ID"}
		if int(c["rank"]) != rank:
			return {"ok": false, "reason": "SET_RANK_MISMATCH"}
		var suit = String(c["suit"])
		if not rules.allow_duplicate_suits_in_set:
			if suits_seen.has(suit):
				return {"ok": false, "reason": "SET_DUPLICATE_SUIT_NOT_ALLOWED"}
			suits_seen[suit] = true
	
	return {"ok": true, "rank": rank}


func _sort_set_cards_in_place(card_ids: Array) -> void:
	card_ids.sort_custom(func(a, b):
		var ca = registry.get_card(String(a))
		var cb = registry.get_card(String(b))
		var sa = SUIT_ORDER.get(String(ca["suit"]), 99)
		var sb = SUIT_ORDER.get(String(cb["suit"]), 99)
		if sa != sb:
			return sa < sb
		return int(ca["deck"]) < int(cb["deck"])
	)


# -------------------------
# Turn / end-hand
# -------------------------

func _advance_turn(state: GameState) -> void:
	state.turn_player = (state.turn_player + 1) % state.num_players
	state.phase = PHASE_DRAW

func _end_hand(state: GameState, reason: String, went_out_player: int = -1) -> void:
	state.hand_over = true
	state.hand_end_reason = reason
	state.went_out_player = went_out_player

	if not state.hand_scored:
		HandResolver.resolve_hand(state, registry, rules)
		state.hand_scored = true


# -------------------------
# Stock refill
# -------------------------

func _handle_stock_empty(state: GameState) -> Dictionary:
	var out = {"ok": false, "reason": "", "events": []}
	
	if stock_empty_policy == StockEmptyPolicy.END_HAND_IMMEDIATELY:
		out.reason = "STOCK_EMPTY_POLICY_END"
		return out
	
	# RESHUFFLE_EXCEPT_TOP
	if state.discard.size() < 2:
		out.reason = "DISCARD_TOO_SMALL_TO_REFILL"
		return out
	
	var top = String(state.discard.pop_back())
	var to_shuffle: Array = []
	while not state.discard.is_empty():
		to_shuffle.append(String(state.discard.pop_back()))
	
	# shuffle
	for i in range(to_shuffle.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var tmp = to_shuffle[i]
		to_shuffle[i] = to_shuffle[j]
		to_shuffle[j] = tmp
	
	state.stock = to_shuffle
	state.discard = [top]
	
	out.ok = true
	out.events.append({"type":"REFILL_STOCK", "kept_discard_top": top, "moved": to_shuffle.size()})
	return out


# -------------------------
# Must-play + playable-target helpers
# -------------------------

func _ensure_must_play_arrays(state: GameState) -> void:
	if state.must_play_discard_target.size() != state.num_players:
		state.must_play_discard_target.resize(state.num_players)
		for i in range(state.num_players):
			state.must_play_discard_target[i] = ""
	if state.must_play_discard_pending.size() != state.num_players:
		state.must_play_discard_pending.resize(state.num_players)
		for i in range(state.num_players):
			state.must_play_discard_pending[i] = false


func _discard_target_playable_this_turn(state: GameState, target_card_id: String, temp_hand: Array) -> bool:
	# Playable if it can layoff target onto any existing meld, OR can create a new meld that includes target from temp_hand
	if _can_layoff_target_to_any_meld(state, target_card_id):
		return true
	if _can_create_set_with_target(temp_hand, target_card_id):
		return true
	if _can_create_run_with_target(temp_hand, target_card_id):
		return true
	return false


func _can_layoff_target_to_any_meld(state: GameState, target_card_id: String) -> bool:
	var tc = registry.get_card(target_card_id)
	if tc.is_empty():
		return false
	
	var target_rank = int(tc["rank"])
	
	for meld_any in state.melds:
		var meld: Dictionary = meld_any
		var mtype = String(meld.get("type", ""))
		
		if mtype == MELD_SET:
			var set_rank = int(meld.get("rank", 0))
			if set_rank == target_rank:
				if rules.allow_duplicate_suits_in_set:
					return true
				
				var tsuit := String(tc["suit"])
				var already_has := false
				for cid_any in Array(meld.get("cards", [])):
					var cid := String(cid_any)
					var c2 := registry.get_card(cid)
					if not c2.is_empty() and String(c2["suit"]) == tsuit:
						already_has = true
						break
				
				if not already_has:
					return true
		
		elif mtype == MELD_RUN:
			# NOTE: pass allow_wrap_runs through to MeldRules
			var check_l = MeldRules.can_extend_run_end(meld, target_card_id, END_LEFT, registry, rules.allow_wrap_runs)
			if bool(check_l.get("ok", false)):
				return true
			var check_r = MeldRules.can_extend_run_end(meld, target_card_id, END_RIGHT, registry, rules.allow_wrap_runs)
			if bool(check_r.get("ok", false)):
				return true
	
	return false


func _can_create_set_with_target(temp_hand: Array, target_card_id: String) -> bool:
	var tc = registry.get_card(target_card_id)
	if tc.is_empty():
		return false
	
	var target_rank = int(tc["rank"])
	var target_suit = String(tc["suit"])
	
	var count = 1
	var suits_used = { target_suit: true }
	
	for cid_any in temp_hand:
		var cid = String(cid_any)
		if cid == target_card_id:
			continue
		
		var c = registry.get_card(cid)
		if c.is_empty():
			continue
		if int(c["rank"]) != target_rank:
			continue
		
		var s = String(c["suit"])
		if not rules.allow_duplicate_suits_in_set and suits_used.has(s):
			continue
		
		suits_used[s] = true
		count += 1
		if count >= 3:
			return true
	
	return false


func _can_create_run_with_target(temp_hand: Array, target_card_id: String) -> bool:
	var tc = registry.get_card(target_card_id)
	if tc.is_empty():
		return false
	
	var suit = String(tc["suit"])
	var target_rank = int(tc["rank"])
	
	# Choose one CardID per rank for this suit
	var rank_to_id: Dictionary = {}
	for cid_any in temp_hand:
		var cid := String(cid_any)
		var c = registry.get_card(cid)
		if c.is_empty():
			continue
		if String(c["suit"]) != suit:
			continue
		var r := int(c["rank"])
		if not rank_to_id.has(r):
			rank_to_id[r] = cid
	
	if rank_to_id.size() < 3:
		return false
	if not rank_to_id.has(target_rank):
		return false
	
	var ranks: Array = rank_to_id.keys()
	var ranks_set: Dictionary = {}
	for r_any in ranks:
		ranks_set[int(r_any)] = true
	
	for start_any in ranks:
		var start = int(start_any)
		
		for L in range(3, ranks.size() + 1):
			var cur = start
			var ok = true
			var contains = false
			var ids: Array = []
			
			for i in range(L):
				if not ranks_set.has(cur):
					ok = false
					break
				if cur == target_rank:
					contains = true
				ids.append(String(rank_to_id[cur]))
				cur = MeldRules.inc_rank(cur)
			
			if ok and contains:
				# NOTE: pass allow_wrap_runs through to MeldRules
				var res = MeldRules.build_run_meld(ids, registry, rules.allow_wrap_runs)
				if bool(res.get("ok", false)):
					return true
	
	return false

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

enum StockEmptyPolicy {
	RESHUFFLE_EXCEPT_TOP,
	END_HAND_IMMEDIATELY
}

# Deterministic set ordering (display only)
const SUIT_ORDER = {"C": 0, "D": 1, "H": 2, "S": 3}

var registry: CardRegistry
var stock_empty_policy: int = StockEmptyPolicy.RESHUFFLE_EXCEPT_TOP
var rng = RandomNumberGenerator.new()

func _init(_registry: CardRegistry, _policy: int = StockEmptyPolicy.RESHUFFLE_EXCEPT_TOP, seed: int = 0) -> void:
	registry = _registry
	stock_empty_policy = _policy
	if seed != 0:
		rng.seed = seed
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
		_end_hand(state, "NO_CARDS_TO_REFILL_STOCK") # STOCK_EXHAUSTED
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
		out.reason = "MISSING_meld_kind_OR_card_ids"
		return out
	
	var meld_kind = String(action["meld_kind"])
	var card_ids: Array = action["card_ids"]
	
	if card_ids.size() < 3:
		out.reason = "MELD_NEEDS_3_PLUS"
		return out
	
	if not _hand_contains_all(state.hands[player], card_ids):
		out.reason = "CARD_NOT_IN_HAND"
		return out
	
	# validate + order
	var build = _build_meld(meld_kind, card_ids)
	if not build["ok"]:
		out.reason = String(build.get("reason", "MELD_INVALID"))
		return out
	
	# must-play enforcement
	if state.must_play_discard_pending[player]:
		var required = String(state.must_play_discard_target[player])
		if required != "" and card_ids.find(required) == -1:
			out.reason = "MUST_PLAY_DISCARD_TARGET_THIS_TURN"
			return out
		state.clear_must_play(player)
	
	_remove_cards_from_hand(state.hands[player], card_ids)
	
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
	
	out.ok = true
	out.events.append({"type":"CREATE_MELD", "player":player, "meld_id":meld_id, "meld":meld.duplicate(true)})
	return out


func _do_layoff(state: GameState, player: int, action: Dictionary) -> Dictionary:
	var out = {"ok": false, "reason": "", "events": [], "hand_ended": false, "went_out": false}
	
	if state.phase != PHASE_PLAY:
		out.reason = "BAD_PHASE_NEED_PLAY"
		return out
	
	if not action.has("meld_id") or not action.has("card_id"):
		out.reason = "MISSING_meld_id_OR_card_id"
		return out
	
	var meld_id = int(action["meld_id"])
	var card_id = String(action["card_id"])
	
	if state.hands[player].find(card_id) == -1:
		out.reason = "CARD_NOT_IN_HAND"
		return out
	
	var meld_idx = _find_meld_index(state.melds, meld_id)
	if meld_idx == -1:
		out.reason = "MELD_NOT_FOUND"
		return out
	
	var meld = state.melds[meld_idx]
	var mtype = String(meld.get("type",""))
	
	if mtype == MELD_SET:
		var set_rank = int(meld.get("rank", 0))
		var c = registry.get_card(card_id)
		if c.is_empty():
			out.reason = "UNKNOWN_CARD_ID"
			return out
		if int(c["rank"]) != set_rank:
			out.reason = "SET_LAYOFF_WRONG_RANK"
			return out
		
		meld["cards"].append(card_id)
		_sort_set_cards_in_place(meld["cards"])
		
		# Record contribution for scoring
		if not meld.has("contrib") or typeof(meld["contrib"]) != TYPE_DICTIONARY:
			meld["contrib"] = {}
		meld["contrib"][card_id] = player
		
		_remove_cards_from_hand(state.hands[player], [card_id])
	
	elif mtype == MELD_RUN:
		if not action.has("end"):
			out.reason = "MISSING_end"
			return out
		var end = String(action["end"])
		if end != END_LEFT and end != END_RIGHT:
			out.reason = "BAD_end"
			return out
		
		# validate via your MeldRules.can_extend_run_end()
		var check = MeldRules.can_extend_run_end(meld, card_id, end, registry)
		if not check["ok"]:
			out.reason = String(check.get("reason", "RUN_LAYOFF_INVALID"))
			return out
		
		# apply the extension (your runs are stored in inc_rank order)
		if end == END_LEFT:
			meld["cards"].insert(0, card_id)
		else:
			meld["cards"].append(card_id)
		
		meld["ace_mode"] = String(check.get("new_ace_mode", meld.get("ace_mode", MeldRules.ACE_UNSET)))
		# Record contribution for scoring
		if not meld.has("contrib") or typeof(meld["contrib"]) != TYPE_DICTIONARY:
			meld["contrib"] = {}
		meld["contrib"][card_id] = player
		
		_remove_cards_from_hand(state.hands[player], [card_id])
	else:
		out.reason = "MELD_TYPE_UNKNOWN"
		return out
	
	# satisfy must-play if the required card was laid off
	if state.must_play_discard_pending[player]:
		var required2 = String(state.must_play_discard_target[player])
		if required2 != "" and required2 == card_id:
			state.clear_must_play(player)
	
	state.melds[meld_idx] = meld
	
	out.ok = true
	out.events.append({"type":"LAYOFF", "player":player, "meld_id":meld_id, "card_id":card_id, "meld":meld.duplicate(true)})
	return out


# -------------------------
# DISCARD (ends turn, or go out)
# -------------------------

func _do_discard(state: GameState, player: int, action: Dictionary) -> Dictionary:
	var out = {"ok": false, "reason": "", "events": [], "hand_ended": false, "went_out": false}
	
	if state.phase != PHASE_PLAY:
		out.reason = "BAD_PHASE_NEED_PLAY"
		return out
	
	if not action.has("card_id"):
		out.reason = "MISSING_card_id"
		return out
	
	if state.must_play_discard_pending[player]:
		out.reason = "MUST_PLAY_DISCARD_TARGET_BEFORE_DISCARD"
		return out
	
	var card_id = String(action["card_id"])
	if state.hands[player].find(card_id) == -1:
		out.reason = "CARD_NOT_IN_HAND"
		return out
	
	_remove_cards_from_hand(state.hands[player], [card_id])
	state.discard.append(card_id)
	
	out.events.append({"type":"DISCARD", "player":player, "card_id":card_id})
	
	# Going out only by discarding your last card
	if state.hands[player].is_empty():
		_end_hand(state, "WENT_OUT")
		state.went_out_player = player
		out.ok = true
		out.hand_ended = true
		out.went_out = true
		out.events.append({"type":"WENT_OUT", "player":player})
		return out
	
	# End turn
	state.turn_player = (state.turn_player + 1) % state.num_players
	state.phase = PHASE_DRAW
	
	out.ok = true
	out.events.append({"type":"END_TURN", "next_player":state.turn_player})
	return out


# -------------------------
# Meld building
# -------------------------

func _build_meld(meld_kind: String, card_ids: Array) -> Dictionary:
	if meld_kind == MELD_SET:
		if not MeldRules.is_valid_set(card_ids, registry):
			return {"ok": false, "reason": "SET_INVALID"}
		var ordered = card_ids.duplicate()
		_sort_set_cards_in_place(ordered)
		return {"ok": true, "rank": MeldRules.get_set_rank(card_ids, registry), "ordered_card_ids": ordered}
	
	if meld_kind == MELD_RUN:
		var res = MeldRules.build_run_meld(card_ids, registry)
		if not res["ok"]:
			return res
		return res
	
	return {"ok": false, "reason": "BAD_meld_kind"}


func _sort_set_cards_in_place(card_ids: Array) -> void:
	card_ids.sort_custom(func(a, b):
		var ca = registry.get_card(String(a))
		var cb = registry.get_card(String(b))
		var sa = SUIT_ORDER.get(String(ca.get("suit", "")), 99)
		var sb = SUIT_ORDER.get(String(cb.get("suit", "")), 99)
		if sa != sb:
			return sa < sb
		var da = int(ca.get("deck", 0))
		var db = int(cb.get("deck", 0))
		if da != db:
			return da < db
		return String(a) < String(b)
	)


# -------------------------
# Stock empty policy
# -------------------------

func _handle_stock_empty(state: GameState) -> Dictionary:
	var out = {"ok": false, "reason": "", "events": []}
	
	if stock_empty_policy == StockEmptyPolicy.END_HAND_IMMEDIATELY:
		out.reason = "STOCK_EMPTY_END_HAND"
		return out
	
	# RESHUFFLE_EXCEPT_TOP
	if state.discard.size() < 2:
		out.reason = "NO_CARDS_TO_REFILL_STOCK"
		return out
	
	var top = String(state.discard.pop_back())
	var to_shuffle = state.discard.duplicate()
	state.discard.clear()
	state.discard.append(top)
	
	_shuffle_in_place(to_shuffle)
	state.stock = to_shuffle
	
	out.ok = true
	out.events.append({"type":"REFILL_STOCK", "kept_top_discard":top, "new_stock_size":state.stock.size()})
	return out

func _shuffle_in_place(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# -------------------------
# Utility
# -------------------------

func _ensure_must_play_arrays(state: GameState) -> void:
	# Make sure these arrays exist + are sized
	if state.must_play_discard_target.size() != state.num_players:
		state.must_play_discard_target = []
		for i in range(state.num_players):
			state.must_play_discard_target.append("")
	if state.must_play_discard_pending.size() != state.num_players:
		state.must_play_discard_pending = []
		for i in range(state.num_players):
			state.must_play_discard_pending.append(false)

func _end_hand(state: GameState, reason: String) -> void:
	state.hand_over = true
	state.hand_end_reason = reason
	HandResolver.resolve_hand(state, registry)

func _hand_contains_all(hand: Array, needed: Array) -> bool:
	# multiplicity-aware
	var counts = {}
	for cid in hand:
		var k = String(cid)
		counts[k] = int(counts.get(k, 0)) + 1
	for cid in needed:
		var k = String(cid)
		var n = int(counts.get(k, 0))
		if n <= 0:
			return false
		counts[k] = n - 1
	return true

func _remove_cards_from_hand(hand: Array, remove_ids: Array) -> void:
	var counts = {}
	for cid in remove_ids:
		var k = String(cid)
		counts[k] = int(counts.get(k, 0)) + 1
	
	var new_hand = []
	for cid in hand:
		var k = String(cid)
		var n = int(counts.get(k, 0))
		if n > 0:
			counts[k] = n - 1
		else:
			new_hand.append(cid)
	
	hand.clear()
	hand.append_array(new_hand)

func _find_meld_index(melds: Array, meld_id: int) -> int:
	for i in range(melds.size()):
		if int(melds[i].get("id", -1)) == meld_id:
			return i
	return -1

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
				return true
		
		elif mtype == MELD_RUN:
			var check_l = MeldRules.can_extend_run_end(meld, target_card_id, END_LEFT, registry)
			if bool(check_l.get("ok", false)):
				return true
			var check_r = MeldRules.can_extend_run_end(meld, target_card_id, END_RIGHT, registry)
			if bool(check_r.get("ok", false)):
				return true
	
	return false


func _can_create_set_with_target(temp_hand: Array, target_card_id: String) -> bool:
	var tc = registry.get_card(target_card_id)
	if tc.is_empty():
		return false
	var target_rank = int(tc["rank"])
	
	var count = 0
	for cid_any in temp_hand:
		var cid = String(cid_any)
		var c = registry.get_card(cid)
		if c.is_empty():
			continue
		if int(c["rank"]) == target_rank:
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
	
	# Choose one CardID per rank for this suit (duplicates exist across decks)
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
	
	# Try any consecutive sequence length >= 3 that includes target_rank
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
				var res = MeldRules.build_run_meld(ids, registry)
				if bool(res.get("ok", false)):
					return true
	
	return false

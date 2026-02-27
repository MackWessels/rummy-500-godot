extends RefCounted
class_name MeldRules

const TYPE_SET = "SET"
const TYPE_RUN = "RUN"

const ACE_UNSET = "UNSET" # run currently has no Ace
const ACE_LOW   = "LOW"   # Ace entered as low (A next to 2), OR Ace present but no Q-K-A subset at first appearance
const ACE_HIGH  = "HIGH"  # Ace entered as high by forming a Q-K-A subset

static func inc_rank(r: int) -> int:
	return (r % 13) + 1

static func dec_rank(r: int) -> int:
	if r == 1:
		return 13
	else:
		return r - 1

# -------------------------
# SET
# -------------------------

static func build_set_meld(card_ids: Array, registry: CardRegistry, allow_duplicate_suits_in_set: bool = true) -> Dictionary:
	if card_ids.size() < 3:
		return {"ok": false, "reason": "SET needs 3+ cards"}
	
	var first = registry.get_card(card_ids[0])
	var rank = int(first["rank"])
	
	var suits = {}
	for cid in card_ids:
		var c = registry.get_card(cid)
		if int(c["rank"]) != rank:
			return {"ok": false, "reason": "SET ranks must match"}
		
		var s = String(c["suit"])
		if not allow_duplicate_suits_in_set and suits.has(s):
			return {"ok": false, "reason": "SET_DUPLICATE_SUIT_NOT_ALLOWED"}
		suits[s] = true
	
	return {
		"ok": true,
		"type": "SET",
		"rank": rank,
		"card_ids": card_ids.duplicate()
	}

static func is_valid_set(card_ids: Array, registry: CardRegistry) -> bool:
	if card_ids.size() < 3:
		return false
	
	var rank = int(registry.get_card(String(card_ids[0]))["rank"])
	
	for cid in card_ids:
		var c = registry.get_card(String(cid))
		if c.is_empty():
			return false
		if int(c["rank"]) != rank:
			return false

	return true

static func get_set_rank(card_ids: Array, registry: CardRegistry) -> int:
	return int(registry.get_card(card_ids[0])["rank"])


# -------------------------
# RUN
# -------------------------

static func _infer_ace_mode_from_ranks(ranks_present: Array) -> String:
	# If Ace is present, HIGH only if the run contains the Q-K-A subset.
	# Otherwise LOW. If no Ace, UNSET.
	if not ranks_present.has(1):
		return ACE_UNSET
	if ranks_present.has(12) and ranks_present.has(13):
		return ACE_HIGH
	return ACE_LOW

static func _seq_key(seq: Array, ace_mode: String) -> Array:
	# in Ace-HIGH mode, treat Ace as 14 for comparisons
	var k: Array = []
	for r in seq:
		var rr = int(r)
		if ace_mode == ACE_HIGH and rr == 1:
			k.append(14)
		else:
			k.append(rr)
	return k

static func _lex_less(a: Array, b: Array) -> bool:
	var n = min(a.size(), b.size())
	for i in range(n):
		if a[i] < b[i]:
			return true
		if a[i] > b[i]:
			return false
	return a.size() < b.size()

static func _candidate_sequences(ranks_set: Dictionary) -> Array:
	var ranks: Array = ranks_set.keys()
	var n = ranks.size()
	var candidates: Array = []
	
	for start in ranks:
		var seq: Array = []
		var cur = int(start)
		var ok = true
		for i in range(n):
			if not ranks_set.has(cur):
				ok = false
				break
			seq.append(cur)
			cur = inc_rank(cur) # wrap behavior lives here
		if ok:
			candidates.append(seq)
	return candidates

static func _wrap_bridge_present(ranks_set: Dictionary) -> bool:
	# The only "wrap" we want to optionally disable is the K-A-2 bridge.
	# This preserves A-2-3 and Q-K-A even when wrap is disabled.
	return ranks_set.has(13) and ranks_set.has(1) and ranks_set.has(2)

static func build_run_meld(card_ids: Array, registry: CardRegistry, allow_wrap_runs: bool = true) -> Dictionary:
	# Returns:
	# {"ok":bool, "reason":String, "suit":String, "ace_mode":String, "ordered_card_ids":Array}
	#
	# - 3+ same suit
	# - wrap allowed if allow_wrap_runs
	# - deterministic order chosen from valid rotations
	# - ace_mode UNSET unless Ace present
	# - if Ace present on creation: HIGH only if Q-K-A subset exists; otherwise LOW
	if card_ids.size() < 3:
		return {"ok": false, "reason": "RUN needs 3+ cards"}

	var first = registry.get_card(String(card_ids[0]))
	if first.is_empty():
		return {"ok": false, "reason": "Unknown card id"}

	var suit = String(first["suit"])

	var rank_to_id: Dictionary = {} # rank -> card_id (only one per rank allowed in a run)
	var ranks: Array = []

	for cid in card_ids:
		var c = registry.get_card(String(cid))
		if c.is_empty():
			return {"ok": false, "reason": "Unknown card id"}
		if String(c["suit"]) != suit:
			return {"ok": false, "reason": "RUN needs same suit"}

		var r = int(c["rank"])
		if rank_to_id.has(r):
			return {"ok": false, "reason": "RUN cannot contain duplicate rank in same suit"}

		rank_to_id[r] = String(cid)
		ranks.append(r)

	var ranks_set: Dictionary = {}
	for r in ranks:
		ranks_set[int(r)] = true

	if not allow_wrap_runs and _wrap_bridge_present(ranks_set):
		return {"ok": false, "reason": "WRAP_RUNS_DISABLED"}

	var candidates = _candidate_sequences(ranks_set)
	if candidates.is_empty():
		return {"ok": false, "reason": "RUN ranks are not consecutive"}

	var ace_mode = _infer_ace_mode_from_ranks(ranks)

	# Pick the smallest key under ace_mode for deterministic storage/display
	var best_seq: Array = candidates[0]
	var best_key: Array = _seq_key(best_seq, ace_mode)

	for i in range(1, candidates.size()):
		var seq: Array = candidates[i]
		var key: Array = _seq_key(seq, ace_mode)
		if _lex_less(key, best_key):
			best_seq = seq
			best_key = key

	var ordered_card_ids: Array = []
	for r in best_seq:
		ordered_card_ids.append(String(rank_to_id[int(r)]))

	return {
		"ok": true,
		"suit": suit,
		"ace_mode": ace_mode,
		"ordered_card_ids": ordered_card_ids
	}

static func can_extend_run_end(run_meld: Dictionary, card_id: String, end: String, registry: CardRegistry, allow_wrap_runs: bool = true) -> Dictionary:
	# Returns {"ok":bool, "reason":String, "new_ace_mode":String}
	#
	# Run extension rules:
	# - Only add to LEFT or RIGHT end
	# - Must be exactly consecutive (wrap behavior exists in inc/dec_rank)
	# - No duplicate rank in a run
	# - ace_mode locks the moment an Ace first enters a run
	# - When allow_wrap_runs is false, disallow creating the K-A-2 bridge.
	if String(run_meld.get("type", "")) != TYPE_RUN:
		return {"ok": false, "reason": "Not a run"}

	var cards: Array = run_meld.get("cards", [])
	if cards.size() < 3:
		return {"ok": false, "reason": "Run is too small"}

	var suit = String(run_meld.get("suit", ""))
	var ace_mode = String(run_meld.get("ace_mode", ACE_UNSET))
	if ace_mode != ACE_UNSET and ace_mode != ACE_LOW and ace_mode != ACE_HIGH:
		ace_mode = ACE_UNSET

	var c = registry.get_card(String(card_id))
	if c.is_empty():
		return {"ok": false, "reason": "Unknown card id"}
	if String(c["suit"]) != suit:
		return {"ok": false, "reason": "Wrong suit for this run"}

	var new_rank := int(c["rank"])

	# Disallow duplicate rank in run
	for existing_id in cards:
		if int(registry.get_card(String(existing_id))["rank"]) == new_rank:
			return {"ok": false, "reason": "Run already has that rank"}

	# Defensive normalize: if run already contains an Ace but ace_mode says UNSET, infer it.
	var ranks_present: Array = []
	var has_ace = false
	for eid in cards:
		var r = int(registry.get_card(String(eid))["rank"])
		ranks_present.append(r)
		if r == 1:
			has_ace = true

	if ace_mode == ACE_UNSET and has_ace:
		ace_mode = _infer_ace_mode_from_ranks(ranks_present)

	var left_rank = int(registry.get_card(String(cards[0]))["rank"])
	var right_rank = int(registry.get_card(String(cards[cards.size() - 1]))["rank"])

	# Must extend an end
	if end == "LEFT":
		if new_rank != dec_rank(left_rank):
			return {"ok": false, "reason": "Card does not extend left end"}
	elif end == "RIGHT":
		if new_rank != inc_rank(right_rank):
			return {"ok": false, "reason": "Card does not extend right end"}
	else:
		return {"ok": false, "reason": "Invalid end (LEFT/RIGHT)"}

	# Enforce wrap toggle: reject if this addition creates the K-A-2 bridge.
	if not allow_wrap_runs:
		var ranks_set: Dictionary = {}
		for rr in ranks_present:
			ranks_set[int(rr)] = true
		ranks_set[int(new_rank)] = true
		if _wrap_bridge_present(ranks_set):
			return {"ok": false, "reason": "WRAP_RUNS_DISABLED"}

	# Lock behavior when Ace first enters a run (ace_mode == UNSET implies no Ace yet)
	var new_ace_mode = ace_mode
	if new_rank == 1 and ace_mode == ACE_UNSET:
		# Because runs are stored as increasing-by-inc_rank order,
		# a no-Ace run can only have K (13) as the RIGHT end, and 2 as the LEFT end.
		if end == "RIGHT" and right_rank == 13:
			new_ace_mode = ACE_HIGH
		elif end == "LEFT" and left_rank == 2:
			new_ace_mode = ACE_LOW
		else:
			return {"ok": false, "reason": "Ace must be added next to K (HIGH) or next to 2 (LOW)"}

	return {"ok": true, "new_ace_mode": new_ace_mode}

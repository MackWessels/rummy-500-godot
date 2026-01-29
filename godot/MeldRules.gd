extends RefCounted
class_name MeldRules

const TYPE_SET := "SET"
const TYPE_RUN := "RUN"

const ACE_UNSET := "UNSET"
const ACE_LOW := "LOW"
const ACE_HIGH := "HIGH"

static func inc_rank(r: int) -> int:
	return (r % 13) + 1

static func dec_rank(r: int) -> int:
	if r == 1:
		return 13
	else:
		return r - 1

# SET 

static func is_valid_set(card_ids: Array, registry: CardRegistry) -> bool:
	if card_ids.size() < 3:
		return false
	
	var rank = int(registry.get_card(card_ids[0])["rank"])
	for cid in card_ids:
		if int(registry.get_card(cid)["rank"]) != rank:
			return false
	
	return true

static func get_set_rank(card_ids: Array, registry: CardRegistry) -> int:
	return int(registry.get_card(card_ids[0])["rank"])

# RUN 

static func _contains_ranks(ranks: Array, a: int, b: int, c: int) -> bool:
	return ranks.has(a) and ranks.has(b) and ranks.has(c)

static func _determine_ace_mode_for_new_run(ranks: Array) -> String:
	#Ace is HIGH only if run was initially played including Q-K-A.
	if _contains_ranks(ranks, 12, 13, 1):
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
			cur = inc_rank(cur)
		if ok:
			candidates.append(seq)
	return candidates

static func build_run_meld(card_ids: Array, registry: CardRegistry) -> Dictionary:
	# Returns {"ok":bool, "reason":String, "suit":String, "ace_mode":String, "ordered_card_ids":Array}
	if card_ids.size() < 3:
		return {"ok": false, "reason": "RUN needs 3+ cards"}

	var suit = String(registry.get_card(card_ids[0])["suit"])

	var rank_to_id: Dictionary = {} # rank -> card_id
	var ranks: Array = []
	for cid in card_ids:
		var c := registry.get_card(cid)
		if String(c["suit"]) != suit:
			return {"ok": false, "reason": "RUN needs same suit"}
		var r := int(c["rank"])
		if rank_to_id.has(r):
			return {"ok": false, "reason": "RUN cannot contain duplicate rank in same suit"}
		rank_to_id[r] = String(cid)
		ranks.append(r)

	var ace_mode := _determine_ace_mode_for_new_run(ranks)

	var ranks_set: Dictionary = {}
	for r in ranks:
		ranks_set[int(r)] = true

	var candidates := _candidate_sequences(ranks_set)
	if candidates.is_empty():
		return {"ok": false, "reason": "RUN ranks are not consecutive (wrap allowed)"}

	#pick smallest key under ace_mode
	var best_seq: Array = candidates[0]
	var best_key: Array = _seq_key(best_seq, ace_mode)
	for i in range(1, candidates.size()):
		var seq: Array = candidates[i]
		var key: Array = _seq_key(seq, ace_mode)
		if _lex_less(key, best_key):
			best_seq = seq
			best_key = key

	# Map ranks to the chosen physical card IDs
	var ordered_card_ids: Array = []
	for r in best_seq:
		ordered_card_ids.append(String(rank_to_id[int(r)]))

	return {
		"ok": true,
		"suit": suit,
		"ace_mode": ace_mode,
		"ordered_card_ids": ordered_card_ids
	}

static func can_extend_run_end(run_meld: Dictionary, card_id: String, end: String, registry: CardRegistry) -> Dictionary:
	# Returns {"ok":bool, "reason":String, "new_ace_mode":String}
	if String(run_meld.get("type", "")) != TYPE_RUN:
		return {"ok": false, "reason": "Not a run"}
	
	var cards: Array = run_meld["cards"]
	var suit := String(run_meld["suit"])
	var ace_mode := String(run_meld["ace_mode"])
	
	var c := registry.get_card(card_id)
	if String(c["suit"]) != suit:
		return {"ok": false, "reason": "Wrong suit for this run"}
	
	var new_rank := int(c["rank"])
	
	# Disallow duplicate rank in run
	for existing_id in cards:
		if int(registry.get_card(String(existing_id))["rank"]) == new_rank:
			return {"ok": false, "reason": "Run already has that rank"}
	
	var left_rank := int(registry.get_card(String(cards[0]))["rank"])
	var right_rank := int(registry.get_card(String(cards[cards.size() - 1]))["rank"])
	
	# Must extend an end
	if end == "LEFT":
		if new_rank != dec_rank(left_rank):
			return {"ok": false, "reason": "Card does not extend left end"}
	elif end == "RIGHT":
		if new_rank != inc_rank(right_rank):
			return {"ok": false, "reason": "Card does not extend right end"}
	else:
		return {"ok": false, "reason": "Invalid end (LEFT/RIGHT)"}
	
	# locked behavior for Ace mode:
	# - If the run has no Ace yet (ace_mode == UNSET), the moment an Ace is added it locks:
	#     HIGH if added onto K end (..Q-K + A)
	#     LOW  if added onto 2 end (A + 2-3..)
	var new_ace_mode := ace_mode
	if new_rank == 1 and ace_mode == ACE_UNSET:
		if end == "RIGHT" and right_rank == 13:
			new_ace_mode = ACE_HIGH
		elif end == "LEFT" and left_rank == 2:
			new_ace_mode = ACE_LOW
		else:
			return {"ok": false, "reason": "Ace must be added next to K (HIGH) or next to 2 (LOW)"}
	
	if new_ace_mode == ACE_LOW:
		var ranks_present: Array = []
		for eid in cards:
			ranks_present.append(int(registry.get_card(String(eid))["rank"]))
		ranks_present.append(new_rank)
		if _contains_ranks(ranks_present, 12, 13, 1):
			return {"ok": false, "reason": "Ace-LOW run cannot introduce Q-K-A"}

	return {"ok": true, "new_ace_mode": new_ace_mode}

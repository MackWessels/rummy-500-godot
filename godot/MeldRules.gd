extends RefCounted
class_name MeldRules

const TYPE_SET := "SET"
const TYPE_RUN := "RUN"

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

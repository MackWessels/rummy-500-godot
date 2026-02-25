extends RefCounted
class_name HandResolver

# Stub point values:
#  Ace counts high in hand (deadwood)
#  Face cards + 10 are 10 points
#  2..9 are their rank value
static func card_points(card_id: String, registry: CardRegistry) -> int:
	var c = registry.get_card(card_id)
	if c.is_empty():
		return 0
	var r = int(c["rank"])
	if r == 1:
		return 15
	if r >= 10:
		return 10
	return r

static func deadwood_points(hand: Array, registry: CardRegistry) -> int:
	var total = 0
	for cid in hand:
		total += card_points(String(cid), registry)
	return total


# ---- Rule-aware helpers (optional) ----

static func _rules_has(rules: Object, prop: String) -> bool:
	if rules == null:
		return false
	for p in rules.get_property_list():
		if String(p.name) == prop:
			return true
	return false

static func _rules_get(rules: Object, prop: String, default_val):
	if rules == null:
		return default_val
	if _rules_has(rules, prop):
		return rules.get(prop)
	return default_val

static func _run_has_qk(meld: Dictionary, registry: CardRegistry) -> bool:
	var has_q := false
	var has_k := false
	var cards: Array = meld.get("cards", [])
	for cid_any in cards:
		var cid := String(cid_any)
		var c := registry.get_card(cid)
		if c.is_empty():
			continue
		var r := int(c["rank"])
		if r == 12:
			has_q = true
		elif r == 13:
			has_k = true
		if has_q and has_k:
			return true
	return false

static func _table_card_points(card_id: String, meld: Dictionary, registry: CardRegistry, rules: Object) -> int:
	var c := registry.get_card(card_id)
	if c.is_empty():
		return 0

	var r := int(c["rank"])
	if r != 1:
		return card_points(card_id, registry) # same as before for non-aces

	# Ace:
	var meld_type := String(meld.get("type", ""))
	if meld_type != "RUN":
		return _rules_get(rules, "ace_high_points", 15)

	# Ace on a RUN:
	var ace_high := int(_rules_get(rules, "ace_high_points", 15))
	var ace_low := int(_rules_get(rules, "ace_low_points", 1))
	var requires_qk := bool(_rules_get(rules, "ace_run_high_requires_qk", true))

	if not requires_qk:
		return ace_high

	return ace_high if _run_has_qk(meld, registry) else ace_low


static func resolve_hand(state: GameState, registry: CardRegistry, rules: Object = null) -> void:
	# Computes per-player table points
	# Stores results into:
	#  state.hand_points_table[player]
	#  state.hand_points_deadwood[player]
	#  state.hand_points_net[player]
	# Sets state.hand_scored = true

	if state.hand_scored:
		return

	var n = int(state.num_players)
	state.hand_points_table = []
	state.hand_points_deadwood = []
	state.hand_points_net = []
	for i in range(n):
		state.hand_points_table.append(0)
		state.hand_points_deadwood.append(0)
		state.hand_points_net.append(0)

	# attribute each card on table to the player who contributed it.
	for meld_any in state.melds:
		var meld: Dictionary = meld_any
		var owner = int(meld.get("owner", -1))
		var contrib = meld.get("contrib", {})
		var cards: Array = meld.get("cards", [])

		for cid_any in cards:
			var cid = String(cid_any)
			var p = owner
			if typeof(contrib) == TYPE_DICTIONARY and contrib.has(cid):
				p = int(contrib[cid])

			if p >= 0 and p < n:
				state.hand_points_table[p] += _table_card_points(cid, meld, registry, rules)

	# cards left in each hand (deadwood)
	for p in range(n):
		state.hand_points_deadwood[p] = deadwood_points(state.hands[p], registry)

	# table minus cards left in each hand
	for p in range(n):
		state.hand_points_net[p] = int(state.hand_points_table[p]) - int(state.hand_points_deadwood[p])

	state.hand_scored = true

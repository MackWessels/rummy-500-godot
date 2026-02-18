extends RefCounted
class_name HandResolver

# Stub point values:
#  Ace counts high in hand 
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

static func resolve_hand(state: GameState, registry: CardRegistry) -> void:
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
	for meld in state.melds:
		var owner = int(meld.get("owner", -1))
		var contrib = meld.get("contrib", {})
		var cards: Array = meld.get("cards", [])
		for cid_any in cards:
			var cid = String(cid_any)
			var p = owner
			if typeof(contrib) == TYPE_DICTIONARY and contrib.has(cid):
				p = int(contrib[cid])
			if p >= 0 and p < n:
				state.hand_points_table[p] += card_points(cid, registry)
	
	# cards left in each hand
	for p in range(n):
		state.hand_points_deadwood[p] = deadwood_points(state.hands[p], registry)
	
	# table minus cards left in each hand
	for p in range(n):
		state.hand_points_net[p] = int(state.hand_points_table[p]) - int(state.hand_points_deadwood[p])

	state.hand_scored = true

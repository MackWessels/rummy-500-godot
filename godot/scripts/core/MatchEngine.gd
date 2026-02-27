extends RefCounted
class_name MatchEngine

var registry: CardRegistry
var ap: ActionProcessor
var match_state: MatchState
var state: GameState

func _init(
	num_players: int,
	target_score: int = 500,
	dealer: int = 0,
	stock_policy: int = ActionProcessor.StockEmptyPolicy.RESHUFFLE_EXCEPT_TOP,
	rng_seed: int = 0
) -> void:
	registry = CardRegistry.new()
	ap = ActionProcessor.new(registry, stock_policy, rng_seed)
	match_state = MatchState.new(num_players, target_score, dealer)
	state = match_state.start_new_hand(registry)

func apply(player: int, action: Dictionary) -> Dictionary:
	# Returns the ActionProcessor result + some match info.
	var res = ap.apply(state, player, action)

	# If the hand ended during this action, roll match forward.
	if state.hand_over and state.hand_scored:
		var fin = match_state.finalize_hand(state)
		res["match_finalize_ok"] = fin.ok
		res["match_totals"] = match_state.total_scores.duplicate()
		res["match_winner"] = match_state.winner

		if match_state.winner == -1:
			state = match_state.start_new_hand(registry)
			res["new_hand_started"] = true
		else:
			res["new_hand_started"] = false

	return res

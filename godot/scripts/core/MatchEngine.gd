extends RefCounted
class_name MatchEngine

var registry: CardRegistry
var ap: ActionProcessor
var match_state: MatchState
var state: GameState
var rules: RulesConfig

var state_version: int = 0

var debug_validate_invariants: bool = false

func _init(
	num_players: int,
	target_score: int = 500,
	dealer: int = 0,
	stock_policy: int = ActionProcessor.StockEmptyPolicy.RESHUFFLE_EXCEPT_TOP,
	rng_seed: int = 0,
	_rules: RulesConfig = null
) -> void:
	registry = CardRegistry.new()
	
	rules = _rules if _rules != null else RulesConfig.new()
	ap = ActionProcessor.new(registry, stock_policy, rng_seed, rules)
	
	match_state = MatchState.new(num_players, target_score, dealer)
	state = match_state.start_new_hand(registry)
	
	state_version = 1

const Invariants := preload("res://scripts/core/RummyInvariants.gd")

func apply(player: int, action: Dictionary) -> Dictionary:
	var res: Dictionary = ap.apply(state, player, action)
	
	if bool(res.get("ok", false)):
		state_version += 1
		
		if debug_validate_invariants:
			var v := Invariants.validate(state, registry, rules)
			if not bool(v.get("ok", false)):
				push_error("INVARIANTS FAILED after action " + String(action.get("type","")) + ":\n - " + "\n - ".join(Array(v.get("errors", []))))
	
	if state.hand_over and state.hand_scored:
		var fin: Dictionary = match_state.finalize_hand(state)
		
		res["match_finalize_ok"] = bool(fin.get("ok", false))
		res["match_totals"] = match_state.total_scores.duplicate()
		res["match_winner"] = match_state.winner
		
		if match_state.winner == -1:
			state = match_state.start_new_hand(registry)
			res["new_hand_started"] = true
			state_version += 1
		else:
			res["new_hand_started"] = false
	
	res["state_version"] = state_version
	res["state_public"] = state.to_public(player, true)
	return res

func get_state_public(player: int, reveal_all: bool = true) -> Dictionary:
	return {
		"state_version": state_version,
		"state_public": state.to_public(player, reveal_all)
	}

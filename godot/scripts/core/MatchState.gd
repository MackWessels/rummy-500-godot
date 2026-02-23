extends RefCounted
class_name MatchState

const DEFAULT_TARGET_SCORE := 500

var num_players: int
var target_score: int = DEFAULT_TARGET_SCORE

var hand_index: int = 0
var dealer: int = 0
var starting_player: int = 0

var total_scores: Array = []      # Array[int]
var last_hand_net: Array = []     # Array[int]
var winner: int = -1              # -1 if none

func _init(_num_players: int, _target_score: int = DEFAULT_TARGET_SCORE, _dealer: int = 0) -> void:
	num_players = _num_players
	target_score = _target_score
	dealer = _dealer

	starting_player = (dealer + 1) % num_players

	total_scores = []
	last_hand_net = []
	for i in range(num_players):
		total_scores.append(0)
		last_hand_net.append(0)

func start_new_hand(registry: CardRegistry) -> GameState:
	# NewGame builds a fresh deck/shoe each hand (it also rebuilds the registry contents).
	var state = NewGame.create_game(num_players, registry)

	# Override defaults so the match controls who starts.
	state.turn_player = starting_player
	state.phase = "DRAW"
	return state

func finalize_hand(state: GameState) -> Dictionary:
	# Call this after ActionProcessor ends the hand (it already calls HandResolver.resolve_hand).
	var out = {"ok": false, "reason": "", "winner": -1, "totals": [], "dealer": dealer, "starting_player": starting_player}

	if not state.hand_over:
		out.reason = "HAND_NOT_OVER"
		return out
	if not state.hand_scored:
		out.reason = "HAND_NOT_SCORED"
		return out

	# Accumulate
	last_hand_net = state.hand_points_net.duplicate()
	for p in range(num_players):
		total_scores[p] += int(last_hand_net[p])

	# Winner check (highest total >= target_score; tie -> lowest index)
	var best_player = -1
	var best_score = -2147483648
	for p in range(num_players):
		var s = int(total_scores[p])
		if s >= target_score:
			if best_player == -1 or s > best_score or (s == best_score and p < best_player):
				best_player = p
				best_score = s

	winner = best_player
	out.winner = winner
	out.totals = total_scores.duplicate()

	# Rotate dealer and starting player for next hand
	hand_index += 1
	dealer = (dealer + 1) % num_players
	starting_player = (dealer + 1) % num_players

	out.dealer = dealer
	out.starting_player = starting_player
	out.ok = true
	return out

func has_winner() -> bool:
	return winner != -1

func debug_summary() -> String:
	return "hand=%s dealer=%s start=%s totals=%s winner=%s" % [hand_index, dealer, starting_player, total_scores, winner]

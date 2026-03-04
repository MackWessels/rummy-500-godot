extends RefCounted
class_name GameState

var num_players: int = 0
var hands: Array = []       # Array[Array[String]] CardIDs per player
var stock: Array = []       # Array[String] (hidden to opponents; expose stock_count)
var discard: Array = []     # Array[String], fully visible
var melds: Array = []       # Array[Dictionary] shared table melds

var turn_player: int = 0
var phase: String = "DRAW"  # "DRAW" -> "PLAY"

var must_play_discard_target: Array = []   # Array[String], "" if none
var must_play_discard_pending: Array = []  # Array[bool]

var hand_over: bool = false
var hand_end_reason: String = ""
var went_out_player: int = -1

var hand_scored: bool = false
var hand_points_table: Array = []     # Array[int]
var hand_points_deadwood: Array = []  # Array[int]
var hand_points_net: Array = []       # Array[int]

func init_for_players(p: int) -> void:
	num_players = p

	hands = []
	for i in range(p):
		hands.append([])

	stock = []
	discard = []
	melds = []

	turn_player = 0
	phase = "DRAW"

	must_play_discard_target = []
	must_play_discard_pending = []
	for i in range(p):
		must_play_discard_target.append("")
		must_play_discard_pending.append(false)

	hand_over = false
	hand_end_reason = ""
	went_out_player = -1

	hand_scored = false
	hand_points_table = []
	hand_points_deadwood = []
	hand_points_net = []
	for i in range(p):
		hand_points_table.append(0)
		hand_points_deadwood.append(0)
		hand_points_net.append(0)

func clear_must_play(player: int) -> void:
	if player < 0 or player >= num_players:
		return
	must_play_discard_target[player] = ""
	must_play_discard_pending[player] = false

# Public snapshot for UI / future network clients.
# reveal_all=true  -> include full hands + must-play arrays (hotseat/dev).
# reveal_all=false -> include only requesting player's hand + opponent hand sizes (multiplayer-ready).
func to_public(for_player: int, reveal_all: bool = false) -> Dictionary:
	var d: Dictionary = {
		"num_players": num_players,
		"turn_player": turn_player,
		"phase": phase,

		"stock_count": stock.size(),
		"discard": discard.duplicate(),
		"melds": melds.duplicate(true),

		"hand_over": hand_over,
		"hand_end_reason": hand_end_reason,
		"went_out_player": went_out_player,

		"hand_scored": hand_scored,
		"hand_points_table": hand_points_table.duplicate(),
		"hand_points_deadwood": hand_points_deadwood.duplicate(),
		"hand_points_net": hand_points_net.duplicate()
	}

	if reveal_all:
		d["hands"] = hands.duplicate(true)
		d["must_play_discard_target"] = must_play_discard_target.duplicate()
		d["must_play_discard_pending"] = must_play_discard_pending.duplicate()
		return d

	# Multiplayer-safe view
	d["player"] = for_player

	var valid_player := (for_player >= 0 and for_player < num_players)

	if valid_player:
		d["your_hand"] = Array(hands[for_player]).duplicate()
		d["must_play"] = {
			"pending": bool(must_play_discard_pending[for_player]),
			"target_card_id": String(must_play_discard_target[for_player])
		}
	else:
		d["your_hand"] = []
		d["must_play"] = {"pending": false, "target_card_id": ""}

	var other_sizes: Array = []
	for i in range(num_players):
		if i == for_player:
			continue
		other_sizes.append(hands[i].size())
	d["other_hand_sizes"] = other_sizes

	return d

func debug_summary() -> String:
	var hand_sizes := []
	for h in hands:
		hand_sizes.append(h.size())
	return "players=%s hand_sizes=%s stock=%s discard=%s melds=%s turn=%s phase=%s" % [
		num_players, hand_sizes, stock.size(), discard.size(), melds.size(), turn_player, phase
	]

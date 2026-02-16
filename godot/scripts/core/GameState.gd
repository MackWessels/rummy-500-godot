
extends RefCounted
class_name GameState

var num_players: int = 0
var hands: Array = []       # Array[Array[String]] CardIDs per player
var stock: Array = []       # Array[String]
var discard: Array = []     # Array[String], fully visible
var melds: Array = []       # Array[Dictionary] shared table melds
var turn_player: int = 0
var phase: String = "DRAW"  # "DRAW" -> "MELD" -> "DISCARD"

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

func debug_summary() -> String:
	var hand_sizes := []
	for h in hands:
		hand_sizes.append(h.size())
	return "players=%s hand_sizes=%s stock=%s discard=%s melds=%s turn=%s phase=%s" % [
	num_players, hand_sizes, stock.size(), discard.size(), melds.size(), turn_player, phase
	]

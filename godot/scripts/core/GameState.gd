
extends RefCounted
class_name GameState

var num_players: int = 0
var hands: Array = []       # Array[Array[String]] CardIDs per player
var stock: Array = []       # Array[String]
var discard: Array = []     # Array[String], fully visible
var turn_player: int = 0
var phase: String = "DRAW"  # "DRAW" -> "MELD" -> "DISCARD"

func debug_summary() -> String:
	var hand_sizes := []
	for h in hands:
		hand_sizes.append(h.size())
	return "players=%s hand_sizes=%s stock=%s discard=%s turn=%s phase=%s" % [
		num_players, hand_sizes, stock.size(), discard.size(), turn_player, phase
	]

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
